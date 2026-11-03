import Combine
import CoreGraphics

/// The height budget the status panel currently has on the screen it hangs
/// from (issue #237).
///
/// The panel window owns the placement maths; the SwiftUI content needs the
/// same number so its outer scroll view can cap itself and scroll instead of
/// letting the window grow past the screen. `@Published` makes the content
/// re-lay-out after a screen change, a Dock show/hide, or a menu bar geometry
/// change re-computes the cap.
@MainActor
final class StatusPanelLayoutMetrics: ObservableObject {
    /// The tallest the panel content may become, in points. `nil` before the
    /// first placement, which leaves the content unconstrained.
    @Published private(set) var maximumPanelHeight: CGFloat?

    func update(maximumPanelHeight: CGFloat?) {
        guard self.maximumPanelHeight != maximumPanelHeight else { return }
        self.maximumPanelHeight = maximumPanelHeight
    }
}
