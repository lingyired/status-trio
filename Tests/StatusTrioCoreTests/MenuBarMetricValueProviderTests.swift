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

    func testExpandedStorageAndFrequencyMetricsFormat() {
        var hardware = HardwareMetricsSnapshot()
        hardware.samples[.memoryUsedBytes] = sample(8 * 1_073_741_824, .measured)
        hardware.samples[.memoryFreeBytes] = sample(4 * 1_073_741_824, .measured)
        hardware.samples[.diskUsedBytes] = sample(512 * 1_000_000_000, .measured)
        hardware.samples[.diskFreeBytes] = sample(256 * 1_000_000_000, .measured)
        hardware.samples[.cpuFrequency] = sample(3.5, .measured)
        hardware.samples[.diskTotal] = sample(3_000_000, .measured)
        let result = provider.readings(
            for: [.memoryUsed, .memoryFree, .diskUsed, .diskFree, .cpuFrequency, .diskTotalSpeed],
            hardware: hardware,
            status: status()
        )
        XCTAssertEqual(result[.memoryUsed]?.text, "8.0 GB")
        XCTAssertEqual(result[.memoryFree]?.text, "4.0 GB")
        XCTAssertEqual(result[.diskUsed]?.text, "512.0 GB")
        XCTAssertEqual(result[.diskFree]?.text, "256.0 GB")
        XCTAssertEqual(result[.cpuFrequency]?.text, "3.50 GHz")
        XCTAssertEqual(result[.diskTotalSpeed]?.text, "3.0 MB/s")
    }

    func testSelectedExternalDiskTotalsSumOnlyTickedVolumes() {
        var hardware = HardwareMetricsSnapshot()
        hardware.diskVolumes = [
            DiskVolumeReading(name: "Ext A", mountPath: "/Volumes/A", totalBytes: 512_000_000_000,
                              freeBytes: 256_000_000_000, fileSystem: "APFS",
                              isExternal: true, isReadOnly: false),
            DiskVolumeReading(name: "Ext B", mountPath: "/Volumes/B", totalBytes: 512_000_000_000,
                              freeBytes: 128_000_000_000, fileSystem: "APFS",
                              isExternal: true, isReadOnly: false),
            DiskVolumeReading(name: "Unticked", mountPath: "/Volumes/C", totalBytes: 999_000_000_000,
                              freeBytes: 999_000_000_000, fileSystem: "APFS",
                              isExternal: true, isReadOnly: false),
            DiskVolumeReading(name: "Internal", mountPath: "/", totalBytes: 1_000_000_000_000,
                              freeBytes: 400_000_000_000, fileSystem: "APFS",
                              isExternal: false, isReadOnly: false),
        ]
        let selected = MenuBarMetricValueProvider(
            localize: { $0.rawValue },
            externalVolumePaths: { ["/Volumes/A", "/Volumes/B"] }
        )
        let result = selected.readings(
            for: [.diskExternalTotal, .diskExternalFree],
            hardware: hardware,
            status: status()
        )
        XCTAssertEqual(result[.diskExternalTotal]?.text, "1.02 TB")
        XCTAssertEqual(result[.diskExternalFree]?.text, "384.0 GB")
    }

    func testPowerMetricsUseLiveSamplesAndBatterySign() {
        let now = Date()
        let power = MenuBarMetricValueProvider(
            localize: { $0.rawValue },
            systemPower: { SystemPowerSample(watts: 42.4, readAt: now) },
            inputPower: { SystemPowerSample(watts: 67.0, readAt: now) },
            batteryPower: { BatteryPowerSample(volts: 12, amps: -0.7, updatedAt: now) }
        )
        let result = power.readings(
            for: [.systemPower, .inputPower, .batteryPower],
            hardware: HardwareMetricsSnapshot(),
            status: status()
        )
        XCTAssertEqual(result[.systemPower]?.text, "42.4 W")
        XCTAssertEqual(result[.inputPower]?.text, "67.0 W")
        XCTAssertEqual(result[.batteryPower]?.text, "-8.4 W")
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
