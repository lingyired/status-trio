import XCTest
@testable import StatusTrioCore

/// The battery details page now presents the three system Power Mode states as
/// one selection. These tests pin the mutual exclusion without SwiftUI.
final class PowerModeSelectionLogicTests: XCTestCase {
    func testSelectionPrefersHighThenLowThenAutomatic() {
        XCTAssertEqual(
            PowerModeSelectionLogic.selection(isLow: false, isHigh: false),
            .automatic
        )
        XCTAssertEqual(
            PowerModeSelectionLogic.selection(isLow: true, isHigh: false),
            .low
        )
        XCTAssertEqual(
            PowerModeSelectionLogic.selection(isLow: false, isHigh: true),
            .high
        )
        // Both reading on is a settling daemon, never a valid user state.
        XCTAssertEqual(
            PowerModeSelectionLogic.selection(isLow: true, isHigh: true),
            .high
        )
    }

    func testSelectingLowFromAutomaticOnlyTurnsLowOn() {
        let transition = PowerModeSelectionLogic.transition(
            to: .low,
            isLow: false,
            isHigh: false
        )
        XCTAssertTrue(transition.turnOnLow)
        XCTAssertFalse(transition.turnOffLow)
        XCTAssertFalse(transition.turnOnHigh)
        XCTAssertFalse(transition.turnOffHigh)
    }

    func testSelectingHighFromLowLeavesTheMutualExclusionToTheDaemon() {
        // One request per user choice: the daemon clears Low while enabling
        // High, so a second write would only add a race.
        let transition = PowerModeSelectionLogic.transition(
            to: .high,
            isLow: true,
            isHigh: false
        )
        XCTAssertTrue(transition.turnOnHigh)
        XCTAssertFalse(transition.turnOffLow)
        XCTAssertFalse(transition.turnOffHigh)
    }

    func testSelectingLowFromHighLeavesTheMutualExclusionToTheDaemon() {
        let transition = PowerModeSelectionLogic.transition(
            to: .low,
            isLow: false,
            isHigh: true
        )
        XCTAssertTrue(transition.turnOnLow)
        XCTAssertFalse(transition.turnOffHigh)
    }

    func testSelectingAutomaticTurnsOffWhicheverModeIsOn() {
        XCTAssertEqual(
            PowerModeSelectionLogic.transition(
                to: .automatic,
                isLow: true,
                isHigh: false
            ),
            PowerModeTransition(turnOffLow: true)
        )
        XCTAssertEqual(
            PowerModeSelectionLogic.transition(
                to: .automatic,
                isLow: false,
                isHigh: true
            ),
            PowerModeTransition(turnOffHigh: true)
        )
    }

    func testSelectingTheCurrentModeIsANoOp() {
        XCTAssertTrue(
            PowerModeSelectionLogic.transition(
                to: .automatic,
                isLow: false,
                isHigh: false
            ).isNoOp
        )
        XCTAssertTrue(
            PowerModeSelectionLogic.transition(
                to: .low,
                isLow: true,
                isHigh: false
            ).isNoOp
        )
        XCTAssertTrue(
            PowerModeSelectionLogic.transition(
                to: .high,
                isLow: false,
                isHigh: true
            ).isNoOp
        )
    }
}
