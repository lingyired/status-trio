import XCTest
@testable import StatusTrioCore

final class MenuBarMetricColorResolverTests: XCTestCase {
    func testRecommendedFallback() {
        let color = MenuBarMetricColorResolver.sourceColor(
            for: .cpuUsage, overrides: [:], batteryLevel: nil
        )
        XCTAssertEqual(color, HardwareRingColorConfiguration.recommendedBaseColor(for: .cpuUsage))
    }

    func testUserOverride() {
        let override = IconRGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        let color = MenuBarMetricColorResolver.sourceColor(
            for: .cpuUsage,
            overrides: [.cpuUsage: override],
            batteryLevel: nil
        )
        XCTAssertEqual(color, override)
    }

    func testTextMetricHasNoSourceColor() {
        XCTAssertNil(MenuBarMetricColorResolver.sourceColor(
            for: .wifiConnectionStatus, overrides: [:], batteryLevel: nil
        ))
    }

    func testBatteryUsesStatusBands() {
        XCTAssertNotEqual(
            MenuBarMetricColorResolver.batteryColor(level: 10),
            MenuBarMetricColorResolver.batteryColor(level: 90)
        )
        XCTAssertEqual(
            MenuBarMetricColorResolver.batteryColor(level: 90),
            HardwareRingColorConfiguration.recommendedBaseColor(for: .batteryLevel)
        )
    }

    func testAppliedColorFixedWins() {
        let fixed = ColorValue(red: 0.2, green: 0.4, blue: 1, alpha: 1)
        let source = IconRGBA(red: 1, green: 0, blue: 0, alpha: 1)
        XCTAssertEqual(
            MenuBarMetricColorResolver.appliedColor(line: .fixed(fixed), source: source),
            IconRGBA(red: 0.2, green: 0.4, blue: 1, alpha: 1)
        )
        XCTAssertEqual(
            MenuBarMetricColorResolver.appliedColor(line: .inheritSource, source: source),
            source
        )
    }
}
