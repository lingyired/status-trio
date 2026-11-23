import Foundation

/// Pure countdown math for the keep-awake pills (#295).
///
/// Deliberately free of UI, timers and locale so the progress fractions and the
/// "never show 0 minutes while running" rule are unit-testable without a live
/// panel or a running clock.
enum SleepProgress {
    /// Fraction of the configured duration still remaining, clamped to 0...1.
    /// A `nil` total means "unlimited", which stays full while running.
    static func fraction(remaining: TimeInterval, total: TimeInterval?) -> Double {
        guard let total, total > 0 else { return 1 }
        return min(1, max(0, remaining / total))
    }

    /// Seconds left until `expiry`, never negative.
    static func remaining(until expiry: Date, now: Date) -> TimeInterval {
        max(0, expiry.timeIntervalSince(now))
    }

    /// Whole minutes to display while a countdown runs. Rounded up and floored
    /// at 1, so a still-running timer never reads "剩余 0 分钟".
    static func displayMinutes(remaining: TimeInterval) -> Int {
        max(1, Int((remaining / 60).rounded(.up)))
    }
}
