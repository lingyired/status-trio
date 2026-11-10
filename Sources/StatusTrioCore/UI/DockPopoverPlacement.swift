import AppKit

/// Where the Dock lives on screen. Its orientation is not exposed directly, but
/// it is the only thing that can shrink a screen's visible frame horizontally.
enum DockPlacement: Equatable {
    case bottom
    case left
    case right

    static func resolve(screenFrame: NSRect, visibleFrame: NSRect) -> DockPlacement {
        if visibleFrame.minX > screenFrame.minX {
            return .left
        }
        if visibleFrame.maxX < screenFrame.maxX {
            return .right
        }
        return .bottom
    }

    /// Whether a screen point sits in the Dock's strip along the screen edge.
    ///
    /// With a visible Dock the strip is the part of the screen the Dock takes
    /// away; with an auto-hiding Dock the visible frame fills the screen, so the
    /// edge tolerance is the only usable signal.
    func containsPointer(
        _ point: NSPoint,
        screenFrame: NSRect,
        visibleFrame: NSRect,
        collapsedTolerance: CGFloat = 120
    ) -> Bool {
        switch self {
        case .bottom:
            let strip = visibleFrame.minY - screenFrame.minY
            let limit = strip > 4 ? visibleFrame.minY : screenFrame.minY + collapsedTolerance
            return point.y <= limit
        case .left:
            let strip = visibleFrame.minX - screenFrame.minX
            let limit = strip > 4 ? visibleFrame.minX : screenFrame.minX + collapsedTolerance
            return point.x <= limit
        case .right:
            let strip = screenFrame.maxX - visibleFrame.maxX
            let limit = strip > 4 ? visibleFrame.maxX : screenFrame.maxX - collapsedTolerance
            return point.x >= limit
        }
    }
}

/// The clearance a Dock-anchored status panel must leave for an auto-hidden
/// Dock that reveals under the pointer (issue #229).
///
/// With the Dock set to auto-hide, `NSScreen.visibleFrame` equals `frame`, so a
/// panel placed against `visibleFrame` can reach the physical screen edge and
/// overlap the revealed Dock, which sits below the panel's window level. When the
/// Dock is visible its `visibleFrame` already excludes it and no inset is needed.
enum DockReveal {
    /// A strip this thin means the Dock is collapsed on that edge. Matches the
    /// visible/collapsed threshold in `DockPlacement.containsPointer`.
    static let collapsedStrip: CGFloat = 4

    /// Reveal depth for a bottom Dock. A revealed Dock extends past a single
    /// tile (icon padding, magnification, glass background); `dockTile` reports
    /// the collapsed tile only, so a documented conservative constant is used
    /// (issue #229 suggests ~90–100pt).
    static let extent: CGFloat = 96

    /// Reveal width for a left/right Dock. A side Dock is narrower than the
    /// bottom one (a visible side Dock measures ~64pt wide), so a small padding
    /// over that keeps the panel close without overlapping the reveal strip.
    static let sideExtent: CGFloat = 72

    /// The reveal depth/width for a Dock on the given edge.
    static func revealExtent(for placement: DockPlacement) -> CGFloat {
        placement == .bottom ? extent : sideExtent
    }

    /// No clearance. Used as the default inset and as the "visible Dock" result.
    static let noInset = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    /// The edge a collapsed Dock hides on, or `nil` when the Dock is visible.
    ///
    /// A collapsed Dock leaves `visibleFrame == frame` on every edge, so the
    /// frames cannot say which edge it hides on; the pointer — which is on the
    /// revealed Dock's icon — picks the nearest edge.
    static func collapsedPlacement(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        pointer: NSPoint
    ) -> DockPlacement? {
        let bottomStrip = visibleFrame.minY - screenFrame.minY
        let leftStrip = visibleFrame.minX - screenFrame.minX
        let rightStrip = screenFrame.maxX - visibleFrame.maxX
        // Any visible Dock already shrinks visibleFrame along its edge.
        guard max(bottomStrip, leftStrip, rightStrip) <= collapsedStrip else {
            return nil
        }
        let toBottom = pointer.y - screenFrame.minY
        let toLeft = pointer.x - screenFrame.minX
        let toRight = screenFrame.maxX - pointer.x
        if toBottom <= toLeft, toBottom <= toRight {
            return .bottom
        }
        return toLeft <= toRight ? .left : .right
    }

    /// The clearance to reserve for an auto-hidden Dock on the edge it reveals
    /// from, or `noInset` when the Dock is visible on any edge.
    static func inset(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        pointer: NSPoint
    ) -> NSEdgeInsets {
        guard let placement = collapsedPlacement(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            pointer: pointer
        ) else {
            return noInset
        }
        let extent = revealExtent(for: placement)
        switch placement {
        case .bottom:
            return NSEdgeInsets(top: 0, left: 0, bottom: extent, right: 0)
        case .left:
            return NSEdgeInsets(top: 0, left: extent, bottom: 0, right: 0)
        case .right:
            return NSEdgeInsets(top: 0, left: 0, bottom: 0, right: extent)
        }
    }

    /// Whether the Dock is collapsed (auto-hidden) on every edge.
    static func isCollapsed(screenFrame: NSRect, visibleFrame: NSRect) -> Bool {
        let bottomStrip = visibleFrame.minY - screenFrame.minY
        let leftStrip = visibleFrame.minX - screenFrame.minX
        let rightStrip = screenFrame.maxX - visibleFrame.maxX
        return max(bottomStrip, leftStrip, rightStrip) <= collapsedStrip
    }

    /// The screen coordinate of the Dock's inner edge along the dock axis: where
    /// a Dock-anchored panel should attach so it sits a small, constant gap away
    /// from the Dock instead of a gap that grows with where the icon was clicked.
    ///
    /// Visible Dock: the matching `visibleFrame` edge. Collapsed Dock: the
    /// physical screen edge pushed in by `extent`, the reveal area it occupies
    /// when it pops up.
    static func dockEdge(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        placement: DockPlacement
    ) -> CGFloat {
        let collapsed = isCollapsed(screenFrame: screenFrame, visibleFrame: visibleFrame)
        let extent = revealExtent(for: placement)
        switch placement {
        case .bottom:
            return collapsed ? screenFrame.minY + extent : visibleFrame.minY
        case .left:
            return collapsed ? screenFrame.minX + extent : visibleFrame.minX
        case .right:
            return collapsed ? screenFrame.maxX - extent : visibleFrame.maxX
        }
    }
}

/// The hidden anchor window position and popover edge for a Dock icon click.
struct DockPopoverAnchor: Equatable {
    let origin: NSPoint
    let preferredEdge: NSRectEdge

    static func make(
        clickPoint: NSPoint,
        tileSize: NSSize,
        placement: DockPlacement
    ) -> DockPopoverAnchor {
        let tileWidth = max(0, tileSize.width)
        let tileHeight = max(0, tileSize.height)

        switch placement {
        case .bottom:
            return DockPopoverAnchor(
                origin: NSPoint(x: clickPoint.x, y: clickPoint.y + tileHeight / 2),
                preferredEdge: .maxY
            )
        case .left:
            return DockPopoverAnchor(
                origin: NSPoint(x: clickPoint.x + tileWidth / 2, y: clickPoint.y),
                preferredEdge: .maxX
            )
        case .right:
            return DockPopoverAnchor(
                origin: NSPoint(x: clickPoint.x - tileWidth / 2, y: clickPoint.y),
                preferredEdge: .minX
            )
        }
    }
}
