import AppKit
import Testing

@testable import StatusTrioCore

struct StatusPanelShortcutPresentationPolicyTests {
    @Test func anOpenPanelClosesAndAClosingPanelIgnoresRepeats() {
        #expect(
            StatusPanelShortcutPresentationPolicy.action(isPopoverShown: true)
                == .close
        )
        #expect(
            StatusPanelShortcutPresentationPolicy.action(isPopoverShown: false)
                == .open
        )
        #expect(
            StatusPanelShortcutPresentationPolicy.action(
                isPopoverShown: false,
                isPopoverClosing: true
            ) == .ignore
        )
    }

    @Test func aVisibleMenuBarAnchorIsPreferred() {
        let screen = StatusPanelShortcutScreen(
            frame: NSRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_440, height: 875)
        )

        let anchor = StatusPanelShortcutPresentationPolicy.anchor(
            menuBarRect: NSRect(x: 700, y: 875, width: 24, height: 25),
            isMenuBarVisible: true,
            pointerLocation: NSPoint(x: 400, y: 400),
            screens: [screen]
        )

        #expect(anchor == .menuBar)
    }

    @Test func dockOnlyModeUsesThePointerScreenFallback() {
        let primary = StatusPanelShortcutScreen(
            frame: NSRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: NSRect(x: 0, y: 70, width: 1_440, height: 805)
        )
        let secondary = StatusPanelShortcutScreen(
            frame: NSRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
            visibleFrame: NSRect(x: -1_920, y: 0, width: 1_920, height: 1_055)
        )

        let anchor = StatusPanelShortcutPresentationPolicy.anchor(
            menuBarRect: NSRect(x: 700, y: 875, width: 24, height: 25),
            isMenuBarVisible: false,
            pointerLocation: NSPoint(x: -400, y: 500),
            screens: [primary, secondary]
        )

        #expect(
            anchor == .fallback(
                origin: NSPoint(x: -960, y: 1_054),
                preferredEdge: .minY
            )
        )
    }

    @Test func anOffscreenMenuBarAnchorUsesTheFallback() {
        let screen = StatusPanelShortcutScreen(
            frame: NSRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: NSRect(x: 0, y: 70, width: 1_440, height: 805)
        )

        let anchor = StatusPanelShortcutPresentationPolicy.anchor(
            menuBarRect: NSRect(x: 2_000, y: 875, width: 24, height: 25),
            isMenuBarVisible: true,
            pointerLocation: NSPoint(x: 400, y: 400),
            screens: [screen]
        )

        #expect(
            anchor == .fallback(
                origin: NSPoint(x: 720, y: 874),
                preferredEdge: .minY
            )
        )
    }

    @Test func aStaleBottomLeftAnchorUsesTheFallback() {
        let screen = StatusPanelShortcutScreen(
            frame: NSRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: NSRect(x: 0, y: 70, width: 1_440, height: 805)
        )

        let anchor = StatusPanelShortcutPresentationPolicy.anchor(
            menuBarRect: NSRect(x: 0, y: 0, width: 24, height: 25),
            isMenuBarVisible: true,
            pointerLocation: NSPoint(x: 400, y: 400),
            screens: [screen]
        )

        #expect(
            anchor == .fallback(
                origin: NSPoint(x: 720, y: 874),
                preferredEdge: .minY
            )
        )
    }

    @Test func aWholeMenuBarWindowIsNotUsedAsTheItemAnchor() {
        let screen = StatusPanelShortcutScreen(
            frame: NSRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: NSRect(x: 0, y: 70, width: 1_440, height: 805)
        )

        let anchor = StatusPanelShortcutPresentationPolicy.anchor(
            menuBarRect: NSRect(x: 0, y: 875, width: 1_440, height: 25),
            isMenuBarVisible: true,
            pointerLocation: NSPoint(x: 400, y: 400),
            screens: [screen]
        )

        #expect(
            anchor == .fallback(
                origin: NSPoint(x: 720, y: 874),
                preferredEdge: .minY
            )
        )
    }

    @Test func aMissingMenuBarAnchorUsesAClampedFallback() {
        let screen = StatusPanelShortcutScreen(
            frame: NSRect(x: -100, y: -50, width: 10, height: 10),
            visibleFrame: NSRect(x: -100, y: -50, width: 10, height: 10)
        )

        let anchor = StatusPanelShortcutPresentationPolicy.anchor(
            menuBarRect: nil,
            isMenuBarVisible: true,
            pointerLocation: NSPoint(x: 5_000, y: 5_000),
            screens: [screen],
            fallbackInset: 4
        )

        #expect(
            anchor == .fallback(
                origin: NSPoint(x: -95, y: -44),
                preferredEdge: .minY
            )
        )
    }

    @Test func anOffscreenPointerFallsBackToTheFirstKnownScreen() {
        let primary = StatusPanelShortcutScreen(
            frame: NSRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_440, height: 875)
        )

        let anchor = StatusPanelShortcutPresentationPolicy.anchor(
            menuBarRect: nil,
            isMenuBarVisible: false,
            pointerLocation: NSPoint(x: 10_000, y: 10_000),
            screens: [primary]
        )

        #expect(
            anchor == .fallback(
                origin: NSPoint(x: 720, y: 874),
                preferredEdge: .minY
            )
        )
    }
}
