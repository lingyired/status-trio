import XCTest
@testable import StatusTrioCore

final class MenuBarMetricValueProviderTests: XCTestCase {
    private func sample(_ value: Double?, _ availability: HardwareMetricAvailability) -> HardwareMetricSample {
        HardwareMetricSample(
            value: value,
            unit: .percent,
            sampledAt: Date(),
            source: .smc,
            availability: availability
        )
    }

    private func status(battery: Int = 80, wifi: WiFiState = .connected) -> StatusSnapshot {
        StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: battery,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            wifi: WiFiStatus(state: wifi, rssi: nil),
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Speakers"),
            brightness: .placeholder
        )
    }

    private var provider: MenuBarMetricValueProvider {
        MenuBarMetricValueProvider(localize: { key in
            switch key {
            case .menuBarMetricWifiConnected: return "Connected"
            case .menuBarMetricWifiDisconnected: return "Disconnected"
            default: return key.rawValue
            }
        })
    }

    func testMeasuredFormatsValue() {
        var hardware = HardwareMetricsSnapshot()
        hardware.samples[.cpuUsage] = sample(45, .measured)
        let result = provider.readings(for: [.cpuUsage], hardware: hardware, status: status())
        XCTAssertEqual(result[.cpuUsage]?.text, "45%")
        XCTAssertEqual(result[.cpuUsage]?.value, 45)
        XCTAssertEqual(result[.cpuUsage]?.availability, .measured)
    }

    func testZeroShowsZeroNotDash() {
        var hardware = HardwareMetricsSnapshot()
        hardware.samples[.cpuUsage] = sample(0, .measured)
        let result = provider.readings(for: [.cpuUsage], hardware: hardware, status: status())
        XCTAssertEqual(result[.cpuUsage]?.text, "0%")
    }

    func testNonMeasuredShowsDash() {
        var hardware = HardwareMetricsSnapshot()
        hardware.samples[.cpuUsage] = sample(nil, .stale)
        let result = provider.readings(for: [.cpuUsage], hardware: hardware, status: status())
        XCTAssertEqual(result[.cpuUsage]?.text, "--")
        XCTAssertNil(result[.cpuUsage]?.value)
    }

    func testWiFiStatusText() {
        let connected = provider.readings(for: [.wifiConnectionStatus], hardware: .init(), status: status(wifi: .connected))
        XCTAssertEqual(connected[.wifiConnectionStatus]?.text, "Connected")
        let off = provider.readings(for: [.wifiConnectionStatus], hardware: .init(), status: status(wifi: .off))
        XCTAssertEqual(off[.wifiConnectionStatus]?.text, "Disconnected")
    }

    func testBatteryFromStatusSnapshot() {
        let result = provider.readings(for: [.batteryLevel], hardware: .init(), status: status(battery: 75))
        XCTAssertEqual(result[.batteryLevel]?.text, "75%")
    }

    func testVolumeFromStatusSnapshot() {
        let result = provider.readings(for: [.outputVolume], hardware: .init(), status: status())
        XCTAssertEqual(result[.outputVolume]?.text, "50%")
    }

    func testMissingMetricShowsDash() {
        let result = provider.readings(for: [.gpuUsage], hardware: .init(), status: status())
        XCTAssertEqual(result[.gpuUsage]?.text, "--")
        XCTAssertEqual(result[.gpuUsage]?.availability, .collecting)
    }
}
