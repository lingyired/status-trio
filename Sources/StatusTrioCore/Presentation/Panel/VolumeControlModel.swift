import Combine
import Foundation

/// Owns the volume panel's presentation.
///
/// A volume drag publishes many readings a second. While this state lived in
/// `StatusPanelViewModel`'s `@Published` surface, every tick invalidated the
/// whole panel body and forced a window layout pass (#263). The panel view now
/// hands this model only to the volume row, so a tick re-renders that row
/// alone. `StatusPanelViewModel` keeps the reference non-published and remains
/// the only writer.
@MainActor
final class VolumeControlModel: ObservableObject {
    @Published private(set) var volume: VolumePanelState

    init(volume: VolumePanelState) {
        self.volume = volume
    }

    /// Publishes a new presentation and reports whether it changed. An
    /// unchanged reading must not send an `objectWillChange`, or the row
    /// re-renders on every duplicate fallback tick.
    @discardableResult
    func update(_ volume: VolumePanelState) -> Bool {
        guard self.volume != volume else { return false }
        self.volume = volume
        return true
    }
}
