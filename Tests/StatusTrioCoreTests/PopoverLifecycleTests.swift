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

