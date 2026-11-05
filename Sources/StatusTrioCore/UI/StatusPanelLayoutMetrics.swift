import Combine
import CoreGraphics
import Foundation

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
    private(set) var contentHeight: CGFloat?
    @Published private(set) var fillsWindow = false
    private var contentMeasurementID: UUID?
    private var onContentHeightChange: ((CGFloat) -> Void)?

    func measure(contentHeight: CGFloat, from measurementID: UUID? = nil) {
        guard measurementID == contentMeasurementID else { return }
        guard contentHeight > 0, contentHeight.isFinite, self.contentHeight != contentHeight else { return }
        self.contentHeight = contentHeight
        onContentHeightChange?(contentHeight)
    }

    /// Only a real panel supplies a finite viewport. Standalone Settings and
    /// preview hosts still ask for an ideal size with an unbounded proposal.
    func attachWindow(
        measurementID: UUID? = nil,
        onContentHeightChange: @escaping (CGFloat) -> Void
    ) {
        contentHeight = nil
        contentMeasurementID = measurementID
        self.onContentHeightChange = onContentHeightChange
        fillsWindow = true
    }

    func update(maximumPanelHeight: CGFloat?) {
        guard self.maximumPanelHeight != maximumPanelHeight else { return }
        self.maximumPanelHeight = maximumPanelHeight
    }
}
