import AppKit
import Testing

@testable import StatusTrioCore

struct StatusMenuPresentationPolicyTests {
    private let screen = StatusPanelShortcutScreen(
        frame: NSRect(x: 0, y: 0, width: 1_440, height: 900),
        visibleFrame: NSRect(x: 0, y: 0, width: 1_440, height: 875)
    )

    /// A plausible status-item rect for the screen above: 24×25 at the top.
    private var statusItemRect: NSRect {
        NSRect(x: 700, y: 875, width: 24, height: 25)
    }

    @Test func aSaneStatusItemRectPresentsImmediately() {
        #expect(decision(rect: statusItemRect, visible: true, attempt: 0) == .present)
    }

    @Test func aMissingRectRetriesAndThenGivesUpToPresent() {
        #expect(decision(rect: nil, visible: true, attempt: 0) == .retry)
        #expect(
            decision(
                rect: nil,
                visible: true,
                attempt: StatusMenuPresentationPolicy.maximumRetries - 1
            ) == .retry
        )
        #expect(
            decision(
                rect: nil,
                visible: true,
                attempt: StatusMenuPresentationPolicy.maximumRetries
            ) == .present
        )
    }

    @Test func aHiddenStatusItemIsNotTrusted() {
        #expect(decision(rect: statusItemRect, visible: false, attempt: 0) == .retry)
    }

    @Test func theWholeMenuBarWindowIsRejected() {
        // AppKit briefly reports the whole menu-bar window during lifecycle
        // churn; a 24pt status item is much smaller than half the screen.
        let wholeBar = NSRect(x: 0, y: 875, width: 1_440, height: 25)
        #expect(decision(rect: wholeBar, visible: true, attempt: 0) == .retry)
    }

    @Test func aRectDetachedFromTheMenuBarIsRejected() {
        // A mid-screen rect can never be a status item in the menu bar.
        let detached = NSRect(x: 700, y: 400, width: 24, height: 25)
        #expect(decision(rect: detached, visible: true, attempt: 0) == .retry)
    }

    @Test func aRectOffEveryScreenIsRejected() {
        let offScreen = NSRect(x: 5_000, y: 2_000, width: 24, height: 25)
        #expect(decision(rect: offScreen, visible: true, attempt: 0) == .retry)
    }

    @Test func aZeroSizedRectIsRejected() {
        let empty = NSRect(x: 700, y: 875, width: 0, height: 0)
        #expect(decision(rect: empty, visible: true, attempt: 0) == .retry)
    }

    private func decision(
        rect: NSRect?,
        visible: Bool,
        attempt: Int
    ) -> StatusMenuPresentationDecision {
        StatusMenuPresentationPolicy.decision(
            menuBarRect: rect,
            isStatusItemVisible: visible,
            screens: [screen],
            attempt: attempt
        )
    }
}
