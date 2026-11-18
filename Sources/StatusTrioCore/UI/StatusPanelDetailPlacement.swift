import AppKit

/// Sizes and positions the attached detail panel that sits beside the status
/// panel when "show details alongside" is enabled.
///
/// The maths stays in the small, NSScreen-free shape used by
/// StatusPanelPlacement so the rules are unit-testable without windows.
struct StatusPanelDetailPlacement {
    enum Side: Equatable {
        case left
        case right
    }

    struct Placement: Equatable {
        let side: Side
        let frame: NSRect

        /// The height budget the detail content may fill before it scrolls.
        var maximumHeight: CGFloat { frame.height }
    }

    /// Detail pages keep the status panel's 330 pt width so both surfaces read
    /// as one unit.
    static let width: CGFloat = 330

    /// The visual gap between the two windows.
    static let gap: CGFloat = 8

    /// Breathing room kept between the detail window and the screen edges.
    static let edgeMargin: CGFloat = 8

    static func frame(
        summaryFrame: NSRect,
        detailHeight: CGFloat,
        screens: [StatusPanelScreen],
        dockInset: NSEdgeInsets = DockReveal.noInset
    ) -> Placement? {
        guard summaryFrame.origin.x.isFinite,
              summaryFrame.origin.y.isFinite,
              summaryFrame.width.isFinite,
              summaryFrame.height.isFinite,
              summaryFrame.width > 0,
              summaryFrame.height > 0,
              detailHeight.isFinite,
              detailHeight > 0,
              let screen = screenContainingSummary(summaryFrame, screens: screens)
        else { return nil }

        let usable = StatusPanelPlacement.usableFrame(screen.visibleFrame, dockInset: dockInset)
        let inner = usable.insetBy(dx: edgeMargin, dy: edgeMargin)
        guard inner.width > 0, inner.height > 0 else { return nil }

        let height = min(detailHeight, inner.height)
        let rightX = summaryFrame.maxX + gap
        let leftX = summaryFrame.minX - gap - width

        let side: Side
        let originX: CGFloat
        if rightX >= inner.minX, rightX + width <= inner.maxX {
            side = .right
            originX = rightX
        } else if leftX >= inner.minX, leftX + width <= inner.maxX {
            side = .left
            originX = leftX
        } else {
            return nil
        }

        var originY = min(summaryFrame.maxY, inner.maxY) - height
        if originY < inner.minY { originY = inner.minY }

        return Placement(
            side: side,
            frame: NSRect(x: originX, y: originY, width: width, height: height)
        )
    }

    /// The detail window must stay on the summary's own screen. Unlike
    /// StatusPanelPlacement.screenContaining there is no first-screen
    /// fallback: a summary whose centre belongs to no known screen must not
    /// borrow an adjacent display's space.
    private static func screenContainingSummary(
        _ summaryFrame: NSRect,
        screens: [StatusPanelScreen]
    ) -> StatusPanelScreen? {
        let centre = NSPoint(x: summaryFrame.midX, y: summaryFrame.midY)
        return screens.first { $0.frame.contains(centre) }
    }
}
