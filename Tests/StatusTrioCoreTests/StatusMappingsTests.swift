import XCTest
@testable import StatusTrioCore

final class StatusMappingsTests: XCTestCase {
    func testWiFiSignalBoundaries() {
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -59), 3)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -60), 3)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -61), 2)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -78), 2)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -79), 1)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -88), 1)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -89), 0)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: nil), 0)
    }

    func testWiFiSummaryRequiresLocationPermissionBeforeOpeningAssociatedNetworkDetails() {
        let notDetermined = WiFiStatus(
            state: .connected,
            rssi: -50,
            nameAccess: .notDetermined
        )
        XCTAssertEqual(
            StatusMappings.wifiSummaryAction(for: notDetermined),
            .requestNameAccess
        )

        let authorized = WiFiStatus(
            state: .connected,
            rssi: -50,
            nameAccess: .authorized
        )
        XCTAssertEqual(
            StatusMappings.wifiSummaryAction(for: authorized),
            .openDetails
        )

        let denied = WiFiStatus(
            state: .connected,
            rssi: -50,
            nameAccess: .denied
        )
        XCTAssertEqual(
            StatusMappings.wifiSummaryAction(for: denied),
            .openLocationSettings
        )

        let unavailable = WiFiStatus(
            state: .unavailable,
            rssi: nil,
            nameAccess: .notDetermined
        )
        XCTAssertEqual(
            StatusMappings.wifiSummaryAction(for: unavailable),
            .openDetails
        )
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
            .percentage
        )
    }

    func testBatteryGapContentUsesThePercentageForConnectedPowerWhenEnabled() {
        XCTAssertEqual(
            StatusMappings.batteryGapContent(
                connectedBattery(),
                options: batteryOptions(showsPercentageWhenConnected: true)
            ),
            .percentage
        )
    }

    func testBatteryGapContentKeepsTheBoltWhileCharging() {
        XCTAssertEqual(
            StatusMappings.batteryGapContent(
                chargingBattery(),
                options: batteryOptions(showsPercentageWhenConnected: true)
            ),
            .bolt
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
                    showsPercentageWhenConnected: true
                )
            ),
            .plug
        )
    }

    func testBluetoothAudioReplacementRequiresABluetoothOutputDeviceAndEnabledOption() {
        let wifi = WiFiStatus(state: .connected, rssi: -50)

        XCTAssertFalse(StatusMappings.shouldReplaceNetworkIcon(
            currentDevice: bluetoothDevice(),
            wifi: wifi,
            connection: .wifi,
            options: BluetoothAudioIconOptions(replacesNetworkIcon: false)
        ))
        XCTAssertFalse(StatusMappings.shouldReplaceNetworkIcon(
            currentDevice: builtInDevice(),
            wifi: wifi,
            connection: .wifi,
            options: BluetoothAudioIconOptions(replacesNetworkIcon: true)
        ))
        XCTAssertTrue(StatusMappings.shouldReplaceNetworkIcon(
            currentDevice: bluetoothDevice(),
            wifi: wifi,
            connection: .wifi,
            options: BluetoothAudioIconOptions(replacesNetworkIcon: true)
        ))
    }

    func testBluetoothAudioReplacementAcceptsBothBluetoothTransports() {
        for transport in [AudioOutputTransport.bluetooth, .bluetoothLowEnergy] {
            XCTAssertTrue(StatusMappings.shouldReplaceNetworkIcon(
                currentDevice: bluetoothDevice(transport: transport),
                wifi: WiFiStatus(state: .connected, rssi: -50),
                connection: .wifi,
                options: BluetoothAudioIconOptions(replacesNetworkIcon: true)
            ))
        }
    }

    func testBluetoothAudioReplacementNetworkErrorPriorityMatrix() {
        let suppressingStates: [WiFiState] = [
            .notAssociated,
            .noInternet,
            .off,
            .unavailable
        ]
        for state in suppressingStates {
            XCTAssertFalse(
                StatusMappings.shouldReplaceNetworkIcon(
                    currentDevice: bluetoothDevice(),
                    wifi: WiFiStatus(state: state, rssi: nil),
                    connection: .wifi,
                    options: BluetoothAudioIconOptions(
                        replacesNetworkIcon: true,
                        prioritizesNetworkErrors: true
                    )
                ),
                "\(state) should keep the network icon"
            )
            XCTAssertTrue(
                StatusMappings.shouldReplaceNetworkIcon(
                    currentDevice: bluetoothDevice(),
                    wifi: WiFiStatus(state: state, rssi: nil),
                    connection: .wifi,
                    options: BluetoothAudioIconOptions(
                        replacesNetworkIcon: true,
                        prioritizesNetworkErrors: false
                    )
                ),
                "\(state) should yield to Bluetooth when priority is off"
            )
        }

        for state in [WiFiState.connected, .hotspot, .temporary, .shared] {
            for prioritizesErrors in [true, false] {
                XCTAssertTrue(StatusMappings.shouldReplaceNetworkIcon(
                    currentDevice: bluetoothDevice(),
                    wifi: WiFiStatus(state: state, rssi: -50),
                    connection: .wifi,
                    options: BluetoothAudioIconOptions(
                        replacesNetworkIcon: true,
                        prioritizesNetworkErrors: prioritizesErrors
                    )
                ))
            }
        }
    }

    /// A picked device pins the glyph: the current output no longer has to be
    /// Bluetooth — or exist at all — for the network icon to yield.
    func testNetworkIconOverrideReplacesRegardlessOfCurrentOutput() {
        let wifi = WiFiStatus(state: .connected, rssi: -50)
        let options = BluetoothAudioIconOptions(
            replacesNetworkIcon: true,
            networkIconSymbolOverride: "keyboard"
        )

        for device in [bluetoothDevice(), builtInDevice(), nil] {
            XCTAssertTrue(
                StatusMappings.shouldReplaceNetworkIcon(
                    currentDevice: device,
                    wifi: wifi,
                    connection: .wifi,
                    options: options
                ),
                "an override replaces the network icon with no audio device"
            )
        }
    }

    /// The toggle still gates the override: turning the option off restores the
    /// network icon even with a device picked.
    func testNetworkIconOverrideRespectsTheEnabledToggle() {
        let wifi = WiFiStatus(state: .connected, rssi: -50)
        let options = BluetoothAudioIconOptions(
            replacesNetworkIcon: false,
            networkIconSymbolOverride: "keyboard"
        )

        XCTAssertFalse(StatusMappings.shouldReplaceNetworkIcon(
            currentDevice: bluetoothDevice(),
            wifi: wifi,
            connection: .wifi,
            options: options
        ))
    }

    /// A network error outranks a picked device exactly as it outranks the
    /// audio device: the matrix of suppressing states is unchanged.
    func testNetworkIconOverrideHonorsNetworkErrorPriority() {
        let suppressingStates: [WiFiState] = [
            .notAssociated,
            .noInternet,
            .off,
            .unavailable
        ]
        for state in suppressingStates {
            XCTAssertFalse(
                StatusMappings.shouldReplaceNetworkIcon(
                    currentDevice: nil,
                    wifi: WiFiStatus(state: state, rssi: nil),
                    connection: .wifi,
                    options: BluetoothAudioIconOptions(
                        replacesNetworkIcon: true,
                        prioritizesNetworkErrors: true,
                        networkIconSymbolOverride: "keyboard"
                    )
                ),
                "\(state) should keep the network icon over the override"
            )
            XCTAssertTrue(
                StatusMappings.shouldReplaceNetworkIcon(
                    currentDevice: nil,
                    wifi: WiFiStatus(state: state, rssi: nil),
                    connection: .wifi,
                    options: BluetoothAudioIconOptions(
                        replacesNetworkIcon: true,
                        prioritizesNetworkErrors: false,
                        networkIconSymbolOverride: "keyboard"
                    )
                ),
                "\(state) should yield to the override when priority is off"
            )
        }

        XCTAssertFalse(StatusMappings.shouldReplaceNetworkIcon(
            currentDevice: nil,
            wifi: WiFiStatus(state: .connected, rssi: -50),
            connection: .offline,
            options: BluetoothAudioIconOptions(
                replacesNetworkIcon: true,
                prioritizesNetworkErrors: true,
                networkIconSymbolOverride: "keyboard"
            )
        ), "an offline connection keeps the network icon over the override")
    }

    /// No override keeps today's rule untouched: the replacement then demands a
    /// Bluetooth current output.
    func testNoNetworkIconOverrideKeepsBluetoothOutputRequirement() {
        let wifi = WiFiStatus(state: .connected, rssi: -50)
        let options = BluetoothAudioIconOptions(replacesNetworkIcon: true)

        XCTAssertFalse(StatusMappings.shouldReplaceNetworkIcon(
            currentDevice: builtInDevice(),
            wifi: wifi,
            connection: .wifi,
            options: options
        ))
        XCTAssertTrue(StatusMappings.shouldReplaceNetworkIcon(
            currentDevice: bluetoothDevice(),
            wifi: wifi,
            connection: .wifi,
            options: options
        ))
    }

    func testOfflineHonorsNetworkErrorPriority() {
        XCTAssertFalse(StatusMappings.shouldReplaceNetworkIcon(
            currentDevice: bluetoothDevice(),
            wifi: WiFiStatus(state: .connected, rssi: -50),
            connection: .offline,
            options: BluetoothAudioIconOptions(
                replacesNetworkIcon: true,
                prioritizesNetworkErrors: true
            )
        ))
        XCTAssertTrue(StatusMappings.shouldReplaceNetworkIcon(
            currentDevice: bluetoothDevice(),
            wifi: WiFiStatus(state: .connected, rssi: -50),
            connection: .offline,
            options: BluetoothAudioIconOptions(
                replacesNetworkIcon: true,
                prioritizesNetworkErrors: false
            )
        ))
    }

    func testBluetoothReplacementDoesNotTreatEthernetOrUnknownConnectionsAsNetworkErrors() {
        for connection in [NetworkConnection.ethernet, .other, .unknown] {
            for prioritizesErrors in [true, false] {
                XCTAssertTrue(StatusMappings.shouldReplaceNetworkIcon(
                    currentDevice: bluetoothDevice(),
                    wifi: WiFiStatus(state: .connected, rssi: -50),
                    connection: connection,
                    options: BluetoothAudioIconOptions(
                        replacesNetworkIcon: true,
                        prioritizesNetworkErrors: prioritizesErrors
                    )
                ))
            }
        }
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
        showsPercentageWhenConnected: Bool = false
    ) -> BatteryIconOptions {
        BatteryIconOptions(
            showsPercentage: showsPercentage,
            showsChargingIndicator: showsIndicator,
            usesStatusColors: true,
            criticalThreshold: 20,
            showsPercentageWhenConnected: showsPercentageWhenConnected
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
