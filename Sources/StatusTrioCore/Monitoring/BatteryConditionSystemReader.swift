import Foundation

/// Fallback for the battery condition when AppleSmartBattery exposes none.
/// `system_profiler` takes ~60 ms and the details page refreshes every 2 s,
/// so an answer (including "unknown") is reused for `ttl`. The condition
/// changes over months, not minutes; the TTL is the cache's only stop path.
/// A run that did not exit cleanly is retried after `failureTTL`, and the
/// short timeout bounds how long it can hold back the rest of the page.
enum BatteryConditionSystemReader {
    static let ttl: TimeInterval = 600
    static let failureTTL: TimeInterval = 60

    /// Runs `system_profiler` with a hard deadline. Injected so tests can drive
    /// success, failure and timeout without launching a real process.
    typealias Runner = (Duration) -> BoundedProcessOutcome

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: (expiresAt: Date, condition: BatteryHealthSnapshot.Condition?)?

    static func read(
        now: Date = Date(),
        timeout: Duration = .seconds(1),
        run: Runner = { timeout in
            BoundedProcessInvocation.runSync(
                executableURL: URL(fileURLWithPath: "/usr/sbin/system_profiler"),
                arguments: ["SPPowerDataType", "-json", "-detailLevel", "mini"],
                timeout: timeout
            )
        }
    ) -> BatteryHealthSnapshot.Condition? {
        // A cached entry's lifetime is at most `ttl`, so `now < expiresAt`
        // alone decides freshness; there is no separate lifetime check.
        if let hit = lock.withLock({ cached }), now < hit.expiresAt {
            return hit.condition
        }
        var condition: BatteryHealthSnapshot.Condition?
        var lifetime = failureTTL
        if case let .exited(data) = run(timeout) {
            condition = BatteryHealthParser.condition(systemProfilerJSON: data)
            lifetime = ttl
        }
        lock.withLock { cached = (now.addingTimeInterval(lifetime), condition) }
        return condition
    }

    /// Test hook: clears the process-wide cache so each test starts cold.
    static func resetCache() {
        lock.withLock { cached = nil }
    }
}
