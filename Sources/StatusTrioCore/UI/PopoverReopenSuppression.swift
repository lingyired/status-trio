import AppKit

/// Suppresses the status item's reopen toggle when the panel was already closed
/// by the mouse-down of the *same* click.
///
/// Issue #224 follow-up 2: the outside-click monitor closes the panel on a
/// mouse-down; the status item's action then fires on the following mouse-up and
/// `togglePopover` sees `popover.isShown == false` and presents the panel again —
/// a single click looks like it "refreshed" instead of closing. `PopoverDismissalPolicy`
/// avoids that by not dismissing when the click is inside the status item's
/// screen rectangle, but that hit test can misjudge the item on some setups
/// (multi-display / notch / menu-bar geometry, or a different macOS build), and
/// the panel still closes on mouse-down for those users.
///
/// This is the coordinate-free safety net: when any close happens while a mouse
/// button is physically held down, the panel records it. The status item's
/// mouse-up toggle that belongs to that same press then refuses to reopen. A
/// genuine outside click (no status-item toggle follows) and a real focus loss
/// (no button held) are unaffected. The short `window` bounds the stored press
/// so a much later opening click is not mistaken for the closing one.
struct PopoverReopenSuppression {
    let window: TimeInterval
    private var closedWhileMouseDownAt: Date?

    init(window: TimeInterval) {
        self.window = window
    }

    /// Records a close. Only a close that happens while a mouse button is down
    /// is remembered; a normal close from the item's own mouse-up toggle, Escape,
    /// or a panel action is not.
    mutating func recordClose(at now: Date, mouseButtonDown: Bool) {
        guard mouseButtonDown else { return }
        closedWhileMouseDownAt = now
    }

    /// Whether the pending status-item toggle should be ignored because this
    /// same click already closed the panel. Consumes the record either way.
    mutating func shouldSuppressReopen(at now: Date) -> Bool {
        guard let closedAt = closedWhileMouseDownAt else { return false }
        closedWhileMouseDownAt = nil
        return now.timeIntervalSince(closedAt) < window
    }

    mutating func reset() {
        closedWhileMouseDownAt = nil
    }
}
