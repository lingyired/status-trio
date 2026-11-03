import AppKit
import XCTest
@testable import StatusTrioCore

/// Wheel routing coverage for the panel scroll cap (#237): only a scroll view
/// that can actually scroll may take the wheel. Otherwise the short panel keeps
/// adjusting the volume as it did before the panel could scroll (issue #22).
@MainActor
final class PanelScrollHitTestingTests: XCTestCase {
    func testPointerOverAnOverflowingScrollViewKeepsTheWheel() throws {
        let (root, scrollView) = makeRoot(documentHeight: 500)

        XCTAssertTrue(
            PanelScrollHitTesting.pointerIsOverScrollableScrollView(
                at: center(of: scrollView, in: root),
                in: root
            )
        )
    }

    func testPointerOverAShortScrollViewStillAdjustsTheVolume() throws {
        let (root, scrollView) = makeRoot(documentHeight: 40)

        XCTAssertFalse(
            PanelScrollHitTesting.pointerIsOverScrollableScrollView(
                at: center(of: scrollView, in: root),
                in: root
            ),
            "a scroll view with nothing to scroll must not swallow the wheel"
        )
    }

    func testPointerOutsideTheScrollViewAdjustsTheVolume() throws {
        let (root, scrollView) = makeRoot(documentHeight: 500)
        let outside = NSPoint(x: 10, y: root.bounds.maxY - 5)

        XCTAssertFalse(
            PanelScrollHitTesting.pointerIsOverScrollableScrollView(at: outside, in: root)
        )
        XCTAssertEqual(scrollView.frame.minY, 0)
    }

    func testPointerOverAChildOfTheDocumentKeepsTheWheel() throws {
        let (root, scrollView) = makeRoot(documentHeight: 500)
        let child = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        scrollView.documentView?.addSubview(child)
        root.layoutSubtreeIfNeeded()

        XCTAssertTrue(
            PanelScrollHitTesting.pointerIsOverScrollableScrollView(
                at: center(of: child, in: root),
                in: root
            )
        )
    }

    func testHitTestingConvertsTheRootsSuperviewCoordinates() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 800))
        let (root, scrollView) = makeRoot(documentHeight: 500)
        root.setFrameOrigin(NSPoint(x: 100, y: 150))
        container.addSubview(root)

        XCTAssertTrue(PanelScrollHitTesting.pointerIsOverScrollableScrollView(
            at: center(of: scrollView, in: root),
            in: root
        ))
        XCTAssertFalse(PanelScrollHitTesting.pointerIsOverScrollableScrollView(
            at: NSPoint(x: 10, y: root.bounds.maxY - 5),
            in: root
        ))
    }

    // MARK: - Fixtures

    private func makeRoot(documentHeight: CGFloat) -> (NSView, NSScrollView) {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 300))
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 330, height: 200))
        scrollView.hasVerticalScroller = true
        scrollView.documentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 330, height: documentHeight)
        )
        root.addSubview(scrollView)
        root.layoutSubtreeIfNeeded()
        return (root, scrollView)
    }

    private func center(of view: NSView, in root: NSView) -> NSPoint {
        let frame = root.convert(view.bounds, from: view)
        return NSPoint(x: frame.midX, y: frame.midY)
    }
}
