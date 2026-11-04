import AppKit
import XCTest
@testable import StatusTrioCore

/// Issue #235: High Power Mode tints the battery ring blue on every surface
/// that draws the shared scene.
final class HighPowerRingColorTests: XCTestCase {
    private func battery(
        percentage: Int,
        lowPower: Bool = false,
        connectedToPower: Bool = false
    ) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: lowPower,
            isConnectedToPower: connectedToPower
        )
    }

    func testHighPowerWinsOverConnectedPowerButNotCritical() {
        // High Power Mode is itself a connected-power state, so it has to win
        // over `.charging`; a critical level still wins over everything.
        XCTAssertEqual(
            StatusMappings.batteryColorRole(
                battery(percentage: 80, connectedToPower: true),
                isHighPowerMode: true
            ),
            .highPower
        )
        XCTAssertEqual(
            StatusMappings.batteryColorRole(
                battery(percentage: 10, connectedToPower: true),
                isHighPowerMode: true
            ),
            .critical
        )
    }

    func testLowPowerWinsOverHighPowerWhenBothReadOn() {
        // The two modes are mutually exclusive; if both controllers report on
        // while the daemon settles, Low Power Mode is the safer tint.
        XCTAssertEqual(
            StatusMappings.batteryColorRole(
                battery(percentage: 80, lowPower: true),
                isHighPowerMode: true
            ),
            .lowPower
        )
    }

    func testHighPowerIsOffByDefault() {
        XCTAssertEqual(
            StatusMappings.batteryColorRole(
                battery(percentage: 80, connectedToPower: true)
            ),
            .charging
        )
    }

    func testHighPowerBaselineIsBlueRatherThanWhite() {
        let palette = BatteryStatusColorPalette.resolved(dark: false)
        let blue = NSColor(cgColor: palette.color(for: .highPower))?
            .usingColorSpace(.deviceRGB)
        let yellow = NSColor(cgColor: palette.color(for: .lowPower))?
            .usingColorSpace(.deviceRGB)

        XCTAssertNotNil(blue)
        XCTAssertGreaterThan(blue?.blueComponent ?? 0, blue?.redComponent ?? 1)
        XCTAssertNotEqual(blue, yellow)
    }

    func testTheHighPowerRolePersistsItsOwnSelection() {
        var colors = BatteryStatusColors.standard
        XCTAssertEqual(colors.selection(for: .highPower), .system)
        XCTAssertFalse(colors.hasOverrides)

        colors.setSelection(.preset(.sky), for: .highPower)
        XCTAssertEqual(colors.selection(for: .highPower), .preset(.sky))
        XCTAssertTrue(colors.hasOverrides)
    }
}
