import XCTest
@testable import StatusTrioCore

@MainActor
final class HardwareMonitorSummaryTests: XCTestCase {
    private func localization() -> Localization {
        let suite = "HardwareMonitorSummaryTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Localization(defaults: defaults, preferredLanguages: ["en"])
    }

    private func fan(_ index: Int, _ value: Double?,
                     _ availability: HardwareMetricAvailability = .measured) -> (HardwareMetricID, HardwareMetricSample) {
        (.fanRPM(index: index), HardwareMetricSample(
            value: value, unit: .rpm, sampledAt: Date(), source: .smc, availability: availability))
    }

    private func measured(_ value: Double?, unit: HardwareMetricUnit = .bytesPerSecond,
                          _ availability: HardwareMetricAvailability = .measured) -> HardwareMetricSample {
        HardwareMetricSample(value: value, unit: unit, sampledAt: Date(), source: .ioStorage,
                             availability: availability)
    }

    func testAverageFanAveragesFreshSamplesIncludingRealZero() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.fanCount = 2
        for (id, sample) in [fan(0, 0), fan(1, 2000)] { snapshot.samples[id] = sample }
        XCTAssertEqual(try XCTUnwrap(snapshot.averageFanSample.value), 1000, accuracy: 0.001)
        XCTAssertEqual(snapshot.averageFanSample.availability, .measured)
        // Highest-fan summary used by the icon must be unchanged.
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

    func testSummaryFixedOrderAndLabels() {
        let items = HardwareMonitorSummaryPresentation.items(
            snapshot: .empty, localization: localization())
        XCTAssertEqual(items.map(\.metric), [.download, .upload, .fan, .disk])
    }

    func testDiskReadWriteShareOneUnit() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.samples[.diskRead] = measured(2_000_000)
        snapshot.samples[.diskWrite] = measured(500_000)
        let disk = HardwareMonitorSummaryPresentation.items(
            snapshot: snapshot, localization: localization()).first { $0.metric == .disk }!
        XCTAssertEqual(disk.valueText, "2/0.5")
        XCTAssertEqual(disk.unitText, "MB/s")
        XCTAssertTrue(disk.accessibilityValue.lowercased().contains("read"))
        XCTAssertTrue(disk.accessibilityValue.lowercased().contains("write"))
    }

    func testKilobyteValuesUseKBUnit() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.samples[.diskRead] = measured(500_000)
        snapshot.samples[.diskWrite] = measured(200_000)
        let disk = HardwareMonitorSummaryPresentation.items(
            snapshot: snapshot, localization: localization()).first { $0.metric == .disk }!
        XCTAssertEqual(disk.valueText, "500/200")
        XCTAssertEqual(disk.unitText, "KB/s")
    }

    func testLargeNetworkValuesScaleToGB() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.samples[.networkDownload] = measured(1_500_000_000)
        let download = HardwareMonitorSummaryPresentation.items(
            snapshot: snapshot, localization: localization()).first { $0.metric == .download }!
        XCTAssertEqual(download.valueText, "1.5")
        XCTAssertEqual(download.unitText, "GB/s")
    }

    func testMissingValuesShowDashNotZero() {
        let items = HardwareMonitorSummaryPresentation.items(
            snapshot: .empty, localization: localization())
        for item in items { XCTAssertEqual(item.valueText, "—", "\(item.metric) must not fabricate a number") }
    }

    func testAverageFanShownInPRMRounded() {
        var snapshot = HardwareMetricsSnapshot.empty
        snapshot.fanCount = 2
        for (id, sample) in [fan(0, 2035), fan(1, 2037)] { snapshot.samples[id] = sample }
        let fan = HardwareMonitorSummaryPresentation.items(
            snapshot: snapshot, localization: localization()).first { $0.metric == .fan }!
        XCTAssertEqual(fan.valueText, "2036")
        XCTAssertEqual(fan.unitText, "RPM")
    }
}
