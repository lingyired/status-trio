import PowerHelperProtocol
import XCTest

final class PowerHelperConstantsTests: XCTestCase {
    func testClientRequirementNamesTheIdentityTheAppChecksAgain() {
        let requirement = PowerHelperConstants.clientRequirement

        // The daemon enforces this string and the app compares its own
        // signature against the same constants, so the two must stay one value.
        XCTAssertTrue(requirement.contains(PowerHelperConstants.clientBundleIdentifier))
        XCTAssertTrue(requirement.contains(PowerHelperConstants.clientTeamIdentifier))
        XCTAssertEqual(
            requirement,
            PowerHelperConstants.clientRequirementString(
                bundleIdentifier: PowerHelperConstants.clientBundleIdentifier,
                teamIdentifier: PowerHelperConstants.clientTeamIdentifier
            )
        )
    }

    func testInjectedIdentityIsReflectedInTheRequirement() {
        let requirement = PowerHelperConstants.clientRequirementString(
            bundleIdentifier: "com.example.StatusTrio.dev",
            teamIdentifier: "TEAM123456"
        )

        XCTAssertTrue(requirement.contains("com.example.StatusTrio.dev"))
        XCTAssertTrue(requirement.contains("TEAM123456"))
        XCTAssertTrue(requirement.hasPrefix("anchor apple generic"))
    }
}
