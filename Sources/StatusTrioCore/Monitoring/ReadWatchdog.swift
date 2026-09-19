import Foundation

/// Bounds how long one system read may take before it is declared stuck, and
/// decides how long to wait before the next attempt.
///
/// A CoreAudio or CoreWLAN property read runs synchronous IPC that cannot be
/// cancelled. Once a read is stuck the only way forward is to abandon it and try
/// again, so successive timeouts back off up to a cap. A transient stall is
/// retried promptly, while a permanently wedged driver costs one abandoned
/// worker thread per capped interval instead of one per read.
///
/// The backed-off interval is also the timeout applied to the retried read, so a
/// read that legitimately takes longer than the base timeout has its result
/// dropped once and then succeeds on a retry with a longer budget.
///
/// Note the cap bounds the *rate* of abandoned threads, not the total: a driver
/// that stays wedged for hours keeps accumulating them, because unbounded
/// recovery and a bounded thread count cannot both hold.
@MainActor
final class ReadWatchdog {
    private let baseTimeout: Duration
    private let maxTimeout: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private var consecutiveTimeouts = 0
    private var task: Task<Void, Never>?

    init(
        baseTimeout: Duration,
        maxTimeout: Duration,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.baseTimeout = baseTimeout
        self.maxTimeout = maxTimeout
        self.sleep = sleep
    }

    deinit {
        // The owning monitor may be released while a read is still outstanding.
        // Cancelling the pending timer here keeps deinit itself nonisolated.
        task?.cancel()
    }

    /// The wait the next armed watchdog will use.
    var nextTimeout: Duration {
        var interval = min(baseTimeout, maxTimeout)
        for _ in 0..<consecutiveTimeouts {
            interval = min(interval * 2, maxTimeout)
        }
        return interval
    }

    /// Starts the timer for the read that is starting now. `onTimeout` runs on
    /// the main actor once that read has been outstanding for `nextTimeout`.
    /// Arming again replaces any previous timer.
    func arm(onTimeout: @escaping @MainActor @Sendable () -> Void) {
        task?.cancel()
        let timeout = nextTimeout
        let sleep = sleep
        task = Task { @MainActor [weak self] in
            do {
                try await sleep(timeout)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.consecutiveTimeouts += 1
            onTimeout()
        }
    }

    /// A read returned, so the system is responsive again and the next stuck read
    /// gets the base timeout rather than the previous backoff.
    func recordSuccess() {
        consecutiveTimeouts = 0
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
