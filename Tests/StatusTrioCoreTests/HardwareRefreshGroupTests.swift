import XCTest
@testable import StatusTrioCore

final class HardwareRefreshGroupTests: XCTestCase {
    func testMetricMapping() {
        XCTAssertEqual(HardwareRefreshGroup.group(for: .cpuUsage), .cpuUsage)
        XCTAssertEqual(HardwareRefreshGroup.group(for: .gpuUsage), .gpuUsage)
        XCTAssertEqual(HardwareRefreshGroup.group(for: .memoryUsage), .memory)
        XCTAssertEqual(HardwareRefreshGroup.group(for: .memoryPressure), .memory)
        XCTAssertEqual(HardwareRefreshGroup.group(for: .networkDownload), .network)
        XCTAssertEqual(HardwareRefreshGroup.group(for: .networkUpload), .network)
        XCTAssertEqual(HardwareRefreshGroup.group(for: .cpuTemperature), .temperature)
        XCTAssertEqual(HardwareRefreshGroup.group(for: .gpuTemperature), .temperature)
        XCTAssertEqual(HardwareRefreshGroup.group(for: .batteryTemperature), .temperature)
        XCTAssertEqual(HardwareRefreshGroup.group(for: .fanRPM(index: 0)), .temperature)
        XCTAssertEqual(HardwareRefreshGroup.group(for: .diskRead), .disk)
        XCTAssertEqual(HardwareRefreshGroup.group(for: .diskWrite), .disk)
        XCTAssertNil(HardwareRefreshGroup.group(for: .volume))
        XCTAssertNil(HardwareRefreshGroup.group(for: .wifiSignal))
        XCTAssertNil(HardwareRefreshGroup.group(for: .batteryLevel))
    }

    func testDefaultsAndOptions() {
        XCTAssertEqual(HardwareRefreshGroup.cpuUsage.defaultSeconds, 2)
        XCTAssertEqual(HardwareRefreshGroup.gpuUsage.defaultSeconds, 2)
        XCTAssertEqual(HardwareRefreshGroup.memory.defaultSeconds, 2)
        XCTAssertEqual(HardwareRefreshGroup.network.defaultSeconds, 1)
        XCTAssertEqual(HardwareRefreshGroup.temperature.defaultSeconds, 4)
        XCTAssertEqual(HardwareRefreshGroup.disk.defaultSeconds, 1)

        XCTAssertEqual(HardwareRefreshGroup.cpuUsage.options, Array(2...8))
        XCTAssertEqual(HardwareRefreshGroup.network.options, Array(1...8))
        XCTAssertEqual(HardwareRefreshGroup.temperature.options, Array(4...8))
        XCTAssertEqual(HardwareRefreshGroup.disk.options, Array(1...8))
    }
}
