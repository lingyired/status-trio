import XCTest
@testable import StatusTrioCore

final class TelemetryEligibilityTests: XCTestCase {
    func testProductionReleaseWithMarkerIsEligible() {
        XCTAssertTrue(TelemetryEligibility.isEligible(.init(
            bundleIdentifier: "com.lingsmbp.StatusTrio",
            productionMarker: true,
            isDebugBuild: false
        )))
    }

    func testDevelopmentBundleIsIneligible() {
        XCTAssertFalse(TelemetryEligibility.isEligible(.init(
            bundleIdentifier: "com.example.StatusTrio",
            productionMarker: true,
            isDebugBuild: false
        )))
    }

    func testMissingBundleIdentifierIsIneligible() {
        XCTAssertFalse(TelemetryEligibility.isEligible(.init(
            bundleIdentifier: nil,
            productionMarker: true,
            isDebugBuild: false
        )))
    }

    func testMissingProductionMarkerIsIneligible() {
        XCTAssertFalse(TelemetryEligibility.isEligible(.init(
            bundleIdentifier: "com.lingsmbp.StatusTrio",
            productionMarker: false,
            isDebugBuild: false
        )))
    }

    func testDebugBuildIsIneligibleEvenWithProductionMarker() {
        XCTAssertFalse(TelemetryEligibility.isEligible(.init(
            bundleIdentifier: "com.lingsmbp.StatusTrio",
            productionMarker: true,
            isDebugBuild: true
        )))
    }
}
