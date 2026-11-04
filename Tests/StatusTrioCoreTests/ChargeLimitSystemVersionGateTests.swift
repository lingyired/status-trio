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