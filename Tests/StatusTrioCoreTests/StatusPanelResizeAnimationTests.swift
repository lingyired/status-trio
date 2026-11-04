import XCTest
@testable import StatusTrioCore

/// Unit coverage for the pure resize-animation math behind the panel's grow /
/// collapse. These tests run headlessly (no window), so they exercise the easing,
/// retarget and settle rules directly without a display.
@MainActor
final class StatusPanelResizeAnimationTests: XCTestCase {
    func testPresentedHeightEasesTowardsTheTargetAndFinishesExactly() {
        var animation = StatusPanelResizeAnimation()
        let start: CFTimeInterval = 1000
        animation.retarget(to: 400, from: 200, time: start, direction: .expanding)

        // Starts at the origin height.
        let initial = animation.presentedHeight(at: start, duration: 0.22)
        XCTAssertEqual(initial.height, 200)
        XCTAssertFalse(initial.finished)

        // Mid-flight is strictly between origin and target (ease-out is monotonic).
        let mid = animation.presentedHeight(at: start + 0.11, duration: 0.22)
        XCTAssertGreaterThan(mid.height, 200)
        XCTAssertLessThan(mid.height, 400)
        XCTAssertFalse(mid.finished)

        // Past the duration, the height is exactly the target and is finished.
        let end = animation.presentedHeight(at: start + 0.30, duration: 0.22)
        XCTAssertEqual(end.height, 400)
        XCTAssertTrue(end.finished)
    }

    func testRetargetContinuesFromTheLiveHeightWithoutJumping() {
        var animation = StatusPanelResizeAnimation()
        let start: CFTimeInterval = 1000
        animation.retarget(to: 400, from: 200, time: start, direction: .expanding)

        // Reverse direction mid-flight: collapse back to 200 from the current
        // height (~350). The new curve's origin is that live height.
        let live = animation.presentedHeight(at: start + 0.17, duration: 0.22).height
        animation.retarget(to: 200, from: live, time: start + 0.17, direction: .collapsing)

        // A fresh snapshot now starts at the live height, not an old value.
        let snapshot = animation.snapshot
        XCTAssertEqual(snapshot?.startHeight, live)
        XCTAssertEqual(snapshot?.targetHeight, 200)

        let begin = animation.presentedHeight(at: start + 0.17, duration: 0.22)
        XCTAssertEqual(begin.height, live)
        XCTAssertFalse(begin.finished)

        // And settles back at the collapsed target.
        let done = animation.presentedHeight(at: start + 0.45, duration: 0.22)
        XCTAssertEqual(done.height, 200)
        XCTAssertTrue(done.finished)
    }

    func testFinishDropsTheSnapshotAndStopsAnimating() {
        var animation = StatusPanelResizeAnimation()
        animation.retarget(to: 400, from: 200, time: 1000, direction: .expanding)
        XCTAssertTrue(animation.isAnimating)
        animation.finish()
        XCTAssertFalse(animation.isAnimating)
        XCTAssertNil(animation.snapshot)
    }

    func testNoAnimationReportsFinishedImmediately() {
        var animation = StatusPanelResizeAnimation()
        let result = animation.presentedHeight(at: 1000, duration: 0.22)
        XCTAssertTrue(result.finished)
    }

    func testHeightsSnapToWholePoints() {
        var animation = StatusPanelResizeAnimation()
        animation.retarget(to: 401.0, from: 200.0, time: 1000, direction: .expanding)
        // A fractional eased height rounds to a whole point each tick.
        for step in 1...8 {
            let t = 1000 + Double(step) * 0.01
            let r = animation.presentedHeight(at: t, duration: 0.22)
            XCTAssertEqual(r.height.rounded(), r.height, "every tick height must be a whole point")
        }
    }
}