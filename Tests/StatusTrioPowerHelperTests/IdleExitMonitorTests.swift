import XCTest
@testable import StatusTrioPowerHelper

final class IdleExitMonitorTests: XCTestCase {
    func testSchedulesTheExitAfterTheConfiguredDelay() {
        let scheduler = ManualDelayedWorkScheduler()
        let exits = ExitRecorder()
        let monitor = IdleExitMonitor(delay: 12, scheduler: scheduler, exitProcess: exits.record)

        monitor.start()

        XCTAssertEqual(scheduler.scheduledDelays, [12])
        XCTAssertEqual(exits.count, 0, "The process must not exit before the window elapses.")
    }

    func testExitsWhenTheSpawnedDaemonNeverGetsAClient() {
        // launchd starts the daemon on the first Mach message, so a peer that
        // the code-signing requirement rejects still leaves a root process
        // behind if "no connection yet" is not idle.
        let scheduler = ManualDelayedWorkScheduler()
        let exits = ExitRecorder()
        let monitor = IdleExitMonitor(scheduler: scheduler, exitProcess: exits.record)

        monitor.start()
        scheduler.runScheduledWork()

        XCTAssertEqual(exits.count, 1)
    }

    func testKeepsRunningWhileAConnectionIsOpen() {
        let scheduler = ManualDelayedWorkScheduler()
        let exits = ExitRecorder()
        let monitor = IdleExitMonitor(scheduler: scheduler, exitProcess: exits.record)

        monitor.start()
        monitor.connectionOpened()
        scheduler.runScheduledWork()

        XCTAssertEqual(exits.count, 0)

        monitor.connectionClosed()
        scheduler.runScheduledWork()

        XCTAssertEqual(exits.count, 1)
    }

    func testAnAcceptedConnectionCancelsThePendingExit() {
        let scheduler = ManualDelayedWorkScheduler()
        let exits = ExitRecorder()
        let monitor = IdleExitMonitor(scheduler: scheduler, exitProcess: exits.record)

        monitor.start()
        monitor.connectionOpened()

        XCTAssertEqual(scheduler.pendingWorkCount, 0)
        scheduler.runScheduledWork()
        XCTAssertEqual(exits.count, 0)
    }

    func testATimerThatAlreadyStartedCannotExitARunningClient() {
        // The cancelled dispatch item can be mid-flight; the generation guard,
        // not cancellation, is what keeps a live client from being dropped.
        let scheduler = ManualDelayedWorkScheduler()
        let exits = ExitRecorder()
        let monitor = IdleExitMonitor(scheduler: scheduler, exitProcess: exits.record)

        monitor.start()
        monitor.connectionOpened()
        monitor.connectionClosed()
        monitor.connectionOpened()
        scheduler.runScheduledWork()

        XCTAssertEqual(exits.count, 0)
    }

    func testRestartsTheIdleWindowAfterTheLastConnectionEnds() {
        let scheduler = ManualDelayedWorkScheduler()
        let exits = ExitRecorder()
        let monitor = IdleExitMonitor(scheduler: scheduler, exitProcess: exits.record)

        monitor.start()
        monitor.connectionOpened()
        monitor.connectionClosed()
        monitor.connectionOpened()
        monitor.connectionClosed()
        scheduler.runScheduledWork()

        XCTAssertEqual(exits.count, 1)
    }

    func testExitsOnlyOnce() {
        let scheduler = ManualDelayedWorkScheduler()
        let exits = ExitRecorder()
        let monitor = IdleExitMonitor(scheduler: scheduler, exitProcess: exits.record)

        monitor.start()
        // A timer that fires twice must not ask the process to exit twice; the
        // exit has to happen for one elapsed idle window, not per firing.
        scheduler.runScheduledWork()
        scheduler.runScheduledWork()

        XCTAssertEqual(exits.count, 1)
    }

    func testEveryIdleWindowIsScheduledOnlyOnce() {
        let scheduler = ManualDelayedWorkScheduler()
        let exits = ExitRecorder()
        let monitor = IdleExitMonitor(scheduler: scheduler, exitProcess: exits.record)

        monitor.start()
        monitor.start()

        XCTAssertEqual(scheduler.scheduledDelays.count, 1)
        scheduler.runScheduledWork()
        XCTAssertEqual(exits.count, 1)
    }
}

final class ConnectionLifetimeTests: XCTestCase {
    func testEndsTheConnectionOnce() {
        let recorder = ExitRecorder()
        let lifetime = ConnectionLifetime { recorder.record() }

        lifetime.end()
        lifetime.end()

        XCTAssertEqual(recorder.count, 1)
    }

    func testConcurrentEndsStillCountOnce() {
        // An interruption and an invalidation can be delivered at the same
        // time; two decrements for one connection would drop another client.
        let recorder = ExitRecorder()
        let lifetime = ConnectionLifetime { recorder.record() }

        DispatchQueue.concurrentPerform(iterations: 64) { _ in lifetime.end() }

        XCTAssertEqual(recorder.count, 1)
    }
}

/// Test clock: records scheduled work and runs it only when a test says so.
final class ManualDelayedWorkScheduler: DelayedWorkScheduling, @unchecked Sendable {
    final class Entry: @unchecked Sendable {
        let delay: TimeInterval
        let action: @Sendable () -> Void
        private let lock = NSLock()
        private var isCancelled = false

        init(delay: TimeInterval, action: @escaping @Sendable () -> Void) {
            self.delay = delay
            self.action = action
        }

        func cancel() {
            lock.lock()
            isCancelled = true
            lock.unlock()
        }

        var cancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return isCancelled
        }
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    var scheduledDelays: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return entries.map(\.delay)
    }

    var pendingWorkCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { !$0.cancelled }.count
    }

    func schedule(after delay: TimeInterval, _ action: @escaping @Sendable () -> Void) -> any DelayedWork {
        let entry = Entry(delay: delay, action: action)
        lock.lock()
        entries.append(entry)
        lock.unlock()
        return ManualDelayedWork(entry: entry)
    }

    /// Runs every item scheduled so far, including cancelled ones: a real
    /// dispatch item can already be executing when it is cancelled.
    func runScheduledWork() {
        lock.lock()
        let snapshot = entries
        lock.unlock()
        for entry in snapshot {
            entry.action()
        }
    }
}

private struct ManualDelayedWork: DelayedWork {
    let entry: ManualDelayedWorkScheduler.Entry

    func cancel() {
        entry.cancel()
    }
}

/// Records how often the daemon asked to exit, from any thread.
final class ExitRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded = 0

    func record() {
        lock.lock()
        recorded += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}
