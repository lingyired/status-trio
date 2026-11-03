import AppKit
import Testing
@testable import StatusTrioCore

struct DockPlacementTests {
    @Test func detectsTheDockOnTheLeft() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = NSRect(x: 70, y: 0, width: 1370, height: 875)

        #expect(DockPlacement.resolve(screenFrame: frame, visibleFrame: visible) == .left)
    }

    @Test func detectsTheDockOnTheRight() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = NSRect(x: 0, y: 0, width: 1370, height: 875)

        #expect(DockPlacement.resolve(screenFrame: frame, visibleFrame: visible) == .right)
    }

    @Test func detectsTheDockAtTheBottom() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = NSRect(x: 0, y: 70, width: 1440, height: 805)

        #expect(DockPlacement.resolve(screenFrame: frame, visibleFrame: visible) == .bottom)
    }
}

struct DockRevealInsetTests {
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func reservesTheBottomsEdgeForACollapsedDock() {
        let inset = DockReveal.inset(
            screenFrame: screen,
            visibleFrame: screen,
            pointer: NSPoint(x: 100, y: 20)
        )

        #expect(inset.bottom == DockReveal.extent)
        #expect(inset.left == 0 && inset.right == 0 && inset.top == 0)
    }

    @Test func reservesTheLeftEdgeForACollapsedDock() {
        let inset = DockReveal.inset(
            screenFrame: screen,
            visibleFrame: screen,
            pointer: NSPoint(x: 20, y: 400)
        )

        #expect(inset.left == DockReveal.extent)
        #expect(inset.bottom == 0 && inset.right == 0 && inset.top == 0)
    }

    @Test func reservesTheRightEdgeForACollapsedDock() {
        let inset = DockReveal.inset(
            screenFrame: screen,
            visibleFrame: screen,
            pointer: NSPoint(x: 1420, y: 400)
        )

        #expect(inset.right == DockReveal.extent)
        #expect(inset.bottom == 0 && inset.left == 0 && inset.top == 0)
    }

    @Test func leavesNoInsetForAVisibleBottomDock() {
        // A visible Dock already shrinks visibleFrame, so placement clears it.
        let visible = NSRect(x: 0, y: 70, width: 1440, height: 805)

        let inset = DockReveal.inset(
            screenFrame: screen,
            visibleFrame: visible,
            pointer: NSPoint(x: 100, y: 20)
        )

        #expect(inset.bottom == 0 && inset.left == 0 && inset.right == 0)
    }

    @Test func leavesNoInsetForAVisibleLeftDock() {
        let visible = NSRect(x: 70, y: 0, width: 1370, height: 875)

        let inset = DockReveal.inset(
            screenFrame: screen,
            visibleFrame: visible,
            pointer: NSPoint(x: 20, y: 400)
        )

        #expect(inset.left == 0 && inset.bottom == 0 && inset.right == 0)
    }

    @Test func aCollapsedDockTakesItsOrientationFromThePointer() {
        #expect(
            DockReveal.collapsedPlacement(
                screenFrame: screen, visibleFrame: screen, pointer: NSPoint(x: 720, y: 20)
            ) == .bottom
        )
        #expect(
            DockReveal.collapsedPlacement(
                screenFrame: screen, visibleFrame: screen, pointer: NSPoint(x: 20, y: 450)
            ) == .left
        )
        #expect(
            DockReveal.collapsedPlacement(
                screenFrame: screen, visibleFrame: screen, pointer: NSPoint(x: 1420, y: 450)
            ) == .right
        )
        // A visible Dock keeps its frame-derived orientation.
        #expect(
            DockReveal.collapsedPlacement(
                screenFrame: screen,
                visibleFrame: NSRect(x: 70, y: 0, width: 1370, height: 875),
                pointer: NSPoint(x: 20, y: 450)
            ) == nil
        )
    }
}

struct DockPopoverAnchorTests {
    @Test func anchorsAboveABottomDock() {
        let anchor = DockPopoverAnchor.make(
            clickPoint: NSPoint(x: 100, y: 20),
            tileSize: NSSize(width: 48, height: 48),
            placement: .bottom
        )

        #expect(anchor.origin == NSPoint(x: 100, y: 44))
        #expect(anchor.preferredEdge == .maxY)
    }

    @Test func anchorsToTheRightOfALeftDock() {
        let anchor = DockPopoverAnchor.make(
            clickPoint: NSPoint(x: 24, y: 500),
            tileSize: NSSize(width: 48, height: 48),
            placement: .left
        )

        #expect(anchor.origin == NSPoint(x: 48, y: 500))
        #expect(anchor.preferredEdge == .maxX)
    }

    @Test func anchorsToTheLeftOfARightDock() {
        let anchor = DockPopoverAnchor.make(
            clickPoint: NSPoint(x: 1416, y: 500),
            tileSize: NSSize(width: 48, height: 48),
            placement: .right
        )

        #expect(anchor.origin == NSPoint(x: 1392, y: 500))
        #expect(anchor.preferredEdge == .minX)
    }
}

struct DockAreaPointerTests {
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func recognisesAPointerInsideAVisibleBottomDock() {
        let visible = NSRect(x: 0, y: 70, width: 1440, height: 805)

        #expect(
            DockPlacement.bottom.containsPointer(
                NSPoint(x: 700, y: 30),
                screenFrame: screen,
                visibleFrame: visible
            )
        )
        #expect(
            DockPlacement.bottom.containsPointer(
                NSPoint(x: 700, y: 400),
                screenFrame: screen,
                visibleFrame: visible
            ) == false
        )
    }

    @Test func recognisesAPointerInsideAVisibleLeftDock() {
        let visible = NSRect(x: 70, y: 0, width: 1370, height: 875)

        #expect(
            DockPlacement.left.containsPointer(
                NSPoint(x: 24, y: 400),
                screenFrame: screen,
                visibleFrame: visible
            )
        )
        #expect(
            DockPlacement.left.containsPointer(
                NSPoint(x: 600, y: 400),
                screenFrame: screen,
                visibleFrame: visible
            ) == false
        )
    }

    @Test func usesAnEdgeToleranceWhenTheDockAutoHides() {
        // With auto-hide the visible frame fills the screen, so the Dock area has
        // to be inferred from the screen edge.
        let visible = screen

        #expect(
            DockPlacement.bottom.containsPointer(
                NSPoint(x: 700, y: 40),
                screenFrame: screen,
                visibleFrame: visible
            )
        )
        #expect(
            DockPlacement.bottom.containsPointer(
                NSPoint(x: 700, y: 400),
                screenFrame: screen,
                visibleFrame: visible
            ) == false
        )
        #expect(
            DockPlacement.right.containsPointer(
                NSPoint(x: 1430, y: 400),
                screenFrame: screen,
                visibleFrame: visible
            )
        )
    }
}
