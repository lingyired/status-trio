import XCTest
@testable import StatusTrioCore

final class HardwareRingDefaultColorTests: XCTestCase {
    private func expected(_ hex: UInt32) -> (Double, Double, Double) {
        (
            Double((hex >> 16) & 0xFF) / 255.0,
            Double((hex >> 8) & 0xFF) / 255.0,
            Double(hex & 0xFF) / 255.0
        )
    }

    private func assertColor(_ color: IconRGBA, _ hex: UInt32, file: StaticString = #filePath, line: UInt = #line) {
        let e = expected(hex)
        XCTAssertEqual(color.red, e.0, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(color.green, e.1, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(color.blue, e.2, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(color.alpha, 1, accuracy: 0.001, file: file, line: line)
    }

    func testDefaultPaletteMatchesSpec() {
        assertColor(HardwareRingColorConfiguration.recommendedBaseColor(for: .cpuUsage), 0x43C97A)
        assertColor(HardwareRingColorConfiguration.recommendedBaseColor(for: .gpuUsage), 0x4A90FF)
        assertColor(HardwareRingColorConfiguration.recommendedBaseColor(for: .memoryUsage), 0xA477F5)
        assertColor(HardwareRingColorConfiguration.solidStateDriveColor, 0xAAB5C8)
        assertColor(HardwareRingColorConfiguration.recommendedBaseColor(for: .cpuTemperature), 0x35BFCF)
        assertColor(HardwareRingColorConfiguration.recommendedBaseColor(for: .batteryTemperature), 0x36ADA4)
        assertColor(HardwareRingColorConfiguration.recommendedBaseColor(for: .fan), 0x8BA4C3)
        assertColor(HardwareRingColorConfiguration.recommendedBaseColor(for: .downloadSpeed), 0x31B985)
        assertColor(HardwareRingColorConfiguration.recommendedBaseColor(for: .uploadSpeed), 0xF2A34B)
    }

    func testStatusColorsMatchSpec() {
        assertColor(HardwareRingColorConfiguration.warningColor, 0xF5A524)
        assertColor(HardwareRingColorConfiguration.criticalColor, 0xE45454)
    }

    @MainActor
    func testCustomColorOverridesDefaultAndResetRestoresPalette() {
        let suite = "HardwareRingDefaultColorTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = SettingsStore(defaults: defaults, systemChargeLimit: { nil })
        XCTAssertEqual(store.hardwareColor(for: .cpuUsage), HardwareRingColorConfiguration.cpuColor)

        let custom = IconRGBA(red: 1, green: 0, blue: 1, alpha: 1)
        store.setHardwareColor(custom, for: .cpuUsage)
        XCTAssertEqual(store.hardwareColor(for: .cpuUsage), custom, "custom colour must win")

        store.hardwareMonitorMetricColors = [:]
        XCTAssertEqual(store.hardwareColor(for: .cpuUsage), HardwareRingColorConfiguration.cpuColor,
                       "clearing the custom colour falls back to the new palette")
    }
}
