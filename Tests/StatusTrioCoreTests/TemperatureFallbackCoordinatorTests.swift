import XCTest
@testable import StatusTrioCore

final class TemperatureFallbackCoordinatorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func makeCoordinator(eligible: Bool = true) -> TemperatureFallbackCoordinator {
        TemperatureFallbackCoordinator(isEligible: { _ in eligible })
    }

    @discardableResult
    private func tick(_ coordinator: TemperatureFallbackCoordinator,
                      demanded: Set<TemperatureMetric> = [.cpu],
                      at offset: TimeInterval,
                      smc: [TemperatureMetric: Double?] = [:],
                      hid: [TemperatureMetric: TemperatureMeasurement] = [:],
                      smcRequests: inout [Set<TemperatureMetric>],
                      hidRequests: inout [Set<TemperatureMetric>])
        -> [TemperatureMetric: TemperatureDecision] {
        coordinator.resolve(
            demanded: demanded,
            at: start.addingTimeInterval(offset),
            smc: { metrics, _ in
                smcRequests.append(metrics)
                return smc
            },
            hid: { metrics, _ in
                hidRequests.append(metrics)
                return hid
            })
    }

    func testHealthySMCNeverCallsHID() {
        let coordinator = makeCoordinator()
        var smcRequests: [Set<TemperatureMetric>] = []
        var hidRequests: [Set<TemperatureMetric>] = []
        for offset in stride(from: 0.0, through: 20, by: 4) {
            let decisions = tick(coordinator, at: offset, smc: [.cpu: 70],
                                 smcRequests: &smcRequests, hidRequests: &hidRequests)
            XCTAssertEqual(decisions[.cpu], .smc)
        }
        XCTAssertTrue(hidRequests.isEmpty)
    }

    func testFirstFailureDoesNotActivateHID() {
        let coordinator = makeCoordinator()
        var smcRequests: [Set<TemperatureMetric>] = []
        var hidRequests: [Set<TemperatureMetric>] = []
        let decisions = tick(coordinator, at: 0, smc: [:],
                             smcRequests: &smcRequests, hidRequests: &hidRequests)
        XCTAssertEqual(decisions[.cpu], .unavailable)
        XCTAssertTrue(hidRequests.isEmpty)
    }

    func testSecondConsecutiveFailureActivatesHID() {
        let coordinator = makeCoordinator()
        var smcRequests: [Set<TemperatureMetric>] = []
        var hidRequests: [Set<TemperatureMetric>] = []
        tick(coordinator, at: 0, smc: [:], smcRequests: &smcRequests, hidRequests: &hidRequests)
        let measurement = TemperatureMeasurement(value: 55, count: 2)
        let decisions = tick(coordinator, at: 4, smc: [:], hid: [.cpu: measurement],
                             smcRequests: &smcRequests, hidRequests: &hidRequests)
        XCTAssertEqual(decisions[.cpu], .hid(measurement))
        XCTAssertEqual(hidRequests.last, [.cpu])
        XCTAssertEqual(coordinator.activeHIDMetrics, [.cpu])
    }

    func testCPUHealthyGPUOnlyFallsBack() {
        let coordinator = makeCoordinator()
        var smcRequests: [Set<TemperatureMetric>] = []
        var hidRequests: [Set<TemperatureMetric>] = []
        tick(coordinator, demanded: [.cpu, .gpu], at: 0, smc: [.cpu: 70],
             smcRequests: &smcRequests, hidRequests: &hidRequests)
        let measurement = TemperatureMeasurement(value: 48, count: 1)
        let decisions = tick(coordinator, demanded: [.cpu, .gpu], at: 4, smc: [.cpu: 71],
                             hid: [.gpu: measurement],
                             smcRequests: &smcRequests, hidRequests: &hidRequests)
        XCTAssertEqual(decisions[.cpu], .smc)
        XCTAssertEqual(decisions[.gpu], .hid(measurement))
        XCTAssertEqual(hidRequests.last, [.gpu])
        XCTAssertEqual(coordinator.activeHIDMetrics, [.gpu])
    }

    func testIneligibleChipNeverActivatesHID() {
        let coordinator = makeCoordinator(eligible: false)
        var smcRequests: [Set<TemperatureMetric>] = []
        var hidRequests: [Set<TemperatureMetric>] = []
        for offset in stride(from: 0.0, through: 100, by: 4) {
            let decisions = tick(coordinator, at: offset, smc: [:],
                                 smcRequests: &smcRequests, hidRequests: &hidRequests)
            XCTAssertEqual(decisions[.cpu], .unavailable)
        }
        XCTAssertTrue(hidRequests.isEmpty)
        XCTAssertTrue(coordinator.activeHIDMetrics.isEmpty)
    }

    func testValidSMCResetsFailureCount() {
        let coordinator = makeCoordinator()
        var smcRequests: [Set<TemperatureMetric>] = []
        var hidRequests: [Set<TemperatureMetric>] = []
        XCTAssertEqual(tick(coordinator, at: 0, smc: [:], smcRequests: &smcRequests, hidRequests: &hidRequests)[.cpu], .unavailable)
        XCTAssertEqual(tick(coordinator, at: 4, smc: [.cpu: 65], smcRequests: &smcRequests, hidRequests: &hidRequests)[.cpu], .smc)
        XCTAssertEqual(tick(coordinator, at: 8, smc: [:], smcRequests: &smcRequests, hidRequests: &hidRequests)[.cpu], .unavailable)
        XCTAssertTrue(hidRequests.isEmpty, "a reset failure count must not activate HID on a single new failure")
    }

    func testFallbackSkipsSMCPRObesUntilRecoveryWindowThenSwitchesBack() {
        let coordinator = makeCoordinator()
        var smcRequests: [Set<TemperatureMetric>] = []
        var hidRequests: [Set<TemperatureMetric>] = []
        tick(coordinator, at: 0, smc: [:], smcRequests: &smcRequests, hidRequests: &hidRequests)
        let first = TemperatureMeasurement(value: 55, count: 2)
        tick(coordinator, at: 4, smc: [:], hid: [.cpu: first], smcRequests: &smcRequests, hidRequests: &hidRequests)

        // Within the ten-minute cache window the failed SMC keys must not be read.
        let second = TemperatureMeasurement(value: 56, count: 2)
        let cached = tick(coordinator, at: 8, smc: [.cpu: 70], hid: [.cpu: second],
                          smcRequests: &smcRequests, hidRequests: &hidRequests)
        XCTAssertEqual(cached[.cpu], .hid(second))
        XCTAssertEqual(smcRequests.last, [], "cached fallback must not retry the SMC temperature keys")

        // Just past the recovery window the SMC is probed again and wins.
        let recovered = tick(coordinator, at: 606, smc: [.cpu: 70],
                             smcRequests: &smcRequests, hidRequests: &hidRequests)
        XCTAssertEqual(recovered[.cpu], .smc)
        XCTAssertEqual(smcRequests.last, [.cpu])
        XCTAssertTrue(coordinator.activeHIDMetrics.isEmpty)
    }

    func testHIDFailureUsesRateLimitedBackoff() {
        let coordinator = makeCoordinator()
        var smcRequests: [Set<TemperatureMetric>] = []
        var hidRequests: [Set<TemperatureMetric>] = []
        tick(coordinator, at: 0, smc: [:], smcRequests: &smcRequests, hidRequests: &hidRequests)
        // Activation tick: HID fails, so a 30 s backoff starts at t=4.
        let failed = tick(coordinator, at: 4, smc: [:], smcRequests: &smcRequests, hidRequests: &hidRequests)
        XCTAssertEqual(failed[.cpu], .unavailable)
        XCTAssertEqual(hidRequests.count, 1)

        // Before 34 s the HID is not attempted again.
        tick(coordinator, at: 8, smc: [:], smcRequests: &smcRequests, hidRequests: &hidRequests)
        XCTAssertEqual(hidRequests.count, 1)

        // After 30 s it is retried; another failure grows the next delay.
        tick(coordinator, at: 35, smc: [:], smcRequests: &smcRequests, hidRequests: &hidRequests)
        XCTAssertEqual(hidRequests.count, 2)
        tick(coordinator, at: 60, smc: [:], smcRequests: &smcRequests, hidRequests: &hidRequests)
        XCTAssertEqual(hidRequests.count, 2)
        tick(coordinator, at: 96, smc: [:], smcRequests: &smcRequests, hidRequests: &hidRequests)
        XCTAssertEqual(hidRequests.count, 3)
    }

    func testDroppingDemandResetsFallbackState() {
        let coordinator = makeCoordinator()
        var smcRequests: [Set<TemperatureMetric>] = []
        var hidRequests: [Set<TemperatureMetric>] = []
        tick(coordinator, at: 0, smc: [:], smcRequests: &smcRequests, hidRequests: &hidRequests)
        tick(coordinator, at: 4, smc: [:], hid: [.cpu: TemperatureMeasurement(value: 55, count: 1)],
             smcRequests: &smcRequests, hidRequests: &hidRequests)
        XCTAssertEqual(coordinator.activeHIDMetrics, [.cpu])

        coordinator.setDemandedMetrics([])
        XCTAssertTrue(coordinator.activeHIDMetrics.isEmpty)

        let after = tick(coordinator, at: 8, smc: [:], smcRequests: &smcRequests, hidRequests: &hidRequests)
        XCTAssertEqual(after[.cpu], .unavailable)
    }

    func testResetClearsActiveFallbackForSleepWake() {
        let coordinator = makeCoordinator()
        var smcRequests: [Set<TemperatureMetric>] = []
        var hidRequests: [Set<TemperatureMetric>] = []
        tick(coordinator, at: 0, smc: [:], smcRequests: &smcRequests, hidRequests: &hidRequests)
        tick(coordinator, at: 4, smc: [:], hid: [.cpu: TemperatureMeasurement(value: 55, count: 1)],
             smcRequests: &smcRequests, hidRequests: &hidRequests)
        XCTAssertEqual(coordinator.activeHIDMetrics, [.cpu])
        coordinator.reset()
        XCTAssertTrue(coordinator.activeHIDMetrics.isEmpty)
        let after = tick(coordinator, at: 8, smc: [:], smcRequests: &smcRequests, hidRequests: &hidRequests)
        XCTAssertEqual(after[.cpu], .unavailable)
    }

    func testPerMetricEligibilityIsRespected() {
        let coordinator = TemperatureFallbackCoordinator(isEligible: { $0 == .cpu })
        var smcRequests: [Set<TemperatureMetric>] = []
        var hidRequests: [Set<TemperatureMetric>] = []
        for offset in [0.0, 4.0] {
            tick(coordinator, demanded: [.cpu, .gpu], at: offset, smc: [:],
                 hid: [:], smcRequests: &smcRequests, hidRequests: &hidRequests)
        }
        XCTAssertEqual(coordinator.activeHIDMetrics, [.cpu])
        XCTAssertEqual(hidRequests.last, [.cpu])
    }

    func testProductionEligibilityIsBaseM1Only() {
        XCTAssertTrue(TemperatureFallbackCoordinator.isEligible(platform: .appleSilicon("Apple M1")))
        XCTAssertFalse(TemperatureFallbackCoordinator.isEligible(platform: .appleSilicon("Apple M1 Pro")))
        XCTAssertFalse(TemperatureFallbackCoordinator.isEligible(platform: .appleSilicon("Apple M1 Max")))
        XCTAssertFalse(TemperatureFallbackCoordinator.isEligible(platform: .appleSilicon("Apple M1 Ultra")))
        XCTAssertFalse(TemperatureFallbackCoordinator.isEligible(platform: .appleSilicon("Apple M2")))
        XCTAssertFalse(TemperatureFallbackCoordinator.isEligible(platform: .appleSilicon("Apple M6")))
        XCTAssertFalse(TemperatureFallbackCoordinator.isEligible(platform: .intel))
        XCTAssertFalse(TemperatureFallbackCoordinator.isEligible(platform: .unknown))
    }
}
