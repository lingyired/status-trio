import AppKit
import Foundation
import XCTest
@testable import StatusTrioCore

/// The Bluetooth controller used to start one `system_profiler` run per caller
/// with nothing serializing them, and it kept polling after the popover that
/// needed the data was gone. These tests pin the read latch and the surface
/// gate that replaced both behaviours.
@MainActor
final class BluetoothPollingLifetimeTests: XCTestCase {
    private func makeController(
        reader: any BluetoothPairedDeviceReading,
        stateMonitor: AvailableBluetoothStateMonitor = AvailableBluetoothStateMonitor(),
        connectionEvents: (any BluetoothConnectionEventMonitoring)? = nil,
        accessoryBatteryEvents: (any BluetoothAccessoryBatteryEventMonitoring)? = nil,
        safetyNetSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        readTimeoutSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) -> BluetoothDeviceController {
        BluetoothDeviceController(
            worker: reader,
            stateMonitor: stateMonitor,
            batteryReader: SilentBluetoothBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            safetyNetSleep: safetyNetSleep,
            connectionEvents: connectionEvents,
            accessoryBatteryEvents: accessoryBatteryEvents,
            readTimeoutSleep: readTimeoutSleep
        )
    }

    func testPopoverReleaseDoesNotDeactivateIconOwnerOrDropBatteryClaim() async {
        let reader = DeferredBluetoothDeviceReader()
        let controller = makeController(reader: reader)
        controller.requestBatteryLevels(IconSourceDemandBridge.batteryLevelsToken)
        controller.requestActivation(BluetoothDeviceController.popoverActivationToken)
        controller.requestActivation(IconSourceDemandBridge.batteryLevelsToken)
        await waitUntil { reader.readCount == 1 }

        controller.releaseActivation(BluetoothDeviceController.popoverActivationToken)

        XCTAssertTrue(controller.isActive)
        XCTAssertTrue(controller.isBatteryLevelsRequested)
        XCTAssertEqual(reader.readCount, 1)
        controller.releaseActivation(IconSourceDemandBridge.batteryLevelsToken)
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(controller.isBatteryLevelsRequested)
    }

    func testIconOwnerUsesEventDrivenBackgroundDemandWithoutPolling() async {
        let reader = DeferredBluetoothDeviceReader()
        let connections = StoppableBluetoothConnectionEventMonitor()
        let batteryEvents = StoppableBluetoothConnectionEventMonitor()
        let controller = makeController(
            reader: reader,
            connectionEvents: connections,
            accessoryBatteryEvents: batteryEvents
        )

        XCTAssertTrue(controller.requestActivation(IconSourceDemandBridge.batteryLevelsToken))
        controller.requestBackgroundBatteryLevels(IconSourceDemandBridge.batteryLevelsToken)
        await waitUntil { reader.readCount == 1 }
        reader.complete(.success([]))
        await waitUntil { controller.availability == .available }
        await waitUntil { connections.startCount == 1 && batteryEvents.startCount == 1 }

        XCTAssertFalse(controller.isSafetyNetPolling)
        controller.releaseActivation(IconSourceDemandBridge.batteryLevelsToken)
        controller.releaseBackgroundBatteryLevels(IconSourceDemandBridge.batteryLevelsToken)
        XCTAssertFalse(connections.isRegistered)
        XCTAssertFalse(batteryEvents.isRegistered)
    }

    /// Declares the outstanding read stuck: waits for the injected watchdog
    /// timer to be armed, then lets it fire. No test ever waits on real time.
    private func releaseWatchdogTimeout(_ sleeper: ManualEventSleeper, armNumber: Int) async {
        let armed = await sleeper.waitForCallCount(armNumber, timeout: .seconds(1))
        XCTAssertTrue(armed, "the controller must arm the read watchdog")
        sleeper.releaseAll()
    }

    /// A read that is in flight swallows the next request into one follow-up,
    /// so a burst of triggers cannot spawn one process per trigger.
    func testReadsCoalesceIntoOneFollowUpWhileAReadIsInFlight() async {
        let reader = DeferredBluetoothDeviceReader()
        let controller = makeController(reader: reader)
        controller.activate()
        await waitUntil { reader.readCount == 1 }

        controller.refresh()
        controller.refresh()
        controller.refresh()
        XCTAssertEqual(reader.readCount, 1, "extra triggers must not start extra reads")

        reader.complete(.success([]))
        await waitUntil { reader.readCount == 2 }
        XCTAssertEqual(reader.readCount, 2, "three requests collapse into one follow-up")

        reader.complete(.success([]))
        await waitUntil { !reader.hasPendingRead }
        XCTAssertEqual(reader.readCount, 2)

        controller.deactivate()
    }

    /// The adapter powering off discards the in-flight read. Its completion
    /// must still release the latch, or every later refresh is coalesced into a
    /// follow-up that never starts and the row freezes forever.
    func testSupersededReadReleasesTheLatchAndTheNextRefreshRuns() async {
        let reader = DeferredBluetoothDeviceReader()
        let monitor = AvailableBluetoothStateMonitor()
        let controller = makeController(reader: reader, stateMonitor: monitor)
        controller.activate()
        await waitUntil { reader.readCount == 1 }

        monitor.emit(authorization: .allowed, managerState: .poweredOff)
        reader.complete(.success([
            BluetoothDevice(id: "1", name: "AirPods Pro", kind: .audio, isConnected: true)
        ]))
        await Task.yield()

        XCTAssertEqual(controller.availability, .poweredOff)
        XCTAssertTrue(controller.devices.isEmpty, "a superseded read must not republish devices")

        monitor.emit(authorization: .allowed, managerState: .poweredOn)
        await waitUntil { reader.readCount == 2 }

        reader.complete(.success([
            BluetoothDevice(id: "2", name: "MX Keys", kind: .peripheral(.keyboard), isConnected: true)
        ]))
        await waitUntil { controller.devices.map(\.id) == ["2"] }

        controller.deactivate()
    }

    /// A read whose completion never runs used to set the single-in-flight latch
    /// for the rest of the session: every later trigger only set
    /// `isRefreshPending`, so the Bluetooth row froze. The watchdog has to
    /// declare such a read stuck and abandon it — releasing the latch — so a
    /// later trigger starts a new read instead of being coalesced forever.
    func testAReadThatNeverCompletesDoesNotWedgeTheLatchForever() async {
        let reader = StallingBluetoothDeviceReader()
        let timeoutSleeper = ManualEventSleeper()
        let controller = makeController(
            reader: reader,
            readTimeoutSleep: { duration in await timeoutSleeper.sleep(duration) }
        )
        controller.activate()
        await waitUntil { reader.readCount == 1 }

        // The trigger that arrives while the stalled read is outstanding is
        // coalesced, exactly as the Task 2 latch designed.
        controller.refresh()
        await settle()
        XCTAssertEqual(reader.readCount, 1, "a stalled read must still hold the latch")

        // The watchdog declares the read stuck and abandons it, which releases
        // the latch and starts the coalesced follow-up on a fresh worker queue.
        await releaseWatchdogTimeout(timeoutSleeper, armNumber: 1)
        await waitUntil { reader.readCount == 2 }
        XCTAssertEqual(reader.readCount, 2, "an abandoned read must not wedge the latch")

        // The second read stalls too, so a later trigger is again coalesced
        // until the watchdog abandons this read as well. The point is that no
        // later trigger is ever dropped for the rest of the session.
        controller.refresh()
        await releaseWatchdogTimeout(timeoutSleeper, armNumber: 2)
        await waitUntil { reader.readCount == 3 }
        XCTAssertEqual(reader.readCount, 3, "a later trigger must still reach a new read")

        controller.deactivate()
    }

    /// The abandoned read's completion finally runs, long after its read token
    /// was retired. It may not publish devices that the read replacing it never
    /// saw, and it may not release that read's latch.
    func testAnAbandonedReadsLateCompletionIsIgnored() async {
        let reader = StallingBluetoothDeviceReader()
        let timeoutSleeper = ManualEventSleeper()
        let controller = makeController(
            reader: reader,
            readTimeoutSleep: { duration in await timeoutSleeper.sleep(duration) }
        )
        controller.activate()
        await waitUntil { reader.readCount == 1 }

        controller.refresh()
        await releaseWatchdogTimeout(timeoutSleeper, armNumber: 1)
        await waitUntil { reader.readCount == 2 }

        // The stalled read's completion arrives late, carrying a device the
        // follow-up read never reported. Accepting it would republish devices
        // that the current read did not see.
        reader.completeFirstRead(with: [
            BluetoothDevice(id: "stale", name: "Stale", kind: .audio, isConnected: true)
        ])
        await settle()
        XCTAssertTrue(controller.devices.isEmpty, "a superseded read must not republish devices")

        controller.deactivate()
    }

    /// A read that returned must disarm its own watchdog. A leftover timer would
    /// later "abandon" a read that already published, release the latch, and
    /// start a spurious extra profiler run.
    func testACompletedReadDisarmsTheWatchdog() async {
        let reader = DeferredBluetoothDeviceReader()
        let timeoutSleeper = ManualEventSleeper()
        let controller = makeController(
            reader: reader,
            readTimeoutSleep: { duration in await timeoutSleeper.sleep(duration) }
        )
        controller.activate()
        await waitUntil { reader.readCount == 1 }
        let armed = await timeoutSleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertTrue(armed, "the controller must arm a read watchdog")

        reader.complete(.success([
            BluetoothDevice(id: "1", name: "MX Keys", kind: .peripheral(.keyboard), isConnected: true)
        ]))
        await waitUntil { controller.devices.map(\.id) == ["1"] }

        // Let the watchdog's timer resume. It was cancelled by the accepted
        // completion, so it must not abandon the read that already published.
        timeoutSleeper.releaseAll()
        await settle()
        XCTAssertEqual(reader.readCount, 1, "a completed read must disarm its watchdog")

        controller.deactivate()
    }

    /// An abandoned read starts the coalesced follow-up itself, so the pending
    /// trigger is consumed by that start. If the flag stayed set, the follow-up's
    /// own completion would consume it a second time and run one extra profiler
    /// pass after every timeout.
    func testAnAbandonedReadConsumesItsPendingTriggerOnce() async {
        let reader = DeferredBluetoothDeviceReader()
        let timeoutSleeper = ManualEventSleeper()
        let controller = makeController(
            reader: reader,
            readTimeoutSleep: { duration in await timeoutSleeper.sleep(duration) }
        )
        controller.activate()
        await waitUntil { reader.readCount == 1 }

        // The trigger that arrives while the first read is outstanding is
        // coalesced into the follow-up the watchdog will start.
        controller.refresh()
        await settle()

        await releaseWatchdogTimeout(timeoutSleeper, armNumber: 1)
        await waitUntil { reader.readCount == 2 }

        // The follow-up completes: the trigger it consumed must not start a
        // third read. The abandoned read's completion is still parked, so the
        // first completion retires nothing and the second one belongs to the
        // follow-up.
        reader.complete(.success([]))
        reader.complete(.success([]))
        await settle()
        XCTAssertEqual(reader.readCount, 2, "the coalesced trigger was consumed by the follow-up")

        controller.deactivate()
    }

    /// Deactivating invalidates an in-flight read, and that must also clear the
    /// watchdog's backoff: otherwise a session that timed out once starts its
    /// next read with the previous penalty instead of the base timeout.
    func testDeactivationResetsTheWatchdogBackoff() async {
        let reader = StallingBluetoothDeviceReader()
        let timeoutSleeper = ManualEventSleeper()
        let controller = makeController(
            reader: reader,
            readTimeoutSleep: { duration in await timeoutSleeper.sleep(duration) }
        )
        controller.activate()
        await waitUntil { reader.readCount == 1 }

        // The first timeout doubles the wait for the next read.
        await releaseWatchdogTimeout(timeoutSleeper, armNumber: 1)
        await waitUntil { reader.readCount == 2 }
        let secondArmed = await timeoutSleeper.waitForCallCount(2, timeout: .seconds(1))
        XCTAssertTrue(secondArmed, "the retried read must arm the watchdog")
        XCTAssertEqual(timeoutSleeper.durations[1], .seconds(10), "a timeout must back off")

        controller.deactivate()
        controller.activate()
        await waitUntil { reader.readCount == 3 }
        let thirdArmed = await timeoutSleeper.waitForCallCount(3, timeout: .seconds(1))
        XCTAssertTrue(thirdArmed, "the new session must arm the watchdog")

        XCTAssertEqual(
            timeoutSleeper.durations[2],
            .seconds(5),
            "a new session must start from the base timeout, not the previous backoff"
        )

        controller.deactivate()
    }

    /// A read that failed cannot be followed by a successful poll, so the
    /// connection-event registration has to go with the poll. Leaving it live
    /// meant a failing controller held a system registration with no poll
    /// behind it, a state no other branch leaves.
    func testAFailedReadStopsThePollAndTheConnectionEvents() async {
        let reader = DeferredBluetoothDeviceReader()
        let events = StoppableBluetoothConnectionEventMonitor()
        let controller = makeController(reader: reader, connectionEvents: events)
        controller.activate()
        await waitUntil { reader.readCount == 1 }

        controller.holdVisibleSurface("bluetooth.popover")
        XCTAssertTrue(controller.isSafetyNetPolling)
        XCTAssertTrue(controller.isMonitoringConnectionEvents)

        reader.complete(.failed)
        await waitUntil { controller.availability == .failed }
        await waitUntil { !controller.isMonitoringConnectionEvents }

        XCTAssertFalse(controller.isSafetyNetPolling)
        XCTAssertFalse(controller.isMonitoringConnectionEvents)
        XCTAssertEqual(events.stopCount, 1, "the registration must be released with the poll")

        controller.deactivate()
    }

    /// The worker runs every read on one fixed serial queue, so a read that never
    /// returns would block every later read behind it for the lifetime of the
    /// process. Calling `read` while a previous read is still outstanding must
    /// retire that queue and run the new read on a fresh one — otherwise the
    /// watchdog's retry would land behind the hung block, and the watchdog would
    /// be a no-op.
    func testAReadRetiresTheQueueWhenThePreviousReadIsStillOutstanding() async {
        let firstReadStarted = expectation(description: "first read started")
        let secondReadFinished = expectation(description: "second read completed")
        let release = DispatchSemaphore(value: 0)
        let calls = CountBox()
        let worker = SystemProfilerBluetoothPairedDeviceWorker(
            outputProvider: {
                if calls.incrementReturning() == 1 {
                    firstReadStarted.fulfill()
                    // Models a `system_profiler` that stays blocked; the test
                    // frees it only after the later read has already run.
                    _ = release.wait(timeout: .now() + 10)
                }
                return nil
            },
            reportCache: BluetoothProfilerReportCache()
        )

        worker.read { _ in }
        await fulfillment(of: [firstReadStarted], timeout: 5)

        // The first read never returned. This one must not queue behind it.
        worker.read { _ in secondReadFinished.fulfill() }
        await fulfillment(of: [secondReadFinished], timeout: 5)
        XCTAssertEqual(calls.value, 2)
        release.signal()
    }

    /// A late completion from a retired queue must not clear the outstanding
    /// flag that describes the read that replaced it, or the next read would be
    /// queued behind a hung block instead of retiring the queue again.
    func testALateCompletionFromARetiredQueueDoesNotStopTheNextRetirement() async {
        let firstReadStarted = expectation(description: "first read started")
        let firstReadReturned = expectation(description: "first read returned late")
        let secondReadFinished = expectation(description: "second read completed")
        let thirdReadStarted = expectation(description: "third read started")
        let fourthReadFinished = expectation(description: "fourth read completed")
        let releaseFirst = DispatchSemaphore(value: 0)
        let releaseThird = DispatchSemaphore(value: 0)
        let calls = CountBox()
        let worker = SystemProfilerBluetoothPairedDeviceWorker(
            outputProvider: {
                switch calls.incrementReturning() {
                case 1:
                    firstReadStarted.fulfill()
                    _ = releaseFirst.wait(timeout: .now() + 10)
                case 3:
                    thirdReadStarted.fulfill()
                    _ = releaseThird.wait(timeout: .now() + 10)
                default:
                    break
                }
                return nil
            },
            reportCache: BluetoothProfilerReportCache()
        )

        // Read 1 wedges the original queue.
        worker.read { _ in firstReadReturned.fulfill() }
        await fulfillment(of: [firstReadStarted], timeout: 5)

        // Read 2 retires that queue and completes on the replacement.
        worker.read { _ in secondReadFinished.fulfill() }
        await fulfillment(of: [secondReadFinished], timeout: 5)

        // Read 3 wedges the replacement queue.
        worker.read { _ in }
        await fulfillment(of: [thirdReadStarted], timeout: 5)

        // Read 1 finally returns. Its completion belongs to the retired queue,
        // so it must not clear the flag that now describes read 3.
        releaseFirst.signal()
        await fulfillment(of: [firstReadReturned], timeout: 5)

        // Read 4 must retire the wedged replacement rather than queue behind it.
        worker.read { _ in fourthReadFinished.fulfill() }
        await fulfillment(of: [fourthReadFinished], timeout: 5)

        XCTAssertEqual(calls.value, 4)
        releaseThird.signal()
    }

    /// The safety net is a fallback for the connection notifications, and it may
    /// only run while the popover that shows device state is open. The
    /// popover-level claim is what sustains it; a view claim never does (rider 1).
    func testSafetyNetPollRunsOnlyWhileASurfaceIsHeld() async {
        let reader = DeferredBluetoothDeviceReader()
        let sleeper = ManualEventSleeper()
        let controller = makeController(
            reader: reader,
            safetyNetSleep: { duration in await sleeper.sleep(duration) }
        )
        controller.activate()
        await waitUntil { reader.readCount == 1 }
        reader.complete(.success([]))
        await waitUntil { !reader.hasPendingRead }

        XCTAssertFalse(controller.isSafetyNetPolling, "a poll started with nothing on screen")

        controller.holdVisibleSurface("bluetooth.popover")
        _ = await sleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertTrue(controller.isSafetyNetPolling)
        XCTAssertEqual(sleeper.durations.first, .seconds(30))

        sleeper.releaseAll()
        await waitUntil { reader.readCount == 2 }
        reader.complete(.success([]))
        await waitUntil { !reader.hasPendingRead }

        controller.releaseVisibleSurface("bluetooth.popover")
        XCTAssertFalse(controller.isSafetyNetPolling)
        let callCountWhenReleased = sleeper.callCount
        sleeper.releaseAll()
        await Task.yield()
        XCTAssertEqual(sleeper.callCount, callCountWhenReleased, "a released surface must stop polling")
        XCTAssertEqual(reader.readCount, 2)

        controller.deactivate()
    }

    /// The summary row and the detail page claim their own view tokens, and they
    /// can appear in either order. Those claims narrow the poll but cannot
    /// sustain it: the popover claim is the one the poll follows (rider 1), so
    /// the poll stops when the popover closes even with a view claim leaked.
    func testTheLastReleasedSurfaceStopsThePoll() async {
        let sleeper = ManualEventSleeper()
        let controller = makeController(
            reader: DeferredBluetoothDeviceReader(),
            safetyNetSleep: { duration in await sleeper.sleep(duration) }
        )
        controller.activate()
        await waitUntil { controller.availability == .available }

        controller.holdVisibleSurface("bluetooth.popover")
        controller.holdVisibleSurface("bluetooth.summary.surface")
        controller.holdVisibleSurface("bluetooth.view.surface")
        XCTAssertTrue(controller.isSafetyNetPolling)

        controller.releaseVisibleSurface("bluetooth.summary.surface")
        XCTAssertTrue(controller.isSafetyNetPolling, "a view claim may only narrow the popover poll")

        // A leaked view claim must not keep the poll alive once the popover is
        // closed: this is the failure the rider exists to remove.
        controller.releaseVisibleSurface("bluetooth.popover")
        XCTAssertFalse(controller.isSafetyNetPolling)
        controller.releaseVisibleSurface("bluetooth.popover")
        XCTAssertFalse(controller.isSafetyNetPolling)
        XCTAssertFalse(controller.hasVisibleSurface)

        controller.releaseVisibleSurface("bluetooth.view.surface")
        controller.deactivate()
    }

    /// Deactivating the controller keeps the surface claims (they belong to the
    /// views) but must not leave a poll running.
    func testDeactivateStopsThePollWithoutDroppingSurfaceClaims() async {
        let sleeper = ManualEventSleeper()
        let controller = makeController(
            reader: DeferredBluetoothDeviceReader(),
            safetyNetSleep: { duration in await sleeper.sleep(duration) }
        )
        controller.activate()
        controller.holdVisibleSurface("bluetooth.popover")
        XCTAssertTrue(controller.isSafetyNetPolling)

        controller.deactivate()
        XCTAssertTrue(controller.hasVisibleSurface)
        XCTAssertFalse(controller.isSafetyNetPolling)
    }

    /// A cancelled poll's `defer` must not clear the reference to the poll that
    /// replaced it. A stop and a start can land in the same main-actor turn,
    /// before the cancelled task has run its `defer`; an unconditional
    /// `periodicRefreshTask = nil` then makes `isSafetyNetPolling` lie and
    /// leaves the running task uncancellable.
    func testARestartInTheSameTurnKeepsTheNewPollTrackedAndCancellable() async {
        let reader = ImmediateBluetoothDeviceReader()
        let sleeper = ManualEventSleeper()
        // The poll's guard also stops it when the surface goes away, so
        // cancellation is only observable from inside the sleep it was parked
        // in: after the sleep resumes, `Task.isCancelled` is the answer.
        let cancellations = SleepCancellationRecorder()
        let controller = BluetoothDeviceController(
            worker: reader,
            stateMonitor: AvailableBluetoothStateMonitor(),
            batteryReader: SilentBluetoothBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            safetyNetSleep: { duration in
                await sleeper.sleep(duration)
                cancellations.record(Task.isCancelled)
            }
        )
        controller.activate()
        await waitUntil { reader.readCount == 1 }
        controller.holdVisibleSurface("bluetooth.popover")
        _ = await sleeper.waitForCallCount(1, timeout: .seconds(1))

        // Stop and restart inside one turn, before the cancelled task's `defer`.
        controller.releaseVisibleSurface("bluetooth.popover")
        controller.holdVisibleSurface("bluetooth.popover")
        XCTAssertTrue(controller.isSafetyNetPolling, "the restarted poll must be tracked")

        // Let the replacement reach its own sleep, then release both so the
        // superseded task runs through to its `defer`.
        _ = await sleeper.waitForCallCount(2, timeout: .seconds(1))
        sleeper.releaseAll()
        await waitUntil { reader.readCount >= 3 }
        await settle()
        XCTAssertTrue(
            controller.isSafetyNetPolling,
            "a superseded poll's defer must not clear the replacement's reference"
        )

        // The replacement must still be cancellable: letting go of the popover
        // claim has to cancel the task the restart created.
        controller.releaseVisibleSurface("bluetooth.popover")
        XCTAssertFalse(controller.isSafetyNetPolling)
        sleeper.releaseAll()
        await settle()
        XCTAssertEqual(
            cancellations.resumed.last,
            true,
            "the restarted poll must actually be cancelled"
        )

        controller.deactivate()
    }

    /// Task 3's gate was satisfied while *any* claim was held, and the two view
    /// tokens are released only from SwiftUI `onDisappear`. The popover's
    /// content view controller is retained after close, so a skipped
    /// `onDisappear` left a claim held forever and the next
    /// `activate()`/`receiveSystemState(.available)` restarted a 30 s poll for
    /// the life of the process. Only the popover claim sustains the poll; a
    /// view claim may only narrow it.
    func testALeakedViewClaimCannotSustainThePoll() async {
        let sleeper = ManualEventSleeper()
        let controller = makeController(
            reader: DeferredBluetoothDeviceReader(),
            safetyNetSleep: { duration in await sleeper.sleep(duration) }
        )
        controller.activate()
        await waitUntil { controller.availability == .available }

        // A view claim on its own never starts the poll.
        controller.holdVisibleSurface("bluetooth.view.surface")
        await settle()
        XCTAssertFalse(
            controller.isSafetyNetPolling,
            "a view claim sustained the poll on its own"
        )

        controller.holdVisibleSurface("bluetooth.popover")
        XCTAssertTrue(controller.isSafetyNetPolling)

        // The popover closes while the view token leaks: the poll must stop.
        controller.releaseVisibleSurface("bluetooth.popover")
        XCTAssertFalse(
            controller.isSafetyNetPolling,
            "a leaked view claim sustained the poll"
        )
        XCTAssertFalse(controller.hasVisibleSurface)

        // Re-opening the popover resumes the poll, leaked view claim and all.
        controller.holdVisibleSurface("bluetooth.popover")
        XCTAssertTrue(controller.isSafetyNetPolling)

        controller.releaseVisibleSurface("bluetooth.view.surface")
        controller.releaseVisibleSurface("bluetooth.popover")
        controller.deactivate()
    }

    /// A controller that is released without `deactivate()` used to leak its
    /// NotificationCenter observers and leave CoreBluetooth running, because
    /// `CBCentralManager` retains its delegate and only `stop()` breaks that.
    func testDeinitWithoutDeactivateRemovesObserversAndStopsTheStateMonitor() async {
        let notifications = NotificationCenter()
        let observers = SystemEventObserverBag(
            notificationCenter: notifications,
            workspaceNotificationCenter: notifications
        )
        let monitor = CountingStopBluetoothStateMonitor()
        var controller: BluetoothDeviceController? = BluetoothDeviceController(
            worker: DeferredBluetoothDeviceReader(),
            stateMonitor: monitor,
            batteryReader: SilentBluetoothBatteryReader(),
            notificationCenter: notifications,
            workspaceNotificationCenter: notifications,
            systemObservers: observers
        )
        // A stored weak reference, not a local `weak var`: a local one that is
        // only read draws the "never mutated" warning, and AGENTS.md bans
        // weak `let`.
        let reference = WeakControllerReference(controller)
        controller?.activate()
        await waitUntil { monitor.startCount == 1 }
        XCTAssertFalse(observers.isEmpty)

        controller = nil
        XCTAssertNil(reference.value)

        // `deinit` is nonisolated, so the CoreBluetooth teardown is handed to
        // the main actor instead of touching the manager off its queue.
        await waitUntil { monitor.stopCount == 1 }
        XCTAssertTrue(observers.isEmpty, "the observers outlived the controller")

        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()
        XCTAssertEqual(monitor.startCount, 1, "a removed observer must not reactivate anything")
    }

    /// `deactivate()` is the other teardown entry point and must release the
    /// registrations too: a deactivated controller must not keep reacting to an
    /// app activation it no longer observes.
    func testDeactivateRemovesSystemObservers() async {
        let notifications = NotificationCenter()
        let observers = SystemEventObserverBag(
            notificationCenter: notifications,
            workspaceNotificationCenter: notifications
        )
        let monitor = CountingStopBluetoothStateMonitor()
        let controller = BluetoothDeviceController(
            worker: ImmediateBluetoothDeviceReader(),
            stateMonitor: monitor,
            batteryReader: SilentBluetoothBatteryReader(),
            notificationCenter: notifications,
            workspaceNotificationCenter: notifications,
            systemObservers: observers
        )
        controller.activate()
        await waitUntil { monitor.startCount == 1 }
        XCTAssertFalse(observers.isEmpty)

        controller.deactivate()
        XCTAssertTrue(observers.isEmpty, "deactivate left the observers registered")
        XCTAssertEqual(monitor.stopCount, 1)

        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        // The removed blocks would be delivered through the main queue, so give
        // them a real window to arrive before asserting nothing happened.
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(monitor.startCount, 1, "a removed observer fired after deactivate")
    }

    /// The connection-event registration outlives the object unless it is
    /// released explicitly.
    func testDeinitWithoutDeactivateStopsTheConnectionEventMonitor() async {
        let events = StoppableBluetoothConnectionEventMonitor()
        var controller: BluetoothDeviceController? = BluetoothDeviceController(
            worker: DeferredBluetoothDeviceReader(),
            stateMonitor: AvailableBluetoothStateMonitor(),
            batteryReader: SilentBluetoothBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            connectionEvents: events
        )
        controller?.activate()
        // The popover claim is what starts the event registration (rider 1).
        controller?.holdVisibleSurface("bluetooth.popover")
        await waitUntil { events.startCount == 1 }

        controller = nil
        await waitUntil { events.stopCount == 1 }
    }

    /// A registration the system refused must still be told to stop: the
    /// monitor can hold a stored handler even though `start` returned `false`,
    /// and the teardown path must have one shape either way.
    func testARefusedConnectionEventRegistrationIsStillStopped() async {
        let events = StoppableBluetoothConnectionEventMonitor(isAccepted: false)
        let controller = BluetoothDeviceController(
            worker: ImmediateBluetoothDeviceReader(),
            stateMonitor: AvailableBluetoothStateMonitor(),
            batteryReader: SilentBluetoothBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            connectionEvents: events
        )
        controller.activate()
        await waitUntil { controller.availability == .available }
        controller.holdVisibleSurface("bluetooth.popover")
        await waitUntil { events.startCount == 1 }
        XCTAssertFalse(controller.isMonitoringConnectionEvents)

        controller.deactivate()
        XCTAssertEqual(events.stopCount, 1, "a refused registration was never stopped")
    }

    /// The safety net is a 30 s loop, so releasing the last reference must
    /// cancel it rather than leave it parked for one more wakeup. The task's
    /// sleep records whether it was cancelled, because `isSafetyNetPolling` is
    /// no longer readable once the controller is gone.
    func testDeinitWithoutDeactivateCancelsTheSafetyNetTask() async {
        let sleeper = ManualEventSleeper()
        let cancellations = SleepCancellationRecorder()
        var controller: BluetoothDeviceController? = BluetoothDeviceController(
            worker: ImmediateBluetoothDeviceReader(),
            stateMonitor: AvailableBluetoothStateMonitor(),
            batteryReader: SilentBluetoothBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            safetyNetSleep: { duration in
                await sleeper.sleep(duration)
                cancellations.record(Task.isCancelled)
            }
        )
        controller?.activate()
        controller?.holdVisibleSurface("bluetooth.popover")
        _ = await sleeper.waitForCallCount(1, timeout: .seconds(1))

        controller = nil
        sleeper.releaseAll()
        await settle()
        XCTAssertEqual(
            cancellations.resumed.last,
            true,
            "the safety-net task outlived the controller"
        )
    }

    /// A connection-event debounce that is still parked when the poll stops must
    /// be discarded: `stopConnectionEvents()` invalidates its gate, so waking it
    /// cannot start a read for a popover that is already closed.
    func testStoppingThePollDiscardsAPendingConnectionEventDebounce() async {
        let reader = ImmediateBluetoothDeviceReader()
        let events = StoppableBluetoothConnectionEventMonitor()
        let sleeper = ManualEventSleeper()
        let controller = BluetoothDeviceController(
            worker: reader,
            stateMonitor: AvailableBluetoothStateMonitor(),
            batteryReader: SilentBluetoothBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            connectionEvents: events,
            connectionEventDebounceInterval: .milliseconds(750),
            connectionEventDebounceSleep: { duration in await sleeper.sleep(duration) }
        )
        controller.activate()
        await waitUntil { reader.readCount == 1 }
        controller.holdVisibleSurface("bluetooth.popover")
        await waitUntil { events.startCount == 1 }

        events.emit()
        _ = await sleeper.waitForCallCount(1, timeout: .seconds(1))
        let readsBeforeTheDebounceFired = reader.readCount

        controller.releaseVisibleSurface("bluetooth.popover")
        XCTAssertFalse(controller.isMonitoringConnectionEvents)

        sleeper.releaseAll()
        await settle()
        XCTAssertEqual(
            reader.readCount,
            readsBeforeTheDebounceFired,
            "a debounce stopped by the teardown still started a read"
        )
    }

    /// The bag is the piece that makes the observer leak observable.
    func testObserverBagRemovesEveryRegistration() async {
        let notifications = NotificationCenter()
        let bag = SystemEventObserverBag(
            notificationCenter: notifications,
            workspaceNotificationCenter: notifications
        )
        let activations = CountBox()
        let wakes = CountBox()
        bag.install(
            applicationActivated: { activations.increment() },
            didWake: { wakes.increment() }
        )

        // Re-installing must not stack a second registration.
        bag.install(
            applicationActivated: { activations.increment() },
            didWake: { wakes.increment() }
        )
        XCTAssertFalse(bag.isEmpty)

        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        await waitUntil { activations.value > 0 && wakes.value > 0 }
        XCTAssertEqual(activations.value, 1)
        XCTAssertEqual(wakes.value, 1)

        bag.removeAll()
        XCTAssertTrue(bag.isEmpty)

        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        // The block is delivered through the main queue, so give it a real
        // window to arrive before asserting that nothing was delivered.
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(activations.value, 1, "a removed observer still fired")
        XCTAssertEqual(wakes.value, 1, "a removed observer still fired")
    }

    /// The bag is the only owner of its tokens. Releasing one without calling
    /// `removeAll()` used to leave both blocks registered for the life of the
    /// process, which is the leak the type exists to prevent.
    func testAReleasedObserverBagRemovesItsRegistrations() async {
        let notifications = NotificationCenter()
        let activations = CountBox()
        let wakes = CountBox()
        var bag: SystemEventObserverBag? = SystemEventObserverBag(
            notificationCenter: notifications,
            workspaceNotificationCenter: notifications
        )
        bag?.install(
            applicationActivated: { activations.increment() },
            didWake: { wakes.increment() }
        )
        XCTAssertFalse(bag?.isEmpty ?? true)

        bag = nil

        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        // The block is delivered through the main queue, so give it a real
        // window to arrive before asserting that nothing was delivered.
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(activations.value, 0, "a released bag must remove its observers")
        XCTAssertEqual(wakes.value, 0, "a released bag must remove its observers")
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for the Bluetooth controller")
    }

    /// Lets every main-actor task that is already runnable finish.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
        for _ in 0..<20 { await Task.yield() }
    }
}

/// Answers every read straight away, so a test that only cares about the poll's
/// task lifetime never has to complete a read by hand.
private final class ImmediateBluetoothDeviceReader: BluetoothPairedDeviceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var readCount: Int { lock.withLock { count } }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        lock.withLock { count += 1 }
        completion(.success([]))
    }
}

/// Records what each parked sleep saw when it resumed, which is how a test tells
/// "the task was cancelled" apart from "the task's guard happened to stop it".
private final class SleepCancellationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    var resumed: [Bool] { lock.withLock { values } }

    func record(_ cancelled: Bool) {
        lock.withLock { values.append(cancelled) }
    }
}

/// Answers device reads only when the test says so, which is what makes the
/// in-flight latch observable.
private final class DeferredBluetoothDeviceReader: BluetoothPairedDeviceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [@Sendable (BluetoothWorkerResult) -> Void] = []
    private var count = 0

    var readCount: Int { lock.withLock { count } }
    var hasPendingRead: Bool { lock.withLock { !pending.isEmpty } }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        lock.withLock {
            count += 1
            pending.append(completion)
        }
    }

    func complete(_ result: BluetoothWorkerResult) {
        let completion = lock.withLock { pending.isEmpty ? nil : pending.removeFirst() }
        completion?(result)
    }
}

/// Never answers a read of its own accord: its completion only runs when the
/// test asks for it, which is what makes a wedged single-in-flight latch
/// observable. Every read stalls, so the follow-up read that the watchdog starts
/// is also still outstanding when the first read's completion finally arrives.
private final class StallingBluetoothDeviceReader: BluetoothPairedDeviceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [@Sendable (BluetoothWorkerResult) -> Void] = []
    private var count = 0

    var readCount: Int { lock.withLock { count } }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        lock.withLock {
            count += 1
            pending.append(completion)
        }
    }

    /// The stalled read's completion finally runs, long after it was abandoned.
    func completeFirstRead(with devices: [BluetoothDevice]) {
        let completion = lock.withLock { pending.isEmpty ? nil : pending.removeFirst() }
        completion?(.success(devices))
    }
}

@MainActor
private final class AvailableBluetoothStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() { onStateChange?(.allowed, .poweredOn) }
    func stop() {}

    func emit(authorization: BluetoothAuthorizationStatus, managerState: BluetoothManagerState) {
        onStateChange?(authorization, managerState)
    }
}

private final class SilentBluetoothBatteryReader: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        completion([:])
    }
}

@MainActor
private final class CountingStopBluetoothStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        startCount += 1
        onStateChange?(.allowed, .poweredOn)
    }

    func stop() { stopCount += 1 }
}

private final class StoppableBluetoothConnectionEventMonitor: BluetoothConnectionEventMonitoring, BluetoothAccessoryBatteryEventMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private let isAccepted: Bool
    private var handler: (@Sendable () -> Void)?
    private var starts = 0
    private var stops = 0

    init(isAccepted: Bool = true) {
        self.isAccepted = isAccepted
    }

    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }
    var isRegistered: Bool { lock.withLock { handler != nil } }

    @discardableResult
    func start(handler: @escaping @Sendable () -> Void) -> Bool {
        lock.withLock {
            self.handler = handler
            starts += 1
        }
        return isAccepted
    }

    func stop() {
        lock.withLock {
            handler = nil
            stops += 1
        }
    }

    /// Delivers one connect/disconnect notification to the stored handler.
    func emit() {
        let handler = lock.withLock { self.handler }
        handler?()
    }
}

private final class CountBox: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }

    /// Increments and reports the new value, so a fake can branch on which call
    /// it is answering without a second round trip through the lock.
    func incrementReturning() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}

/// Holds the controller weakly so a test can prove `deinit` ran, without the
/// local `weak var` the compiler warns about (or the banned weak `let`).
private final class WeakControllerReference {
    weak var value: BluetoothDeviceController?

    init(_ value: BluetoothDeviceController?) {
        self.value = value
    }
}
