import XCTest
@testable import StatusTrioCore

final class HardwareDetailTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 20_000)

    // MARK: - Memory

    func testMemoryDetailKeepsGaugeSemanticsAndSeparatesCache() {
        let stats = MemoryReader.MemoryStatistics(
            activeBytes: 500, purgeableBytes: 100, wiredBytes: 200, compressedBytes: 50,
            internalBytes: 600, externalBytes: 300, freeBytes: 400, totalBytes: 1_600)
        let detail = MemoryReader.detail(from: stats, swapUsedBytes: 10, swapTotalBytes: 20,
                                         pressure: .warning, at: start)
        XCTAssertEqual(detail.appBytes, 400)
        XCTAssertEqual(detail.usedBytes, 650) // app + wired + compressed
        XCTAssertEqual(detail.percent, 650.0 / 1_600 * 100, accuracy: 0.0001)
        XCTAssertEqual(detail.cachedBytes, 400) // external + purgeable, NOT in usedBytes
        XCTAssertNotEqual(detail.usedBytes, detail.usedBytes + detail.cachedBytes)
        XCTAssertEqual(detail.pressure, .warning)
    }

    func testMemoryPressureMapping() {
        XCTAssertEqual(MemoryPressureLevel.from(rawLevel: 1), .normal)
        XCTAssertEqual(MemoryPressureLevel.from(rawLevel: 2), .warning)
        XCTAssertEqual(MemoryPressureLevel.from(rawLevel: 4), .critical)
        XCTAssertEqual(MemoryPressureLevel.from(rawLevel: 9), .unknown)
    }

    // MARK: - GPU

    func testGPUSelectsBusiestOnlineDeviceAndKeepsMissingFieldsNil() {
        let sources = [
            GPUReader.GPUDetailSource(deviceName: "A", statistics: ["Device Utilization %": 40,
                                                                    "Renderer Utilization %": 66,
                                                                    "Tiler Utilization %": 61],
                                      inUseMemoryBytes: 1_000, isOnline: true),
            GPUReader.GPUDetailSource(deviceName: "B", statistics: ["Device Utilization %": 75],
                                      inUseMemoryBytes: nil, isOnline: true),
            GPUReader.GPUDetailSource(deviceName: "off", statistics: ["Device Utilization %": 99],
                                      inUseMemoryBytes: nil, isOnline: false)
        ]
        let detail = try? XCTUnwrap(GPUReader.selectDetail(sources, at: start))
        XCTAssertEqual(detail?.deviceName, "B")
        XCTAssertEqual(detail?.usage, 75)
        XCTAssertNil(detail?.rendererUtilization) // B does not report it
        XCTAssertNil(detail?.tilerUtilization)
        XCTAssertNil(detail?.inUseSystemMemoryBytes)
    }

    func testGPUDetailReturnsNilWithoutOnlineDevices() {
        let sources = [GPUReader.GPUDetailSource(deviceName: "off",
                                                 statistics: ["Device Utilization %": 10],
                                                 inUseMemoryBytes: nil, isOnline: false)]
        XCTAssertNil(GPUReader.selectDetail(sources, at: start))
    }

    // MARK: - CPU grouping (from CPUReader)

    func testCPUCoreGroupingExcludesUnknownFromPerformance() {
        let topology = CPUCoreTopology(kinds: [.efficiency, .unknown, .performance])
        let group = CPUReader.groupUsage(cores: [10, 999, 40], topology: topology)
        XCTAssertEqual(group?.efficiencyAverage ?? -1, 10, accuracy: 0.0001)
        XCTAssertEqual(group?.performanceAverage ?? -1, 40, accuracy: 0.0001)
    }

    // MARK: - Demand metric map

    @MainActor
    func testDetailMetricIDsCoverEachPage() {
        XCTAssertEqual(HardwareMetricsService.detailMetricIDs(for: .cpu), [.cpuUsage, .cpuTemperature])
        XCTAssertEqual(HardwareMetricsService.detailMetricIDs(for: .gpu), [.gpuUsage, .gpuTemperature])
        XCTAssertEqual(HardwareMetricsService.detailMetricIDs(for: .memory), [.memoryUsage])
        XCTAssertEqual(HardwareMetricsService.detailMetricIDs(for: .network), [.networkDownload, .networkUpload])
        XCTAssertEqual(HardwareMetricsService.detailMetricIDs(for: .disk), [.diskRead, .diskWrite])
    }

    // MARK: - Network

    func testNetworkDetailNilWithoutReadingOrSession() {
        let reader = NetworkThroughputReader()
        XCTAssertNil(reader.detailReading(from: nil, at: start))
    }

    // MARK: - Disk capacity (host dependent)

    func testDiskCapacityReaderReturnsConsistentTotals() throws {
        guard let capacity = DiskCapacityReader.read(at: start) else {
            throw XCTSkip("volume capacity unavailable on this host")
        }
        XCTAssertGreaterThan(capacity.totalBytes, 0)
        XCTAssertLessThanOrEqual(capacity.freeBytes, capacity.totalBytes)
        XCTAssertEqual(capacity.usedBytes, capacity.totalBytes - capacity.freeBytes)
        XCTAssertTrue((0...1).contains(capacity.usedFraction))
    }

    // MARK: - History store

    private func usageSnapshot(_ value: Double, at date: Date) -> HardwareMetricsSnapshot {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.samples[.cpuUsage] = HardwareMetricSample(value: value, unit: .percent,
                                                          sampledAt: date, source: .mach, availability: .measured)
        return snapshot
    }

    @MainActor
    func testHistoryStoreDeduplicatesAndPrunes() {
        let observable = HardwareMonitorObservable(snapshot: usageSnapshot(10, at: start))
        let store = HardwareDetailHistoryStore(seriesCount: 1)
        store.start(observable: observable,
                    timestamp: { $0[.cpuUsage].sampledAt },
                    values: { [$0[.cpuUsage].value] })
        // start ingested the first point.
        XCTAssertEqual(store.points.count, 1)
        // Same timestamp must not append a duplicate.
        store.ingest(usageSnapshot(99, at: start))
        XCTAssertEqual(store.points.count, 1)
        let older = start.addingTimeInterval(HardwareDetailHistoryStore.window + 20)
        let newest = start.addingTimeInterval(HardwareDetailHistoryStore.window + 50)
        store.ingest(usageSnapshot(20, at: older))
        store.ingest(usageSnapshot(30, at: newest))
        XCTAssertEqual(store.points.count, 2)
        XCTAssertEqual(store.points.first?.date, older)
        store.stop()
        XCTAssertTrue(store.points.isEmpty)
    }

    @MainActor
    func testHistoryStoreIsBounded() {
        let observable = HardwareMonitorObservable(snapshot: usageSnapshot(0, at: start))
        let store = HardwareDetailHistoryStore(seriesCount: 1)
        store.start(observable: observable,
                    timestamp: { $0[.cpuUsage].sampledAt },
                    values: { [$0[.cpuUsage].value] })
        for index in 0..<600 {
            store.ingest(usageSnapshot(Double(index % 100), at: start.addingTimeInterval(Double(index) * 0.05)))
        }
        XCTAssertLessThanOrEqual(store.points.count, HardwareDetailHistoryStore.maxPoints)
    }

    @MainActor
    func testHistorySeedsFromPanelSessionRows() {
        let observable = HardwareMonitorObservable(snapshot: .empty)
        for index in 0..<5 {
            let date = start.addingTimeInterval(Double(index) * 2)
            var snapshot = HardwareMetricsSnapshot.empty
            snapshot.samples[.cpuUsage] = HardwareMetricSample(value: Double(index) * 10, unit: .percent,
                                                               sampledAt: date, source: .mach, availability: .measured)
            observable.update(snapshot, now: date)
        }
        XCTAssertEqual(observable.historyRowsForDetail.count, 5)

        let store = HardwareDetailHistoryStore(seriesCount: 1)
        store.start(observable: observable,
                    timestamp: { $0[.cpuUsage].sampledAt },
                    values: { [$0[.cpuUsage].value] },
                    seedRows: observable.historyRowsForDetail,
                    seedMetricIDs: [.cpuUsage])
        XCTAssertEqual(store.points.count, 5)
        XCTAssertEqual(store.points.first?.values.first ?? nil, 0)
    }

    @MainActor
    func testHistorySurvivesStaleAndPayloadClear() {
        let observable = HardwareMonitorObservable(snapshot: .empty)
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.samples[.cpuUsage] = HardwareMetricSample(value: 30, unit: .percent,
                                                           sampledAt: start, source: .mach, availability: .measured)
        observable.update(snapshot, now: start)
        XCTAssertEqual(observable.historyRowsForDetail.count, 1)
        // Closing the panel / switching pages stales samples and clears payloads,
        // but must keep the session history for the next detail page.
        observable.markStale(now: start.addingTimeInterval(1))
        observable.clearDetailPayloads(except: nil)
        XCTAssertEqual(observable.historyRowsForDetail.count, 1)
        observable.clearHistory()
        XCTAssertTrue(observable.historyRowsForDetail.isEmpty)
    }

    // MARK: - Chart geometry

    private func geometryPoints(_ offsets: [TimeInterval], now: Date) -> [HardwareDetailHistoryPoint] {
        offsets.enumerated().map { index, offset in
            HardwareDetailHistoryPoint(id: index, date: now.addingTimeInterval(offset), values: [25])
        }
    }

    func testChartGeometryKeepsUniformSlowCadenceConnected() {
        let now = Date()
        let points = geometryPoints([-40, -30, -20, -10], now: now)
        let samples = HardwareDetailChartGeometry.samples(points: points, series: 0, now: now,
                                                          yMaximum: 100, size: CGSize(width: 300, height: 50))
        let threshold = HardwareDetailChartGeometry.breakThreshold(for: samples)
        XCTAssertEqual(threshold, HardwareDetailHistoryStore.window, accuracy: 0.001)
        XCTAssertEqual(HardwareDetailChartGeometry.segments(for: samples, threshold: threshold).count, 1)
        XCTAssertTrue(HardwareDetailChartGeometry.isolatedPoints(for: samples, threshold: threshold).isEmpty)
    }

    func testChartGeometryKeepsMixedCadenceContinuous() {
        let now = Date()
        // 1 s samples, then a 19 s slow gap, then more 1 s samples.
        let points = geometryPoints([-40, -39, -38, -19, -18, -17], now: now)
        let samples = HardwareDetailChartGeometry.samples(points: points, series: 0, now: now,
                                                          yMaximum: 100, size: CGSize(width: 300, height: 50))
        let threshold = HardwareDetailChartGeometry.breakThreshold(for: samples)
        XCTAssertEqual(threshold, HardwareDetailHistoryStore.window, accuracy: 0.001)
        XCTAssertEqual(HardwareDetailChartGeometry.segments(for: samples, threshold: threshold).count, 1)
        XCTAssertTrue(HardwareDetailChartGeometry.isolatedPoints(for: samples, threshold: threshold).isEmpty)
    }

    func testChartGeometrySinglePointSpansWidth() {
        let now = Date()
        let points = geometryPoints([-10], now: now)
        let samples = HardwareDetailChartGeometry.samples(points: points, series: 0, now: now,
                                                          yMaximum: 100, size: CGSize(width: 300, height: 50))
        XCTAssertEqual(samples.count, 2, "a lone sample is drawn as a full-width flat line")
        XCTAssertTrue(HardwareDetailChartGeometry.isolatedPoints(
            for: samples, threshold: HardwareDetailHistoryStore.maximumGap).isEmpty)
    }

    func testChartSpansFullWidthWithoutSideGaps() {
        let now = Date()
        let width: CGFloat = 300
        // History younger than the chart window used to leave a left gap.
        let shortHistory = geometryPoints([-8, -4], now: now)
        let samples = HardwareDetailChartGeometry.samples(points: shortHistory, series: 0, now: now,
                                                          yMaximum: 100, size: CGSize(width: width, height: 50))
        XCTAssertEqual(samples.first?.point.x ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(samples.last?.point.x ?? -1, width, accuracy: 0.01)

        // Newest sample one refresh interval behind `now` used to leave a right gap.
        let lagging = geometryPoints([-30, -2], now: now)
        let laggingSamples = HardwareDetailChartGeometry.samples(points: lagging, series: 0, now: now,
                                                                 yMaximum: 100, size: CGSize(width: width, height: 50))
        XCTAssertEqual(laggingSamples.last?.point.x ?? -1, width, accuracy: 0.01)

        // A single sample fills the width as a flat line instead of leaving
        // side gaps while the next sample arrives.
        let single = HardwareDetailChartGeometry.samples(points: geometryPoints([-10], now: now),
                                                          series: 0, now: now, yMaximum: 100,
                                                          size: CGSize(width: width, height: 50))
        XCTAssertEqual(single.count, 2)
        XCTAssertEqual(single.first?.point.x ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(single.last?.point.x ?? -1, width, accuracy: 0.01)
    }

    // MARK: - Shared network timeline

    private func networkPoints(_ now: Date) -> [HardwareDetailHistoryPoint] {
        [
            HardwareDetailHistoryPoint(id: 0, date: now.addingTimeInterval(-2), values: [1, nil]),
            HardwareDetailHistoryPoint(id: 1, date: now.addingTimeInterval(-1), values: [2, 3]),
            HardwareDetailHistoryPoint(id: 2, date: now, values: [4, 5])
        ]
    }

    func testChartSharedDomainAlignsBothDirectionsAtOneTimestamp() {
        let now = Date(timeIntervalSince1970: 100)
        let points = networkPoints(now)
        let size = CGSize(width: 100, height: 80)
        let domain = HardwareDetailChartGeometry.domain(points: points, now: now)
        XCTAssertNotNil(domain)

        let download = HardwareDetailChartGeometry.samples(points: points, series: 0, now: now,
                                                           yMaximum: 10, size: size, domain: domain)
        let upload = HardwareDetailChartGeometry.samples(points: points, series: 1, now: now,
                                                         yMaximum: 10, size: size, domain: domain)
        let middle = now.addingTimeInterval(-1)
        XCTAssertEqual(download.first { $0.date == middle }?.point.x ?? -1, 50, accuracy: 0.01)
        XCTAssertEqual(upload.first { $0.date == middle }?.point.x ?? -1, 50, accuracy: 0.01)
    }

    func testChartSharedDomainKeepsLoneSeriesAtItsRealTime() {
        let now = Date(timeIntervalSince1970: 100)
        let points = [
            HardwareDetailHistoryPoint(id: 0, date: now.addingTimeInterval(-2), values: [1, nil]),
            HardwareDetailHistoryPoint(id: 1, date: now.addingTimeInterval(-1), values: [2, 3]),
            HardwareDetailHistoryPoint(id: 2, date: now, values: [4, nil])
        ]
        let size = CGSize(width: 100, height: 80)
        let domain = HardwareDetailChartGeometry.domain(points: points, now: now)

        let upload = HardwareDetailChartGeometry.samples(points: points, series: 1, now: now,
                                                         yMaximum: 10, size: size, domain: domain)
        XCTAssertEqual(upload.count, 1)
        XCTAssertEqual(upload.first?.point.x ?? -1, 50, accuracy: 0.01,
                       "a lone upload sample must not be stretched across the full width")
    }

    func testChartSharedDomainSingleTimestampStaysFullWidth() {
        let now = Date(timeIntervalSince1970: 100)
        let points = [HardwareDetailHistoryPoint(id: 0, date: now, values: [2, 3])]
        let size = CGSize(width: 100, height: 80)
        let domain = HardwareDetailChartGeometry.domain(points: points, now: now)

        let download = HardwareDetailChartGeometry.samples(points: points, series: 0, now: now,
                                                           yMaximum: 10, size: size, domain: domain)
        XCTAssertEqual(download.first?.point.x ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(download.last?.point.x ?? -1, 100, accuracy: 0.01)
    }

    // MARK: - Fan page

    private func fanSample(_ rpm: Double?, availability: HardwareMetricAvailability,
                           maximum: Double? = nil, label: String? = nil,
                           fanless: Bool = false) -> HardwareMetricSample {
        HardwareMetricSample(value: rpm, unit: .rpm, source: .smc,
                             availability: availability, sensorLabel: label,
                             metadata: HardwareMetricMetadata(maximum: maximum, isFanless: fanless))
    }

    func testFanDetailKnownZeroIsFanlessWithoutInventedCard() {
        var snapshot = HardwareMetricsSnapshot()
        snapshot.fanCount = 0
        snapshot.samples[.fanRPM(index: 0)] = fanSample(nil, availability: .unsupported, fanless: true)

        let page = FanDetailPresentation(snapshot: snapshot)

        XCTAssertEqual(page.fanCount, 0)
        XCTAssertTrue(page.isFanless)
        XCTAssertTrue(page.rows.isEmpty)
        XCTAssertNil(page.averageRPM)
    }

    func testFanDetailUnreadCountDoesNotInventOneFan() {
        var snapshot = HardwareMetricsSnapshot()
        snapshot.samples[.fanRPM(index: 0)] = fanSample(nil, availability: .temporarilyUnavailable)

        let page = FanDetailPresentation(snapshot: snapshot)

        XCTAssertNil(page.fanCount)
        XCTAssertFalse(page.isFanless)
        XCTAssertTrue(page.rows.isEmpty, "an unread FNum must not become one placeholder fan")
        XCTAssertNil(page.averageRPM)
    }

    func testFanDetailKeepsUnmeasuredFanButAveragesOnlyReadableOnes() {
        var snapshot = HardwareMetricsSnapshot()
        snapshot.fanCount = 2
        snapshot.samples[.fanRPM(index: 0)] = fanSample(1_500, availability: .measured, maximum: 5_000, label: "Left")
        snapshot.samples[.fanRPM(index: 1)] = fanSample(nil, availability: .temporarilyUnavailable, maximum: 5_000)

        let page = FanDetailPresentation(snapshot: snapshot)

        XCTAssertEqual(page.fanCount, 2)
        XCTAssertEqual(page.rows.count, 2)
        XCTAssertEqual(page.rows[0].rpm, 1_500)
        XCTAssertNil(page.rows[1].rpm)
        XCTAssertEqual(page.rows[0].sensorLabel, "Left")
        XCTAssertEqual(page.averageRPM, 1_500)
    }

    func testFanDetailStaleAverageKeepsValueAndFlag() {
        var snapshot = HardwareMetricsSnapshot()
        snapshot.fanCount = 1
        snapshot.samples[.fanRPM(index: 0)] = fanSample(1_200, availability: .stale, maximum: 4_000)

        let page = FanDetailPresentation(snapshot: snapshot)

        XCTAssertEqual(page.averageRPM, 1_200)
        XCTAssertTrue(page.isAverageStale)
        XCTAssertFalse(page.isFanless)
        XCTAssertEqual(page.rows.count, 1)
    }

    // MARK: - Formatting

    func testFormatFallsBackToDash() {
        XCTAssertEqual(HardwareDetailFormat.percent(nil), "—")
        XCTAssertEqual(HardwareDetailFormat.frequency(0), "—")
        XCTAssertEqual(HardwareDetailFormat.bytes(nil as UInt64?), "—")
        XCTAssertEqual(HardwareDetailFormat.rate(nil), "—")
    }
}
