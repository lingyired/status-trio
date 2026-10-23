import XCTest
@testable import StatusTrioCore

@MainActor
final class StatusBarBackingScaleTests: XCTestCase {
    func testTheButtonsOwnWindowDecidesTheScaleOnASecondaryDisplay() {
        // The item landed on a 1x secondary display while the main screen is 2x.
        let resolution = StatusBarController.resolveBackingScale(
            windowScale: 1,
            mainScreenScale: 2
        )

        XCTAssertEqual(resolution.scale, 1)
        XCTAssertTrue(resolution.isFinal)
    }

    func testAMissingWindowGuessesFromTheMainScreenButLeavesTheScaleProvisional() {
        let resolution = StatusBarController.resolveBackingScale(
            windowScale: nil,
            mainScreenScale: 2
        )

        XCTAssertEqual(resolution.scale, 2)
        XCTAssertFalse(
            resolution.isFinal,
            "a guessed scale must never be cached as the successful render key"
        )
    }

    func testNoScreenAtAllDrawsAtOneXAndAlsoStaysProvisional() {
        let resolution = StatusBarController.resolveBackingScale(
            windowScale: nil,
            mainScreenScale: nil
        )

        XCTAssertEqual(resolution.scale, 1)
        XCTAssertFalse(resolution.isFinal)
    }

    func testAnUnusableWindowScaleIsTreatedAsNoWindow() {
        for unusable in [CGFloat(0), -2, .nan, .infinity] {
            let resolution = StatusBarController.resolveBackingScale(
                windowScale: unusable,
                mainScreenScale: 2
            )

            XCTAssertEqual(resolution.scale, 2, "windowScale \(unusable) should be ignored")
            XCTAssertFalse(resolution.isFinal)
        }
    }
}
