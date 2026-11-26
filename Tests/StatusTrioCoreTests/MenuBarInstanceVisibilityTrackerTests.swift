import XCTest
@testable import StatusTrioCore

final class MenuBarInstanceVisibilityTrackerTests: XCTestCase {
    func testSelfInitiatedChangeIgnored() {
        var tracker = MenuBarInstanceVisibilityTracker()
        tracker.setSelfInitiated(true)
        XCTAssertEqual(tracker.evaluate(previousVisible: true, newVisible: false, isEnabled: true), .none)
    }

    func testUserDragOutDetected() {
        let tracker = MenuBarInstanceVisibilityTracker()
        XCTAssertEqual(tracker.evaluate(previousVisible: true, newVisible: false, isEnabled: true), .userRemoved)
    }

    func testAlreadyDisabledIgnored() {
        let tracker = MenuBarInstanceVisibilityTracker()
        XCTAssertEqual(tracker.evaluate(previousVisible: true, newVisible: false, isEnabled: false), .none)
    }

    func testNoChangeIgnored() {
        let tracker = MenuBarInstanceVisibilityTracker()
        XCTAssertEqual(tracker.evaluate(previousVisible: false, newVisible: false, isEnabled: true), .none)
        XCTAssertEqual(tracker.evaluate(previousVisible: true, newVisible: true, isEnabled: true), .none)
    }

    func testOverflowDoesNotFlipVisible() {
        // menu-bar overflow leaves visible == true; no transition, no removal.
        let tracker = MenuBarInstanceVisibilityTracker()
        XCTAssertEqual(tracker.evaluate(previousVisible: true, newVisible: true, isEnabled: true), .none)
    }
}
