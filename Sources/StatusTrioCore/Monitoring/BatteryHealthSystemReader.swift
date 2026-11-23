import Foundation

/// Fallback for the battery health fields AppleSmartBattery does not expose
/// reliably: the condition on recent Macs, and macOS's own Maximum Capacity
/// percentage. `system_profiler` takes ~60 ms and the details page refreshes
/// every 2 s, so one answer (including "unknown") is reused for `ttl`. Both
/// values change over months, not minutes; the TTL is the cache's only stop
/// path. A run that did not exit cleanly is retried after `failureTTL`, and the
/// short timeout bounds how long it can hold back the rest of the page.
enum BatteryHealthSystemReader {
    static let ttl: TimeInterval = 600
    static let failureTTL: TimeInterval = 60

    /// Everything one `system_profiler` read yields. Each field is optional so
    /// a Mac that publishes one value but not the other still reports the one
    /// it has.
    struct Reading: Equatable, Sendable {
        var condition: BatteryHealthSnapshot.Condition?
        var maximumCapacityPercent: Double?
    }

    /// Runs `system_profiler` with a hard deadline. Injected so tests can drive
    /// success, failure and timeout without launching a real process.
    typealias Runner = (Duration) -> BoundedProcessOutcome

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: (expiresAt: Date, reading: Reading?)?

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
    ) -> Reading? {
        // A cached entry's lifetime is at most `ttl`, so `now < expiresAt`
        // alone decides freshness; there is no separate lifetime check.
        if let hit = lock.withLock({ cached }), now < hit.expiresAt {
            return hit.reading
        }
        var reading: Reading?
        var lifetime = failureTTL
        if case let .exited(data) = run(timeout) {
            reading = Reading(
                condition: BatteryHealthParser.condition(systemProfilerJSON: data),
                maximumCapacityPercent: BatteryHealthParser.maximumCapacityPercent(systemProfilerJSON: data)
            )
            lifetime = ttl
        }
        lock.withLock { cached = (now.addingTimeInterval(lifetime), reading) }
        return reading
    }

    /// Test hook: clears the process-wide cache so each test starts cold.
    static func resetCache() {
        lock.withLock { cached = nil }
    }
}
