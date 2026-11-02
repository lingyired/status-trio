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
        return !statusItemFrame.contains(point)
    }
}
