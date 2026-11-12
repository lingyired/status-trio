import Foundation

/// Formats network throughput (bytes/second) for the monitor card and ring top.
enum NetworkSpeedFormatter {
    /// "12.3 MB/s" at/above 1 MB/s, otherwise "456 KB/s".
    static func display(bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        let megabytes = value / 1_000_000
        if megabytes >= 1 {
            return String(format: "%.1f MB/s", megabytes)
        }
        return "\(Int((value / 1000).rounded())) KB/s"
    }

    /// Compact glyph for the tight ring top gap: "12.3M" / "456K".
    static func compact(bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        let megabytes = value / 1_000_000
        if megabytes >= 1 {
            return String(format: "%.1fM", megabytes)
        }
        return "\(Int((value / 1000).rounded()))K"
    }
}
