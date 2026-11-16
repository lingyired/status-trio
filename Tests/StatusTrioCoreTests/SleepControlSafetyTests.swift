import Combine
import XCTest
@testable import StatusTrioCore

private final class ProbeAssertion: DisplaySleepAsserting {
    var acquireResult = true
    private(set) var isHeld = false
    func acquire() -> Bool { if acquireResult { isHeld = true }; return acquireResult }
    func release() { isHeld = false }
}

@MainActor
private final class ProbeReadiness: HelperReadinessProviding {
    var isReady: Bool
    private let subject: CurrentValueSubject<Bool, Never>
    var readinessPublisher: AnyPublisher<Bool, Never> { subject.eraseToAnyPublisher() }
    init(isReady: Bool) { self.isReady = isReady; subject = CurrentValueSubject(isReady) }
    func setReady(_ value: Bool) { isReady = value; subject.send(value) }
}

private final class ProbeOwnership: SleepOwnershipStoring {
    var ownsDisableSleep: Bool
    init(owns: Bool = false) { ownsDisableSleep = owns }
}

private final class ControllableClient: DisableSleepClienting, @unchecked Sendable {
    enum Failure: Error { case failed }
    private let lock = NSLock()
    private var _disableSleep: Bool
    private var _version: Int
    private var _versionThrows: Bool
    private var _readThrows: Bool
    private var _autoComplete: Bool
    private var _failSetCount: Int
    private var _setCalls: [Bool] = []
    private var _readCalls = 0
    private var _pending: [(Bool, CheckedContinuation<Bool, Error>)] = []

    init(disableSleep: Bool = false, version: Int = 3, versionThrows: Bool = false,
         readThrows: Bool = false, autoComplete: Bool = true, failSetCount: Int = 0) {
        _disableSleep = disableSleep; _version = version; _versionThrows = versionThrows
        _readThrows = readThrows; _autoComplete = autoComplete; _failSetCount = failSetCount
    }

    var disableSleep: Bool { lock.withLock { _disableSleep } }
    var setCalls: [Bool] { lock.withLock { _setCalls } }
    var readCalls: Int { lock.withLock { _readCalls } }
    var pendingCount: Int { lock.withLock { _pending.count } }
    func setFailSetCount(_ v: Int) { lock.withLock { _failSetCount = v } }

    func protocolVersion() async throws -> Int {
        try lock.withLock {
            if _versionThrows { throw Failure.failed }
            return _version
        }
    }
    func readDisableSleep() async throws -> Bool {
        try lock.withLock {
            _readCalls += 1
            if _readThrows { throw Failure.failed }
            return _disableSleep
        }
    }
    func setDisableSleep(_ enabled: Bool) async throws -> Bool {
        enum Decision { case fail, complete(Bool), suspend }
        let decision: Decision = lock.withLock {
            _setCalls.append(enabled)
            if _failSetCount > 0 { _failSetCount -= 1; return .fail }
            if _autoComplete { _disableSleep = enabled; return .complete(enabled) }
            return .suspend
        }
        switch decision {
        case .fail:
            throw Failure.failed
        case .complete(let value):
            return value
        case .suspend:
            return try await withCheckedThrowingContinuation { cont in
                lock.withLock { _pending.append((enabled, cont)) }
            }
        }
    }
    func completeNext() {
        let next = lock.withLock { () -> (Bool, CheckedContinuation<Bool, Error>)? in
            guard !_pending.isEmpty else { return nil }
            let item = _pending.removeFirst()
            _disableSleep = item.0
            return item
        }
        next?.1.resume(returning: next!.0)
    }
    func failNext() {
        let next = lock.withLock { () -> CheckedContinuation<Bool, Error>? in
            guard !_pending.isEmpty else { return nil }
            return _pending.removeFirst().1
        }
        next?.resume(throwing: Failure.failed)
    }
}

@MainActor
final class SleepControlSafetyTests: XCTestCase {
    private func make(
        client: ControllableClient,
        readiness: ProbeReadiness = ProbeReadiness(isReady: true),
        ownership: ProbeOwnership = ProbeOwnership()
    ) -> SleepControlController {
        SleepControlController(
            assertion: ProbeAssertion(),
            client: client,
            helperReadiness: readiness,
            ownership: ownership,
            lidDisableRetryDelays: [0, 0, 0]
        )
    }

    private func battery(connected: Bool, percentage: Int = 50) -> BatteryStatus {
        BatteryStatus(rawPercentage: percentage, isPresent: true, isCharging: false,
                      isLowPowerMode: false, isConnectedToPower: connected)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool,
                           iterations: Int = 800) async {
        for _ in 0..<iterations {
            if condition() { return }
            await Task.yield()
        }
    }

    func testUnplugDuringInFlightEnableEndsOff() async {
        let client = ControllableClient(autoComplete: false)
        let control = make(client: client)
        // This asserts the race guarantee when battery operation is disallowed.
        control.allowsLidSleepOnBattery = false
        control.updatePowerState(battery: battery(connected: true))
        control.setLidSleep(true)
        await waitUntil { client.pendingCount == 1 }
        XCTAssertEqual(client.setCalls, [true])
        XCTAssertTrue(control.needsTerminationCleanup)

        control.updatePowerState(battery: battery(connected: false))
        client.completeNext()
        await waitUntil { client.pendingCount == 1 }
        XCTAssertEqual(client.setCalls, [true, false])
        client.completeNext()
        await waitUntil { !control.isApplyingLidSleep }

        XCTAssertFalse(control.isPreventingLidSleep)
        XCTAssertFalse(client.disableSleep)
        XCTAssertEqual(control.notice, .turnedOffUnplugged)
    }

    func testLowBatteryDuringInFlightEnableEndsOff() async {
        let client = ControllableClient(autoComplete: false)
        let control = make(client: client)
        control.updatePowerState(battery: battery(connected: true))
        control.setLidSleep(true)
        await waitUntil { client.pendingCount == 1 }
        control.updatePowerState(battery: battery(connected: false, percentage: 10))
        client.completeNext()
        await waitUntil { client.pendingCount == 1 }
        client.completeNext()
        await waitUntil { !control.isApplyingLidSleep }
        XCTAssertFalse(control.isPreventingLidSleep)
        XCTAssertEqual(control.notice, .turnedOffLowBattery)
    }

    func testDisableRequestedWhileEnableInFlightWins() async {
        let client = ControllableClient(autoComplete: false)
        let control = make(client: client)
        control.setLidSleep(true)
        await waitUntil { client.pendingCount == 1 }
        control.setLidSleep(false)
        client.completeNext()
        await waitUntil { client.pendingCount == 1 }
        client.completeNext()
        await waitUntil { !control.isApplyingLidSleep }
        XCTAssertFalse(control.isPreventingLidSleep)
        XCTAssertEqual(client.setCalls.last, false)
    }

    func testFailedEnableLeavesConsistentState() async {
        let client = ControllableClient(failSetCount: 1)
        let ownership = ProbeOwnership()
        let control = make(client: client, ownership: ownership)
        control.setLidSleep(true)
        await waitUntil { !control.isApplyingLidSleep && control.lastError != nil }
        XCTAssertFalse(control.isPreventingLidSleep)
        XCTAssertFalse(ownership.ownsDisableSleep)
        XCTAssertFalse(client.disableSleep)
    }

    func testRapidToggleConvergesToOff() async {
        let client = ControllableClient()
        let control = make(client: client)
        control.setLidSleep(true)
        control.setLidSleep(false)
        await waitUntil { !control.isApplyingLidSleep }
        XCTAssertFalse(control.isPreventingLidSleep)
        XCTAssertFalse(client.disableSleep)
        // True→false coalesced before the worker ran, so no write is also valid.
        XCTAssertTrue(client.setCalls.isEmpty || client.setCalls.last == false)
    }

    func testForeignDisableSleepIsNotClaimed() async {
        let client = ControllableClient(disableSleep: true)
        let ownership = ProbeOwnership(owns: false)
        let control = make(client: client, ownership: ownership)
        control.setLidSleep(true)
        await waitUntil { control.lidSleepExternalState == .managedExternally }
        XCTAssertEqual(control.lidSleepExternalState, .managedExternally)
        XCTAssertNil(control.lastError, "external ownership is guidance, not a red error")
        XCTAssertTrue(client.setCalls.isEmpty)
        XCTAssertFalse(ownership.ownsDisableSleep)
        XCTAssertFalse(control.isPreventingLidSleep)
        XCTAssertTrue(client.disableSleep)
    }

    func testStaleOwnershipMarkerWithSystemOffStillEnables() async {
        let client = ControllableClient(disableSleep: false)
        let ownership = ProbeOwnership(owns: true)
        let control = make(client: client, ownership: ownership)
        control.setLidSleep(true)
        await waitUntil { control.isPreventingLidSleep }
        XCTAssertTrue(control.isPreventingLidSleep)
        XCTAssertEqual(client.setCalls, [true])
    }

    func testReadFailureRefusesEnable() async {
        let client = ControllableClient(readThrows: true)
        let control = make(client: client)
        control.setLidSleep(true)
        await waitUntil { control.lidSleepExternalState == .stateUnreadable }
        XCTAssertEqual(control.lidSleepExternalState, .stateUnreadable)
        XCTAssertTrue(client.setCalls.isEmpty)
        XCTAssertFalse(control.isPreventingLidSleep)
    }

    func testTimerCloseFailureRetriesThenSucceeds() async {
        let client = ControllableClient()
        let control = make(client: client)
        control.setLidSleep(true)
        await waitUntil { control.isPreventingLidSleep }
        client.setFailSetCount(1)
        control.lidTimerFired()
        await waitUntil { !control.isPreventingLidSleep }
        XCTAssertFalse(control.isPreventingLidSleep)
        XCTAssertFalse(client.disableSleep)
        XCTAssertEqual(client.setCalls.last, false)
    }

    func testTimerClosePersistentFailureStaysOnAndRecovers() async {
        let client = ControllableClient()
        let ownership = ProbeOwnership()
        let control = make(client: client, ownership: ownership)
        control.setLidSleep(true)
        await waitUntil { control.isPreventingLidSleep }
        client.setFailSetCount(99)
        control.lidTimerFired()
        await waitUntil { !control.isApplyingLidSleep && control.lastError != nil }
        XCTAssertTrue(control.isPreventingLidSleep)
        XCTAssertTrue(control.needsTerminationCleanup)
    }

    func testOldHelperBlocksWrites() async {
        let client = ControllableClient(version: 2)
        let control = make(client: client)
        control.start()
        await waitUntil { control.helperCapability == .needsUpdate }
        XCTAssertEqual(control.helperCapability, .needsUpdate)
        XCTAssertEqual(control.lidUnavailableReason, .helperNeedsUpdate)
        control.setLidSleep(true)
        await waitUntil { control.helperCapability == .needsUpdate }
        XCTAssertTrue(client.setCalls.isEmpty)
    }

    func testVersionQueryFailureMarksNeedsUpdate() async {
        let client = ControllableClient(versionThrows: true)
        let control = make(client: client)
        control.start()
        await waitUntil { control.helperCapability == .needsUpdate }
        XCTAssertEqual(control.helperCapability, .needsUpdate)
    }
}
