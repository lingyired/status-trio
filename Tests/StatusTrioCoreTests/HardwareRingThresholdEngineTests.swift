import XCTest
@testable import StatusTrioCore

final class HardwareRingThresholdEngineTests: XCTestCase {
    private let cpu = HardwareMetricRingOptions.default(for: .cpuUsage)          // warn 75 / crit 90
    private let temperature = HardwareMetricRingOptions.default(for: .cpuTemperature) // warn 85 / crit 95

    func testEnteringWarningNeedsTwoConsecutiveSamples() {
        var engine = HardwareRingThresholdEngine()
        XCTAssertEqual(engine.ingest(value: 76, metric: .cpuUsage, options: cpu), .normal)
        XCTAssertEqual(engine.ingest(value: 76, metric: .cpuUsage, options: cpu), .warning)
    }

    func testSingleSpikeDoesNotFlash() {
        var engine = HardwareRingThresholdEngine()
        XCTAssertEqual(engine.ingest(value: 99, metric: .cpuUsage, options: cpu), .normal)
        // Back below the threshold before the second confirmation.
        XCTAssertEqual(engine.ingest(value: 40, metric: .cpuUsage, options: cpu), .normal)
        XCTAssertEqual(engine.ingest(value: 99, metric: .cpuUsage, options: cpu), .normal)
    }

    func testWarningExitUsesHysteresisMargin() {
        var engine = HardwareRingThresholdEngine()
        _ = engine.ingest(value: 76, metric: .cpuUsage, options: cpu)
        XCTAssertEqual(engine.ingest(value: 76, metric: .cpuUsage, options: cpu), .warning)
        // 73 is below the 75 threshold but above the 72 exit margin: stay warning.
        XCTAssertEqual(engine.ingest(value: 73, metric: .cpuUsage, options: cpu), .warning)
        // 71 drops below 72: back to normal.
        XCTAssertEqual(engine.ingest(value: 71, metric: .cpuUsage, options: cpu), .normal)
    }

    func testEnteringCriticalNeedsTwoConsecutiveSamples() {
        var engine = HardwareRingThresholdEngine()
        _ = engine.ingest(value: 78, metric: .cpuUsage, options: cpu)
        XCTAssertEqual(engine.ingest(value: 78, metric: .cpuUsage, options: cpu), .warning)
        XCTAssertEqual(engine.ingest(value: 91, metric: .cpuUsage, options: cpu), .warning)
        XCTAssertEqual(engine.ingest(value: 91, metric: .cpuUsage, options: cpu), .critical)
    }

    func testTemperatureUsesTwoDegreeMargin() {
        var engine = HardwareRingThresholdEngine()
        _ = engine.ingest(value: 86, metric: .cpuTemperature, options: temperature)
        XCTAssertEqual(engine.ingest(value: 86, metric: .cpuTemperature, options: temperature), .warning)
        // warnExit = 83; 84 stays warning.
        XCTAssertEqual(engine.ingest(value: 84, metric: .cpuTemperature, options: temperature), .warning)
        // 82 < 83 -> normal.
        XCTAssertEqual(engine.ingest(value: 82, metric: .cpuTemperature, options: temperature), .normal)
    }

    func testUnavailableResetsToNormal() {
        var engine = HardwareRingThresholdEngine()
        _ = engine.ingest(value: 76, metric: .cpuUsage, options: cpu)
        XCTAssertEqual(engine.ingest(value: 76, metric: .cpuUsage, options: cpu), .warning)
        XCTAssertEqual(engine.ingest(value: nil, metric: .cpuUsage, options: cpu), .normal)
    }

    func testImmediateLevelIgnoresHysteresis() {
        XCTAssertEqual(HardwareRingThresholdEngine.immediateLevel(value: 76, options: cpu), .warning)
        XCTAssertEqual(HardwareRingThresholdEngine.immediateLevel(value: 91, options: cpu), .critical)
        XCTAssertEqual(HardwareRingThresholdEngine.immediateLevel(value: 10, options: cpu), .normal)
    }

    @MainActor
    func testTrackerDeduplicatesIdenticalSnapshot() {
        let tracker = HardwareRingStatusTracker()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let configuration = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage)

        func snapshot(at date: Date) -> HardwareMetricsSnapshot {
            var snapshot = HardwareMetricsSnapshot()
            snapshot.samples = [
                .cpuUsage: HardwareMetricSample(
                    value: 76, unit: .percent, sampledAt: date, source: .mach,
                    availability: .measured
                )
            ]
            return snapshot
        }

        let first = snapshot(at: now)
        XCTAssertEqual(tracker.levels(snapshot: first, configuration: configuration, now: now)[.cpuUsage], .normal)
        // Same snapshot again must not count as a second consecutive sample.
        XCTAssertEqual(tracker.levels(snapshot: first, configuration: configuration, now: now)[.cpuUsage], .normal)
        // A new sample at the same value advances the counter to warning.
        XCTAssertEqual(
            tracker.levels(snapshot: snapshot(at: now.addingTimeInterval(1)),
                           configuration: configuration, now: now.addingTimeInterval(1))[.cpuUsage],
            .warning
        )
    }
}
