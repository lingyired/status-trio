import XCTest
@testable import StatusTrioCore

final class CapabilityAvailabilityTests: XCTestCase {
    func testOnlyNativeOrHelperCanPerformActions() {
        XCTAssertTrue(CapabilityAvailability.nativeAvailable.isActionable)
        XCTAssertTrue(CapabilityAvailability.helperProvided.isActionable)

        let blocked: [CapabilityAvailability] = [
            .helperNotInstalled,
            .helperUpdateRequired,
            .helperMissingAuthorization,
            .permissionDenied(reason: "denied"),
            .unsupported(reason: "distribution"),
            .temporarilyUnavailable(reason: "device disconnected"),
            .notVerified
        ]
        for state in blocked {
            XCTAssertFalse(state.isActionable, "\(state) must not be actionable")
        }
    }

    func testUnknownAndDeniedAreNotUnsupported() {
        XCTAssertNotEqual(
            CapabilityAvailability.notVerified,
            .unsupported(reason: "distribution")
        )
        XCTAssertNotEqual(
            CapabilityAvailability.permissionDenied(reason: "d"),
            .notVerified
        )
    }

    func testCompositionBlockedClassification() {
        XCTAssertTrue(CapabilityAvailability.helperNotInstalled.isCompositionBlocked)
        XCTAssertTrue(CapabilityAvailability.helperUpdateRequired.isCompositionBlocked)
        XCTAssertTrue(CapabilityAvailability.helperMissingAuthorization.isCompositionBlocked)
        XCTAssertTrue(CapabilityAvailability.unsupported(reason: "x").isCompositionBlocked)
        XCTAssertTrue(CapabilityAvailability.notVerified.isCompositionBlocked)
        XCTAssertFalse(CapabilityAvailability.nativeAvailable.isCompositionBlocked)
        XCTAssertFalse(CapabilityAvailability.helperProvided.isCompositionBlocked)
        XCTAssertFalse(CapabilityAvailability.permissionDenied(reason: "x").isCompositionBlocked)
        XCTAssertFalse(CapabilityAvailability.temporarilyUnavailable(reason: "x").isCompositionBlocked)
    }
}
