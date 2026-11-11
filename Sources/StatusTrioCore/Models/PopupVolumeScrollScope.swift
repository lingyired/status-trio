import Foundation

/// Where inside the status panel a scroll gesture is allowed to change the
/// volume.
enum PopupVolumeScrollScope: String, CaseIterable, Identifiable, Sendable {
    /// Sliders adjust themselves; empty summary areas also adjust the volume.
    case panel

    /// Only while the pointer is over a slider; empty areas do nothing.
    case volumeControl

    var id: Self { self }

    /// Detail pages own their wheel events even when their content fits without
    /// scrolling. Only the summary may fall back to adjusting output volume.
    func allowsPanelAdjustment(on route: StatusPanelRoute) -> Bool {
        self == .panel && route == .summary
    }
}
