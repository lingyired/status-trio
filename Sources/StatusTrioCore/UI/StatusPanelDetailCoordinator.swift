import AppKit

/// Chooses how the selected detail page is presented for the current panel
/// geometry: hidden without a detail, inline when no side panel fits, or
/// alongside the summary when there is room on the same screen.
@MainActor
struct StatusPanelDetailCoordinator {
    enum Decision: Equatable {
        case hidden
        case inline
        case alongside(StatusPanelDetailPlacement.Placement)
    }

    private struct Geometry: Equatable {
        let summaryMinX: CGFloat
        let summaryMaxX: CGFloat
        let screenFrame: NSRect
        let visibleFrame: NSRect
        let dockTop: CGFloat
        let dockLeft: CGFloat
        let dockBottom: CGFloat
        let dockRight: CGFloat

        init(summaryFrame: NSRect, screen: StatusPanelScreen, dockInset: NSEdgeInsets) {
            summaryMinX = summaryFrame.minX
            summaryMaxX = summaryFrame.maxX
            screenFrame = screen.frame
            visibleFrame = screen.visibleFrame
            dockTop = dockInset.top
            dockLeft = dockInset.left
            dockBottom = dockInset.bottom
            dockRight = dockInset.right
        }
    }

    private(set) var decision: Decision = .hidden
    private var chosenSide: StatusPanelDetailPlacement.Side?
    private var geometry: Geometry?

    /// Re-decides the presentation. Changing only the route or the vertical
    /// position keeps the side already in use; a horizontal screen change or a
    /// different display re-evaluates the preferred right side first.
    @discardableResult
    mutating func update(
        route: StatusPanelRoute,
        enabled: Bool,
        summaryFrame: NSRect,
        screens: [StatusPanelScreen],
        dockInset: NSEdgeInsets = DockReveal.noInset,
        limitsToSummaryHeight: Bool = false
    ) -> Decision {
        guard enabled, route != .summary else {
            decision = .hidden
            chosenSide = nil
            geometry = nil
            return .hidden
        }

        let centre = NSPoint(x: summaryFrame.midX, y: summaryFrame.midY)
        let screen = screens.first { $0.frame.contains(centre) }
        let nextGeometry = screen.map { Geometry(summaryFrame: summaryFrame, screen: $0, dockInset: dockInset) }
        let stable = nextGeometry != nil && nextGeometry == geometry
        let preferredSide = stable ? chosenSide : nil

        guard let placement = StatusPanelDetailPlacement.frame(
            summaryFrame: summaryFrame,
            detailHeight: .greatestFiniteMagnitude,
            screens: screens,
            dockInset: dockInset,
            preferredSide: preferredSide,
            limitsToSummaryHeight: limitsToSummaryHeight
        ) else {
            decision = .inline
            chosenSide = nil
            geometry = nextGeometry
            return .inline
        }

        chosenSide = placement.side
        geometry = nextGeometry
        decision = .alongside(placement)
        return decision
    }
}
