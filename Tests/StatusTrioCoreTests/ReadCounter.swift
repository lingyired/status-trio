import Foundation

/// Thread-safe call counter for closures that run off the main actor.
final class ReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    /// Increments and returns the new value, so callers can number their calls.
    @discardableResult
    func increment() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }

    var calls: Int { lock.withLock { count } }
}
