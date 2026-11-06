import XCTest
@testable import StatusTrioCore

final class StatusMappingsTests: XCTestCase {
    func testWiFiSignalBoundaries() {
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -59), 3)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -70), 3)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -71), 2)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -78), 2)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -79), 1)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -88), 1)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -89), 0)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: nil), 0)
    }

    func testVolumeBoundaries() {
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0, isMuted: false), 0)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: -0.1, isMuted: false), 0)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.01, isMuted: false), 1)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.25, isMuted: false), 1)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.26, isMuted: false), 2)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.50, isMuted: false), 2)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.51, isMuted: false), 3)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.75, isMuted: false), 3)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.76, isMuted: false), 4)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 1.0, isMuted: false), 4)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 1.1, isMuted: false), 4)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.8, isMuted: true), 0)
        XCTAssertNil(StatusMappings.volumeSteps(scalar: nil, isMuted: false))
    }

    func testBatteryProgress() {
        XCTAssertEqual(StatusMappings.batteryProgress(makeBattery(rawPercentage: 0)), 0.0)
        XCTAssertEqual(StatusMappings.batteryProgress(makeBattery(rawPercentage: 100)), 1.0)
        XCTAssertEqual(StatusMappings.batteryProgress(makeBattery(rawPercentage: -1)), 0.0)
        XCTAssertEqual(StatusMappings.batteryProgress(makeBattery(rawPercentage: 101)), 1.0)
    }

    /// Issue #105: charge limiting holds a plugged-in battery below 100%, so the
    /// ring has to close at the level the user picked instead of a fixed 100%.
    func testBatteryProgressRescalesAgainstTheFullThreshold() {
        let capped = makeBattery(rawPercentage: 80)

        XCTAssertEqual(
            StatusMappings.batteryProgress(capped, fullThreshold: 100),
            0.8,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            StatusMappings.batteryProgress(capped, fullThreshold: 80),
            1.0,
            accuracy: 0.0001,
            "The level the user calls full must close the ring."
        )
        XCTAssertEqual(
            StatusMappings.batteryProgress(makeBattery(rawPercentage: 60), fullThreshold: 80),
            0.75,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            StatusMappings.batteryProgress(makeBattery(rawPercentage: 90), fullThreshold: 80),
            1.0,
            accuracy: 0.0001,
            "Above the threshold the arc is clamped, never overfull."
        )
        XCTAssertEqual(
            StatusMappings.batteryProgress(capped, fullThreshold: 0),
            1.0,
            accuracy: 0.0001,
            "A degenerate threshold is clamped, never a division by zero."
        )
        XCTAssertEqual(
            StatusMappings.batteryProgress(makeBattery(rawPercentage: nil), fullThreshold: 80),
            1.0,
            accuracy: 0.0001,
            "A missing battery reports full, matching BatteryStatus.percentage."
        )
    }

    func testBatteryColorPriority() {
        let normal = BatteryStatus(
            rawPercentage: 100,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
        XCTAssertEqual(StatusMappings.batteryColorRole(normal), .foreground)

        let lowPower = BatteryStatus(
            rawPercentage: 100,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: true,
            isConnectedToPower: false
        )
        XCTAssertEqual(StatusMappings.batteryColorRole(lowPower), .lowPower)

        let chargingOnly = BatteryStatus(
            rawPercentage: 100,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
        XCTAssertEqual(StatusMappings.batteryColorRole(chargingOnly), .charging)

        let charging = BatteryStatus(
            rawPercentage: 100,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: true,
            isConnectedToPower: true
        )
        XCTAssertEqual(StatusMappings.batteryColorRole(charging), .lowPower)

        let connectedOnly = BatteryStatus(
            rawPercentage: 80,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
        XCTAssertEqual(StatusMappings.batteryColorRole(connectedOnly), .charging)
    }

    func testBatteryCriticalThreshold() {
        let battery = makeBattery(rawPercentage: 20)

        XCTAssertEqual(StatusMappings.batteryColorRole(battery), .foreground)
        XCTAssertEqual(
            StatusMappings.batteryColorRole(battery, criticalThreshold: 20),
            .foreground
        )
        XCTAssertEqual(
            StatusMappings.batteryColorRole(
                makeBattery(rawPercentage: 19),
                criticalThreshold: 20
            ),
            .critical
        )
    }

    func testCriticalPrecedesLowPowerAndCharging() {
        let battery = BatteryStatus(
            rawPercentage: 19,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: true,
            isConnectedToPower: true
        )

        XCTAssertEqual(
            StatusMappings.batteryColorRole(battery, criticalThreshold: 20),
            .critical
        )
    }

    func testBatteryGapContentDecisionTable() {
        XCTAssertEqual(
            StatusMappings.batteryGapContent(chargingBattery(), options: .standard),
            .bolt
        )
        XCTAssertEqual(
            StatusMappings.batteryGapContent(connectedBattery(), options: .standard),
            .plug
        )
        XCTAssertEqual(
            StatusMappings.batteryGapContent(chargedOnPower(), options: .standard),
            .plug
        )
        XCTAssertEqual(
            StatusMappings.batteryGapContent(makeBattery(rawPercentage: 80), options: .standard),
            .percentage
        )
        XCTAssertEqual(
            StatusMappings.batteryGapContent(absentBattery(), options: .standard),
            .empty,
            "no battery must not claim a percentage"
        )
    }

    func testBatteryGapContentUsesThePercentageForConnectedPowerWhenEnabled() {
        XCTAssertEqual(
            StatusMappings.batteryGapContent(
                connectedBattery(),
                options: batteryOptions(connectedIndicator: .percentage)
            ),
            .percentage
        )
    }

    func testBatteryGapContentKeepsTheBoltWhileCharging() {
        XCTAssertEqual(
            StatusMappings.batteryGapContent(
                chargingBattery(),
                options: batteryOptions(connectedIndicator: .percentage)
            ),
            .bolt
        )
    }

    func testBatteryGapContentShowsTheBoltForConnectedPowerWhenPicked() {
        XCTAssertEqual(
            StatusMappings.batteryGapContent(
                connectedBattery(),
                options: batteryOptions(connectedIndicator: .bolt)
            ),
            .bolt
        )
        XCTAssertEqual(
            StatusMappings.batteryGapContent(
                chargedOnPower(),
                options: batteryOptions(connectedIndicator: .bolt)
            ),
            .bolt
        )
        // Without the charging indicator the bolt has no gap to live in.
        XCTAssertEqual(
            StatusMappings.batteryGapContent(
                connectedBattery(),
                options: batteryOptions(showsIndicator: false, connectedIndicator: .bolt)
            ),
            .percentage
        )
    }

    func testBatteryGapContentPlugsWhenPercentageIsPickedButHidden() {
        XCTAssertEqual(
            StatusMappings.batteryGapContent(
                connectedBattery(),
                options: batteryOptions(showsPercentage: false, connectedIndicator: .percentage)
            ),
            .plug
        )
    }

    func testBatteryGapContentFallsBackWhenNothingCanBeDrawn() {
        XCTAssertEqual(
            StatusMappings.batteryGapContent(
                connectedBattery(),
                options: batteryOptions(showsIndicator: false, showsPercentage: false)
            ),
            .empty
        )
        XCTAssertEqual(
            StatusMappings.batteryGapContent(
                connectedBattery(),
                options: batteryOptions(showsIndicator: false)
            ),
            .percentage
        )
        XCTAssertEqual(
            StatusMappings.batteryGapContent(
                connectedBattery(),
                options: batteryOptions(
                    showsPercentage: false,
                    connectedIndicator: .percentage
                )
            ),
            .plug
        )
    }

    func testBluetoothIconNeedsABluetoothOutputOrAPinnedDevice() {
        XCTAssertFalse(StatusMappings.canShowBluetoothIcon(
            currentDevice: builtInDevice(),
            options: .standard
        ))
        XCTAssertTrue(StatusMappings.canShowBluetoothIcon(
            currentDevice: bluetoothDevice(),
            options: .standard
        ))
        for transport in [AudioOutputTransport.bluetooth, .bluetoothLowEnergy] {
            XCTAssertTrue(StatusMappings.canShowBluetoothIcon(
                currentDevice: bluetoothDevice(transport: transport),
                options: .standard
            ))
        }
        XCTAssertTrue(StatusMappings.canShowBluetoothIcon(
            currentDevice: nil,
            options: BluetoothAudioIconOptions(networkIconSymbolOverride: "headphones")
        ))
    }

    func testANetworkOutageKeepsALiveWiredLinkOnline() {
        XCTAssertFalse(StatusMappings.isNetworkOffline(
            wifi: WiFiStatus(state: .off, rssi: nil), connection: .ethernet))
        XCTAssertFalse(StatusMappings.isNetworkOffline(
            wifi: WiFiStatus(state: .noInternet, rssi: nil), connection: .other))
        XCTAssertTrue(StatusMappings.isNetworkOffline(
            wifi: WiFiStatus(state: .noInternet, rssi: nil), connection: .wifi))
        XCTAssertFalse(StatusMappings.isNetworkOffline(
            wifi: WiFiStatus(state: .connected, rssi: -50), connection: .wifi))
    }

    private func chargingBattery() -> BatteryStatus {
        BatteryStatus(
            rawPercentage: 80,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
    }

    private func connectedBattery() -> BatteryStatus {
        BatteryStatus(
            rawPercentage: 80,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
    }

    private func absentBattery() -> BatteryStatus {
        BatteryStatus(
            rawPercentage: nil,
            isPresent: false,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
    }

    private func batteryOptions(
        showsIndicator: Bool = true,
        showsPercentage: Bool = true,
        connectedIndicator: BatteryConnectedIndicator = .plug
    ) -> BatteryIconOptions {
        BatteryIconOptions(
            showsPercentage: showsPercentage,
            showsChargingIndicator: showsIndicator,
            usesStatusColors: true,
            criticalThreshold: 20,
            connectedIndicator: connectedIndicator
        )
    }

    private func chargedOnPower() -> BatteryStatus {
        BatteryStatus(
            rawPercentage: 100,
            isPresent: true,
            isCharging: false,
            isCharged: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
    }

    private func makeBattery(rawPercentage: Int?) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: rawPercentage,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
    }

    private func bluetoothDevice(
        transport: AudioOutputTransport = .bluetooth
    ) -> AudioOutputDevice {
        AudioOutputDevice(
            id: 1,
            name: "AirPods Pro",
            uid: "airpods",
            isCurrent: true,
            volume: 0.5,
            transport: transport
        )
    }

    private func builtInDevice() -> AudioOutputDevice {
        AudioOutputDevice(
            id: 2,
            name: "MacBook Pro Speakers",
            uid: "built-in",
            isCurrent: true,
            volume: 0.5,
            transport: .builtIn
        )
    }
}
