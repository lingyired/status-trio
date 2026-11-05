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
        let initial = animation.presentedHeight(at: start)
        XCTAssertEqual(initial.height, 200)
        XCTAssertFalse(initial.finished)

        // Mid-flight is strictly between origin and target (ease-out is monotonic).
        let mid = animation.presentedHeight(at: start + 0.11)
        XCTAssertGreaterThan(mid.height, 200)
        XCTAssertLessThan(mid.height, 400)
        XCTAssertFalse(mid.finished)

        // Past the duration, the height is exactly the target and is finished.
        let end = animation.presentedHeight(at: start + 0.30)
        XCTAssertEqual(end.height, 400)
        XCTAssertTrue(end.finished)
    }

    func testRetargetContinuesFromTheLiveHeightWithoutJumping() {
        var animation = StatusPanelResizeAnimation()
        let start: CFTimeInterval = 1000
        animation.retarget(to: 400, from: 200, time: start, direction: .expanding)

        // Reverse direction mid-flight: collapse back to 200 from the current
        // height (~350). The new curve's origin is that live height.
        let live = animation.presentedHeight(at: start + 0.17).height
        animation.retarget(to: 200, from: live, time: start + 0.17, direction: .collapsing)

        // A fresh snapshot now starts at the live height, not an old value.
        let snapshot = animation.snapshot
        XCTAssertEqual(snapshot?.startHeight, live)
        XCTAssertEqual(snapshot?.targetHeight, 200)

        let begin = animation.presentedHeight(at: start + 0.17)
        XCTAssertEqual(begin.height, live)
        XCTAssertFalse(begin.finished)

        // And settles back at the collapsed target.
        let done = animation.presentedHeight(at: start + 0.45)
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
        let animation = StatusPanelResizeAnimation()
        let result = animation.presentedHeight(at: 1000)
        XCTAssertTrue(result.finished)
    }

    func testAnimationKeepsSubpixelPrecisionUntilTheWindowWrite() {
        var animation = StatusPanelResizeAnimation()
        animation.retarget(to: 401.0, from: 200.0, time: 1000, direction: .expanding)
        let height = animation.presentedHeight(at: 1000.013).height
        XCTAssertNotEqual(height.rounded(), height)
    }

    func testReversalPreservesVelocityInsteadOfRestartingAnEaseOutCurve() {
        var animation = StatusPanelResizeAnimation()
        animation.retarget(to: 600, from: 200, time: 1000, direction: .expanding)
        let time: CFTimeInterval = 1000.05
        let epsilon: CFTimeInterval = 0.000001
        let live = animation.presentedHeight(at: time).height
        let prior = animation.presentedHeight(at: time - epsilon).height
        let speed = (live - prior) / epsilon
        animation.retarget(to: 200, from: live, time: time, direction: .collapsing)
        let next = animation.presentedHeight(at: time + epsilon).height
        XCTAssertGreaterThan(speed, 0)
        XCTAssertEqual((next - live) / epsilon, speed, accuracy: 1,
                       "the target changes now, but momentum must not jump")
        let end = animation.presentedHeight(at: time + 1)
        XCTAssertTrue(end.finished)
        XCTAssertEqual(end.height, 200)
    }
}
