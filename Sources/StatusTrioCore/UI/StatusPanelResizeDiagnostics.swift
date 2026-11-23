#if DEBUG
import AppKit

/// A privacy-safe snapshot of the panel's content-resize state, used by the live
/// jitter diagnostic and the convergence regression tests.
///
/// It records geometry and animation bookkeeping only: heights, the anchored
/// edge, phase and counts. It never records a device name, UID or address, so it
/// is safe to log from a development build.
@MainActor
struct StatusPanelResizeDiagnostics: Equatable {
    enum Phase: String, Equatable {
        case idle, expanding, collapsing, settling
    }

    /// What triggered the most recent frame write during this recording.
    enum WriteTrigger: String, Equatable {
        case immediate
        case animatedTick
        case settle
    }

    var phase: Phase = .idle
    /// Window height, and the y of the anchored edge (maxY for a menu-bar panel).
    var windowHeight: CGFloat = 0
    var anchoredEdgeY: CGFloat = 0
    /// The content's natural, screen-capped target height.
    var targetHeight: CGFloat = 0
    /// Currently presented height during an animation.
    var presentedHeight: CGFloat = 0
    /// Number of frame writes, and how many retargeted a live curve.
    var frameWriteCount: Int = 0
    var retargetCount: Int = 0
    /// How many times the content was pinned / unpinned.
    var pinCount: Int = 0
    var unpinCount: Int = 0

    /// Compact, log-friendly description with no personal data.
    var debugDescription: String {
        "phase=\(phase.rawValue) h=\(windowHeight) edgeY=\(anchoredEdgeY) "
            + "target=\(targetHeight) presented=\(presentedHeight) "
            + "writes=\(frameWriteCount) retargets=\(retargetCount) "
            + "pins=\(pinCount) unpins=\(unpinCount)"
    }
}
#endif