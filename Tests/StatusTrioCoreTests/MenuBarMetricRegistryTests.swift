import XCTest
@testable import StatusTrioCore

final class MenuBarMetricRegistryTests: XCTestCase {
    func testAllIdsHaveTitleAndKind() {
        XCTAssertEqual(MenuBarMetricID.allCases.count, 14)
        for metric in MenuBarMetricID.allCases {
            _ = MenuBarMetricRegistry.titleKey(for: metric)
        }
        XCTAssertEqual(MenuBarMetricRegistry.valueKind(for: .wifiConnectionStatus), .text)
        XCTAssertEqual(MenuBarMetricRegistry.valueKind(for: .cpuUsage), .numeric)
        XCTAssertEqual(MenuBarMetricRegistry.valueKind(for: .screenBrightness), .numeric)
    }

    func testFormats() {
        XCTAssertEqual(MenuBarMetricRegistry.format(45, for: .cpuUsage), "45%")
        XCTAssertEqual(MenuBarMetricRegistry.format(62.4, for: .cpuTemperature), "62°")
        XCTAssertEqual(MenuBarMetricRegistry.format(1500, for: .fanRPM), "1500 RPM")
        XCTAssertEqual(MenuBarMetricRegistry.format(80, for: .batteryLevel), "80%")
        let speed = MenuBarMetricRegistry.format(1_200_000, for: .networkDownload)
        XCTAssertTrue(speed.contains("B"), "speed \(speed)")
    }

    func testHardwareMapping() {
        XCTAssertEqual(MenuBarMetricRegistry.hardwareMonitorMetric(for: .cpuUsage), .cpuUsage)
        XCTAssertEqual(MenuBarMetricRegistry.hardwareMonitorMetric(for: .batteryLevel), .batteryLevel)
        XCTAssertNil(MenuBarMetricRegistry.hardwareMonitorMetric(for: .wifiConnectionStatus))
        XCTAssertNil(MenuBarMetricRegistry.hardwareMonitorMetric(for: .diskReadSpeed))
    }

    func testHardwareMetricIDMapping() {
        XCTAssertEqual(MenuBarMetricRegistry.hardwareMetricID(for: .diskReadSpeed), .diskRead)
        XCTAssertNil(MenuBarMetricRegistry.hardwareMetricID(for: .wifiConnectionStatus))
        XCTAssertNil(MenuBarMetricRegistry.hardwareMetricID(for: .screenBrightness))
    }
}
