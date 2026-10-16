import Foundation

/// Collapses a connection's end-of-life callbacks into a single event.
///
/// Foundation can deliver an interruption and an invalidation for the same
/// connection, and the daemon treats both as "the client is gone". Counting one
/// connection twice would let the daemon exit while another client is still
/// connected, so the first callback wins and the rest are ignored.
final class ConnectionLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var hasEnded = false
    private let onEnd: @Sendable () -> Void

    init(onEnd: @escaping @Sendable () -> Void) {
        self.onEnd = onEnd
    }

    func end() {
        lock.lock()
        guard !hasEnded else {
            lock.unlock()
            return
        }
        hasEnded = true
        lock.unlock()
        onEnd()
    }
}
