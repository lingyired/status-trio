import Foundation

/// Where inside the status panel a scroll gesture is allowed to change the
/// volume.
enum PopupVolumeScrollScope: String, CaseIterable, Identifiable, Sendable {
    /// Sliders adjust themselves; empty panel areas also adjust the volume.
    case panel

    /// Only while the pointer is over a slider; empty areas do nothing.
    case volumeControl

    var id: Self { self }
}
