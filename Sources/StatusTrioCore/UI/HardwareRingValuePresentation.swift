import Foundation

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

    private static func topText(_ fraction: Double) -> String {
        String(format: "%d%%", Int((min(1, max(0, fraction)) * 100).rounded()))
    }
}
