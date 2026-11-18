import AppKit
import Testing
@testable import StatusTrioCore

struct StatusPanelDetailPlacementTests {
    private let screen = StatusPanelScreen(
        frame: NSRect(x: 0, y: 0, width: 1000, height: 700),
        visibleFrame: NSRect(x: 0, y: 0, width: 1000, height: 700)
    )

    private func place(
        summaryX: CGFloat,
        summaryTop: CGFloat = 650,
        detailHeight: CGFloat = 200,
        dockInset: NSEdgeInsets = DockReveal.noInset,
        screens: [StatusPanelScreen]? = nil
    ) -> StatusPanelDetailPlacement.Placement? {
        StatusPanelDetailPlacement.frame(
            summaryFrame: NSRect(x: summaryX, y: summaryTop - 400, width: 330, height: 400),
            detailHeight: detailHeight,
            screens: screens ?? [screen],
            dockInset: dockInset
        )
    }

    @Test func rightSideSitsEightPointsFromTheSummary() {
        let placement = place(summaryX: 324)

        #expect(placement?.side == .right)
        #expect(placement?.frame == NSRect(x: 662, y: 450, width: 330, height: 200))
    }

    @Test func summaryAtLeadingEdgeUsesTheRightSide() {
        #expect(place(summaryX: 0)?.side == .right)
    }

    @Test func fallsBackToTheLeftWhenTheRightDoesNotFit() {
        let placement = place(summaryX: 600)

        #expect(placement?.side == .left)
        #expect(placement?.frame.minX == 262)
    }

    @Test func noSpaceOnEitherSideReturnsNil() {
        #expect(place(summaryX: 325) == nil)
    }

    @Test func leftSideKeepsTheScreenMargin() {
        let placement = place(summaryX: 346)

        #expect(placement?.side == .left)
        #expect(placement?.frame.minX == 8)
        #expect(place(summaryX: 345) == nil)
    }

    @Test func topAlignsWithTheSummaryWhenItFits() {
        let placement = place(summaryX: 0, detailHeight: 200)

        #expect(placement?.frame.maxY == 650)
    }

    @Test func tallDetailUsesTheWholeUsableHeight() {
        let placement = place(summaryX: 0, detailHeight: 900)

        #expect(placement?.frame.height == 684)
        #expect(placement?.frame.minY == 8)
        #expect(placement?.maximumHeight == 684)
    }

    @Test func translatedScreenGivesTheSameRelativeFrame() {
        let moved = StatusPanelScreen(
            frame: NSRect(x: -1600, y: 200, width: 1000, height: 700),
            visibleFrame: NSRect(x: -1600, y: 200, width: 1000, height: 700)
        )
        let placement = place(summaryX: -1600 + 324, summaryTop: 650 + 200, screens: [moved])

        #expect(placement?.side == .right)
        let expectedMinX: CGFloat = -1600 + 662
        #expect(placement?.frame.minX == expectedMinX)
        #expect(placement?.frame.maxY == 850)
    }

    @Test func doesNotBorrowSpaceFromAnAdjacentScreen() {
        let second = StatusPanelScreen(
            frame: NSRect(x: 1000, y: 0, width: 1000, height: 700),
            visibleFrame: NSRect(x: 1000, y: 0, width: 1000, height: 700)
        )
        let placement = place(summaryX: 680, screens: [screen, second])

        #expect(placement?.side == .left)
        #expect((placement?.frame.maxX ?? .infinity) <= screen.frame.maxX)
    }

    @Test func rightDockInsetRemovesTheRightCandidate() {
        let inset = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 20)

        #expect(place(summaryX: 324, dockInset: inset) == nil)
        #expect(place(summaryX: 600, dockInset: inset)?.side == .left)
    }

    @Test func unknownScreenReturnsNil() {
        #expect(place(summaryX: 0, screens: []) == nil)

        let farAway = StatusPanelScreen(
            frame: NSRect(x: 5000, y: 0, width: 1000, height: 700),
            visibleFrame: NSRect(x: 5000, y: 0, width: 1000, height: 700)
        )
        #expect(place(summaryX: 0, screens: [farAway]) == nil)
    }
}
