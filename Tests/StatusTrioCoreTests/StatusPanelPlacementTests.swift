import AppKit
import Testing
@testable import StatusTrioCore

struct StatusPanelPlacementTests {
    private let screen = StatusPanelScreen(
        frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 875)
    )

    @Test func menuBarAnchorHangsCentredBelowWithTheGap() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 708, y: 880, width: 24, height: 18),
            preferredEdge: .minY
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 400),
            anchor: anchor,
            screens: [screen]
        )

        #expect(frame.origin == NSPoint(x: 555, y: 474))
        #expect(frame.size == NSSize(width: 330, height: 400))
    }

    @Test func clampsToTheTrailingScreenEdge() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 1410, y: 880, width: 24, height: 18),
            preferredEdge: .minY
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 400),
            anchor: anchor,
            screens: [screen]
        )

        #expect(frame.maxX == 1440)
        #expect(frame.minX == 1110)
        // Horizontal overflow must clamp, not flip: the panel stays below the
        // menu bar with the regular gap.
        #expect(frame.maxY == anchor.screenRect.minY - StatusPanelPlacement.gap)
    }

    @Test func flipsAboveWhenThereIsNoRoomBelow() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 488, y: 10, width: 24, height: 18),
            preferredEdge: .minY
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 400),
            anchor: anchor,
            screens: [screen]
        )

        #expect(frame.minY == 34)
        #expect(frame.maxY == 434)
    }

    @Test func bottomDockAnchorSitsAboveTheIcon() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 488, y: 20, width: 24, height: 18),
            preferredEdge: .maxY
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 400),
            anchor: anchor,
            screens: [screen]
        )

        #expect(frame.origin == NSPoint(x: 335, y: 44))
    }

    @Test func leftDockAnchorSitsToTheRightOfTheIcon() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 10, y: 388, width: 18, height: 24),
            preferredEdge: .maxX
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 400),
            anchor: anchor,
            screens: [screen]
        )

        #expect(frame.origin == NSPoint(x: 34, y: 200))
    }

    @Test func rightDockAnchorSitsToTheLeftOfTheIcon() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 1410, y: 388, width: 18, height: 24),
            preferredEdge: .minX
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 400),
            anchor: anchor,
            screens: [screen]
        )

        #expect(frame.origin == NSPoint(x: 1074, y: 200))
    }

    @Test func picksTheScreenContainingTheAnchor() {
        let secondary = StatusPanelScreen(
            frame: NSRect(x: -1920, y: 0, width: 1920, height: 1080),
            visibleFrame: NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        )
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: -600, y: 500, width: 24, height: 18),
            preferredEdge: .minY
        )

        #expect(StatusPanelPlacement.screenContaining(anchor.screenRect, screens: [screen, secondary]) == secondary)
    }

    @Test func growingContentKeepsTheTopEdgeFixedForMenuBarAnchors() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 708, y: 880, width: 24, height: 18),
            preferredEdge: .minY
        )

        let short = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 200),
            anchor: anchor,
            screens: [screen]
        )
        let tall = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 500),
            anchor: anchor,
            screens: [screen]
        )

        #expect(short.maxY == tall.maxY)
        #expect(tall.minY < short.minY)
    }

    // MARK: - Collapsed (auto-hidden) Dock (#229)

    private let collapsedScreen = StatusPanelScreen(
        frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
    )

    @Test func collapsedBottomDockKeepsThePanelAboveTheRevealStrip() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 488, y: 44, width: 24, height: 18),
            preferredEdge: .maxY
        )
        let inset = DockReveal.inset(
            screenFrame: collapsedScreen.frame,
            visibleFrame: collapsedScreen.visibleFrame,
            pointer: NSPoint(x: 500, y: 20)
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 400),
            anchor: anchor,
            screens: [collapsedScreen],
            dockInset: inset
        )

        #expect(inset.bottom == DockReveal.extent)
        #expect(frame.minY >= collapsedScreen.frame.minY + DockReveal.extent)
    }

    @Test func collapsedLeftDockKeepsThePanelClearOfTheRevealStrip() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 34, y: 388, width: 18, height: 24),
            preferredEdge: .maxX
        )
        let inset = DockReveal.inset(
            screenFrame: collapsedScreen.frame,
            visibleFrame: collapsedScreen.visibleFrame,
            pointer: NSPoint(x: 20, y: 400)
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 400),
            anchor: anchor,
            screens: [collapsedScreen],
            dockInset: inset
        )

        #expect(inset.left == DockReveal.sideExtent)
        #expect(frame.minX >= collapsedScreen.frame.minX + DockReveal.sideExtent)
    }

    @Test func collapsedRightDockKeepsThePanelClearOfTheRevealStrip() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 1392, y: 388, width: 18, height: 24),
            preferredEdge: .minX
        )
        let inset = DockReveal.inset(
            screenFrame: collapsedScreen.frame,
            visibleFrame: collapsedScreen.visibleFrame,
            pointer: NSPoint(x: 1420, y: 400)
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 400),
            anchor: anchor,
            screens: [collapsedScreen],
            dockInset: inset
        )

        #expect(inset.right == DockReveal.sideExtent)
        #expect(frame.maxX <= collapsedScreen.frame.maxX - DockReveal.sideExtent)
    }

    /// A Dock-anchored panel attaches by its bottom edge, so growing content
    /// must extend upwards. This is what keeps the panel off the Dock when the
    /// window later resizes to its real content height (#229).
    @Test func growingContentKeepsTheBottomEdgeFixedForDockAnchors() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 100, y: 44, width: 1, height: 1),
            preferredEdge: .maxY
        )

        let short = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 200),
            anchor: anchor,
            screens: [screen]
        )
        let tall = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 500),
            anchor: anchor,
            screens: [screen]
        )

        #expect(short.minY == tall.minY)
        #expect(tall.maxY > short.maxY)
    }

    /// With the anchor snapped to the Dock's inner edge, the panel keeps the
    /// normal gap instead of floating away from the Dock (#229 follow-up).
    @Test func dockAnchorAtTheVisibleEdgeKeepsTheNormalGap() {
        let leftDock = StatusPanelScreen(
            frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: NSRect(x: 64, y: 0, width: 1376, height: 875)
        )
        let leftAnchor = StatusPanelAnchor(
            screenRect: NSRect(x: 64, y: 400, width: 1, height: 1),
            preferredEdge: .maxX
        )
        let leftFrame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 300),
            anchor: leftAnchor,
            screens: [leftDock]
        )
        #expect(leftFrame.minX == 64 + StatusPanelPlacement.gap + 1)

        let bottomDock = StatusPanelScreen(
            frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: NSRect(x: 0, y: 90, width: 1440, height: 810)
        )
        let bottomAnchor = StatusPanelAnchor(
            screenRect: NSRect(x: 700, y: 90, width: 1, height: 1),
            preferredEdge: .maxY
        )
        let bottomFrame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 300),
            anchor: bottomAnchor,
            screens: [bottomDock]
        )
        #expect(bottomFrame.minY == 90 + StatusPanelPlacement.gap + 1)
    }

    @Test func noScreensPreservesContentSizeAndHasNoHeightBudget() {
        for edge: NSRectEdge in [.minY, .maxY, .minX, .maxX] {
            let anchor = StatusPanelAnchor(
                screenRect: NSRect(x: 708, y: 880, width: 24, height: 18),
                preferredEdge: edge
            )
            let frame = StatusPanelPlacement.frame(
                contentSize: NSSize(width: 330, height: 300),
                anchor: anchor,
                screens: []
            )
            #expect(frame.size == NSSize(width: 330, height: 300))
            #expect(StatusPanelPlacement.maximumPanelHeight(anchor: anchor, screens: []) == nil)
            switch edge {
            case .minY: #expect(frame.maxY == anchor.screenRect.minY - StatusPanelPlacement.gap)
            case .maxY: #expect(frame.minY == anchor.screenRect.maxY + StatusPanelPlacement.gap)
            case .minX: #expect(frame.maxX == anchor.screenRect.minX - StatusPanelPlacement.gap)
            case .maxX: #expect(frame.minX == anchor.screenRect.maxX + StatusPanelPlacement.gap)
            default: break
            }
        }
    }

    // MARK: - Screen-height cap (#237)

    @Test func menuBarAnchorBudgetReachesTheBottomOfTheVisibleFrame() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 708, y: 880, width: 24, height: 18),
            preferredEdge: .minY
        )

        // 875pt visible frame minus 8pt of breathing room on each side. The
        // distance from the anchor to the bottom of the frame is larger, so the
        // screen height is the binding constraint.
        #expect(
            StatusPanelPlacement.maximumPanelHeight(
                anchor: anchor,
                screens: [screen]
            ) == screen.visibleFrame.height - StatusPanelPlacement.edgeMargin * 2
        )
    }

    // MARK: - Side-Dock full-height budget and vertical clamp (#321)

    // Side screen: 1440x900, visible 875 high with a 64pt left Dock strip.
    private let sideDockScreen = StatusPanelScreen(
        frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: NSRect(x: 64, y: 0, width: 1376, height: 875)
    )

    @Test func sideDockViewModelBudgetSpansTheWholeVisibleHeight() {
        // The full available height minus the two 8pt margins on either side.
        let expected = 875 - StatusPanelPlacement.edgeMargin * 2
        for preferredEdge: NSRectEdge in [.minX, .maxX] {
            // Click point near the top of the screen, where the old symmetric
            // budget would have capped at roughly 2x the top inset.
            let nearTop = StatusPanelAnchor(
                screenRect: NSRect(x: 64, y: 850, width: 18, height: 24),
                preferredEdge: preferredEdge
            )
            #expect(
                StatusPanelPlacement.maximumPanelHeight(
                    anchor: nearTop,
                    screens: [sideDockScreen]
                ) == expected
            )
            // ... and near the bottom, where the old budget would be ~2x the
            // bottom inset.
            let nearBottom = StatusPanelAnchor(
                screenRect: NSRect(x: 64, y: 20, width: 18, height: 24),
                preferredEdge: preferredEdge
            )
            #expect(
                StatusPanelPlacement.maximumPanelHeight(
                    anchor: nearBottom,
                    screens: [sideDockScreen]
                ) == expected
            )
        }
    }

    @Test func sideDockTallPanelTranslatesUpAndStaysInScreen() {
        // visibleFrame 875 tall; vertical travel bounds are 8pt inset each side.
        let bounds = StatusPanelPlacement.verticalTravelBounds(
            visibleFrame: sideDockScreen.visibleFrame,
            dockInset: DockReveal.noInset
        )
        #expect(bounds.lowerBound == StatusPanelPlacement.edgeMargin)
        #expect(
            bounds.upperBound
                == 875 - StatusPanelPlacement.edgeMargin
        )

        // A click near the top with a panel nearly as tall as the screen: the
        // centred origin would start above the screen; it must clamp down to
        // the top edge (keep maxY inside).
        let topClamped = StatusPanelPlacement.clampedVerticalOrigin(
            center: 862,
            height: 850,
            bounds: bounds
        )
        #expect(topClamped + 850 <= bounds.upperBound + 0.001)
        #expect(topClamped >= bounds.lowerBound - 0.001)

        // A click near the bottom: the centred origin would poke below the
        // screen; it must clamp up so minY stays above the bottom edge.
        let bottomClamped = StatusPanelPlacement.clampedVerticalOrigin(
            center: 15,
            height: 850,
            bounds: bounds
        )
        #expect(bottomClamped >= bounds.lowerBound - 0.001)
        #expect(bottomClamped + 850 <= bounds.upperBound + 0.001)

        // A small panel centred on a mid-screen click keeps its exact centre.
        let midClamped = StatusPanelPlacement.clampedVerticalOrigin(
            center: 437,
            height: 200,
            bounds: bounds
        )
        #expect(midClamped == 337)
    }

    @Test func contentTallerThanTheScreenIsCappedAndThePanelStaysVisible() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 708, y: 880, width: 24, height: 18),
            preferredEdge: .minY
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 4000),
            anchor: anchor,
            screens: [screen]
        )

        #expect(frame.size.height == 875 - StatusPanelPlacement.edgeMargin * 2)
        #expect(frame.size.width == 330)
        #expect(frame.minY >= screen.visibleFrame.minY)
        #expect(frame.maxY <= screen.visibleFrame.maxY)
        #expect(frame.maxY == anchor.screenRect.minY - StatusPanelPlacement.gap)
    }

    @Test func contentWiderThanTheScreenIsCapped() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 708, y: 880, width: 24, height: 18),
            preferredEdge: .minY
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 4000, height: 400),
            anchor: anchor,
            screens: [screen]
        )

        #expect(frame.size.width == screen.visibleFrame.width - StatusPanelPlacement.edgeMargin * 2)
        #expect(frame.minX >= screen.visibleFrame.minX)
        #expect(frame.maxX <= screen.visibleFrame.maxX)
    }

    @Test func dockAnchoredContentIsCappedAboveTheDockEdge() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 488, y: 20, width: 24, height: 18),
            preferredEdge: .maxY
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 4000),
            anchor: anchor,
            screens: [screen]
        )

        // The panel keeps its 6pt gap above the Dock icon and the 8pt margin
        // before the menu bar.
        #expect(frame.size.height == 875 - 38 - StatusPanelPlacement.gap - StatusPanelPlacement.edgeMargin)
        #expect(frame.minY == 38 + StatusPanelPlacement.gap)
        #expect(frame.maxY <= screen.visibleFrame.maxY)
    }

    /// The cap must not shrink panels that already fit.
    @Test func contentThatFitsKeepsItsExactHeight() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 708, y: 880, width: 24, height: 18),
            preferredEdge: .minY
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 700),
            anchor: anchor,
            screens: [screen]
        )

        #expect(frame.size.height == 700)
    }
}
