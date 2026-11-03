import AppKit

/// The anchor a status panel hangs from: a positioning rect in screen
/// coordinates plus the edge of that rect the panel should sit next to.
///
/// The panel replaces `NSPopover` (issue #186), so the placement maths that the
/// popover used to own are explicit and testable here.
struct StatusPanelAnchor: Equatable {
    /// The anchor rect in screen coordinates (origin bottom-left, Y up).
    let screenRect: NSRect
    /// The edge of `screenRect` the panel attaches to, mirroring
    /// `NSPopover.show(relativeTo:of:preferredEdge:)`.
    let preferredEdge: NSRectEdge
}

/// A screen's geometry in the small shape placement needs, so the maths can be
/// unit-tested without constructing an `NSScreen`.
struct StatusPanelScreen: Equatable {
    let frame: NSRect
    let visibleFrame: NSRect

    init(frame: NSRect, visibleFrame: NSRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }

    init(_ screen: NSScreen) {
        self.init(frame: screen.frame, visibleFrame: screen.visibleFrame)
    }
}

enum StatusPanelPlacement {
    /// The visual gap between the anchor and the panel. `NSPopover` spent this
    /// distance on its arrow; with the arrow gone the panel sits close to the
    /// menu bar / Dock without touching it.
    static let gap: CGFloat = 6

    /// Chooses the frame for a panel of `contentSize` anchored at `anchor`.
    ///
    /// The panel is centred on the anchor's perpendicular axis, flushed to the
    /// chosen edge with `gap`, and clamped to the screen's visible frame. When
    /// the preferred side has no room it flips to the opposite side, matching
    /// the popover behaviour users already expect. The frame keeps its top edge
    /// fixed for `.minY` (menu bar) anchors, so a growing panel extends
    /// downwards instead of jumping.
    static func frame(
        contentSize: NSSize,
        anchor: StatusPanelAnchor,
        screens: [StatusPanelScreen],
        dockInset: NSEdgeInsets = DockReveal.noInset
    ) -> NSRect {
        let size = NSSize(
            width: max(contentSize.width, 1),
            height: max(contentSize.height, 1)
        )
        let anchorRect = anchor.screenRect
        let raw = screenContaining(anchorRect, screens: screens)
        let visibleFrame = usableFrame(
            raw?.visibleFrame ?? anchorRect,
            dockInset: dockInset
        )

        var origin: NSPoint
        switch anchor.preferredEdge {
        case .minY, .maxY:
            let below = NSPoint(
                x: anchorRect.midX - size.width / 2,
                y: anchorRect.minY - gap - size.height
            )
            let above = NSPoint(
                x: anchorRect.midX - size.width / 2,
                y: anchorRect.maxY + gap
            )
            if anchor.preferredEdge == .minY {
                origin = fitsVertically(below, size: size, in: visibleFrame) ? below : above
            } else {
                origin = fitsVertically(above, size: size, in: visibleFrame) ? above : below
            }
        case .maxX, .minX:
            let toRight = NSPoint(
                x: anchorRect.maxX + gap,
                y: anchorRect.midY - size.height / 2
            )
            let toLeft = NSPoint(
                x: anchorRect.minX - gap - size.width,
                y: anchorRect.midY - size.height / 2
            )
            if anchor.preferredEdge == .maxX {
                origin = fitsHorizontally(toRight, size: size, in: visibleFrame) ? toRight : toLeft
            } else {
                origin = fitsHorizontally(toLeft, size: size, in: visibleFrame) ? toLeft : toRight
            }
        @unknown default:
            origin = NSPoint(
                x: anchorRect.midX - size.width / 2,
                y: anchorRect.minY - gap - size.height
            )
        }

        origin.x = min(
            max(origin.x, visibleFrame.minX),
            max(visibleFrame.minX, visibleFrame.maxX - size.width)
        )
        origin.y = min(
            max(origin.y, visibleFrame.minY),
            max(visibleFrame.minY, visibleFrame.maxY - size.height)
        )
        return NSRect(origin: origin, size: size)
    }

    /// Shrinks the screen's visible frame by the clearance an auto-hidden Dock
    /// needs on the edge it reveals from.
    ///
    /// A collapsed Dock reports `visibleFrame == frame`, so placement would
    /// otherwise let a Dock-anchored panel reach the physical screen edge and
    /// overlap the revealed Dock (issue #229). A visible Dock already reduces
    /// `visibleFrame`, and `DockReveal` returns no inset there.
    private static func usableFrame(
        _ visibleFrame: NSRect,
        dockInset: NSEdgeInsets
    ) -> NSRect {
        guard !(dockInset.top == 0 && dockInset.left == 0
            && dockInset.bottom == 0 && dockInset.right == 0) else { return visibleFrame }
        let minX = visibleFrame.minX + max(0, dockInset.left)
        let maxX = visibleFrame.maxX - max(0, dockInset.right)
        let minY = visibleFrame.minY + max(0, dockInset.bottom)
        let maxY = visibleFrame.maxY - max(0, dockInset.top)
        guard maxX > minX, maxY > minY else { return visibleFrame }
        return NSRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    /// The screen whose frame contains the anchor's centre, falling back to the
    /// first screen. A menu-bar anchor can sit just outside `visibleFrame`
    /// (inside the menu bar strip), so the full `frame` is the right test.
    static func screenContaining(
        _ rect: NSRect,
        screens: [StatusPanelScreen]
    ) -> StatusPanelScreen? {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        return screens.first { $0.frame.contains(center) } ?? screens.first
    }

    /// Vertical edges flip only on the vertical axis: a wide panel that
    /// overflows the side of the screen is clamped horizontally, not flipped
    /// above/below the anchor.
    private static func fitsVertically(
        _ origin: NSPoint,
        size: NSSize,
        in visibleFrame: NSRect
    ) -> Bool {
        origin.y >= visibleFrame.minY && origin.y + size.height <= visibleFrame.maxY
    }

    /// Horizontal edges flip only on the horizontal axis, for the same reason.
    private static func fitsHorizontally(
        _ origin: NSPoint,
        size: NSSize,
        in visibleFrame: NSRect
    ) -> Bool {
        origin.x >= visibleFrame.minX && origin.x + size.width <= visibleFrame.maxX
    }
}
