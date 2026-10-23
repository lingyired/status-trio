import XCTest
@testable import StatusTrioCore

@MainActor
final class DDCVolumeCoordinatorTests: XCTestCase {
    func testSelectionImmediatelyReadsAndEmitsValidatedScalar() async {
        let transport = FakeDDCTransport()
        transport.reply = DDCVolumeReply(current: 50, maximum: 100)
        var updates: [DDCVolumeUpdate] = []
        let coordinator = DDCVolumeCoordinator(transport: transport) { updates.append($0) }

        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await waitUntil("selection read callback") { updates.contains { $0.scalar == 0.5 } }
        XCTAssertEqual(updates.last?.outputID, 93)
        XCTAssertEqual(updates.last?.uid, "DISPLAY-A")
        coordinator.stop()
    }

    func testPollingCadenceAndWakePerformFreshRead() async {
        let clock = ManualDDCClock()
        let transport = FakeDDCTransport()
        transport.reply = DDCVolumeReply(current: 70, maximum: 100)
        var updates: [DDCVolumeUpdate] = []
        // The default 2 s read watchdog sleeps on this same clock, so it would
        // share a duration with the first backoff interval and a duration-keyed
        // release could resume the watchdog instead of the poll timer. Keep it
        // out of the way here; watchdog behaviour has its own tests.
        let coordinator = DDCVolumeCoordinator(
            transport: transport,
            readWatchdog: .seconds(600),
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await waitUntil("initial read callback") { updates.contains { $0.scalar == 0.7 } }
        await waitForClock(clock, .seconds(10), "closed poll timer")

        coordinator.setDisplayAsleep(true)
        let readsBeforeWake = transport.readCount
        coordinator.setDisplayAsleep(false)
        await waitUntil("wake read entered worker") { transport.readCount > readsBeforeWake }
        await waitUntil("wake read callback for new generation") { updates.contains { $0.generation == coordinator.generation && $0.scalar == 0.7 } }

        coordinator.setDetailsVisible(true)
        let readsBeforeOpen = transport.readCount
        await waitUntil("open details immediate read") { transport.readCount > readsBeforeOpen }
        await waitForClock(clock, .seconds(2), "visible poll timer")

        let resolutions = transport.resolveCount
        coordinator.topologyChanged()
        await waitUntil("topology read resolves same UID again") { transport.resolveCount > resolutions }
        coordinator.stop()
        await clock.cancelAll()
    }

    func testFailedReadsBackOffAndCapAtSixtySeconds() async {
        let clock = ManualDDCClock()
        let transport = FakeDDCTransport()
        transport.failReads = 8
        // The default 2 s read watchdog sleeps on this same clock, so it would
        // share a duration with the first backoff interval and a duration-keyed
        // release could resume the watchdog instead of the poll timer. Keep it
        // out of the way here; watchdog behaviour has its own tests.
        let coordinator = DDCVolumeCoordinator(
            transport: transport,
            readWatchdog: .seconds(600),
            sleep: { try await clock.sleep($0) }
        ) { _ in }
        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        for interval in [Duration.seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(32), .seconds(60), .seconds(60)] {
            await waitForClock(clock, interval, "failed-read poll at \(interval)")
            let readsBefore = transport.readCount
            await clock.release(interval)
            await waitUntil("next failed read") { transport.readCount > readsBefore }
        }
        coordinator.stop()
        await clock.cancelAll()
    }

    func testSuccessfulReadResetsFailureBackoff() async {
        let clock = ManualDDCClock()
        let transport = FakeDDCTransport()
        transport.failReads = 3
        // The default 2 s read watchdog sleeps on this same clock, so it would
        // share a duration with the first backoff interval and a duration-keyed
        // release could resume the watchdog instead of the poll timer. Keep it
        // out of the way here; watchdog behaviour has its own tests.
        let coordinator = DDCVolumeCoordinator(
            transport: transport,
            readWatchdog: .seconds(600),
            sleep: { try await clock.sleep($0) }
        ) { _ in }
        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        for interval in [Duration.seconds(2), .seconds(4)] {
            await waitForClock(clock, interval, "failed poll at \(interval)")
            await clock.release(interval)
        }
        transport.reply = DDCVolumeReply(current: 40, maximum: 100)
        await waitForClock(clock, .seconds(8), "third failed poll")
        await clock.release(.seconds(8))
        await waitUntil("successful recovery read") { transport.readCount >= 4 }
        await waitForClock(clock, .seconds(10), "success poll interval")
        transport.reply = nil
        await clock.release(.seconds(10))
        await waitForClock(clock, .seconds(2), "backoff resets to two seconds after success")
        coordinator.stop()
        await clock.cancelAll()
    }

    func testDebounceWaitsForFull150MillisecondsAndWritesLatestValue() async {
        let clock = ManualDDCClock()
        let transport = FakeDDCTransport()
        transport.reply = DDCVolumeReply(current: 50, maximum: 100)
        let coordinator = DDCVolumeCoordinator(transport: transport, sleep: { try await clock.sleep($0) }) { _ in }
        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await waitUntil("initial read") { transport.readCount == 1 }
        coordinator.setVolume(0.2)
        coordinator.setVolume(0.4)
        coordinator.setVolume(0.8)
        await waitForClock(clock, .milliseconds(150), "150ms debounce timer")
        XCTAssertTrue(transport.writeValues.isEmpty, "No write should happen before the debounce clock advances")
        await clock.release(.milliseconds(150))
        await waitUntil("debounced write") { transport.writeValues == [80] }
        await waitUntil("post-write readback") { transport.readCount >= 2 }
        coordinator.stop()
        await clock.cancelAll()
    }

    func testFlushPendingVolumeBypassesDebounceForFinalDragValue() async {
        let clock = ManualDDCClock()
        let transport = FakeDDCTransport()
        transport.reply = DDCVolumeReply(current: 50, maximum: 100)
        let coordinator = DDCVolumeCoordinator(transport: transport, sleep: { try await clock.sleep($0) }) { _ in }
        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await waitUntil("initial read") { transport.readCount == 1 }
        coordinator.setVolume(0.9)
        coordinator.flushPendingVolume()
        await waitUntil("flushed final drag value") { transport.writeValues == [90] }
        coordinator.stop()
        await clock.cancelAll()
    }

    func testSleepInvalidatesQueuedWriteAndPreSleepReadAcrossWake() async {
        let transport = FakeDDCTransport()
        transport.reply = DDCVolumeReply(current: 20, maximum: 100)
        transport.blockNextRead()
        var updates: [DDCVolumeUpdate] = []
        let coordinator = DDCVolumeCoordinator(transport: transport, readWatchdog: .milliseconds(20)) { updates.append($0) }
        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await waitUntil("pre-sleep read is blocked") { transport.blockedReadCount == 1 }
        coordinator.setVolume(0.8)
        coordinator.flushPendingVolume()
        coordinator.setDisplayAsleep(true)
        transport.reply = DDCVolumeReply(current: 60, maximum: 100)
        coordinator.setDisplayAsleep(false)
        await waitUntil("wake-generation watchdog reports unavailable while old worker is blocked") {
            updates.contains { $0.generation == coordinator.generation && $0.scalar == nil }
        }
        transport.releaseBlockedRead()

        await waitUntil("wake read runs after old read") { transport.readCount >= 2 }
        await waitUntil("fresh-generation wake result") { updates.contains { $0.generation == coordinator.generation && $0.scalar == 0.6 } }
        XCTAssertTrue(transport.writeValues.isEmpty, "The pre-sleep queued write must fail its generation check")
        XCTAssertFalse(updates.contains { $0.generation < coordinator.generation && $0.scalar != nil }, "The late pre-sleep reply must be ignored")
        XCTAssertEqual(transport.maximumConcurrentReads, 1)
        coordinator.stop()
    }

    func testInvalidatedQueuedReadCompletesAcrossSelectionSleepAndTopology() async {
        for action in ["selection", "sleep-wake", "topology"] {
            let validationGate = ReadValidationGate()
            let transport = FakeDDCTransport()
            transport.reply = DDCVolumeReply(current: 55, maximum: 100)
            var updates: [DDCVolumeUpdate] = []
            let coordinator = DDCVolumeCoordinator(
                transport: transport,
                beforeReadValidation: { validationGate.enterAndWait() }
            ) { updates.append($0) }
            coordinator.select(outputID: 93, uid: "DISPLAY-A")
            await waitUntil("first read paused before identity validation") { validationGate.hasEntered }

            if action == "selection" {
                coordinator.select(outputID: 94, uid: "DISPLAY-B")
            } else if action == "sleep-wake" {
                coordinator.setDisplayAsleep(true)
                coordinator.setDisplayAsleep(false)
            } else {
                coordinator.topologyChanged()
            }
            validationGate.release()
            await waitUntil("fresh \(action) read completes") {
                updates.contains { $0.generation == coordinator.generation && $0.scalar == 0.55 }
            }
            XCTAssertEqual(transport.readCount, 1, "The stale queued request must be rejected before DDC I/O")
            XCTAssertEqual(transport.resolveCount, 1)
            XCTAssertEqual(updates.last?.uid, action == "selection" ? "DISPLAY-B" : "DISPLAY-A")
            coordinator.stop()
            await coordinator.waitForWorkerIdle()
        }
    }

    func testSelectionAlternatingABAUsesAFreshlyResolvedTargetEachTime() async {
        let transport = FakeDDCTransport()
        transport.reply = DDCVolumeReply(current: 50, maximum: 100)
        var updates: [DDCVolumeUpdate] = []
        let coordinator = DDCVolumeCoordinator(transport: transport) { updates.append($0) }

        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await waitUntil("A read") { transport.readServiceTags.count >= 1 }
        coordinator.select(outputID: 94, uid: "DISPLAY-B")
        await waitUntil("B read") { transport.readServiceTags.count >= 2 }
        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        // Wait for the matching emission, not just for the transport to be hit:
        // `readServiceTags` grows on the worker queue, so the main-actor publish
        // for this generation can still be in flight when the wait returns.
        await waitUntil("A re-read emitted for the current generation") {
            transport.readServiceTags.count >= 3 && updates.last?.generation == coordinator.generation
        }

        XCTAssertEqual(transport.resolveCount, 3, "Each selection must resolve its own target")
        XCTAssertEqual(
            Set(transport.readServiceTags.prefix(3)).count, 3,
            "A→B→A must re-resolve instead of reusing a stale service"
        )
        XCTAssertEqual(updates.last?.uid, "DISPLAY-A")
        coordinator.stop()
    }

    func testSameUIDTopologyChangeResolvesAFreshService() async {
        let transport = FakeDDCTransport()
        transport.reply = DDCVolumeReply(current: 50, maximum: 100)
        var updates: [DDCVolumeUpdate] = []
        let coordinator = DDCVolumeCoordinator(transport: transport) { updates.append($0) }

        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await waitUntil("initial read") { transport.readServiceTags.count == 1 }
        coordinator.topologyChanged()
        await waitUntil("post-topology read") { transport.readServiceTags.count >= 2 }

        XCTAssertEqual(transport.resolveCount, 2, "A same-UID topology change must re-resolve, not reuse the cached service")
        XCTAssertEqual(
            Array(transport.readServiceTags.prefix(2)), [0, 1],
            "The post-topology read must run against the freshly resolved service"
        )
        coordinator.stop()
    }

    func testUnresolvableTargetNeverWritesAndReportsUnavailable() async {
        let transport = FakeDDCTransport()
        transport.failResolve = true
        var updates: [DDCVolumeUpdate] = []
        let coordinator = DDCVolumeCoordinator(transport: transport) { updates.append($0) }

        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await waitUntil("unavailable read") { updates.contains { $0.scalar == nil } }
        coordinator.setVolume(0.8)
        coordinator.flushPendingVolume()
        await coordinator.waitForWorkerIdle()

        XCTAssertTrue(transport.writeValues.isEmpty, "An unresolvable target must never be written to")
        XCTAssertEqual(transport.readServiceTags, [], "No physical read may run without a resolved service")
        coordinator.stop()
    }

    func testProtocolFailureWithoutAValidatedReplyNeverWrites() async {
        // The service resolves, but no read ever returns a validated reply
        // (all profiles failed). The slider must stay unavailable and no
        // Set VCP may be attempted.
        let transport = FakeDDCTransport()
        var updates: [DDCVolumeUpdate] = []
        let coordinator = DDCVolumeCoordinator(transport: transport) { updates.append($0) }

        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await waitUntil("failed read reports unavailable") { updates.contains { $0.scalar == nil } }
        coordinator.setVolume(0.8)
        coordinator.flushPendingVolume()
        await coordinator.waitForWorkerIdle()

        XCTAssertTrue(transport.writeValues.isEmpty, "No write may run without a validated read reply")
        XCTAssertFalse(updates.contains { $0.scalar != nil }, "No percentage may be published without a validated reply")
        XCTAssertEqual(updates.last?.capability, .unavailable(.replyReadFailed))
        coordinator.stop()
    }

    func testWriteAcknowledgementAndReadBackVerificationAreSeparateStates() async {
        let transport = FakeDDCTransport()
        transport.reply = DDCVolumeReply(current: 50, maximum: 100)
        transport.writeEchoesValue = true
        var updates: [DDCVolumeUpdate] = []
        let coordinator = DDCVolumeCoordinator(transport: transport) { updates.append($0) }

        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await waitUntil("initial read") { updates.contains { $0.capability == .readable(DDCVolumeReply(current: 50, maximum: 100)) } }

        coordinator.setVolume(0.8)
        coordinator.flushPendingVolume()
        await waitUntil("verified read-back") {
            updates.contains { $0.capability == .writeVerified(DDCVolumeReply(current: 80, maximum: 100)) }
        }
        XCTAssertEqual(transport.writeValues, [80])
        coordinator.stop()
    }

    func testAcknowledgedWriteThatTheDisplayDidNotApplyIsNotReportedAsVerified() async {
        // I2C acceptance is not evidence that the register changed: the
        // read-back is what decides, and a mismatch must not be called success.
        let transport = FakeDDCTransport()
        transport.reply = DDCVolumeReply(current: 50, maximum: 100)
        var updates: [DDCVolumeUpdate] = []
        let coordinator = DDCVolumeCoordinator(transport: transport) { updates.append($0) }

        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await waitUntil("initial read") { updates.contains { $0.scalar == 0.5 } }

        coordinator.setVolume(0.8)
        coordinator.flushPendingVolume()
        await waitUntil("mismatching read-back") {
            updates.contains { $0.capability == .writeUnverified(DDCVolumeReply(current: 50, maximum: 100)) }
        }

        XCTAssertEqual(transport.writeValues, [80], "The write was acknowledged, so it must have been attempted exactly once")
        XCTAssertFalse(
            updates.contains { $0.capability == .writeVerified(DDCVolumeReply(current: 50, maximum: 100)) },
            "A display that stayed at 50 must never be reported as a verified write"
        )
        coordinator.stop()
    }

    func testFailedWriteStopsPublishingAValueInsteadOfKeepingTheOptimisticScalar() async {
        let transport = FakeDDCTransport()
        transport.reply = DDCVolumeReply(current: 50, maximum: 100)
        transport.failWrites = true
        var updates: [DDCVolumeUpdate] = []
        let coordinator = DDCVolumeCoordinator(transport: transport) { updates.append($0) }

        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await waitUntil("initial read") { updates.contains { $0.scalar == 0.5 } }

        coordinator.setVolume(0.8)
        coordinator.flushPendingVolume()
        await waitUntil("failed write publishes unavailable") {
            updates.contains { $0.capability == .unavailable(.requestWriteFailed) }
        }

        XCTAssertNil(updates.last?.scalar)
        coordinator.stop()
    }

    func testWatchdogPublishesATimeoutInsteadOfAGenericUnavailable() async {
        let transport = FakeDDCTransport()
        transport.reply = DDCVolumeReply(current: 35, maximum: 100)
        transport.blockNextRead()
        var updates: [DDCVolumeUpdate] = []
        let coordinator = DDCVolumeCoordinator(transport: transport, readWatchdog: .milliseconds(20)) { updates.append($0) }

        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await waitUntil("watchdog reports a timeout") {
            updates.contains { $0.capability == .unavailable(.timeout) }
        }
        transport.releaseBlockedRead()
        coordinator.stop()
    }

    func testSleepCancelsDebouncedWriteBeforeWake() async {
        let clock = ManualDDCClock()
        let transport = FakeDDCTransport()
        transport.reply = DDCVolumeReply(current: 20, maximum: 100)
        var debounceSettledCount = 0
        let coordinator = DDCVolumeCoordinator(
            transport: transport,
            onDebounceSettled: { debounceSettledCount += 1 },
            sleep: { try await clock.sleep($0) }
        ) { _ in }
        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await waitUntil("initial read") { transport.readCount == 1 }
        coordinator.setVolume(0.8)
        await waitForClock(clock, .milliseconds(150), "pending debounce")
        coordinator.setDisplayAsleep(true)
        coordinator.setDisplayAsleep(false)
        await waitUntil("canceled debounce task acknowledges completion") { debounceSettledCount == 1 }
        await waitUntil("wake read") { transport.readCount >= 2 }
        await clock.advance(by: .milliseconds(150))
        await coordinator.waitForWorkerIdle()
        XCTAssertTrue(transport.writeValues.isEmpty, "Advancing the canceled pre-sleep debounce after wake must not write")
        coordinator.stop()
        await clock.cancelAll()
    }

    func testStopAndTopologyChangeInvalidateQueuedWrites() async {
        for action in ["stop", "topology"] {
            let transport = FakeDDCTransport()
            transport.reply = DDCVolumeReply(current: 20, maximum: 100)
            transport.blockNextRead()
            var updates: [DDCVolumeUpdate] = []
            var readCompletions: [UInt64] = []
            let coordinator = DDCVolumeCoordinator(
                transport: transport,
                readWatchdog: .seconds(30),
                onReadCompletion: { _, _, generation in readCompletions.append(generation) }
            ) { updates.append($0) }
            coordinator.select(outputID: 93, uid: "DISPLAY-A")
            await waitUntil("blocked read for \(action)") { transport.blockedReadCount == 1 }
            let oldGeneration = coordinator.generation
            coordinator.setVolume(0.8)
            coordinator.flushPendingVolume()
            if action == "stop" { coordinator.stop() } else { coordinator.topologyChanged() }
            let currentGeneration = coordinator.generation
            transport.releaseBlockedRead()
            if action == "stop" {
                await waitUntil("stopped read completion acknowledgment") { readCompletions.contains(oldGeneration) }
                XCTAssertTrue(updates.isEmpty, "Stop must suppress the released read callback")
            } else {
                await waitUntil("topology refresh and stale completion acknowledgments") {
                    readCompletions.contains(oldGeneration)
                        && readCompletions.contains(currentGeneration)
                        && updates.contains { $0.generation == currentGeneration && $0.scalar == 0.2 }
                }
                XCTAssertEqual(updates.map(\.generation), [currentGeneration], "No stale-generation topology update may be published")
            }
            await coordinator.waitForWorkerIdle()
            XCTAssertTrue(transport.writeValues.isEmpty, "Queued write must be invalidated by \(action) after completion acknowledgment")
            coordinator.stop()
            await coordinator.waitForWorkerIdle()
        }
    }

    func testStalledReadWatchdogMarksUnavailableWithoutOverlappingWorker() async {
        let transport = FakeDDCTransport()
        transport.reply = DDCVolumeReply(current: 35, maximum: 100)
        var updates: [DDCVolumeUpdate] = []
        let coordinator = DDCVolumeCoordinator(transport: transport, readWatchdog: .milliseconds(20)) { updates.append($0) }
        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await waitUntil("first successful read") { updates.contains { $0.scalar == 0.35 } }
        transport.blockNextRead()
        coordinator.refresh()
        await waitUntil("second read is blocked") { transport.blockedReadCount == 1 }
        await waitUntil("watchdog emitted unavailable") { updates.contains { $0.scalar == nil && $0.generation == coordinator.generation } }
        XCTAssertEqual(transport.maximumConcurrentReads, 1)
        XCTAssertEqual(transport.readCount, 2, "The watchdog must not start a second physical read")
        transport.releaseBlockedRead()
        coordinator.stop()
    }

    func testSwitchBeforeDebounceDropsQueuedWrite() async {
        let clock = ManualDDCClock()
        let transport = FakeDDCTransport()
        var debounceSettledCount = 0
        let coordinator = DDCVolumeCoordinator(
            transport: transport,
            onDebounceSettled: { debounceSettledCount += 1 },
            sleep: { try await clock.sleep($0) }
        ) { _ in }
        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        coordinator.setVolume(0.8)
        let debounceStarted = await clock.waitForRecorded(.milliseconds(150))
        XCTAssertTrue(debounceStarted, "Debounce timer must start before output switching")
        coordinator.select(outputID: 94, uid: "DISPLAY-B")
        await waitUntil("canceled output debounce acknowledgment") { debounceSettledCount == 1 }
        let oldDebounceRemains = await clock.hasPending(.milliseconds(150))
        XCTAssertFalse(oldDebounceRemains, "Selection must cancel the old output debounce")
        await clock.advance(by: .milliseconds(150))
        await coordinator.waitForWorkerIdle()
        XCTAssertTrue(transport.writeValues.isEmpty, "Advancing the settled old-output debounce must not write")
        coordinator.stop()
        await clock.cancelAll()
    }

    /// Waits for a predicate on coordinator state.
    ///
    /// The budget is wall clock, not a number of attempts. It used to be
    /// `200 × 5 ms`, which is only a second when the machine is idle: on a loaded
    /// runner each `Task.sleep(5ms)` can take tens of milliseconds and the budget
    /// was gone before the coordinator's work was scheduled, so a correct
    /// implementation failed the test. The timeout here is a hang guard; a slow
    /// machine makes the wait longer, never the assertion false.
    private func waitUntil(_ description: String, file: StaticString = #filePath, line: UInt = #line, _ predicate: @escaping @MainActor () -> Bool) async {
        let started = ContinuousClock.now
        let deadline = started.advanced(by: .seconds(10))
        while !predicate(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
        let waited = ContinuousClock.now - started
        XCTAssertTrue(predicate(), "Timed out waiting for \(description) after \(waited)", file: file, line: line)
    }

    private func waitForClock(_ clock: ManualDDCClock, _ duration: Duration, _ description: String, file: StaticString = #filePath, line: UInt = #line) async {
        let result = await clock.waitForPending(duration)
        XCTAssertTrue(result, "Timed out waiting for \(description)", file: file, line: line)
    }
}

private final class ReadValidationGate: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private var shouldBlock = true
    private var entered = false
    var hasEntered: Bool { lock.withLock { entered } }

    func enterAndWait() {
        let shouldWait = lock.withLock { () -> Bool in
            guard shouldBlock else { return false }
            shouldBlock = false
            entered = true
            return true
        }
        if shouldWait { releaseSemaphore.wait() }
    }

    func release() { releaseSemaphore.signal() }
}

private final class FakeDDCTransport: DDCVolumeTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var storedReply: DDCVolumeReply?
    private var storedFailReads = 0
    private var storedWriteValues: [UInt16] = []
    private var storedOperations: [String] = []
    private var storedReadCount = 0
    private var storedResolveCount = 0
    private var storedMaximumConcurrentReads = 0
    private var activeReads = 0
    private var gateNextRead = false
    private var blockedReadCountStorage = 0
    private let blockedRead = DispatchSemaphore(value: 0)
    private var storedFailResolve = false
    private var storedFailWrites = false
    private var storedWriteEchoesValue = false
    private var storedNextServiceTag = 0
    private var serviceTagByTarget: [ObjectIdentifier: Int] = [:]
    private var storedReadServiceTags: [Int] = []

    var reply: DDCVolumeReply? { get { lock.withLock { storedReply } } set { lock.withLock { storedReply = newValue } } }
    var failReads: Int { get { lock.withLock { storedFailReads } } set { lock.withLock { storedFailReads = newValue } } }
    var writeValues: [UInt16] { lock.withLock { storedWriteValues } }
    var operations: [String] { lock.withLock { storedOperations } }
    var readCount: Int { lock.withLock { storedReadCount } }
    var resolveCount: Int { lock.withLock { storedResolveCount } }
    var maximumConcurrentReads: Int { lock.withLock { storedMaximumConcurrentReads } }
    var blockedReadCount: Int { lock.withLock { blockedReadCountStorage } }
    var failResolve: Bool { get { lock.withLock { storedFailResolve } } set { lock.withLock { storedFailResolve = newValue } } }
    var failWrites: Bool { get { lock.withLock { storedFailWrites } } set { lock.withLock { storedFailWrites = newValue } } }
    /// Simulates a display that applies what it was sent, so the read-back can
    /// agree with the requested register value.
    var writeEchoesValue: Bool { get { lock.withLock { storedWriteEchoesValue } } set { lock.withLock { storedWriteEchoesValue = newValue } } }
    var readServiceTags: [Int] { lock.withLock { storedReadServiceTags } }

    func blockNextRead() { lock.withLock { gateNextRead = true } }
    func releaseBlockedRead() { blockedRead.signal() }

    func resolve(uid: String) -> DDCDisplayTarget? {
        lock.withLock {
            storedOperations.append("resolve")
            storedResolveCount += 1
            guard !storedFailResolve else { return nil }
            let target = DDCDisplayTarget(uid: uid, service: nil)
            serviceTagByTarget[ObjectIdentifier(target)] = storedNextServiceTag
            storedNextServiceTag += 1
            return target
        }
    }

    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult {
        let shouldBlock = lock.withLock { () -> Bool in
            storedOperations.append("read")
            storedReadCount += 1
            activeReads += 1
            storedMaximumConcurrentReads = max(storedMaximumConcurrentReads, activeReads)
            storedReadServiceTags.append(serviceTagByTarget[ObjectIdentifier(target)] ?? -1)
            if gateNextRead { gateNextRead = false; blockedReadCountStorage += 1; return true }
            return false
        }
        if shouldBlock { blockedRead.wait() }
        return lock.withLock {
            activeReads -= 1
            if storedFailReads > 0 { storedFailReads -= 1; return .failure(.replyReadFailed) }
            guard let storedReply else { return .failure(.replyReadFailed) }
            return .reply(storedReply)
        }
    }

    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool {
        lock.withLock {
            storedOperations.append("write")
            storedWriteValues.append(value)
            guard !storedFailWrites else { return false }
            if storedWriteEchoesValue, let current = storedReply {
                storedReply = DDCVolumeReply(current: value, maximum: current.maximum)
            }
            return true
        }
    }
}

/// Records cancellations synchronously, so a cancelled sleep can never satisfy a
/// wait or absorb a release.
///
/// `onCancel` runs on whatever thread cancels the task and cannot touch actor
/// state, so the actor-side reap is always a hop behind: `timerTask?.cancel()`
/// marks the id here immediately, while the entry is still in `entries`.
/// `release(_:)` matches by duration, so without the mark it could resume an
/// entry nobody is waiting on and leave the live timer parked for the rest of
/// the test.
///
/// This is hardening of the double, not the fix for the reported failure: the
/// suite stays green for 15 solo runs and 10 loaded runs with the box removed.
/// The load-bearing fixes are the wall-clock deadline in `waitUntil` and keeping
/// the default 2 s read watchdog off this clock in the backoff tests.
private final class CancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var ids = Set<UUID>()

    func mark(_ id: UUID) { lock.withLock { _ = ids.insert(id) } }
    func consume(_ id: UUID) -> Bool { lock.withLock { ids.remove(id) != nil } }
    func contains(_ id: UUID) -> Bool { lock.withLock { ids.contains(id) } }
}

private actor ManualDDCClock {
    private struct Entry {
        let id: UUID
        let duration: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }
    private var entries: [Entry] = []
    private var cancelledBeforeRegistration = Set<UUID>()
    private var recordedDurations: [Duration] = []
    /// One stream per waiter. `sleep` signals here instead of the waiter polling a
    /// snapshot, so a registration wakes it directly.
    private var waiters: [UUID: AsyncStream<Void>.Continuation] = [:]
    private let cancellation = CancellationBox()

    /// Entries a cancelling thread has already given up on. They stay in
    /// `entries` until the actor hop reaps them and must never satisfy a wait or
    /// absorb a release.
    private var liveEntries: [Entry] { entries.filter { !cancellation.contains($0.id) } }

    private func signal() {
        for continuation in waiters.values { continuation.yield() }
    }

    /// Waits for a condition over the clock's own state, woken by `signal`.
    ///
    /// The deadline is a hang guard, not the condition: if the coordinator's task
    /// is starved the wait simply takes longer. Polling a snapshot could not tell
    /// those two cases apart, which is exactly how a loaded machine turned a
    /// correct implementation into a failing test.
    private func wait(within limit: Duration, until condition: () -> Bool) async -> Bool {
        if condition() { return true }
        let deadline = ContinuousClock.now.advanced(by: limit)
        while ContinuousClock.now < deadline {
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            let id = UUID()
            waiters[id] = continuation
            let remaining = ContinuousClock.now.duration(to: deadline)
            _ = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    var iterator = stream.makeAsyncIterator()
                    _ = await iterator.next()
                    return true
                }
                group.addTask {
                    try? await Task.sleep(for: remaining)
                    return false
                }
                let first = await group.next() ?? false
                group.cancelAll()
                return first
            }
            waiters[id] = nil
            if condition() { return true }
        }
        return condition()
    }

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                recordedDurations.append(duration)
                if Task.isCancelled || cancellation.consume(id) || cancelledBeforeRegistration.remove(id) != nil {
                    continuation.resume(throwing: CancellationError())
                } else {
                    entries.append(Entry(id: id, duration: duration, continuation: continuation))
                }
                signal()
            }
        } onCancel: {
            // Synchronous, so a release on the test side cannot pick this entry
            // in the window before the hop below reaps it.
            cancellation.mark(id)
            Task { await self.cancel(id) }
        }
    }

    func hasPending(_ duration: Duration) -> Bool { liveEntries.contains(where: { $0.duration == duration }) }

    func waitForPending(_ duration: Duration) async -> Bool {
        await wait(within: .seconds(30)) { self.liveEntries.contains { $0.duration == duration } }
    }

    var pendingDurations: [Duration] { liveEntries.map(\.duration) }
    var durations: [Duration] { recordedDurations }
    func waitForRecorded(_ duration: Duration) async -> Bool {
        await wait(within: .seconds(60)) { self.recordedDurations.contains(duration) }
    }

    func advance(by duration: Duration) {
        release(duration)
    }

    func release(_ duration: Duration) {
        guard let index = entries.firstIndex(where: { $0.duration == duration && !cancellation.contains($0.id) }) else { return }
        entries.remove(at: index).continuation.resume()
    }

    func cancelAll() {
        let pending = entries
        entries.removeAll()
        pending.forEach { $0.continuation.resume(throwing: CancellationError()) }
    }

    private func cancel(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            cancelledBeforeRegistration.insert(id)
            return
        }
        entries.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
