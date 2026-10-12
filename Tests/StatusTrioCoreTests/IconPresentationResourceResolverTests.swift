import XCTest
@testable import StatusTrioCore

@MainActor
final class IconPresentationResourceResolverTests: XCTestCase {
    func testMissingDeviceIconUsesClassifiedFallbackSymbol() {
        let device = AudioOutputDevice(id: 1, name: "AirPods Pro", isCurrent: true,
                                       transport: .bluetooth, iconURL: URL(fileURLWithPath: "/missing/device.png"))
        let inputs = IconPresentationResourceResolver.inputs(snapshot: snapshot(device: device),
            fileExists: { _ in false }, isSymbolAvailable: { $0 == "airpods.pro" })

        XCTAssertEqual(inputs.audioIcon, .symbol(name: "airpods.pro", variableValue: nil, fallback: "headphones"))
    }

    func testExistingDeviceImageIsCarriedWithRendererFallback() {
        let url = URL(fileURLWithPath: "/fixture/device.png")
        let device = AudioOutputDevice(id: 1, name: "Driver Audio", isCurrent: true,
                                       transport: .usb, iconURL: url)
        let inputs = IconPresentationResourceResolver.inputs(snapshot: snapshot(device: device),
            fileExists: { $0 == url }, isSymbolAvailable: { _ in XCTFail("symbol lookup is unnecessary for an existing image"); return false })

        XCTAssertEqual(inputs.audioIcon, .image(url: url, fallbackSymbol: "headphones"))
    }

    func testNoCurrentDeviceHasNoAudioIcon() {
        let inputs = IconPresentationResourceResolver.inputs(snapshot: snapshot(device: nil),
            fileExists: { _ in XCTFail("file lookup is unnecessary without a current device"); return false },
            isSymbolAvailable: { _ in XCTFail("symbol lookup is unnecessary without a current device"); return false })
        XCTAssertNil(inputs.audioIcon)
    }

    func testAvailabilityDistinguishesConnectedDisconnectedAndUnknownSources() {
        let bluetooth = AudioOutputDevice(
            id: 1, name: "Bluetooth Output", isCurrent: true, transport: .bluetooth, iconURL: nil
        )
        let connected = IconPresentationResourceResolver.sourceSnapshot(
            snapshot: StatusSnapshot(
                battery: .placeholder,
                wifi: WiFiStatus(state: .connected, rssi: -40),
                connection: .wifi,
                volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: bluetooth.name, currentDevice: bluetooth)
            )
        )
        XCTAssertEqual(connected.availability["network"], .available)
        XCTAssertEqual(connected.availability["systemBattery"], .available)
        XCTAssertEqual(connected.availability["systemVolume"], .available)
        XCTAssertEqual(connected.availability["bluetoothAudioOutput"], .available)

        let disconnected = IconPresentationResourceResolver.sourceSnapshot(
            snapshot: StatusSnapshot(
                battery: BatteryStatus(rawPercentage: nil, isPresent: false, isCharging: false,
                                        isLowPowerMode: false, isConnectedToPower: false),
                wifi: WiFiStatus(state: .off, rssi: nil),
                connection: .offline,
                volume: .placeholder
            )
        )
        XCTAssertEqual(disconnected.availability["network"], .unavailable(.disconnected))
        XCTAssertEqual(disconnected.availability["systemBattery"], .unavailable(.disconnected))
        XCTAssertEqual(disconnected.availability["bluetoothAudioOutput"], .unavailable(.disconnected))

        let unknown = IconPresentationResourceResolver.sourceSnapshot(
            snapshot: StatusSnapshot(
                battery: .placeholder,
                wifi: .placeholder,
                connection: .offline,
                volume: .placeholder
            )
        )
        XCTAssertEqual(unknown.availability["network"], .unavailable(.unknown))
    }

    func testAirPodsSourceSnapshotUsesAUniqueDeviceWithoutUsingCoreAudioUID() {
        let device = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:09", name: "Renamed", kind: .audio, isConnected: true, airPodsModel: .airPodsPro
        )
        let levels = ["AABBCCDDEE09": BluetoothBatteryLevel(
            deviceAddress: device.id, main: 0, left: 0, right: nil, caseLevel: 88
        )]
        let status = StatusSnapshot(
            battery: .placeholder, wifi: .placeholder, connection: .offline,
            volume: VolumeStatus(scalar: 0.2, isMuted: false, deviceName: "Renamed", currentDevice: AudioOutputDevice(
                id: 42, name: "Renamed", uid: "not-a-bluetooth-address", isCurrent: true, transport: .bluetooth
            ))
        )

        let sources = IconPresentationResourceResolver.sourceSnapshot(
            snapshot: status, bluetoothDevices: [device], batteryLevels: levels,
            batteryLevelsUpdatedAt: Date(timeIntervalSince1970: 100), now: Date(timeIntervalSince1970: 101)
        )

        XCTAssertEqual(sources.availability[RingSource.airPodsBattery.rawValue], .available)
        XCTAssertEqual(sources.airPodsBattery?.main, 0)
        XCTAssertEqual(sources.airPodsBattery?.left, 0)
        XCTAssertEqual(sources.airPodsBattery?.caseLevel, 88)
    }

    func testFutureAirPodsBatteryTimestampIsUnavailable() {
        let device = BluetoothDevice(id: "AA:00:00:00:00:03", name: "AirPods Pro", kind: .audio,
                                     isConnected: true, airPodsModel: .airPodsPro)
        let levels = [BluetoothBatteryReader.normalizedAddress(device.id): BluetoothBatteryLevel(
            deviceAddress: device.id, main: 50, left: 49, right: 51, caseLevel: nil
        )]
        let status = StatusSnapshot(battery: .placeholder, wifi: .placeholder,
                                    connection: .offline, volume: .placeholder)
        let sources = IconPresentationResourceResolver.sourceSnapshot(
            snapshot: status, bluetoothDevices: [device], batteryLevels: levels,
            batteryLevelsUpdatedAt: Date(timeIntervalSince1970: 202), now: Date(timeIntervalSince1970: 201)
        )
        XCTAssertEqual(sources.availability[RingSource.airPodsBattery.rawValue], .unavailable(.temporarilyStale))
        XCTAssertNil(sources.airPodsBattery)
    }

    func testAmbiguousAirPodsSourceNeedsExplicitDeviceSelection() {
        let devices = ["AA:00:00:00:00:01", "AA:00:00:00:00:02"].map {
            BluetoothDevice(id: $0, name: "Same display name", kind: .audio, isConnected: true, airPodsModel: .airPodsPro)
        }
        let status = StatusSnapshot(battery: .placeholder, wifi: .placeholder, connection: .offline, volume: .placeholder)
        let levels = Dictionary(uniqueKeysWithValues: devices.map {
            (BluetoothBatteryReader.normalizedAddress($0.id), BluetoothBatteryLevel(
                deviceAddress: $0.id, main: 50, left: nil, right: nil, caseLevel: nil
            ))
        })

        let sources = IconPresentationResourceResolver.sourceSnapshot(
            snapshot: status, bluetoothDevices: devices, batteryLevels: levels,
            batteryLevelsUpdatedAt: Date(), now: Date()
        )

        XCTAssertEqual(sources.availability[RingSource.airPodsBattery.rawValue], .unavailable(.unknown))
        XCTAssertNil(sources.airPodsBattery)
    }

    func testConnectedBluetoothDeviceRequiresAnExplicitSelection() {
        let device = BluetoothDevice(id: "AA:BB:CC:DD:EE:01", name: "Headphones", kind: .audio, isConnected: true)
        let sources = IconPresentationResourceResolver.sourceSnapshot(
            snapshot: StatusSnapshot(battery: .placeholder, wifi: .placeholder, connection: .offline, volume: .placeholder),
            bluetoothDevices: [device], selectedConnectedDeviceAddress: nil
        )

        XCTAssertEqual(sources.availability[CenterSource.connectedBluetoothDevice.rawValue], .unavailable(.unknown))
        XCTAssertNil(sources.connectedBluetoothDeviceSymbol)
    }

    func testConnectedDeviceSnapshotCarriesAudioCapabilityAndRejectsNonLocalRows() {
        let audio = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:01", name: "AirPods", kind: .audio, isConnected: true
        )
        let keyboard = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:02", name: "Keyboard", kind: .peripheral(.keyboard), isConnected: true
        )
        let ghost = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:03", name: "Ghost", kind: .audio,
            isConnected: true, isUnpairedGhost: true
        )
        let remote = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:04", name: "Remote", kind: .audio,
            isConnected: true, isReadOverTheAir: true
        )
        let snapshot = StatusSnapshot(
            battery: .placeholder, wifi: .placeholder,
            connection: .offline, volume: .placeholder
        )

        let audioSource = IconPresentationResourceResolver.sourceSnapshot(
            snapshot: snapshot, bluetoothDevices: [audio], selectedConnectedDeviceAddress: audio.id
        )
        XCTAssertEqual(audioSource.connectedBluetoothDeviceIsAudio, true)
        XCTAssertEqual(audioSource.availability[CenterSource.connectedBluetoothDevice.rawValue], .available)

        let keyboardSource = IconPresentationResourceResolver.sourceSnapshot(
            snapshot: snapshot, bluetoothDevices: [keyboard], selectedConnectedDeviceAddress: keyboard.id
        )
        XCTAssertEqual(keyboardSource.connectedBluetoothDeviceIsAudio, false)
        XCTAssertEqual(keyboardSource.availability[CenterSource.connectedBluetoothDevice.rawValue], .available)

        for rejected in [ghost, remote] {
            let source = IconPresentationResourceResolver.sourceSnapshot(
                snapshot: snapshot, bluetoothDevices: [rejected], selectedConnectedDeviceAddress: rejected.id
            )
            XCTAssertNil(source.connectedBluetoothDeviceIsAudio)
            XCTAssertNil(source.connectedBluetoothDeviceSymbol)
            XCTAssertEqual(source.availability[CenterSource.connectedBluetoothDevice.rawValue], .unavailable(.disconnected))
        }
    }

    func testPermissionDeniedCachedBluetoothTargetFallsBackInsteadOfRemainingOnline() {
        let staleAudioDevice = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:41", name: "Previously connected headset", kind: .audio, isConnected: true
        )
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -40),
            connection: .wifi,
            volume: .placeholder
        )
        let sources = IconPresentationResourceResolver.sourceSnapshot(
            snapshot: snapshot,
            bluetoothDevices: [staleAudioDevice],
            selectedConnectedDeviceAddress: staleAudioDevice.id,
            bluetoothAvailability: .authorizationDenied
        )
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(
            primary: .connectedBluetoothDevice,
            fallback: .network
        )
        let output = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationResourceResolver.inputs(snapshot: snapshot),
                sources: sources
            ),
            configuration: configuration
        )

        XCTAssertEqual(
            sources.availability[CenterSource.connectedBluetoothDevice.rawValue],
            .unavailable(.permissionDenied)
        )
        XCTAssertNil(sources.connectedBluetoothDeviceSymbol)
        XCTAssertNil(sources.connectedBluetoothDeviceIsAudio)
        XCTAssertEqual(output.trace.center.role, .fallback)
        XCTAssertEqual(output.trace.center.primaryFailure, .permissionDenied)
        XCTAssertEqual(output.trace.center.selectedSourceID, CenterSource.network.rawValue)
    }

    func testWiredConnectionKeepsNetworkSourceAvailableWhenWiFiIsOff() {
        let wired = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .off, rssi: nil),
            connection: .ethernet,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
        )
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network)
        let output = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationInputs(snapshot: wired, audioIcon: nil),
                sources: IconPresentationResourceResolver.sourceSnapshot(snapshot: wired)
            ),
            configuration: configuration
        )

        XCTAssertEqual(output.trace.center.selectedSourceID, CenterSource.network.rawValue)
        XCTAssertEqual(output.scene.center, .symbol(IconSymbolState(source: .primitive(.wiredPort), color: .primary, scale: 1)))
    }

    func testClassicNoBatteryCompositionMatchesLegacyRingThroughProductionAvailability() {
        let wiredWithoutBattery = StatusSnapshot(
            battery: BatteryStatus(rawPercentage: nil, isPresent: false, isCharging: false,
                                   isLowPowerMode: false, isConnectedToPower: false),
            wifi: WiFiStatus(state: .off, rssi: nil),
            connection: .ethernet,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
        )
        let inputs = IconPresentationInputs(snapshot: wiredWithoutBattery, audioIcon: nil)
        let output = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(system: inputs,
                                         sources: IconPresentationResourceResolver.sourceSnapshot(snapshot: wiredWithoutBattery)),
            configuration: .classic
        )
        let legacy = IconPresentationMapper.scene(inputs: inputs, configuration: IconPresentationConfiguration.standard)

        XCTAssertEqual(output.scene.outerRing, legacy.outerRing)
        XCTAssertEqual(output.scene.outerRing?.segments.first?.progress, 1)
        XCTAssertEqual(output.scene.outerRing?.gap, .value)
        XCTAssertEqual(output.scene.outerRing?.accessory, .text(IconTextState(text: "100", color: .primary, scale: 1.8)))
    }

    private func snapshot(device: AudioOutputDevice?) -> StatusSnapshot {
        StatusSnapshot(battery: .placeholder, wifi: .placeholder, connection: .wifi,
                      volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: device?.name, currentDevice: device))
    }
}
