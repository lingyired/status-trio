import XCTest
@testable import StatusTrioCore

@MainActor
final class HardwareMonitorSummaryTests: XCTestCase {
    private let ts = Date(timeIntervalSince1970: 1_000)

    private func localization() -> Localization {
        let suite = "HardwareMonitorSummaryTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Localization(defaults: defaults, preferredLanguages: ["en"])
    }

    private func fan(_ index: Int, _ value: Double?,
                     _ availability: HardwareMetricAvailability = .measured) -> (HardwareMetricID, HardwareMetricSample) {
        (.fanRPM(index: index), HardwareMetricSample(
            value: value, unit: .rpm, sampledAt: ts, source: .smc, availability: availability))
    }

    private func rate(_ value: Double?, _ availability: HardwareMetricAvailability = .measured,
                      at date: Date? = nil) -> HardwareMetricSample {
        HardwareMetricSample(value: value, unit: .bytesPerSecond, sampledAt: date ?? ts,
                             source: .ioStorage, availability: availability)
    }

    private func diskItem(_ snapshot: HardwareMetricsSnapshot) -> HardwareSummaryMetricPresentation {
        HardwareMonitorSummaryPresentation.items(snapshot: snapshot, localization: localization())
            .first { $0.metric == .disk }!
    }

    private func item(_ metric: HardwareSummaryMetric, _ snapshot: HardwareMetricsSnapshot) -> HardwareSummaryMetricPresentation {
        HardwareMonitorSummaryPresentation.items(snapshot: snapshot, localization: localization())
            .first { $0.metric == metric }!
    }

    // MARK: - Fan average

    func testAverageFanAveragesFreshSamplesIncludingRealZero() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.fanCount = 2
        for (id, sample) in [fan(0, 0), fan(1, 2000)] { snapshot.samples[id] = sample }
        XCTAssertEqual(try XCTUnwrap(snapshot.averageFanSample.value), 1000, accuracy: 0.001)
        XCTAssertEqual(snapshot.averageFanSample.availability, .measured)
        XCTAssertEqual(snapshot.fanSummarySample.value, 2000)
    }

    func testAverageFanIgnoresNaNNegativeStaleAndUnavailable() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.fanCount = 4
        for (id, sample) in [fan(0, 1500), fan(1, -10), fan(2, .nan), fan(3, 9000, .stale)] {
            snapshot.samples[id] = sample
        }
        XCTAssertEqual(try XCTUnwrap(snapshot.averageFanSample.value), 1500, accuracy: 0.001)
    }

    func testAverageFanFanlessIsUnsupported() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.fanCount = 0
        let summary = snapshot.averageFanSample
        XCTAssertNil(summary.value)
        XCTAssertEqual(summary.availability, .unsupported)
        XCTAssertTrue(summary.metadata.isFanless)
    }

    func testAverageFanAllUnavailableIsNotZero() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.fanCount = 2
        for (id, sample) in [fan(0, nil, .temporarilyUnavailable), fan(1, nil, .temporarilyUnavailable)] {
            snapshot.samples[id] = sample
        }
        XCTAssertNil(snapshot.averageFanSample.value)
        XCTAssertEqual(snapshot.averageFanSample.availability, .temporarilyUnavailable)
    }

    func testFanSampleCountMentionedWhenSomeFansUnreadable() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.fanCount = 2
        snapshot.samples[.fanRPM(index: 0)] = fan(0, 2000).1
        snapshot.samples[.fanRPM(index: 1)] = fan(1, nil, .temporarilyUnavailable).1
        let fanItem = item(.fan, snapshot)
        XCTAssertEqual(fanItem.valueText, "2000")
        XCTAssertTrue(fanItem.help.lowercased().contains("1"), "help should mention the 1 contributing sensor")
    }

    // MARK: - Order / missing

    func testSummaryFixedOrderAndLabels() {
        let items = HardwareMonitorSummaryPresentation.items(snapshot: .empty, localization: localization())
        XCTAssertEqual(items.map(\.metric), [.download, .upload, .fan, .disk])
    }

    func testMissingValuesShowDashNotZero() {
        for item in HardwareMonitorSummaryPresentation.items(snapshot: .empty, localization: localization()) {
            XCTAssertEqual(item.valueText, "—", "\(item.metric) must not fabricate a number")
        }
    }

    // MARK: - Network formatting (Auto)

    func testNetworkBoundaryValues() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.samples[.networkDownload] = rate(999_000)
        XCTAssertEqual(item(.download, snapshot).valueText, "999")
        XCTAssertEqual(item(.download, snapshot).unitText, "KB/s")
        snapshot.samples[.networkDownload] = rate(1_000_000)
        XCTAssertEqual(item(.download, snapshot).valueText, "1.0")
        XCTAssertEqual(item(.download, snapshot).unitText, "MB/s")
        snapshot.samples[.networkDownload] = rate(125_000_000)
        XCTAssertEqual(item(.download, snapshot).valueText, "125")
        snapshot.samples[.networkDownload] = rate(1_300_000_000)
        XCTAssertEqual(item(.download, snapshot).valueText, "1.3")
        XCTAssertEqual(item(.download, snapshot).unitText, "GB/s")
    }

    func testNetworkRealZeroShowsZeroKilobytes() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.samples[.networkDownload] = rate(0)
        XCTAssertEqual(item(.download, snapshot).valueText, "0")
        XCTAssertEqual(item(.download, snapshot).unitText, "KB/s")
    }

    // MARK: - Disk total

    func testDiskShowsReadWriteTotal() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.samples[.diskRead] = rate(2_000_000)
        snapshot.samples[.diskWrite] = rate(500_000)
        let disk = diskItem(snapshot)
        XCTAssertEqual(disk.valueText, "2.5")
        XCTAssertEqual(disk.unitText, "MB/s")
        XCTAssertTrue(disk.help.lowercased().contains("read"))
        XCTAssertTrue(disk.help.lowercased().contains("write"))
        XCTAssertTrue(disk.accessibilityValue.lowercased().contains("total"))
    }

    func testDiskTotalExampleRead70Write13p4() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.samples[.diskRead] = rate(70_000_000)
        snapshot.samples[.diskWrite] = rate(13_400_000)
        let disk = diskItem(snapshot)
        XCTAssertEqual(disk.valueText, "83.4")
        XCTAssertEqual(disk.unitText, "MB/s")
        XCTAssertTrue(disk.help.contains("70.0 MB/s"))
        XCTAssertTrue(disk.help.contains("13.4 MB/s"))
    }

    func testDiskBothRealZeroShowsZero() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.samples[.diskRead] = rate(0)
        snapshot.samples[.diskWrite] = rate(0)
        let disk = diskItem(snapshot)
        XCTAssertEqual(disk.valueText, "0")
        XCTAssertEqual(disk.unitText, "KB/s")
    }

    func testDiskMissingDirectionIsNotCalledTotal() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.samples[.diskRead] = rate(2_000_000)
        snapshot.samples[.diskWrite] = rate(nil, .temporarilyUnavailable)
        let disk = diskItem(snapshot)
        XCTAssertEqual(disk.valueText, "—", "a partial direction must not be shown as the total")
        XCTAssertTrue(disk.help.lowercased().contains("read"))
    }

    func testDiskMixedLiveAndCacheIsNotSummed() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.samples[.diskRead] = rate(2_000_000, .measured, at: ts)
        snapshot.samples[.diskWrite] = rate(1_000_000, .stale, at: ts.addingTimeInterval(-100))
        XCTAssertEqual(diskItem(snapshot).valueText, "—", "mixed live/cache must not be summed")
    }

    func testDiskStaleSameCycleShowsDimmedTotal() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.samples[.diskRead] = rate(2_000_000, .stale)
        snapshot.samples[.diskWrite] = rate(1_000_000, .stale)
        let disk = diskItem(snapshot)
        XCTAssertEqual(disk.valueText, "3.0")
        XCTAssertEqual(disk.unitText, "MB/s")
        XCTAssertTrue(disk.isStale)
    }

    func testAverageFanShownInPRMRounded() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.fanCount = 2
        for (id, sample) in [fan(0, 2035), fan(1, 2037)] { snapshot.samples[id] = sample }
        let fanItem = item(.fan, snapshot)
        XCTAssertEqual(fanItem.valueText, "2036")
        XCTAssertEqual(fanItem.unitText, "RPM")
    }
}
