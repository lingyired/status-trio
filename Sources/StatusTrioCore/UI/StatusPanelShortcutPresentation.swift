import AppKit

struct StatusPanelShortcutScreen {
    let frame: NSRect
    let visibleFrame: NSRect
}

enum StatusPanelShortcutAnchor: Equatable {
    case menuBar
    case fallback(origin: NSPoint, preferredEdge: NSRectEdge)
}

enum StatusPanelShortcutPresentationAction: Equatable {
    case open
    case close
    case ignore
}

enum StatusPanelShortcutPresentationPolicy {
    static func action(
        isPopoverShown: Bool,
        isPopoverClosing: Bool = false
    ) -> StatusPanelShortcutPresentationAction {
        if isPopoverClosing {
            return .ignore
        }
        return isPopoverShown ? .close : .open
    }

    static func anchor(
        menuBarRect: NSRect?,
        isMenuBarVisible: Bool,
        pointerLocation: NSPoint,
        screens: [StatusPanelShortcutScreen],
        fallbackInset: CGFloat = 1
    ) -> StatusPanelShortcutAnchor {
        if isMenuBarVisible,
           let menuBarRect,
           isUsableMenuBarRect(menuBarRect, screens: screens) {
            return .menuBar
        }

        // Use one stable, menu-bar-like point rather than Dock-tile geometry:
        // the pointer only selects the screen that should receive the panel.
        let screen =
            screens.first { $0.frame.contains(pointerLocation) }
            ?? screens.first
        guard let screen else {
            return .fallback(origin: .zero, preferredEdge: .minY)
        }

        let visibleFrame = screen.visibleFrame
        let horizontalInset = min(
            max(0, fallbackInset),
            max(0, visibleFrame.width / 2)
        )
        let verticalInset = min(
            max(0, fallbackInset),
            max(0, visibleFrame.height / 2)
        )
        let origin = NSPoint(
            x: min(
                max(visibleFrame.midX, visibleFrame.minX + horizontalInset),
                visibleFrame.maxX - horizontalInset
            ),
            y: visibleFrame.maxY - verticalInset
        )
        return .fallback(origin: origin, preferredEdge: .minY)
    }

    private static func isUsableMenuBarRect(
        _ rect: NSRect,
        screens: [StatusPanelShortcutScreen]
    ) -> Bool {
        guard rect.width > 0,
              rect.height > 0,
              rect.minX.isFinite,
              rect.maxX.isFinite,
              rect.minY.isFinite,
              rect.maxY.isFinite else {
            return false
        }
        guard let screen = screens.first(where: { $0.frame.intersects(rect) }) else {
            return false
        }

        // A status item is small. Reject a stale bottom-left frame and the
        // whole menu-bar window that AppKit briefly reports during lifecycle
        // churn; both produce a plausible but wrong keyboard anchor.
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        guard menuBarHeight > 0,
              rect.width <= screen.frame.width / 2,
              rect.height <= max(menuBarHeight * 1.5, 32),
              abs(rect.maxY - screen.frame.maxY) <= max(menuBarHeight, 8) else {
            return false
        }
        return true
    }
}
