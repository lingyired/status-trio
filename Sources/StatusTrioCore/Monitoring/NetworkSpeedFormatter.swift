import Foundation

/// Formats network throughput (bytes/second) for the monitor card, summary row
/// and ring top. Delegates to the shared `ByteRateFormatter` so every surface
/// uses the same Auto unit/precision rules; this type only adapts the return
/// shape expected by existing call sites.
enum NetworkSpeedFormatter {
    /// "12.3 MB/s" style; "—" for an undisplayable (non-finite) value.
    static func display(bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite else { return "—" }
        return ByteRateFormatter.text(bytesPerSecond: Swift.max(0, bytesPerSecond)) ?? "—"
    }

    /// Compact glyph for the tight ring top gap: "12.5M" / "456K". Returns an
    /// em dash for an undisplayable value so the non-optional ring-top call site
    /// stays simple.
    static func compact(bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite else { return "—" }
        return ByteRateFormatter.compact(bytesPerSecond: Swift.max(0, bytesPerSecond)) ?? "—"
    }
}
