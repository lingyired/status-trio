import Combine
import XCTest
@testable import StatusTrioCore

private final class FakeLegacyClient: LegacyChargeLimitClienting, @unchecked Sendable {
    var probeResult: Result<LegacyChargeLimitProbeFacts, any Error> = .success(
        LegacyChargeLimitProbeFacts(
            hasInternalBattery: true,
            intelBCLMPresent: true,
            siliconPairPresent: false,
            siliconCHTEPresent: false
        )
    )
    var setLimitResult: Result<LegacyChargeLimitWriteOutcome, any Error> = .success(.success)
    var disableResult: Result<LegacyChargeLimitWriteOutcome, any Error> = .success(.success)
    var chargeToFullResult: Result<LegacyChargeLimitWriteOutcome, any Error> = .success(.success)
    var cancelResult: Result<LegacyChargeLimitWriteOutcome, any Error> = .success(.success)
    var verifyResult: Result<LegacyChargeLimitWriteOutcome, any Error> = .success(.success)

    private(set) var setLimitCalls: [(limit: Int, expected: Int?)] = []
    private(set) var disableCalls: [Int?] = []
    private(set) var chargeToFullCalls = 0
    private(set) var cancelCalls = 0
    private(set) var verifyCalls: [Int] = []
    private(set) var probeCalls = 0
    private(set) var releaseCalls = 0

    func probe() async throws -> LegacyChargeLimitProbeFacts {
        probeCalls += 1
        return try probeResult.get()
    }

    func setLimit(_ limit: Int, expectedLimit: Int?) async throws -> LegacyChargeLimitWriteOutcome {
        setLimitCalls.append((limit, expectedLimit))
        return try setLimitResult.get()
    }

    func chargeToFullOnce() async throws -> LegacyChargeLimitWriteOutcome {
        chargeToFullCalls += 1
        return try chargeToFullResult.get()
    }

    func cancelChargeToFull() async throws -> LegacyChargeLimitWriteOutcome {
        cancelCalls += 1
        return try cancelResult.get()
    }

    func disable(expectedLimit: Int?) async throws -> LegacyChargeLimitWriteOutcome {
        disableCalls.append(expectedLimit)
        return try disableResult.get()
    }

    func verify(_ limit: Int) async throws -> LegacyChargeLimitWriteOutcome {
        verifyCalls.append(limit)
        return try verifyResult.get()
    }

    func releaseConnection() {
        releaseCalls += 1
    }
}

@MainActor
final class LegacyChargeLimitControllerTests: XCTestCase {
    private func makeController(
        client: FakeLegacyClient = FakeLegacyClient(),
        store: any LegacyChargeLimitSessionStoring = VolatileLegacyChargeLimitSessionStore(),
        architecture: LegacyRuntimeArchitecture = .intel,
        osBand: LegacyOSBand = .thirteenToFourteen
    ) -> LegacyChargeLimitController {
        LegacyChargeLimitController(
            client: client,
            sessionStore: store,
            architecture: architecture,
            osBand: osBand
        )
    }

    func testUnsupportedOSNeverProbesAndShowsUnsupported() async {
        let client = FakeLegacyClient()
        let controller = makeController(client: client, osBand: .tahoe)
        await controller.refresh()
        XCTAssertEqual(controller.availability, .unavailable(.unsupportedOS))
        XCTAssertEqual(controller.status, .notEnabled)
        XCTAssertEqual(client.probeCalls, 0)
    }

    func testProbeFailureReportsHelperUnavailable() async {
        let client = FakeLegacyClient()
        client.probeResult = .failure(LegacyChargeLimitClientError.helperUnavailable)
        let controller = makeController(client: client)
        await controller.refresh()
        XCTAssertEqual(controller.availability, .unavailable(.helperUnavailable))
    }

    func testNoSavedSessionShowsNotEnabled() async {
        let controller = makeController()
        await controller.refresh()
        XCTAssertTrue(controller.isAvailable)
        XCTAssertEqual(controller.status, .notEnabled)
        XCTAssertNil(controller.selectedLimit)
    }

    func testSavedSessionIsVerifiedNotAssumedActive() async {
        let store = VolatileLegacyChargeLimitSessionStore()
        store.save(LegacyChargeLimitSession(requestedLimit: 80, originalLimit: 100))
        let client = FakeLegacyClient()
        client.verifyResult = .success(
            LegacyChargeLimitWriteOutcome(succeeded: true, verified: true, observedLimit: 80, error: nil)
        )
        let controller = makeController(client: client, store: store)
        await controller.refresh()
        XCTAssertEqual(client.verifyCalls, [80])
        XCTAssertEqual(controller.status, .holding(at: 80))
    }

    func testSavedSessionThatIsNotOnHardwareIsUnverified() async {
        let store = VolatileLegacyChargeLimitSessionStore()
        store.save(LegacyChargeLimitSession(requestedLimit: 80, originalLimit: 100))
        let client = FakeLegacyClient()
        client.verifyResult = .success(
            LegacyChargeLimitWriteOutcome(succeeded: false, verified: false, observedLimit: nil, error: .verificationFailed)
        )
        let controller = makeController(client: client, store: store)
        await controller.refresh()
        XCTAssertEqual(controller.status, .unverified)
    }

    func testSetLimitPersistsIntentAndHolds() async {
        let store = VolatileLegacyChargeLimitSessionStore()
        let client = FakeLegacyClient()
        let controller = makeController(client: client, store: store)
        await controller.refresh()

        let ok = await controller.setLimit(85)
        XCTAssertTrue(ok)
        XCTAssertEqual(controller.status, .holding(at: 85))
        XCTAssertEqual(controller.selectedLimit, 85)
        XCTAssertEqual(store.load()?.requestedLimit, 85)
        XCTAssertEqual(client.setLimitCalls.map(\.limit), [85])
    }

    func testSetLimitConflictPausesAutomaticManagement() async {
        let client = FakeLegacyClient()
        client.setLimitResult = .success(
            LegacyChargeLimitWriteOutcome(succeeded: false, verified: false, observedLimit: nil, error: .ownershipConflict)
        )
        let controller = makeController(client: client)
        await controller.refresh()
        _ = await controller.setLimit(80)
        XCTAssertEqual(controller.status, .externalChange)
    }

    func testDisableClearsIntentAndRestoresSystemManaged() async {
        let store = VolatileLegacyChargeLimitSessionStore()
        let controller = makeController(store: store)
        await controller.refresh()
        _ = await controller.setLimit(80)
        let ok = await controller.disable()
        XCTAssertTrue(ok)
        XCTAssertEqual(controller.status, .notEnabled)
        XCTAssertNil(controller.selectedLimit)
        XCTAssertNil(store.load())
    }

    func testDisableFailureReportsRestoreFailedAndKeepsIntent() async {
        let store = VolatileLegacyChargeLimitSessionStore()
        let client = FakeLegacyClient()
        client.disableResult = .success(
            LegacyChargeLimitWriteOutcome(succeeded: false, verified: false, observedLimit: nil, error: .restoreFailed)
        )
        let controller = makeController(client: client, store: store)
        await controller.refresh()
        _ = await controller.setLimit(80)

        let ok = await controller.disable()
        XCTAssertFalse(ok)
        XCTAssertEqual(controller.status, .restoreFailed)
        XCTAssertNotNil(store.load(), "A failed restore must keep the intent for a recovery path")
    }

    func testChargeToFullThenCancelReturnsToHolding() async {
        let controller = makeController()
        await controller.refresh()
        _ = await controller.setLimit(80)

        _ = await controller.chargeToFullOnce()
        XCTAssertEqual(controller.status, .temporarilyChargingToFull)

        _ = await controller.cancelChargeToFull()
        XCTAssertEqual(controller.status, .holding(at: 80))
    }

    func testWakeDoesNotInterruptATemporaryFullCharge() async {
        let client = FakeLegacyClient()
        let controller = makeController(client: client)
        await controller.refresh()
        _ = await controller.setLimit(80)
        _ = await controller.chargeToFullOnce()
        let callsBefore = client.setLimitCalls.count

        await controller.handleWake()
        XCTAssertEqual(client.setLimitCalls.count, callsBefore, "A temporary override must survive a wake event")
        XCTAssertEqual(controller.status, .temporarilyChargingToFull)
    }

    func testWakeReappliesWhenIdleAndNoSessionDoesNothing() async {
        let client = FakeLegacyClient()
        let controller = makeController(client: client)
        await controller.refresh()
        await controller.handleWake()
        XCTAssertTrue(client.setLimitCalls.isEmpty, "No session means nothing to reapply")
    }

    func testWakeReappliesTheHeldLimit() async {
        let client = FakeLegacyClient()
        let controller = makeController(client: client)
        await controller.refresh()
        _ = await controller.setLimit(90)
        await controller.handleWake()
        XCTAssertEqual(client.setLimitCalls.map(\.limit), [90, 90])
        XCTAssertEqual(controller.status, .holding(at: 90))
    }

    func testStartWithNoSessionDoesNotProbeOrStartTheHelper() async {
        let client = FakeLegacyClient()
        let controller = makeController(client: client)
        controller.start()
        // Give the (possibly scheduled) task a turn to run.
        await Task.yield()
        XCTAssertEqual(client.probeCalls, 0, "An idle app must not spawn the root helper")
        XCTAssertEqual(controller.status, .notEnabled)
    }

    func testStartWithSavedSessionVerifiesIt() async {
        let store = VolatileLegacyChargeLimitSessionStore()
        store.save(LegacyChargeLimitSession(requestedLimit: 80, originalLimit: 100))
        let client = FakeLegacyClient()
        let controller = makeController(client: client, store: store)
        controller.start()
        for _ in 0..<50 where client.verifyCalls.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(client.verifyCalls, [80])
    }

    func testRefreshAvailabilityProbesWhenThePaneIsShown() async {
        let client = FakeLegacyClient()
        let controller = makeController(client: client)
        await controller.refreshAvailability()
        XCTAssertEqual(client.probeCalls, 1)
    }

    func testDisableReleasesTheHelperConnection() async {
        let client = FakeLegacyClient()
        let controller = makeController(client: client)
        await controller.refresh()
        _ = await controller.setLimit(80)
        let before = client.releaseCalls
        _ = await controller.disable()
        XCTAssertGreaterThan(client.releaseCalls, before, "No limit held means the helper may exit")
    }

    func testIdleRefreshReleasesTheConnection() async {
        let client = FakeLegacyClient()
        let controller = makeController(client: client)
        await controller.refresh()
        XCTAssertGreaterThan(client.releaseCalls, 0)
    }

    func testBatteryEventInhibitsAtTheCeilingThenHoldsInsideTheBand() async {
        let client = FakeLegacyClient()
        let controller = makeController(client: client)
        await controller.refresh()
        _ = await controller.setLimit(80)
        let baseline = client.setLimitCalls.count

        await controller.handleBattery(level: 90, isOnAC: true)
        XCTAssertEqual(client.setLimitCalls.count, baseline + 1, "At/above the limit must write the gate")

        // 79 sits inside the 2% band: hold, do not flap.
        await controller.handleBattery(level: 79, isOnAC: true)
        XCTAssertEqual(client.setLimitCalls.count, baseline + 1)

        // 78 is the lower band edge: allow charging.
        await controller.handleBattery(level: 78, isOnAC: true)
        XCTAssertEqual(client.setLimitCalls.count, baseline + 2)
    }

    func testBatteryEventOnBatteryPowerNeverWrites() async {
        let client = FakeLegacyClient()
        let controller = makeController(client: client)
        await controller.refresh()
        _ = await controller.setLimit(80)
        let baseline = client.setLimitCalls.count
        await controller.handleBattery(level: 90, isOnAC: false)
        XCTAssertEqual(client.setLimitCalls.count, baseline)
    }

    func testBatteryEventDuringTemporaryFullChargeDoesNotInterrupt() async {
        let client = FakeLegacyClient()
        let controller = makeController(client: client)
        await controller.refresh()
        _ = await controller.setLimit(80)
        _ = await controller.chargeToFullOnce()
        let baseline = client.setLimitCalls.count
        await controller.handleBattery(level: 90, isOnAC: true)
        XCTAssertEqual(client.setLimitCalls.count, baseline)
        XCTAssertEqual(controller.status, .temporarilyChargingToFull)
    }

    func testBatteryEventWithoutSessionDoesNothing() async {
        let client = FakeLegacyClient()
        let controller = makeController(client: client)
        await controller.refresh()
        await controller.handleBattery(level: 90, isOnAC: true)
        XCTAssertTrue(client.setLimitCalls.isEmpty)
    }

    func testAppStartWithPublisherReconcilesSavedIntentAndConsumesFirstRealUpdate() async {
        let client = FakeLegacyClient()
        let store = VolatileLegacyChargeLimitSessionStore()
        store.save(LegacyChargeLimitSession(requestedLimit: 80, originalLimit: 100))
        let controller = makeController(client: client, store: store)
        let batteries = PassthroughSubject<BatteryStatus, Never>()
        controller.start(batteries: batteries.eraseToAnyPublisher())
        await waitUntil { client.verifyCalls == [80] }
        XCTAssertEqual(controller.status, .holding(at: 80))

        // AppEnvironment already omits the store's initial snapshot. The
        // controller must not drop this first genuine power/battery event.
        batteries.send(battery(90))
        await waitUntil { client.setLimitCalls.count == 1 }
        batteries.send(battery(79))
        batteries.send(battery(78))
        await waitUntil { client.setLimitCalls.count == 2 }
        XCTAssertEqual(client.setLimitCalls.map(\.limit), [80, 80])
        controller.stop()
    }

    func testPublisherCompletesTemporaryFullChargeAndRestoresTheHeldIntent() async {
        let client = FakeLegacyClient()
        let controller = makeController(client: client)
        let batteries = PassthroughSubject<BatteryStatus, Never>()
        controller.start(batteries: batteries.eraseToAnyPublisher())
        await controller.refresh()
        _ = await controller.setLimit(85)
        _ = await controller.chargeToFullOnce()
        batteries.send(battery(99))
        batteries.send(battery(100))
        await waitUntil { client.cancelCalls == 1 }
        XCTAssertEqual(controller.status, .holding(at: 85))
        XCTAssertEqual(client.setLimitCalls.map(\.limit), [85])
        controller.stop()
    }

    func testWakeFailureShowsFailedAndKeepsTheSavedIntent() async {
        let client = FakeLegacyClient()
        let store = VolatileLegacyChargeLimitSessionStore()
        let controller = makeController(client: client, store: store)
        await controller.refresh()
        _ = await controller.setLimit(90)
        client.setLimitResult = .success(LegacyChargeLimitWriteOutcome(
            succeeded: false, verified: false, observedLimit: nil, error: .verificationFailed
        ))
        await controller.handleWake()
        XCTAssertEqual(controller.status, .failed)
        XCTAssertEqual(store.load()?.requestedLimit, 90)
    }

    private func battery(_ level: Int) -> BatteryStatus {
        BatteryStatus(rawPercentage: level, isPresent: true, isCharging: level < 100,
                      isCharged: level == 100, isLowPowerMode: false, isConnectedToPower: true)
    }

    private func waitUntil(
        file: StaticString = #filePath, line: UInt = #line, _ predicate: () -> Bool
    ) async {
        for _ in 0..<100 {
            if predicate() { return }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Expected asynchronous controller event was not observed", file: file, line: line)
    }

    func testHoldingACapRaisesAndReleasingItWithdrawsTheSharedHelperDemand() async {
        let controller = makeController()
        await controller.refresh()
        var demands: [Bool] = []
        controller.onHelperDemandChanged = { demands.append($0) }
        _ = await controller.setLimit(80)
        XCTAssertEqual(demands, [true])
        _ = await controller.disable()
        XCTAssertEqual(demands, [true, false])
    }

    func testUnavailableControllerDoesNotIssueCommands() async {
        let client = FakeLegacyClient()
        let controller = makeController(client: client, osBand: .tahoe)
        await controller.refresh()
        let ok = await controller.setLimit(80)
        XCTAssertFalse(ok)
        XCTAssertEqual(controller.status, .unsupported)
        XCTAssertTrue(client.setLimitCalls.isEmpty)
    }
}