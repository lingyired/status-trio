import AppKit
import Foundation
import Testing
@testable import StatusTrioCore

struct PopoverToggleGateTests {
    @Test func acceptsTheFirstToggleImmediately() {
        var gate = PopoverToggleGate(lockout: 0.25)
        let start = Date()

        let accepted = gate.shouldAccept(at: start)
        #expect(accepted)
    }

    @Test func ignoresRepeatsInsideTheLockout() {
        var gate = PopoverToggleGate(lockout: 0.25)
        let start = Date()
        _ = gate.shouldAccept(at: start)

        let shortlyAfter = gate.shouldAccept(at: start.addingTimeInterval(0.1))
        let justInsideLockout = gate.shouldAccept(at: start.addingTimeInterval(0.24))
        #expect(shortlyAfter == false)
        #expect(justInsideLockout == false)
    }

    @Test func acceptsAgainAfterTheLockout() {
        var gate = PopoverToggleGate(lockout: 0.25)
        let start = Date()
        _ = gate.shouldAccept(at: start)

        let afterLockout = gate.shouldAccept(at: start.addingTimeInterval(0.25))
        #expect(afterLockout)
    }
}

@MainActor
struct PopoverContentRetentionTests {
    @Test func usesOneDeterministicFiveSecondReleaseContract() {
        #expect(StatusBarController.popoverContentReleaseDelay == 5)
    }
}

/// Issue #224: a single click on the status item must toggle the panel exactly
/// once. The outside-click monitor must leave a click inside the item's
/// rectangle to the item's own `togglePopover`; otherwise the mouse-down
/// closes the panel and the mouse-up reopens it.
struct PopoverDismissalPolicyTests {
    private let statusItemFrame = NSRect(x: 100, y: 900, width: 30, height: 24)

    @Test func ignoresMouseDownInsideTheStatusItem() {
        let policy = PopoverDismissalPolicy(statusItemFrame: statusItemFrame)
        let center = NSPoint(x: statusItemFrame.midX, y: statusItemFrame.midY)

        #expect(policy.shouldDismiss(at: center) == false)
    }

    @Test func ignoresMouseDownJustInsideTheStatusItemEdge() {
        let policy = PopoverDismissalPolicy(statusItemFrame: statusItemFrame)
        // `NSRect.contains` is half-open, so probe just inside the top-left
        // corner rather than exactly on the excluded maximum edge.
        let topLeftInside = NSPoint(
            x: statusItemFrame.minX + 0.5,
            y: statusItemFrame.maxY - 0.5
        )

        #expect(policy.shouldDismiss(at: topLeftInside) == false)
    }

    @Test func dismissesMouseDownOutsideTheStatusItem() {
        let policy = PopoverDismissalPolicy(statusItemFrame: statusItemFrame)
        let elsewhere = NSPoint(x: statusItemFrame.maxX + 1, y: statusItemFrame.midY)

        #expect(policy.shouldDismiss(at: elsewhere))
    }

    @Test func dismissesWhenTheStatusItemIsNotVisible() {
        let policy = PopoverDismissalPolicy(statusItemFrame: nil)

        #expect(policy.shouldDismiss(at: NSPoint(x: 0, y: 0)))
    }

    /// Composes the two halves of one gesture: the global monitor's mouse-down
    /// decision followed by the status item's mouse-up toggle. A click on the
    /// item must leave the panel visible for the toggle, so the gesture closes
    /// it once instead of closing and reopening (the old #224 behaviour).
    @Test func singleStatusItemClickTogglesExactlyOnce() {
        let policy = PopoverDismissalPolicy(statusItemFrame: statusItemFrame)
        var panelVisible = true

        // Mouse-down: the outside-click monitor runs first.
        let click = NSPoint(x: statusItemFrame.midX, y: statusItemFrame.midY)
        if policy.shouldDismiss(at: click) {
            panelVisible = false
        }

        // Mouse-up: the status item's own toggle flips the panel.
        panelVisible.toggle()

        #expect(panelVisible == false)
    }
}


/// Issue #224 follow-up: while the app itself is active (regular mode), a status
/// item click makes the app resign active. The focus-loss close paths must leave
/// that click to the item's own mouse-up toggle instead of closing on mouse-down
/// and reopening on mouse-up.
struct PopoverFocusLossDismissalPolicyTests {
    private let statusItemFrame = NSRect(x: 100, y: 900, width: 30, height: 24)
    private var itemCenter: NSPoint {
        NSPoint(x: statusItemFrame.midX, y: statusItemFrame.midY)
    }

    @Test func defersFocusLossWhilePressingTheStatusItem() {
        let policy = PopoverDismissalPolicy(statusItemFrame: statusItemFrame)

        #expect(
            policy.shouldDismissOnFocusLoss(
                at: itemCenter,
                isMouseButtonDown: true
            ) == false
        )
    }

    @Test func dismissesFocusLossWhenPressingOutsideTheItem() {
        let policy = PopoverDismissalPolicy(statusItemFrame: statusItemFrame)
        let elsewhere = NSPoint(x: 10, y: 10)

        #expect(
            policy.shouldDismissOnFocusLoss(
                at: elsewhere,
                isMouseButtonDown: true
            )
        )
    }

    /// Cmd-Tab away with the pointer parked over the menu bar item must still
    /// dismiss (issue #183 keeps working): no button is pressed.
    @Test func dismissesFocusLossWithNoButtonPressedEvenOverTheItem() {
        let policy = PopoverDismissalPolicy(statusItemFrame: statusItemFrame)

        #expect(
            policy.shouldDismissOnFocusLoss(
                at: itemCenter,
                isMouseButtonDown: false
            )
        )
    }

    @Test func dismissesFocusLossWhenTheItemFrameIsUnknown() {
        let policy = PopoverDismissalPolicy(statusItemFrame: nil)

        #expect(
            policy.shouldDismissOnFocusLoss(
                at: NSPoint(x: 0, y: 0),
                isMouseButtonDown: true
            )
        )
    }

    /// Composes the active-app gesture: the focus-loss notification arrives on
    /// mouse-down and must defer, then the item's mouse-up toggle closes the
    /// panel exactly once instead of the panel closing then reopening.
    @Test func activeAppStatusItemClickClosesExactlyOnce() {
        let policy = PopoverDismissalPolicy(statusItemFrame: statusItemFrame)
        var panelVisible = true

        // Mouse-down: the focus-loss observer runs and defers.
        if policy.shouldDismissOnFocusLoss(at: itemCenter, isMouseButtonDown: true) {
            panelVisible = false
        }
        // Mouse-up: the status item's own toggle flips the panel.
        panelVisible.toggle()

        #expect(panelVisible == false)
    }
}

/// Issue #224 follow-up 2: when the mouse-down already closed the panel, the
/// same click's mouse-up must not reopen it — the coordinate-free safety net for
/// setups where the status-item hit test misjudges the item.
struct PopoverReopenSuppressionTests {
    private let window: TimeInterval = 0.35

    @Test func suppressesReopenAfterAMouseDownClose() {
        var suppression = PopoverReopenSuppression(window: window)
        let close = Date()
        suppression.recordClose(at: close, mouseButtonDown: true)

        let suppressed = suppression.shouldSuppressReopen(
            at: close.addingTimeInterval(0.05)
        )
        #expect(suppressed)
    }

    @Test func doesNotSuppressWhenTheCloseWasNotAMouseDown() {
        var suppression = PopoverReopenSuppression(window: window)
        let close = Date()
        // The item's own toggle closes on mouse-up: a legitimate close.
        suppression.recordClose(at: close, mouseButtonDown: false)

        let suppressed = suppression.shouldSuppressReopen(
            at: close.addingTimeInterval(0.05)
        )
        #expect(suppressed == false)
    }

    @Test func doesNotSuppressALaterOpeningClick() {
        var suppression = PopoverReopenSuppression(window: window)
        let close = Date()
        suppression.recordClose(at: close, mouseButtonDown: true)

        let suppressed = suppression.shouldSuppressReopen(
            at: close.addingTimeInterval(window + 0.01)
        )
        #expect(suppressed == false)
    }

    @Test func consumesTheRecordSoOnlyOneToggleIsSuppressed() {
        var suppression = PopoverReopenSuppression(window: window)
        let close = Date()
        suppression.recordClose(at: close, mouseButtonDown: true)

        let first = suppression.shouldSuppressReopen(at: close.addingTimeInterval(0.05))
        let second = suppression.shouldSuppressReopen(at: close.addingTimeInterval(0.06))
        #expect(first)
        #expect(second == false)
    }

    @Test func resetClearsAPendingRecord() {
        var suppression = PopoverReopenSuppression(window: window)
        let close = Date()
        suppression.recordClose(at: close, mouseButtonDown: true)

        suppression.reset()

        let suppressed = suppression.shouldSuppressReopen(
            at: close.addingTimeInterval(0.05)
        )
        #expect(suppressed == false)
    }

    /// The whole failing gesture: mouse-down closes the panel (outside-click
    /// monitor), then the status item's mouse-up toggle must keep it closed
    /// instead of reopening it.
    @Test func mouseDownCloseThenMouseUpToggleKeepsThePanelClosed() {
        var suppression = PopoverReopenSuppression(window: window)
        let mouseDown = Date()
        var panelVisible = true

        // Mouse-down: the outside-click monitor closes the panel.
        panelVisible = false
        suppression.recordClose(at: mouseDown, mouseButtonDown: true)

        // Mouse-up: the status item's toggle runs but is suppressed.
        let mouseUp = mouseDown.addingTimeInterval(0.08)
        if !panelVisible, suppression.shouldSuppressReopen(at: mouseUp) {
            // stay closed
        } else {
            panelVisible.toggle()
        }

        #expect(panelVisible == false)
    }
}

/// Issue #224 (reported again on v1.9.4 / macOS 27.0.1, pure menu-bar mode):
/// clicking the status item's **very edge** reopened the panel instead of
/// closing it. `NSRect.contains` is half-open, so a click exactly on `maxX` or
/// `maxY` counted as an outside click: the monitor closed on mouse-down and the
/// item's mouse-up toggle reopened it.
struct PopoverDismissalPolicyEdgeTests {
    private let frame = NSRect(x: 100, y: 900, width: 30, height: 22)

    @Test func ignoresMouseDownOnTheRightEdge() {
        let policy = PopoverDismissalPolicy(statusItemFrame: frame)
        let rightEdge = NSPoint(x: frame.maxX, y: frame.midY)

        #expect(policy.shouldDismiss(at: rightEdge) == false)
    }

    @Test func ignoresMouseDownOnTheTopEdge() {
        let policy = PopoverDismissalPolicy(statusItemFrame: frame)
        let topEdge = NSPoint(x: frame.midX, y: frame.maxY)

        #expect(policy.shouldDismiss(at: topEdge) == false)
    }

    @Test func ignoresMouseDownOnEveryCorner() {
        let policy = PopoverDismissalPolicy(statusItemFrame: frame)
        let corners = [
            NSPoint(x: frame.minX, y: frame.minY),
            NSPoint(x: frame.maxX, y: frame.minY),
            NSPoint(x: frame.minX, y: frame.maxY),
            NSPoint(x: frame.maxX, y: frame.maxY)
        ]

        for corner in corners {
            #expect(policy.shouldDismiss(at: corner) == false)
        }
    }

    /// The inclusive edge must not swallow a genuine outside click just past it.
    @Test func stillDismissesImmediatelyOutsideTheEdges() {
        let policy = PopoverDismissalPolicy(statusItemFrame: frame)
        let pastRight = NSPoint(x: frame.maxX + 0.5, y: frame.midY)
        let aboveTop = NSPoint(x: frame.midX, y: frame.maxY + 0.5)
        let pastLeft = NSPoint(x: frame.minX - 0.5, y: frame.midY)
        let belowBottom = NSPoint(x: frame.midX, y: frame.minY - 0.5)

        #expect(policy.shouldDismiss(at: pastRight))
        #expect(policy.shouldDismiss(at: aboveTop))
        #expect(policy.shouldDismiss(at: pastLeft))
        #expect(policy.shouldDismiss(at: belowBottom))
    }

    /// The focus-loss path had the same half-open bug.
    @Test func ignoresFocusLossPressingTheRightEdge() {
        let policy = PopoverDismissalPolicy(statusItemFrame: frame)
        let rightEdge = NSPoint(x: frame.maxX, y: frame.midY)

        let shouldDismiss = policy.shouldDismissOnFocusLoss(
            at: rightEdge,
            isMouseButtonDown: true
        )
        #expect(shouldDismiss == false)
    }

    @Test func ignoresFocusLossPressingTheTopEdge() {
        let policy = PopoverDismissalPolicy(statusItemFrame: frame)
        let topEdge = NSPoint(x: frame.midX, y: frame.maxY)

        let shouldDismiss = policy.shouldDismissOnFocusLoss(
            at: topEdge,
            isMouseButtonDown: true
        )
        #expect(shouldDismiss == false)
    }

    /// `NSRect.contains` really is half-open — the assumption this fix rests on.
    /// If a future SDK changed it, the explicit inclusive test stays correct but
    /// this documents why the helper exists.
    @Test func nsRectContainsIsHalfOpenOnMaxEdges() {
        let point = NSPoint(x: frame.maxX, y: frame.midY)

        #expect(frame.contains(point) == false)
        #expect(PopoverDismissalPolicy.containsInclusive(frame, point))
    }

    /// The reported gesture at the edge: monitor decision then item toggle.
    @Test func edgeClickClosesExactlyOnce() {
        let policy = PopoverDismissalPolicy(statusItemFrame: frame)
        var panelVisible = true

        let click = NSPoint(x: frame.maxX, y: frame.midY)
        if policy.shouldDismiss(at: click) {
            panelVisible = false
        }
        panelVisible.toggle()

        #expect(panelVisible == false)
    }
}
