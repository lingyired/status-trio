import XCTest
@testable import StatusTrioCore

/// The "prefer the system battery optimization" hint must depend only on the
/// running macOS version. Gating it on the PowerUI capability would silently
/// extend the recommendation to legacy macOS once the SMC backend ships.
final class ChargeLimitSystemVersionGateTests: XCTestCase {
    private func v(_ major: Int, _ minor: Int) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
    }

    func testPreferenceAppearsOnTahoeAndLater() {
        XCTAssertTrue(ChargeLimitSystemVersionGate.prefersSystemBatteryOptimization(version: v(26, 4)))
        XCTAssertTrue(ChargeLimitSystemVersionGate.prefersSystemBatteryOptimization(version: v(26, 6)))
        XCTAssertTrue(ChargeLimitSystemVersionGate.prefersSystemBatteryOptimization(version: v(27, 0)))
    }

    func testPreferenceIsHiddenBeforeTheNativeLimitExists() {
        XCTAssertFalse(ChargeLimitSystemVersionGate.prefersSystemBatteryOptimization(version: v(13, 0)))
        XCTAssertFalse(ChargeLimitSystemVersionGate.prefersSystemBatteryOptimization(version: v(14, 7)))
        XCTAssertFalse(ChargeLimitSystemVersionGate.prefersSystemBatteryOptimization(version: v(15, 4)))
        XCTAssertFalse(ChargeLimitSystemVersionGate.prefersSystemBatteryOptimization(version: v(26, 3)))
    }
}
/// The native charge-to-full option must not appear below the OS that ships the
/// system charge limit, even if a private-API probe ever reported support.
final class NativeChargeToFullVersionGateTests: XCTestCase {
    private func v(_ major: Int, _ minor: Int) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
    }

    func testNativeOptionIsHiddenBeforeMacOS264() {
        for version in [v(13, 0), v(14, 7), v(15, 5), v(26, 3)] {
            XCTAssertEqual(
                PowerUIChargeController.gatedCapability(.available, version: version),
                .unavailable(.unsupportedSystem)
            )
        }
    }

    func testNativeOptionKeepsTheBridgeAnswerFrom264On() {
        XCTAssertEqual(
            PowerUIChargeController.gatedCapability(.available, version: v(26, 4)),
            .available
        )
        XCTAssertEqual(
            PowerUIChargeController.gatedCapability(
                .unavailable(.frameworkUnavailable), version: v(27, 0)
            ),
            .unavailable(.frameworkUnavailable)
        )
    }
}
