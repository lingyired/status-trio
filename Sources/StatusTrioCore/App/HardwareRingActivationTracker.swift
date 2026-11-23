import Foundation

/// Records which inner/outer-ring source the icon actually resolved to during
/// the last scene build. Demand can then follow the *selected* source instead of
/// the configured primary/fallback pair, so a hardware ring kept only as a
/// fallback never starts the sampler until the fallback is actually on screen.
@MainActor
final class HardwareRingActivationTracker {
    private(set) var selectedOuterRingSourceID: String?

    var isHardwareRingSelected: Bool {
        selectedOuterRingSourceID == RingSource.hardwareMonitor.rawValue
    }

    func update(_ sourceID: String?) {
        selectedOuterRingSourceID = sourceID
    }
}
