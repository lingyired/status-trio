import AppKit

/// Decides whether a global mouse-down is an *outside* click that should
/// dismiss the status panel.
///
/// Issue #224: when the app is not active after the panel opens, a click on the
/// status item itself is delivered by the system menu bar process and reaches
/// `NSEvent.addGlobalMonitorForEvents`. Dismissing on that mouse-down closed the
/// panel, and the status item's own mouse-up toggle then presented it again, so
/// a single click looked like "does not close" and required a double click. Each
/// re-present also ordered windows and re-requested activation, which made other
/// windows flicker.
///
/// A click inside the status item button's rectangle is the item's own toggle,
/// never an outside click. The controller lets `togglePopover` own it.
struct PopoverDismissalPolicy: Equatable {
    /// The status item button's rectangle in screen coordinates, when the item
    /// is visible. `nil` means the item is not mounted or hidden; there is no
    /// toggle to protect, so every click is treated as an outside click.
    let statusItemFrame: NSRect?

    func shouldDismiss(at point: NSPoint) -> Bool {
        guard let statusItemFrame else { return true }
        return !Self.containsInclusive(statusItemFrame, point)
    }

    /// Whether `frame` covers `point` **including its right and top edges**.
    ///
    /// `NSRect.contains(_:)` (and `NSPointInRect` / `NSMouseInRect`) treat the
    /// rectangle as half-open: `maxX` and `maxY` fall *outside* it. A click on
    /// the status item's rightmost or topmost pixel therefore looked like an
    /// outside click, so the panel closed on mouse-down and the item's mouse-up
    /// toggle reopened it — the "click the very edge and it refreshes instead of
    /// closing" report on v1.9.4 (issue #224).
    ///
    /// Menu-bar items are small and are clicked at their edges, so the inclusive
    /// test is the correct one. The frame is compared as-is: widening it would
    /// swallow a real outside click on the neighbouring menu-bar item.
    static func containsInclusive(_ frame: NSRect, _ point: NSPoint) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX
            && point.y >= frame.minY && point.y <= frame.maxY
    }

    /// Decides whether a *focus-loss* dismissal should go ahead.
    ///
    /// Issue #224 follow-up: while the app itself is active (it is `regular`
    /// because the Settings or first-run window is open, or the Dock icon is
    /// shown), a click on the status item makes the app resign active. The
    /// panel's `didResignActive` and `another app activated` observers then
    /// close it on mouse-down, and the status item's own mouse-up toggle
    /// re-presents it — the same "looks like it refreshed instead of closing"
    /// bug, now on a second close path the outside-click monitor does not cover
    /// (the monitor ignores events delivered to this app while it is active).
    ///
    /// Defer the close while a mouse button is actually held down on the status
    /// item, so the item's own toggle owns the click. A genuine focus loss with
    /// no button pressed — Cmd-Tab, a Space switch, clicking another app — still
    /// dismisses, even if the pointer happens to rest over the item, so the
    /// #183 full-screen / Cmd-Tab dismissal stays intact.
    func shouldDismissOnFocusLoss(
        at point: NSPoint,
        isMouseButtonDown: Bool
    ) -> Bool {
        if isMouseButtonDown, let statusItemFrame,
           Self.containsInclusive(statusItemFrame, point) {
            return false
        }
        return true
    }
}
