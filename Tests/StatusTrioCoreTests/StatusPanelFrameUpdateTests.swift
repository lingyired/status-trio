import AppKit
import Testing
@testable import StatusTrioCore

/// Issue #259: a measured content size must be compared against the frame the
/// placement maths will actually apply, not against an intermediate size.
/// Otherwise a panel that is capped or clamped rewrites the same window frame on
/// every update and the main thread never settles.
struct StatusPanelFrameUpdateTests {
    /// A 316pt-wide screen keeps 300pt of usable width after the 8pt margins,
    /// and the visible height caps a panel at 200.25pt so the cap stays
    /// fractional — the case the old guard rounded up and then clamped back.
    private let screen = StatusPanelScreen(
        frame: NSRect(x: 0, y: 0, width: 316, height: 240.25),
        visibleFrame: NSRect(x: 0, y: 0, width: 316, height: 216.25)
    )

    private let sidewaysAnchor = StatusPanelAnchor(
        screenRect: NSRect(x: 0, y: 100, width: 24, height: 18),
        preferredEdge: .maxX
    )

    private func target(
        contentSize: NSSize,
        currentFrame: NSRect? = nil,
        anchor: StatusPanelAnchor? = nil
    ) -> NSRect? {
        let anchor = anchor ?? sidewaysAnchor
        let placed = StatusPanelPlacement.frame(
            contentSize: contentSize,
            anchor: anchor,
            screens: [screen]
        )
        return StatusPanelPlacement.contentFrameUpdate(
            from: currentFrame ?? placed,
            contentSize: contentSize,
            anchor: anchor,
            screens: [screen]
        )
    }

    @Test func fractionalHeightCapDoesNotRewriteTheSameFrame() {
        let contentSize = NSSize(width: 200, height: 400)
        let placed = StatusPanelPlacement.frame(
            contentSize: contentSize,
            anchor: sidewaysAnchor,
            screens: [screen]
        )
        #expect(placed.height == 200.25, "the fixture must cap at the fractional budget")

        let update = StatusPanelPlacement.contentFrameUpdate(
            from: placed,
            contentSize: contentSize,
            anchor: sidewaysAnchor,
            screens: [screen]
        )

        #expect(update == nil, "a capped panel already at its frame must not rewrite it")
    }

    @Test func screenWidthClampDoesNotRewriteTheSameFrame() {
        let contentSize = NSSize(width: 330, height: 100)
        let placed = StatusPanelPlacement.frame(
            contentSize: contentSize,
            anchor: sidewaysAnchor,
            screens: [screen]
        )
        #expect(placed.width == 300, "the fixture must clamp the width to the screen budget")

        let update = StatusPanelPlacement.contentFrameUpdate(
            from: placed,
            contentSize: contentSize,
            anchor: sidewaysAnchor,
            screens: [screen]
        )

        #expect(update == nil, "a width-clamped panel already at its frame must not rewrite it")
    }

    @Test func tallerContentProducesTheNewFrame() {
        let currentFrame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 200, height: 120),
            anchor: sidewaysAnchor,
            screens: [screen]
        )
        let contentSize = NSSize(width: 200, height: 160)

        let update = StatusPanelPlacement.contentFrameUpdate(
            from: currentFrame,
            contentSize: contentSize,
            anchor: sidewaysAnchor,
            screens: [screen]
        )

        #expect(update?.height == 160, "new content height must still resize the window")
    }

    @Test func movedAnchorRepositionsEvenWhenTheSizeMatches() {
        let contentSize = NSSize(width: 200, height: 100)
        let originalAnchor = sidewaysAnchor
        let currentFrame = StatusPanelPlacement.frame(
            contentSize: contentSize,
            anchor: originalAnchor,
            screens: [screen]
        )
        let movedAnchor = StatusPanelAnchor(
            screenRect: originalAnchor.screenRect.offsetBy(dx: 60, dy: 0),
            preferredEdge: .maxX
        )

        let update = StatusPanelPlacement.contentFrameUpdate(
            from: currentFrame,
            contentSize: contentSize,
            anchor: movedAnchor,
            screens: [screen]
        )

        #expect(update != nil, "a moved anchor must reposition the panel")
        #expect(update?.origin != currentFrame.origin)
        #expect(update?.size == currentFrame.size)
    }

    @Test func invalidMeasurementsProduceNoUpdate() {
        let currentFrame = NSRect(x: 0, y: 0, width: 200, height: 100)
        for size in [
            NSSize(width: 0, height: 100),
            NSSize(width: 200, height: 0),
            NSSize(width: CGFloat.nan, height: 100),
            NSSize(width: 200, height: CGFloat.infinity)
        ] {
            #expect(
                StatusPanelPlacement.contentFrameUpdate(
                    from: currentFrame,
                    contentSize: size,
                    anchor: sidewaysAnchor,
                    screens: [screen]
                ) == nil,
                "invalid content size \(size) must not move the window"
            )
        }
    }

    @Test func repeatedIdenticalRequestsConvergeAfterOneWrite() {
        let contentSize = NSSize(width: 200, height: 400)
        var currentFrame = NSRect.zero
        var writes = 0

        for _ in 0..<20 {
            guard let update = StatusPanelPlacement.contentFrameUpdate(
                from: currentFrame,
                contentSize: contentSize,
                anchor: sidewaysAnchor,
                screens: [screen]
            ) else { continue }
            writes += 1
            // `setFrame` makes the window's frame the returned frame.
            currentFrame = update
        }

        #expect(writes == 1, "the same capped request must settle after the first write")
        #expect(currentFrame.height == 200.25)
    }

    @Test func noAnchorKeepsTheOriginAndAdoptsTheSize() {
        let currentFrame = NSRect(x: 12, y: 34, width: 200, height: 100)

        let update = StatusPanelPlacement.contentFrameUpdate(
            from: currentFrame,
            contentSize: NSSize(width: 220, height: 140),
            anchor: nil,
            screens: []
        )

        #expect(update?.origin == currentFrame.origin)
        #expect(update?.size == NSSize(width: 220, height: 140))
    }
}
