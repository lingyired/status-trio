import XCTest
@testable import StatusTrioCore

/// #246: Low Power Mode turns on by itself once per low-battery cycle when the
/// battery falls below the existing low-battery threshold on battery power.
@MainActor
final class LowPowerAutoEnableControllerTests: XCTestCase {
    func testFiresOnceWhenTheBatteryDropsBelowTheThresholdOnBattery() {
        let controller = LowPowerAutoEnableController()

        XCTAssertTrue(
            controller.evaluate(
                battery: battery(percent: 15, connected: false),
                threshold: 20,
                isEnabled: true
            )
        )
        // A second snapshot in the same cycle must not write again.
        XCTAssertFalse(
            controller.evaluate(
                battery: battery(percent: 14, connected: false),
                threshold: 20,
                isEnabled: true
            )
        )
    }

    func testDoesNotFireWhilePluggedIn() {
        let controller = LowPowerAutoEnableController()
        XCTAssertFalse(
            controller.evaluate(
                battery: battery(percent: 10, connected: true),
                threshold: 20,
                isEnabled: true
            )
        )
    }

    func testDoesNotFireAtOrAboveTheThreshold() {
        let controller = LowPowerAutoEnableController()
        XCTAssertFalse(
            controller.evaluate(
                battery: battery(percent: 20, connected: false),
                threshold: 20,
                isEnabled: true
            )
        )
        XCTAssertFalse(
            controller.evaluate(
                battery: battery(percent: 45, connected: false),
                threshold: 20,
                isEnabled: true
            )
        )
    }

    func testPluggingInRearmsTheCycle() {
        let controller = LowPowerAutoEnableController()
        XCTAssertTrue(
            controller.evaluate(
                battery: battery(percent: 15, connected: false),
                threshold: 20,
                isEnabled: true
            )
        )
        // Plug in: the low-battery cycle ends.
        XCTAssertFalse(
            controller.evaluate(
                battery: battery(percent: 15, connected: true),
                threshold: 20,
                isEnabled: true
            )
        )
        // Back on battery and still low: the next cycle may fire again.
        XCTAssertTrue(
            controller.evaluate(
                battery: battery(percent: 12, connected: false),
                threshold: 20,
                isEnabled: true
            )
        )
    }

    func testRisingAboveTheThresholdRearmsTheCycle() {
        let controller = LowPowerAutoEnableController()
        XCTAssertTrue(
            controller.evaluate(
                battery: battery(percent: 15, connected: false),
                threshold: 20,
                isEnabled: true
            )
        )
        XCTAssertFalse(
            controller.evaluate(
                battery: battery(percent: 30, connected: false),
                threshold: 20,
                isEnabled: true
            )
        )
        XCTAssertTrue(
            controller.evaluate(
                battery: battery(percent: 18, connected: false),
                threshold: 20,
                isEnabled: true
            )
        )
    }

    func testAlreadyInLowPowerModeConsumesTheCycleWithoutAWrite() {
        let controller = LowPowerAutoEnableController()
        XCTAssertFalse(
            controller.evaluate(
                battery: battery(percent: 15, connected: false, lowPower: true),
                threshold: 20,
                isEnabled: true
            )
        )
        // The user turns it off in the same cycle: the automation must not
        // fight the user by switching it straight back on.
        XCTAssertFalse(
            controller.evaluate(
                battery: battery(percent: 15, connected: false, lowPower: false),
                threshold: 20,
                isEnabled: true
            )
        )
    }

    func testDisabledNeverFires() {
        let controller = LowPowerAutoEnableController()
        XCTAssertFalse(
            controller.evaluate(
                battery: battery(percent: 5, connected: false),
                threshold: 20,
                isEnabled: false
            )
        )
    }

    func testNoBatteryNeverFires() {
        let controller = LowPowerAutoEnableController()
        let noBattery = BatteryStatus(
            rawPercentage: nil,
            isPresent: false,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
        XCTAssertFalse(
            controller.evaluate(battery: noBattery, threshold: 20, isEnabled: true)
        )
    }

    func testResetRearmsTheCycle() {
        let controller = LowPowerAutoEnableController()
        XCTAssertTrue(
            controller.evaluate(
                battery: battery(percent: 15, connected: false),
                threshold: 20,
                isEnabled: true
            )
        )
        controller.reset()
        XCTAssertTrue(
            controller.evaluate(
                battery: battery(percent: 15, connected: false),
                threshold: 20,
                isEnabled: true
            )
        )
    }

    // MARK: - Helpers

    private func battery(
        percent: Int,
        connected: Bool,
        lowPower: Bool = false
    ) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percent,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: lowPower,
            isConnectedToPower: connected
        )
    }
}
