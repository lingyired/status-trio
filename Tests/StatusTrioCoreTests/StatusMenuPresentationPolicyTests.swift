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

    @Test func theMenuAnchorsJustBelowTheStatusItemInScreenCoordinates() {
        // macOS 15 regression: anchoring with `button.bounds.maxY` put the
        // menu's top edge above the icon, clipping the version row into a
        // scrollable menu. The anchor is now the icon's lower edge minus the
        // gap, in screen coordinates, so the button's flipped state cannot
        // matter.
        let point = StatusMenuPresentationPolicy.anchorPoint(for: statusItemRect, gap: 4)
        #expect(point.x == statusItemRect.minX)
        #expect(point.y == statusItemRect.minY - 4)
    }

    @Test func aNegativeGapNeverPushesTheMenuOntoTheIcon() {
        let point = StatusMenuPresentationPolicy.anchorPoint(for: statusItemRect, gap: -10)
        #expect(point.y == statusItemRect.minY)
    }

    @Test func theMenuNeverStartsInsideTheMenuBar() {
        // The status item is centred in the menu bar, so its bottom can sit more
        // than `gap` points above the bar's lower edge. Clamp to that edge so
        // the first row (the version line) is never clipped into a scroll menu.
        let clamped = StatusMenuPresentationPolicy.anchorPoint(
            for: statusItemRect,
            gap: 4,
            menuBarBottom: statusItemRect.minY - 10
        )
        #expect(clamped.y == statusItemRect.minY - 10)

        // A bar bottom below the natural anchor leaves it unchanged.
        let natural = StatusMenuPresentationPolicy.anchorPoint(
            for: statusItemRect,
            gap: 4,
            menuBarBottom: statusItemRect.minY - 1
        )
        #expect(natural.y == statusItemRect.minY - 4)
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
