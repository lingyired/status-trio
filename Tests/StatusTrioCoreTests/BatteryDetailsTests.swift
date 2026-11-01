import Foundation
import XCTest
@testable import StatusTrioCore

final class BatteryDetailsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_555_974)
    private func state(connected: Bool = false, charging: Bool = false) -> BatteryPowerState {
        BatteryPowerState(BatteryStatus(rawPercentage: 80, isPresent: true,
                                       isCharging: charging, isLowPowerMode: false,
                                       isConnectedToPower: connected))
    }
    private var registry: [String: Any] {
        ["Voltage": 12279, "Amperage": -1528, "UpdateTime": now.timeIntervalSince1970,
         "ExternalConnected": false, "IsCharging": false, "CycleCount": 43]
    }
    private func parse(_ values: [String: Any], state: BatteryPowerState? = nil,
                       notBefore: Date? = nil, seconds: Double = -1) -> BatteryDetails {
        BatteryDetailsReader.parse(registry: values, adapterWatts: 90, remainingSeconds: seconds,
                                   state: state ?? self.state(), now: now, notBefore: notBefore)
    }

    func testBatteryNetPowerUsesOneSourceAndPreservesDischargeSign() throws {
        var values = registry
        values["PowerTelemetryData"] = ["BatteryPower": 999999]
        let details = parse(values)
        XCTAssertEqual(try XCTUnwrap(details.power).watts, -18.762312, accuracy: 0.000001)
        XCTAssertEqual(details.cycleCount, 43)
        XCTAssertNil(details.adapterWatts, "Disconnected power must not show a residual adapter rating")
        XCTAssertNil(details.remainingMinutes, "IOPS unknown (-1) is not zero minutes")
    }

    func testUnsigned64BitNegativeCurrentIsDecodedAndBounded() throws {
        var values = registry
        values["Amperage"] = NSNumber(value: UInt64(bitPattern: -1528))
        XCTAssertEqual(try XCTUnwrap(parse(values).power).amps, -1.528)
        for current: Any in [NSNumber(value: UInt64.max / 2), NSNumber(value: Int64.min), true, 0, 30_001, -30_001, 1.5] {
            values["Amperage"] = current
            XCTAssertNil(parse(values).power)
        }
    }

    func testChargingAndACIdleHaveDistinctSemantics() throws {
        var values = registry
        values["ExternalConnected"] = true
        values["IsCharging"] = true
        values["Amperage"] = 1000
        let charging = parse(values, state: state(connected: true, charging: true))
        XCTAssertEqual(charging.power?.watts, 12.279)
        XCTAssertEqual(charging.adapterWatts, 90)
        XCTAssertEqual(charging.powerAvailability, .available)
        values["IsCharging"] = false
        XCTAssertNil(parse(values, state: state(connected: true)).power, "Positive current without charging is inconsistent")
        values["Amperage"] = -1000
        XCTAssertNil(parse(values, state: state(connected: true)).power,
                     "Connected power is represented by the system sample, not battery current")
    }

    func testPowerTransitionsRequireAConsistentNewSample() {
        let laggingRegistry = parse(registry, state: state(connected: true))
        XCTAssertNil(laggingRegistry.power)
        XCTAssertEqual(laggingRegistry.powerAvailability, .collecting)
        let beforeTransition = parse(registry, notBefore: now.addingTimeInterval(1))
        XCTAssertNil(beforeTransition.power)
        XCTAssertEqual(beforeTransition.powerAvailability, .collecting)
        XCTAssertNotNil(parse(registry, notBefore: now).power)
    }

    func testPositiveSMCSampleShowsChargingWhileFlagsStillLag() {
        var values = registry
        values["ExternalConnected"] = true
        values["IsCharging"] = false
        let sample = BatteryPowerSample(volts: 12.4, amps: 4.2, updatedAt: now)

        let details = BatteryDetailsReader.parse(
            registry: values,
            adapterWatts: 140,
            remainingSeconds: -1,
            state: state(connected: true, charging: false),
            now: now,
            systemPower: SystemPowerSample(watts: 10.6, readAt: now),
            inputPower: SystemPowerSample(watts: 61.56, readAt: now),
            batteryPower: sample
        )

        XCTAssertEqual(try XCTUnwrap(details.power).watts, 52.08, accuracy: 0.001)
        XCTAssertEqual(details.powerAvailability, .available)
    }

    func testConnectedIntelMacUsesSystemPowerWhenBatteryCurrentIsZero() {
        let systemPower = SystemPowerSample(watts: 18.5, readAt: now)
        var values = registry
        values["ExternalConnected"] = true
        values["IsCharging"] = false
        values["Amperage"] = 0

        let details = BatteryDetailsReader.parse(
            registry: values,
            adapterWatts: 90,
            remainingSeconds: -1,
            state: state(connected: true),
            now: now,
            systemPower: systemPower
        )

        XCTAssertEqual(details.systemPower, systemPower)
        XCTAssertEqual(details.powerAvailability, .available)
        XCTAssertEqual(details.adapterWatts, 90)
        XCTAssertNil(details.power)
    }

    func testConnectedIntelMacUsesSystemPowerWhenBatteryCurrentIsNegative() {
        let systemPower = SystemPowerSample(watts: 22.75, readAt: now)
        var values = registry
        values["ExternalConnected"] = true
        values["IsCharging"] = false
        values["Amperage"] = -1000

        let details = BatteryDetailsReader.parse(
            registry: values,
            adapterWatts: 90,
            remainingSeconds: -1,
            state: state(connected: true),
            now: now,
            systemPower: systemPower
        )

        XCTAssertEqual(details.systemPower, systemPower)
        XCTAssertEqual(details.powerAvailability, .available)
        XCTAssertNil(details.power, "Battery net power is not the system total while adapter power is available")
    }

    func testUnsupportedTelemetryIsUnavailableRatherThanCollecting() {
        for key in ["Voltage", "Amperage", "UpdateTime"] {
            var values = registry
            _ = values.removeValue(forKey: key)
            let details = BatteryDetailsReader.parse(
                registry: values, adapterWatts: 90, remainingSeconds: -1,
                state: state(), now: now)
            XCTAssertNil(details.power, key)
            XCTAssertEqual(details.powerAvailability, .unavailable, key)
        }
        var values = registry
        values["Amperage"] = 30_001
        XCTAssertEqual(parse(values).powerAvailability, .collecting)
    }

    func testAvailablePowerReportsAvailable() {
        XCTAssertEqual(parse(registry).powerAvailability, .available)
    }

    func testDefaultAvailabilityFailsClosed() {
        XCTAssertEqual(BatteryDetails().powerAvailability, .unavailable)
    }

    func testIdleBatteryOnAdapterDoesNotPublishBatteryNetPower() throws {
        var values = registry
        values["ExternalConnected"] = true
        values["IsCharging"] = false
        values["Amperage"] = 0
        let idle = parse(values, state: state(connected: true))
        XCTAssertNil(idle.power)
        XCTAssertEqual(idle.adapterWatts, 90)
        values["ExternalConnected"] = false
        let unplugged = parse(values)
        XCTAssertNil(unplugged.power, "Zero while unplugged stays a transition, not an idle battery")
        XCTAssertEqual(unplugged.powerAvailability, .collecting)
    }

    func testSystemPowerIsIndependentOfBatteryCurrentAndAvailability() throws {
        let system = SystemPowerSample(watts: 17.25, readAt: now)
        var idle = registry
        idle["ExternalConnected"] = true
        idle["Amperage"] = 0
        let pluggedIn = BatteryDetailsReader.parse(
            registry: idle, adapterWatts: 90, remainingSeconds: -1,
            state: state(connected: true), now: now, systemPower: system)
        XCTAssertNil(pluggedIn.power, "Connected Macs show whole-system power, not battery net power")
        XCTAssertEqual(pluggedIn.systemPower?.watts, 17.25)
        XCTAssertEqual(pluggedIn.powerAvailability, .available)
        let missingBattery = BatteryDetailsReader.parse(
            registry: [:], adapterWatts: 90, remainingSeconds: -1,
            state: state(connected: true), now: now, systemPower: system)
        XCTAssertNil(missingBattery.power)
        XCTAssertEqual(missingBattery.systemPower?.watts, 17.25)
        let withoutSMC = parse(registry)
        XCTAssertNil(withoutSMC.systemPower)
        XCTAssertNotNil(withoutSMC.power)
    }

    func testSystemPowerIsMeaningfulForNoBatteryAndOnExternalPower() {
        XCTAssertTrue(BatteryDetailsReader.readsSystemPower(for: state(connected: true)))
        XCTAssertFalse(BatteryDetailsReader.readsSystemPower(for: state()))
        let absent = BatteryPowerState(BatteryStatus(rawPercentage: 0, isPresent: false,
                                                     isCharging: false, isLowPowerMode: false,
                                                     isConnectedToPower: true))
        XCTAssertTrue(BatteryDetailsReader.readsSystemPower(for: absent),
                      "A Mac without a battery still has a whole-machine power reading to show")
    }

    func testNoBatteryDetailsExposeOnlyTheSystemPowerRow() {
        let absent = BatteryPowerState(BatteryStatus(rawPercentage: nil, isPresent: false,
                                                     isCharging: false, isLowPowerMode: false,
                                                     isConnectedToPower: false))
        let sample = SystemPowerSample(watts: 18.4, readAt: now)
        let details = BatteryDetailsReader.parse(
            registry: [:], adapterWatts: 90, remainingSeconds: -1,
            state: absent, now: now, systemPower: sample)
        XCTAssertEqual(details.systemPower, sample)
        XCTAssertEqual(details.powerAvailability, .available)
        XCTAssertNil(details.adapterWatts)
        XCTAssertNil(details.remainingMinutes)
        XCTAssertNil(details.cycleCount)
        XCTAssertNil(details.power)

        let collecting = BatteryDetailsReader.parse(
            registry: [:], adapterWatts: 90, remainingSeconds: -1,
            state: absent, now: now)
        XCTAssertEqual(collecting.powerAvailability, .collecting)
    }

    func testMissingStaleAndFutureTelemetryFailClosed() {
        for key in ["Voltage", "Amperage", "UpdateTime", "ExternalConnected", "IsCharging"] {
            var values = registry
            values.removeValue(forKey: key)
            XCTAssertNil(parse(values).power, key)
        }
        for timestamp in [now.timeIntervalSince1970 - 91, now.timeIntervalSince1970 + 6,
                          now.timeIntervalSince1970 * 1_000, Double.nan, Double.infinity] {
            var values = registry
            values["UpdateTime"] = timestamp
            XCTAssertNil(parse(values).power)
        }
    }

    func testPublicRemainingTimeUsesSecondsAndUnknownDoesNotFallBackToRegistry() {
        var values = registry
        values["TimeRemaining"] = 177
        for invalid in [-2.0, -1, 0, Double.nan, Double.infinity, Double(Int.max)] {
            XCTAssertNil(parse(values, seconds: invalid).remainingMinutes)
        }
        XCTAssertEqual(parse(values, seconds: 7260).remainingMinutes, 121)
        XCTAssertNil(parse(values, state: state(connected: true), seconds: 7260).remainingMinutes)
    }
}

private final class BatteryStateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [BatteryPowerState] = []

    var states: [BatteryPowerState] {
        lock.withLock { recorded }
    }

    func record(_ state: BatteryPowerState) {
        lock.withLock { recorded.append(state) }
    }
}

private final class BlockingBatteryDetailsReader: @unchecked Sendable {
    private let lock = NSLock()
    let gate = DispatchSemaphore(value: 0)
    private var reads = 0
    var count: Int { lock.withLock { reads } }
    func read() -> BatteryDetails {
        lock.withLock { reads += 1 }
        _ = gate.wait(timeout: .now() + 5)
        return BatteryDetails(cycleCount: 43)
    }
}

@MainActor
final class BatteryDetailsControllerTests: XCTestCase {
    private let state = BatteryPowerState(.placeholder)
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for background read")
    }

    func testBlockedReadDoesNotBlockMainActorAndCoalescesRequests() async {
        let reader = BlockingBatteryDetailsReader()
        let controller = BatteryDetailsController { _, _ in reader.read() }
        controller.activate(state: state)
        await waitUntil { reader.count == 1 }
        for _ in 0..<100 { controller.refresh() }
        XCTAssertEqual(reader.count, 1)
        reader.gate.signal()
        await waitUntil { reader.count == 2 }
        reader.gate.signal()
        await waitUntil { controller.details != nil }
        XCTAssertEqual(reader.count, 2)
        controller.deactivate()
    }

    func testStateUpdateWhileActiveReachesTheNextRead() async {
        let recorder = BatteryStateRecorder()
        let controller = BatteryDetailsController { state, _ in
            recorder.record(state)
            return BatteryDetails(cycleCount: 43)
        }
        controller.activate(state: recordingState(charging: false))
        await waitUntil { recorder.states.count == 1 }
        XCTAssertEqual(recorder.states.last?.isCharging, false)

        controller.update(state: recordingState(charging: true))
        controller.refresh()
        await waitUntil { recorder.states.count >= 2 }
        XCTAssertEqual(recorder.states.last?.isCharging, true)
        controller.deactivate()
    }

    private func recordingState(charging: Bool) -> BatteryPowerState {
        BatteryPowerState(
            BatteryStatus(
                rawPercentage: 80,
                isPresent: true,
                isCharging: charging,
                isLowPowerMode: false,
                isConnectedToPower: true
            )
        )
    }

    func testExpiredOrFuturePowerIsNotPublishedWhenBackgroundReadReturns() async {
        for offset in [-91.0, 10] {
            let controller = BatteryDetailsController { _, _ in
                BatteryDetails(cycleCount: 43, power: BatteryPowerSample(
                    volts: 12, amps: -1, updatedAt: Date().addingTimeInterval(offset)
                ), systemPower: SystemPowerSample(watts: 17.25, readAt: Date().addingTimeInterval(offset)),
                   inputPower: SystemPowerSample(watts: 67, readAt: Date().addingTimeInterval(offset)))
            }
            controller.activate(state: state)
            await waitUntil { controller.details != nil }
            XCTAssertNil(controller.details?.power)
            XCTAssertNil(controller.details?.systemPower)
            XCTAssertNil(controller.details?.inputPower)
            XCTAssertEqual(controller.details?.cycleCount, 43)
            controller.deactivate()
        }
    }

    func testExpiredPowerIsRemovedEvenWhileNextReadIsBlocked() async {
        let reader = BlockingBatteryDetailsReader()
        let sampled = Date()
        let controller = BatteryDetailsController { _, _ in
            _ = reader.read()
            return BatteryDetails(power: BatteryPowerSample(volts: 12, amps: -1, updatedAt: sampled))
        }
        controller.activate(state: state)
        reader.gate.signal()
        await waitUntil { controller.details?.power != nil }
        controller.refresh()
        await waitUntil { reader.count == 2 }
        controller.refresh(now: sampled.addingTimeInterval(91))
        XCTAssertNil(controller.details?.power)
        controller.deactivate()
        reader.gate.signal()
    }

    func testSystemPowerExpiresWhileTheNextReadIsBlocked() async {
        let reader = BlockingBatteryDetailsReader()
        let sampled = Date()
        let controller = BatteryDetailsController { _, _ in
            _ = reader.read()
            return BatteryDetails(systemPower: SystemPowerSample(watts: 17.25, readAt: sampled),
                inputPower: SystemPowerSample(watts: 67, readAt: sampled))
        }
        controller.activate(state: state)
        reader.gate.signal()
        await waitUntil { controller.details?.systemPower != nil }
        controller.refresh()
        await waitUntil { reader.count == 2 }
        controller.refresh(now: sampled.addingTimeInterval(91))
        XCTAssertNil(controller.details?.systemPower)
        XCTAssertNil(controller.details?.inputPower)
        controller.deactivate()
        reader.gate.signal()
    }

    func testClosingDiscardsLateResultsAndDoesNotStartPendingRead() async {
        let reader = BlockingBatteryDetailsReader()
        let controller = BatteryDetailsController { _, _ in reader.read() }
        controller.activate(state: state)
        await waitUntil { reader.count == 1 }
        controller.refresh()
        controller.deactivate()
        reader.gate.signal()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(controller.details)
        XCTAssertEqual(reader.count, 1)
    }

    func testTransitionDiscardsOldResultAndReopenGetsFreshRead() async {
        let reader = BlockingBatteryDetailsReader()
        let controller = BatteryDetailsController { _, _ in reader.read() }
        controller.activate(state: state)
        await waitUntil { reader.count == 1 }
        controller.deactivate()
        controller.activate(state: state)
        reader.gate.signal()
        await waitUntil { reader.count == 2 }
        XCTAssertNil(controller.details)
        reader.gate.signal()
        await waitUntil { controller.details != nil }
        controller.deactivate()
    }

    func testRepeatedActivationWithTheSameStateKeepsTheFirstRead() async {
        let reader = BlockingBatteryDetailsReader()
        let controller = BatteryDetailsController { _, _ in reader.read() }
        defer {
            controller.deactivate()
            reader.gate.signal()
        }

        controller.activate(state: state)
        await waitUntil { reader.count == 1 }

        controller.activate(state: state)
        reader.gate.signal()
        await waitUntil { controller.details != nil }

        XCTAssertEqual(reader.count, 1)
        XCTAssertTrue(controller.isActive)
    }

    func testActiveReflectsWhetherCollectionIsRunning() {
        let controller = BatteryDetailsController { _, _ in BatteryDetails(cycleCount: 43) }
        XCTAssertFalse(controller.isActive)
        controller.activate(state: state)
        XCTAssertTrue(controller.isActive)
        controller.deactivate()
        XCTAssertFalse(controller.isActive)
    }
}
