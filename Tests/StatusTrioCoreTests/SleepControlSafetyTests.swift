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
    private var _landSetButThrow = false
    private var _failReadCount = 0
    private var _failReadOnCall: Int?
    private var _suspendReads = false
    private var _pendingReads: [CheckedContinuation<Bool, Error>] = []
    private var _helperUnavailableReadCount = 0

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
    /// Makes the next write land in the helper but answer with an error, the
    /// shape of a reply lost after the privileged side already applied it.
    func setLandSetButThrow(_ v: Bool) { lock.withLock { _landSetButThrow = v } }
    func setFailReadCount(_ v: Int) { lock.withLock { _failReadCount = v } }
    func setFailReadOnCall(_ call: Int) { lock.withLock { _failReadOnCall = call } }
    func setSuspendReads(_ v: Bool) { lock.withLock { _suspendReads = v } }
    func setReadThrows(_ v: Bool) { lock.withLock { _readThrows = v } }
    /// Makes the next `n` reads fail as a cold/unreachable helper (XPC timeout),
    /// the transient error the controller must retry before reporting failure.
    func setHelperUnavailableReadCount(_ v: Int) { lock.withLock { _helperUnavailableReadCount = v } }
    var pendingReadCount: Int { lock.withLock { _pendingReads.count } }
    func completeNextRead(_ value: Bool) {
        let next = lock.withLock { () -> CheckedContinuation<Bool, Error>? in
            guard !_pendingReads.isEmpty else { return nil }
            _disableSleep = value
            return _pendingReads.removeFirst()
        }
        next?.resume(returning: value)
    }

    func protocolVersion() async throws -> Int {
        try lock.withLock {
            if _versionThrows { throw Failure.failed }
            return _version
        }
    }
    func readDisableSleep() async throws -> Bool {
        enum Decision { case fail, helperUnavailable, complete(Bool), suspend }
        let decision: Decision = lock.withLock {
            _readCalls += 1
            if _helperUnavailableReadCount > 0 {
                _helperUnavailableReadCount -= 1
                return .helperUnavailable
            }
            if let failOn = _failReadOnCall, _readCalls == failOn { return .fail }
            if _failReadCount > 0 { _failReadCount -= 1; return .fail }
            if _readThrows { return .fail }
            if _suspendReads { return .suspend }
            return .complete(_disableSleep)
        }
        switch decision {
        case .fail: throw HighPowerModeClientError.rejected("read failed")
        case .helperUnavailable: throw HighPowerModeClientError.helperUnavailable
        case .complete(let value): return value
        case .suspend:
            return try await withCheckedThrowingContinuation { cont in
                lock.withLock { _pendingReads.append(cont) }
            }
        }
    }
    func setDisableSleep(_ enabled: Bool) async throws -> Bool {
        enum Decision { case fail, complete(Bool), suspend }
        let decision: Decision = lock.withLock {
            _setCalls.append(enabled)
            if _failSetCount > 0 { _failSetCount -= 1; return .fail }
            if _landSetButThrow {
                _landSetButThrow = false
                _disableSleep = enabled
                return .fail
            }
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
        ownership: ProbeOwnership = ProbeOwnership(),
        recoveryRetryDelay: TimeInterval = 2
    ) -> SleepControlController {
        SleepControlController(
            assertion: ProbeAssertion(),
            client: client,
            helperReadiness: readiness,
            ownership: ownership,
            lidDisableRetryDelays: [0, 0, 0],
            lidRecoveryRetryDelay: recoveryRetryDelay,
            lidReadRetryDelays: [0, 0]
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

    /// A cold helper that times out on the very first read must be retried and
    /// then enable normally — this is the #383 regression.
    func testColdStartReadTimeoutRetriesThenEnables() async {
        let client = ControllableClient()
        client.setHelperUnavailableReadCount(1)
        let control = make(client: client)
        control.setLidSleep(true)
        await waitUntil { control.isPreventingLidSleep }
        XCTAssertTrue(control.isPreventingLidSleep)
        XCTAssertNil(control.lidSleepExternalState, "a recovered read must not leave a notice")
        XCTAssertEqual(client.setCalls, [true])
        XCTAssertEqual(client.readCalls, 2, "the first timeout is retried once")
    }

    /// When the helper never answers, the copy must say it is starting rather
    /// than claiming the value is unreadable.
    func testPersistentReadTimeoutReportsHelperStarting() async {
        let client = ControllableClient()
        client.setHelperUnavailableReadCount(99)
        let control = make(client: client)
        control.setLidSleep(true)
        await waitUntil { control.lidSleepExternalState == .helperStarting }
        XCTAssertEqual(control.lidSleepExternalState, .helperStarting)
        XCTAssertTrue(client.setCalls.isEmpty)
        XCTAssertFalse(control.isPreventingLidSleep)
        XCTAssertEqual(client.readCalls, 3, "initial read plus the two bounded retries")
    }

    /// A later successful read clears a stale "unreadable" notice instead of
    /// leaving it hanging in the card.
    func testSuccessfulEnableClearsStaleUnreadableNotice() async {
        let client = ControllableClient(readThrows: true)
        let control = make(client: client)
        control.setLidSleep(true)
        await waitUntil { control.lidSleepExternalState == .stateUnreadable }
        await waitUntil { !control.isApplyingLidSleep }

        client.setReadThrows(false)
        control.setLidSleep(true)
        await waitUntil { control.isPreventingLidSleep }
        XCTAssertTrue(control.isPreventingLidSleep)
        XCTAssertNil(control.lidSleepExternalState)
        XCTAssertEqual(client.setCalls, [true])
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

    /// A reply lost after the privileged write already landed, followed by an
    /// unreadable status, must not be treated as "definitely off".
    func testLostEnableReplyKeepsRecoveryMarkerForNextLaunch() async {
        let client = ControllableClient()
        let ownership = ProbeOwnership()
        let control = make(client: client, ownership: ownership)
        client.setLandSetButThrow(true)
        client.setFailReadOnCall(2)

        control.setLidSleep(true)
        await waitUntil { !control.isApplyingLidSleep && control.lastError != nil }

        XCTAssertTrue(client.disableSleep)
        XCTAssertTrue(ownership.ownsDisableSleep)
        XCTAssertTrue(control.needsTerminationCleanup)
        XCTAssertFalse(control.isPreventingLidSleep)
        control.stop()

        // The next launch must confirm the system is off before dropping the
        // durable recovery marker.
        let restarted = make(client: client, ownership: ownership)
        restarted.start()
        await waitUntil { !ownership.ownsDisableSleep }
        XCTAssertFalse(client.disableSleep)
    }

    func testUnplugDuringInitialReadDoesNotWriteEnable() async {
        let client = ControllableClient()
        client.setSuspendReads(true)
        let control = make(client: client)
        control.allowsLidSleepOnBattery = false
        control.updatePowerState(battery: battery(connected: true))

        control.setLidSleep(true)
        await waitUntil { client.pendingReadCount == 1 }
        control.updatePowerState(battery: battery(connected: false))
        client.completeNextRead(false)
        await waitUntil { !control.isApplyingLidSleep }

        XCTAssertFalse(client.setCalls.contains(true))
        XCTAssertFalse(control.isPreventingLidSleep)
        XCTAssertFalse(client.disableSleep)
    }

    func testReadinessRecoveryDoesNotClearIntentionalLidSleep() async {
        let client = ControllableClient()
        let readiness = ProbeReadiness(isReady: true)
        let control = make(client: client, readiness: readiness)
        control.start()
        await waitUntil { control.helperCapability == .available }
        control.setLidSleep(true)
        await waitUntil { control.isPreventingLidSleep }
        XCTAssertEqual(client.setCalls, [true])

        readiness.setReady(false)
        await waitUntil { control.helperCapability == .unavailable }
        readiness.setReady(true)
        await waitUntil { control.helperCapability == .available }
        for _ in 0..<40 { await Task.yield() }

        XCTAssertTrue(control.isPreventingLidSleep)
        XCTAssertEqual(client.setCalls, [true])
        XCTAssertTrue(client.disableSleep)
    }

    // MARK: - Residual recovery must never act on a newer session

    func testSuspendedRecoveryReadDoesNotDisableNewSession() async {
        let client = ControllableClient(disableSleep: true)
        let ownership = ProbeOwnership(owns: true)
        let control = make(client: client, ownership: ownership)
        client.setSuspendReads(true)
        control.start()
        await waitUntil { client.pendingReadCount == 1 }

        // The user turns lid sleep on while the residual read is still out.
        client.setSuspendReads(false)
        control.setLidSleep(true)
        client.completeNextRead(true)
        await waitUntil { control.isPreventingLidSleep }

        XCTAssertFalse(client.setCalls.contains(false),
                       "recovery must not turn off a session the user just enabled")
        XCTAssertTrue(ownership.ownsDisableSleep)
        XCTAssertTrue(control.isPreventingLidSleep)
    }

    func testSuspendedRecoveryReadOffKeepsOwnershipForNewSession() async {
        let client = ControllableClient(disableSleep: true)
        let ownership = ProbeOwnership(owns: true)
        let control = make(client: client, ownership: ownership)
        client.setSuspendReads(true)
        control.start()
        await waitUntil { client.pendingReadCount == 1 }

        client.setSuspendReads(false)
        control.setLidSleep(true)
        client.completeNextRead(false)
        await waitUntil { control.isPreventingLidSleep }

        XCTAssertFalse(client.setCalls.contains(false))
        XCTAssertTrue(ownership.ownsDisableSleep,
                      "an off reading that raced a new session must keep the durable marker")
    }

    func testShutdownDuringSuspendedRecoveryReadWritesNothing() async {
        let client = ControllableClient(disableSleep: true)
        let ownership = ProbeOwnership(owns: true)
        let control = make(client: client, ownership: ownership)
        client.setSuspendReads(true)
        control.start()
        await waitUntil { client.pendingReadCount == 1 }

        control.stop()
        client.completeNextRead(true)
        await waitUntil { !control.isApplyingLidSleep }

        XCTAssertEqual(client.setCalls, [])
        XCTAssertTrue(ownership.ownsDisableSleep)
    }

    func testRecoveryRetryDoesNotServeANewerSession() async {
        let client = ControllableClient()
        let ownership = ProbeOwnership()
        let control = make(client: client, ownership: ownership, recoveryRetryDelay: 0.05)
        client.setLandSetButThrow(true)
        client.setFailReadOnCall(2)
        control.setLidSleep(true)
        await waitUntil { !control.isApplyingLidSleep && control.lastError != nil }
        XCTAssertTrue(control.needsTerminationCleanup)

        // The user retries and succeeds before the stale retry timer fires.
        control.setLidSleep(true)
        await waitUntil { control.isPreventingLidSleep }
        let settledCalls = client.setCalls
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(client.setCalls, settledCalls,
                       "a stale retry must not issue another write")
        XCTAssertTrue(control.isPreventingLidSleep)
    }
}
