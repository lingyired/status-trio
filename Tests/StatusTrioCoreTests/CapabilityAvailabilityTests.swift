import XCTest
@testable import StatusTrioCore

final class CapabilityAvailabilityTests: XCTestCase {
    func testOnlyAvailableCanPerformActions() {
        XCTAssertTrue(CapabilityAvailability.available.isActionable)

        let blocked: [CapabilityAvailability] = [
            .permissionRequired,
            .unsupported(reason: "distribution"),
            .temporarilyUnavailable(reason: "device disconnected"),
            .notVerified
        ]
        for state in blocked {
            XCTAssertFalse(state.isActionable)
        }
    }

    func testUnknownAndDeniedAreNotUnsupported() {
        XCTAssertNotEqual(
            CapabilityAvailability.notVerified,
            .unsupported(reason: "distribution")
        )
        XCTAssertNotEqual(
            CapabilityAvailability.permissionRequired,
            .notVerified
        )
    }
}
