import Foundation


/// What a CPU/GPU ring shows in the middle of the arc. CPU offers both because
/// its estimate comes from IOReport; GPU only exposes temperature because macOS
/// has no reliable unprivileged GPU clock reading.
enum HardwareRingCenterContent: String, CaseIterable, Identifiable, Codable, Sendable {
    case temperature
    case frequency

    var id: Self { self }

    var titleKey: LocalizationKey {
        switch self {
        case .temperature: .hardwareMonitorRingCenterTemperature
        case .frequency: .hardwareMonitorRingCenterFrequency
        }
    }
}


/// Whether a RAM/SSD ring reads as consumed or remaining. CPU/GPU rings are
/// always consumed; only memory and the SSD have a meaningful "free" side, so
/// they are configurable independently (Settings → 监控 → 环内显示).
enum RingValueDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case used
    case remaining

    var id: Self { self }

    var titleKey: LocalizationKey {
        switch self {
        case .used: .hardwareMonitorRingValueUsed
        case .remaining: .hardwareMonitorRingValueRemaining
        }
    }
}

/// The three values one ring draws, resolved from a sample and a display mode.
/// Pure so the used/remaining maths stays unit-testable without a SwiftUI host.
struct HardwareRingValueSpec: Equatable {
    let topText: String
    let centerText: String
    let progress: Double
}

enum HardwareRingValuePresentation {
    static func memory(usedPercent: Double?, totalBytes: UInt64,
                       mode: RingValueDisplayMode) -> HardwareRingValueSpec {
        guard let usedPercent, usedPercent.isFinite else {
            return HardwareRingValueSpec(topText: "0%", centerText: "--", progress: 0)
        }
        let used = min(1, max(0, usedPercent / 100))
        let fraction = mode == .used ? used : 1 - used
        let bytes = Double(totalBytes) * fraction
        return HardwareRingValueSpec(topText: topText(fraction),
                                     centerText: HardwareDetailFormat.compactMemory(bytes),
                                     progress: fraction)
    }

    static func disk(usedFraction: Double?, totalBytes: Int64?, freeBytes: Int64?,
                     mode: RingValueDisplayMode) -> HardwareRingValueSpec {
        guard let usedFraction, usedFraction.isFinite else {
            return HardwareRingValueSpec(topText: "0%", centerText: "--", progress: 0)
        }
        let used = min(1, max(0, usedFraction))
        let fraction = mode == .used ? used : 1 - used
        let bytes: Int64?
        switch mode {
        case .used: bytes = Self.usedDiskBytes(totalBytes: totalBytes, freeBytes: freeBytes)
        case .remaining: bytes = freeBytes
        }
        let center = bytes.map { HardwareDetailFormat.compactDisk(Double($0)) } ?? "--"
        return HardwareRingValueSpec(topText: topText(fraction), centerText: center, progress: fraction)
    }

    static func usedDiskBytes(totalBytes: Int64?, freeBytes: Int64?) -> Int64? {
        guard let totalBytes, let freeBytes else { return nil }
        return max(0, totalBytes - freeBytes)
    }

    /// Used fraction when the SSD ring pools the internal disk with ticked
    /// external volumes: (internal + external used) / (internal + external
    /// total). Returns nil when the internal totals are unknown or the pooled
    /// capacity is zero, so callers fall back to the internal-only value.
    static func combinedUsedFraction(internalTotal: Int64?, internalFree: Int64?,
                                     externalTotal: Int64, externalFree: Int64) -> Double? {
        guard let internalTotal, let internalFree else { return nil }
        let total = Double(max(0, internalTotal) + max(0, externalTotal))
        guard total > 0 else { return nil }
        let free = Double(max(0, internalFree) + max(0, externalFree))
        return min(1, max(0, (total - free) / total))
    }

    private static func topText(_ fraction: Double) -> String {
        String(format: "%d%%", Int((min(1, max(0, fraction)) * 100).rounded()))
    }
}
