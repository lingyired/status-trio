import AppKit
import Testing
@testable import StatusTrioCore

/// Issue #267: when the Settings window is already open, opening the status
/// panel and then clicking the Settings window must close the panel the way
/// clicking any other app's window does. The panel is a custom non-activating
/// `NSPanel`, so the controller observes `NSWindow.didBecomeKeyNotification` /
/// `didBecomeMainNotification`. This suite locks the *decision* boundaries so
/// the fix does not regress into closing on the panel's own controls, sheets,
/// menus or confirmations.
struct PanelFocusDismissPolicyTests {
    private let policy = PanelFocusDismissPolicy()

    private func candidate(
        isPanel: Bool = false,
        isVisible: Bool = true,
        level: NSWindow.Level = .normal,
        hasSheetParent: Bool = false,
        hasParent: Bool = false
    ) -> PanelFocusDismissPolicy.FocusedWindow {
        PanelFocusDismissPolicy.FocusedWindow(
            isPanel: isPanel,
            isVisible: isVisible,
            level: level,
            hasSheetParent: hasSheetParent,
            hasParent: hasParent
        )
    }

    // MARK: - Dismissing (the #267 fix)

    @Test func dismissesWhenTheSettingsWindowBecomesKey() {
        // The Settings window is a normal, independent, visible window. This is
        // exactly the click in the reported bug.
        #expect(policy.shouldDismiss(for: candidate()))
    }

    @Test func dismissesWhenTheSettingsWindowBecomesMain() {
        // `didBecomeMainNotification` uses the same descriptors; the result
        // must match the key path.
        #expect(policy.shouldDismiss(for: candidate()))
    }

    // MARK: - Must-not-close boundaries

    @Test func keepsThePanelWhenThePanelItselfBecomesKey() {
        // Clicking an internal control/slider makes the panel itself key again.
        #expect(policy.shouldDismiss(for: candidate(isPanel: true)) == false)
    }

    @Test func keepsThePanelWhenItsOwnSheetOrAlertBecomesKey() {
        // A panel-owned sheet/alert carries a sheetParent.
        #expect(policy.shouldDismiss(for: candidate(hasSheetParent: true)) == false)
    }

    @Test func keepsThePanelWhenItsOwnChildWindowBecomesKey() {
        // A child window (e.g. a pop-up menu's host) carries a parent.
        #expect(policy.shouldDismiss(for: candidate(hasParent: true)) == false)
    }

    @Test func keepsThePanelWhenAMenuOrFloatingWindowBecomesKey() {
        // NSMenu and alert-style windows run above `.normal`. Only a normal
        // top-level window is a genuine "click another window" gesture.
        #expect(policy.shouldDismiss(for: candidate(level: .floating)) == false)
        #expect(policy.shouldDismiss(for: candidate(level: .popUpMenu)) == false)
        #expect(policy.shouldDismiss(for: candidate(level: .modalPanel)) == false)
    }

    @Test func keepsThePanelWhenTheWindowIsNotVisible() {
        #expect(policy.shouldDismiss(for: candidate(isVisible: false)) == false)
    }

    /// The four `didBecomeKey`/`didBecomeMain` transitions that must not close
    /// the panel when combined: none of them pass the guard.
    @Test func internalInteractionsNeverCollapseTheGuard() {
        let internalTransitions = [
            candidate(isPanel: true),
            candidate(hasSheetParent: true),
            candidate(hasParent: true),
            candidate(level: .floating)
        ]
        for transition in internalTransitions {
            #expect(policy.shouldDismiss(for: transition) == false)
        }
    }
}