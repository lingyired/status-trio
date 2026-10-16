import Foundation

/// Work that runs once after a delay and can be taken back before it runs.
///
/// A protocol so the daemon's idle policy can be tested against a clock the
/// test drives rather than wall-clock time.
protocol DelayedWorkScheduling: Sendable {
    func schedule(after delay: TimeInterval, _ action: @escaping @Sendable () -> Void) -> any DelayedWork
}

protocol DelayedWork: Sendable {
    func cancel()
}

/// Production scheduler: a libdispatch timer on a queue private to the daemon.
struct DispatchDelayedWorkScheduler: DelayedWorkScheduling {
    private let queue = DispatchQueue(label: "com.lingsmbp.StatusTrio.PowerHelper.idleExit")

    func schedule(after delay: TimeInterval, _ action: @escaping @Sendable () -> Void) -> any DelayedWork {
        let cancellation = DelayedWorkCancellation()
        queue.asyncAfter(deadline: .now() + delay) {
            guard !cancellation.isCancelled else { return }
            action()
        }
        return cancellation
    }
}

/// Flag a scheduled block reads when it fires. A cancelled block is not
/// removed from the queue — it may already be mid-flight — so the block itself
/// decides whether to run.
final class DelayedWorkCancellation: DelayedWork, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// Ends the daemon's process once it has no client left.
///
/// launchd does not stop an idle on-demand job: a `MachServices` job that never
/// exits itself keeps running long after the app that asked for it is gone, and
/// adding `EnableTransactions` does not change that (both measured on macOS 27
/// with an equivalent user LaunchAgent). Without this monitor the root daemon
/// outlives a quit app and sits in the process list, which is what the opt-in
/// promise says must not happen.
///
/// Exiting is safe because the daemon is cheap to relaunch: launchd starts it
/// again on the next Mach message. The LaunchDaemon property list lowers
/// `ThrottleInterval` to 1 second so that relaunch is immediate instead of
/// waiting out launchd's 10-second default for a job that just exited.
///
/// Thread-safe: the XPC runtime delivers listener callbacks on its own queues,
/// so every mutation is guarded by `lock`.
final class IdleExitMonitor: @unchecked Sendable {
    /// Seconds without a client before the process exits. Long enough for one
    /// app interaction (a popover read, then a toggle a few seconds later) to
    /// reuse the running daemon, short enough that the process is gone soon
    /// after the app quits.
    static let defaultDelay: TimeInterval = 5

    private let delay: TimeInterval
    private let scheduler: any DelayedWorkScheduling
    private let exitProcess: @Sendable () -> Void

    private let lock = NSLock()
    private var liveConnections = 0
    /// Bumped whenever the idle window is invalidated, so a timer that has
    /// already started running cannot exit a process that has a client again.
    private var generation: UInt64 = 0
    private var pendingExit: (any DelayedWork)?

    init(
        delay: TimeInterval = IdleExitMonitor.defaultDelay,
        scheduler: any DelayedWorkScheduling = DispatchDelayedWorkScheduler(),
        exitProcess: @escaping @Sendable () -> Void = { exit(EXIT_SUCCESS) }
    ) {
        self.delay = delay
        self.scheduler = scheduler
        self.exitProcess = exitProcess
    }

    /// Starts watching. The listener has no client at this point, so a daemon
    /// that launchd spawned but that never gets a usable connection — a peer
    /// rejected by the code-signing requirement, a request cancelled in flight
    /// — still goes away instead of lingering as root forever.
    func start() {
        armExitIfIdle()
    }

    /// The listener accepted a connection: keep the process alive.
    func connectionOpened() {
        lock.lock()
        liveConnections += 1
        generation &+= 1
        let pending = pendingExit
        pendingExit = nil
        lock.unlock()
        pending?.cancel()
    }

    /// The connection ended — invalidated or interrupted, which is what the
    /// daemon sees both when the app invalidates the connection and when the
    /// app quits or dies mid-connection.
    func connectionClosed() {
        lock.lock()
        liveConnections = max(0, liveConnections - 1)
        lock.unlock()
        armExitIfIdle()
    }

    private func armExitIfIdle() {
        lock.lock()
        guard liveConnections == 0, pendingExit == nil else {
            lock.unlock()
            return
        }
        generation &+= 1
        let scheduled = generation
        pendingExit = scheduler.schedule(after: delay) { [weak self] in
            self?.idleWindowElapsed(generation: scheduled)
        }
        lock.unlock()
    }

    /// Only the newest idle window may exit the process: a connection that
    /// arrived after this window was scheduled has already invalidated it.
    private func idleWindowElapsed(generation scheduled: UInt64) {
        lock.lock()
        guard generation == scheduled, liveConnections == 0 else {
            lock.unlock()
            return
        }
        pendingExit = nil
        generation &+= 1
        lock.unlock()
        NSLog("StatusTrioPowerHelper exiting after %.1f seconds without a client", delay)
        exitProcess()
    }
}
