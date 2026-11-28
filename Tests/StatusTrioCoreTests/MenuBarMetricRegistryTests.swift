import XCTest
@testable import StatusTrioCore

final class MenuBarMetricRegistryTests: XCTestCase {
    func testAllIdsHaveTitleAndKind() {
        XCTAssertEqual(MenuBarMetricID.allCases.count, 29)
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
        XCTAssertEqual(MenuBarMetricRegistry.format(3.456, for: .cpuFrequency), "3.46 GHz")
        XCTAssertEqual(MenuBarMetricRegistry.format(8 * 1_073_741_824, for: .memoryUsed), "8.0 GB")
        XCTAssertEqual(MenuBarMetricRegistry.format(512 * 1_000_000_000, for: .diskFree), "512.0 GB")
        XCTAssertEqual(MenuBarMetricRegistry.format(2_000_000_000_000, for: .diskExternalTotal), "2.00 TB")
        let total = MenuBarMetricRegistry.format(3_000_000, for: .diskTotalSpeed)
        XCTAssertTrue(total.contains("B"), "total \(total)")
        XCTAssertEqual(MenuBarMetricRegistry.format(42.44, for: .systemPower), "42.4 W")
        XCTAssertEqual(MenuBarMetricRegistry.format(60, for: .diskUsagePercent), "60%")
        XCTAssertEqual(MenuBarMetricRegistry.format(63, for: .diskExternalUsagePercent), "63%")
        XCTAssertEqual(MenuBarMetricRegistry.format(61.2, for: .diskCombinedUsagePercent), "61%")
        XCTAssertEqual(MenuBarMetricRegistry.format(784 * 1_000_000_000, for: .diskCombinedFree), "784.0 GB")
        XCTAssertEqual(MenuBarMetricRegistry.format(2.0, for: .batteryPower), "+2.0 W")
        XCTAssertEqual(MenuBarMetricRegistry.format(-8.25, for: .batteryPower), "-8.2 W")
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
        XCTAssertEqual(MenuBarMetricRegistry.hardwareMetricID(for: .cpuFrequency), .cpuFrequency)
        XCTAssertEqual(MenuBarMetricRegistry.hardwareMetricID(for: .memoryUsed), .memoryUsedBytes)
        XCTAssertEqual(MenuBarMetricRegistry.hardwareMetricID(for: .diskFree), .diskFreeBytes)
        XCTAssertEqual(MenuBarMetricRegistry.hardwareMetricID(for: .diskExternalTotal), .diskExternalTotalBytes)
        XCTAssertEqual(MenuBarMetricRegistry.hardwareMetricID(for: .diskTotalSpeed), .diskTotal)
        XCTAssertEqual(MenuBarMetricRegistry.hardwareMetricIDs(for: .diskCombinedFree),
                       [.diskUsedBytes, .diskFreeBytes, .diskExternalTotalBytes, .diskExternalFreeBytes])
        XCTAssertNil(MenuBarMetricRegistry.hardwareMetricID(for: .systemPower))
        XCTAssertNil(MenuBarMetricRegistry.hardwareMonitorMetric(for: .batteryPower))
        XCTAssertNil(MenuBarMetricRegistry.hardwareMetricID(for: .wifiConnectionStatus))
        XCTAssertNil(MenuBarMetricRegistry.hardwareMetricID(for: .screenBrightness))
    }
}
