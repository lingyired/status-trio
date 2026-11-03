import XCTest
@testable import StatusTrioCore

final class PopupLevelScrollSessionTests: XCTestCase {
    func testSessionKeepsAccumulatingAgainstItsOwnTargetInsteadOfTheEcho() throws {
        var session = PopupLevelScrollSession()
        let initial = try XCTUnwrap(
            session.scalar(at: 10, displayID: "display-a", fallback: 0.2)
        )
        XCTAssertEqual(initial, 0.2, accuracy: 0.000_001)

        let first = session.applying(delta: 0.05, to: initial)
        XCTAssertEqual(first, 0.25, accuracy: 0.000_001)
        // The system echo lags behind; the session must keep the draft target.
        let second = try XCTUnwrap(
            session.scalar(at: 10.1, displayID: "display-a", fallback: 0.21)
        )
        XCTAssertEqual(second, 0.25, accuracy: 0.000_001)

        let third = session.applying(delta: 0.05, to: second)
        XCTAssertEqual(third, 0.3, accuracy: 0.000_001)
    }

    func testSessionClampsToOneAndZero() throws {
        var session = PopupLevelScrollSession()
        let top = try XCTUnwrap(
            session.scalar(at: 1, displayID: "display-a", fallback: 0.98)
        )
        XCTAssertEqual(session.applying(delta: 0.5, to: top), 1.0, accuracy: 0.000_001)

        session.reset()
        let bottom = try XCTUnwrap(
            session.scalar(at: 2, displayID: "display-a", fallback: 0.02)
        )
        XCTAssertEqual(session.applying(delta: -0.5, to: bottom), 0.0, accuracy: 0.000_001)
    }

    func testSessionResetsWhenTheDisplayChanges() throws {
        var session = PopupLevelScrollSession()
        let first = try XCTUnwrap(
            session.scalar(at: 5, displayID: "display-a", fallback: 0.2)
        )
        _ = session.applying(delta: 0.4, to: first)

        let switched = try XCTUnwrap(
            session.scalar(at: 5.1, displayID: "display-b", fallback: 0.7)
        )
        XCTAssertEqual(switched, 0.7, accuracy: 0.000_001)
    }

    func testSessionResetsAfterTheTimeout() throws {
        var session = PopupLevelScrollSession()
        let first = try XCTUnwrap(
            session.scalar(at: 1, displayID: "display-a", fallback: 0.2)
        )
        _ = session.applying(delta: 0.3, to: first)

        let afterTimeout = try XCTUnwrap(
            session.scalar(
                at: 1 + PopupLevelScrollSession.timeout + 0.1,
                displayID: "display-a",
                fallback: 0.9
            )
        )
        XCTAssertEqual(afterTimeout, 0.9, accuracy: 0.000_001)
    }

    func testSessionReturnsNilWithoutAReadableFallback() {
        var session = PopupLevelScrollSession()
        XCTAssertNil(
            session.scalar(at: 1, displayID: "display-a", fallback: nil)
        )
    }
}