import Foundation

/// Structured byte-rate display: the number and the unit kept apart so SwiftUI
/// can render/align them independently, with the suffix optionally omitted.
struct ByteRateDisplay: Equatable, Sendable {
    let valueText: String
    let unitText: String

    var combined: String { "\(valueText) \(unitText)" }
}

/// One shared "Stats Auto" style formatter for byte rates (always bytes/second).
/// Decimal (1000-based) units KB/s → TB/s with precision chosen by magnitude.
/// Pure and free of SwiftUI/localization so every surface (status panel, legacy
/// card, menu-bar top) forms the same number from the same input.
enum ByteRateFormatter {
    /// nil means "not a displayable rate" (negative/NaN/infinite); callers show
    /// an em dash rather than faking 0.
    static func format(bytesPerSecond: Double) -> ByteRateDisplay? {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return nil }
        let bytes = bytesPerSecond

        // 0–999 B/s reads as 0 KB/s.
        if bytes < 1_000 {
            return ByteRateDisplay(valueText: "0", unitText: "KB/s")
        }
        // 1 KB/s – just under 1 MB/s: whole KB/s (rounding up to 1000 KB → 1.0 MB).
        let kilobytes = bytes / 1_000
        if kilobytes < 1_000 {
            let rounded = Int(kilobytes.rounded())
            if rounded >= 1_000 {
                return ByteRateDisplay(valueText: "1.0", unitText: "MB/s")
            }
            return ByteRateDisplay(valueText: String(rounded), unitText: "KB/s")
        }
        // 1 – under 100 MB/s: one decimal.
        let megabytes = bytes / 1_000_000
        if megabytes < 100 {
            let text = oneDecimal(megabytes)
            if let value = Double(text), value >= 100 {
                return ByteRateDisplay(valueText: "100", unitText: "MB/s")
            }
            return ByteRateDisplay(valueText: text, unitText: "MB/s")
        }
        // 100 – under 1000 MB/s: whole MB/s.
        if megabytes < 1_000 {
            let rounded = Int(megabytes.rounded())
            if rounded >= 1_000 {
                return ByteRateDisplay(valueText: "1.0", unitText: "GB/s")
            }
            return ByteRateDisplay(valueText: String(rounded), unitText: "MB/s")
        }
        // 1 – under 1000 GB/s: one decimal GB/s (rounding up to 1000 GB → TB).
        let gigabytes = bytes / 1_000_000_000
        if gigabytes < 1_000 {
            let text = oneDecimal(gigabytes)
            if let value = Double(text), value >= 1_000 {
                return ByteRateDisplay(valueText: oneDecimal(gigabytes / 1_000), unitText: "TB/s")
            }
            return ByteRateDisplay(valueText: text, unitText: "GB/s")
        }
        return ByteRateDisplay(valueText: oneDecimal(gigabytes / 1_000), unitText: "TB/s")
    }

    /// "12.5 MB/s", or nil for an undisplayable rate.
    static func text(bytesPerSecond: Double) -> String? {
        format(bytesPerSecond: bytesPerSecond)?.combined
    }

    /// Tight glyph for the menu-bar top gap: "456K" / "12.5M" / "1.3G" / "2.0T".
    static func compact(bytesPerSecond: Double) -> String? {
        guard let display = format(bytesPerSecond: bytesPerSecond) else { return nil }
        let suffix: String
        switch display.unitText {
        case "KB/s": suffix = "K"
        case "MB/s": suffix = "M"
        case "GB/s": suffix = "G"
        case "TB/s": suffix = "T"
        default: suffix = "K"
        }
        return display.valueText + suffix
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
