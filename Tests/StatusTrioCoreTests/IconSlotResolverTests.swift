import XCTest
@testable import StatusTrioCore

final class IconSlotResolverTests: XCTestCase {
    func testChooseSourceSelectsAvailablePrimary() {
        let result = chooseSource(
            SlotSelection<RingSource>(primary: .systemBattery, fallback: nil), none: .none
        ) { _ in .available(true) }

        XCTAssertEqual(result.source, .systemBattery)
        XCTAssertEqual(result.role, .primary)
        XCTAssertNil(result.primaryFailure)
    }

    func testChooseSourceUsesFallbackAfterPrimaryFailure() {
        let result = chooseSource(
            SlotSelection<CenterSource>(primary: .bluetoothAudioOutput, fallback: .network), none: .none
        ) { source in
            source == .bluetoothAudioOutput ? .unavailable(.disconnected) : .available(true)
        }

        XCTAssertEqual(result.source, .network)
        XCTAssertEqual(result.role, .fallback)
        XCTAssertEqual(result.primaryFailure, .disconnected)
    }

    func testChooseSourceReportsUnavailableWhenBothSourcesFail() {
        let result = chooseSource(
            SlotSelection<CenterSource>(primary: .bluetoothAudioOutput, fallback: .network), none: .none
        ) { _ in .unavailable(.permissionDenied) }

        XCTAssertNil(result.source)
        XCTAssertEqual(result.role, .none)
        XCTAssertEqual(result.primaryFailure, .permissionDenied)
    }

    func testExplicitNoneDoesNotConsultFallback() {
        var queried = false
        let result = chooseSource(
            SlotSelection<RingSource>(primary: .none, fallback: .systemBattery), none: .none
        ) { _ in
            queried = true
            return .available(true)
        }

        XCTAssertNil(result.source)
        XCTAssertEqual(result.role, .none)
        XCTAssertFalse(queried)
    }

    func testClassicRingAndFooterKeepZeroAsAvailableData() {
        var configuration = IconConfigurationV1.classic
        configuration.behaviors.systemVolumeFooter.displayStyle = .arc
        let battery = BatteryStatus(rawPercentage: 0, isPresent: true, isCharging: false,
                                    isLowPowerMode: false, isConnectedToPower: false)
        let snapshot = StatusSnapshot(
            battery: battery, wifi: WiFiStatus(state: .off, rssi: nil),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0, isMuted: false, deviceName: "Output")
        )

        let output = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
                sources: .empty
            ),
            configuration: configuration
        )

        XCTAssertEqual(output.scene.outerRing?.segments.first?.progress, 0)
        XCTAssertEqual(output.scene.footer, .arc(ArcState(
            progress: 0, color: .primary, strokeScale: configuration.appearance.footer.strokeScale
        )))
        XCTAssertEqual(output.scene.center, .symbol(IconSymbolState(
            source: .symbol(name: "wifi.slash", variableValue: 1, fallback: nil), color: .primary, scale: 1.0
        )))
    }

    func testClassicPercentageStillPreemptsBluetoothAndNetworkError() {
        let battery = BatteryStatus(rawPercentage: 45, isPresent: true, isCharging: false,
                                    isLowPowerMode: false, isConnectedToPower: false)
        let snapshot = StatusSnapshot(
            battery: battery, wifi: WiFiStatus(state: .noInternet, rssi: -45),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output",
                                 currentDevice: PresentationFixtures.bluetoothDevice)
        )
        var configuration = IconConfigurationV1.classic
        configuration.behaviors.networkCenter.showsBatteryPercentageInConnectionSlot = true
        configuration.behaviors.bluetoothAudioCenter.replacesNetworkIcon = true

        let output = resolve(snapshot, configuration: configuration)

        XCTAssertEqual(output.scene.center, .text(IconTextState(text: "45", color: .primary, scale: 1)))
        XCTAssertEqual(output.trace.center.selectedSourceID, CenterSource.automaticLegacy.rawValue)
    }

    func testExplicitBluetoothPrimaryFallsBackToNetworkAndTracesFailure() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .bluetoothAudioOutput, fallback: .network)
        let snapshot = StatusSnapshot(
            battery: .placeholder, wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
        )
        let output = resolve(
            snapshot,
            configuration: configuration,
            sources: IconSourceSnapshot(availability: [
                CenterSource.bluetoothAudioOutput.rawValue: .unavailable(.disconnected)
            ])
        )

        XCTAssertEqual(output.trace.center.selectedSourceID, CenterSource.network.rawValue)
        XCTAssertEqual(output.trace.center.role, .fallback)
        XCTAssertEqual(output.trace.center.primaryFailure, .disconnected)
        XCTAssertEqual(output.scene.center, .symbol(IconSymbolState(
            source: .symbol(name: "wifi", variableValue: 1, fallback: nil), color: .primary, scale: 1.0
        )))
    }

    func testBluetoothSourceWithoutCurrentOutputFallsBackToNetwork() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .bluetoothAudioOutput, fallback: .network)
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
        )

        let output = resolve(snapshot, configuration: configuration)

        XCTAssertEqual(output.trace.center.selectedSourceID, CenterSource.network.rawValue)
        XCTAssertEqual(output.trace.center.role, .fallback)
        XCTAssertEqual(output.trace.center.primaryFailure, .disconnected)
    }

    func testNetworkErrorOverrideOnlyAppliesToExplicitBluetoothPrimary() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .bluetoothAudioOutput, fallback: .network)
        configuration.composition.centerOverride.networkProblemOverridesPrimary = true
        configuration.behaviors.bluetoothAudioCenter.replacesNetworkIcon = true
        configuration.behaviors.networkCenter.showsBatteryPercentageInConnectionSlot = true
        let snapshot = StatusSnapshot(
            battery: .placeholder, wifi: WiFiStatus(state: .noInternet, rssi: -45),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output",
                                 currentDevice: PresentationFixtures.bluetoothDevice)
        )
        let output = resolve(snapshot, configuration: configuration)

        XCTAssertEqual(output.trace.center.reason, .overridden(.networkProblem))
        XCTAssertEqual(output.scene.center, .symbol(IconSymbolState(
            source: .symbol(name: "wifi.exclamationmark", variableValue: 1, fallback: nil),
            color: .primary, scale: 1.0
        )))

        configuration.composition.center = SlotSelection(primary: .automaticLegacy)
        let legacy = resolve(snapshot, configuration: configuration)
        XCTAssertEqual(legacy.trace.center.reason, .primary)
        XCTAssertEqual(legacy.trace.center.selectedSourceID, CenterSource.automaticLegacy.rawValue)
        XCTAssertEqual(legacy.scene.center, IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: configuration.legacyPresentationConfiguration
        ).center)
    }

    func testMissingBatteryPercentageUsesNetworkFallback() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .systemBatteryPercentage, fallback: .network)
        let snapshot = StatusSnapshot(
            battery: BatteryStatus(rawPercentage: nil, isPresent: false, isCharging: false,
                                   isLowPowerMode: false, isConnectedToPower: false),
            wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
        )

        let output = resolve(snapshot, configuration: configuration)

        XCTAssertEqual(output.trace.center.selectedSourceID, CenterSource.network.rawValue)
        XCTAssertEqual(output.trace.center.role, .fallback)
        XCTAssertEqual(output.trace.center.primaryFailure, .unavailable)
    }

    func testPinnedBluetoothGlyphUsesSavedSymbolWithoutAudioOutput() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .pinnedBluetoothGlyph)
        configuration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride = "airpods.pro"
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
        )

        let output = resolve(snapshot, configuration: configuration)

        XCTAssertEqual(output.scene.center, .symbol(IconSymbolState(
            source: .symbol(name: "airpods.pro", variableValue: nil, fallback: "dot.radiowaves.left.and.right"),
            color: .bluetooth, scale: configuration.behaviors.bluetoothAudioCenter.symbolScale
        )))
        XCTAssertEqual(output.trace.center.selectedSourceID, CenterSource.pinnedBluetoothGlyph.rawValue)
    }

    func testSpecifiedAudioDeviceUsesCustomSymbolAndNetworkFailureOverride() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .connectedBluetoothDevice)
        configuration.composition.centerOverride.networkProblemOverridesPrimary = true
        configuration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride = "airpods.pro"
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .noInternet, rssi: -45),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Built-in")
        )
        let output = resolve(snapshot, configuration: configuration, sources: IconSourceSnapshot(
            availability: [CenterSource.connectedBluetoothDevice.rawValue: .available],
            connectedBluetoothDeviceSymbol: "headphones",
            connectedBluetoothDeviceIsAudio: true
        ))

        XCTAssertEqual(output.trace.center.reason, .overridden(.networkProblem))
        XCTAssertEqual(output.scene.center, .symbol(IconSymbolState(
            source: .symbol(name: "wifi.exclamationmark", variableValue: 1, fallback: nil),
            color: .primary,
            scale: 1
        )))
    }

    func testSpecifiedAudioDeviceUsesCustomGlyphAndSystemVolumeColorWhenNoNetworkError() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .connectedBluetoothDevice)
        configuration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride = "airpods.pro"
        configuration.behaviors.bluetoothAudioCenter.usesVolumeColor = true
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -45),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Built-in")
        )
        let sources = IconSourceSnapshot(
            availability: [CenterSource.connectedBluetoothDevice.rawValue: .available],
            connectedBluetoothDeviceSymbol: "headphones",
            connectedBluetoothDeviceIsAudio: true
        )

        let audible = resolve(snapshot, configuration: configuration, sources: sources)
        XCTAssertEqual(audible.scene.center, .symbol(IconSymbolState(
            source: .symbol(name: "airpods.pro", variableValue: nil, fallback: BluetoothDeviceRowIcon.genericSymbol),
            color: .bluetooth,
            scale: configuration.behaviors.bluetoothAudioCenter.symbolScale
        )))

        let mutedSnapshot = StatusSnapshot(
            battery: snapshot.battery, wifi: snapshot.wifi, connection: snapshot.connection,
            volume: VolumeStatus(scalar: 0.5, isMuted: true, deviceName: "Built-in")
        )
        let muted = resolve(mutedSnapshot, configuration: configuration, sources: sources)
        XCTAssertEqual(muted.scene.center, .symbol(IconSymbolState(
            source: .symbol(name: "airpods.pro", variableValue: nil, fallback: BluetoothDeviceRowIcon.genericSymbol),
            color: .primary,
            scale: configuration.behaviors.bluetoothAudioCenter.symbolScale
        )))
    }

    func testNonAudioConnectedDeviceDoesNotReceiveAudioOverrideOrVolumeColor() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .connectedBluetoothDevice)
        configuration.composition.centerOverride.networkProblemOverridesPrimary = true
        configuration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride = "airpods.pro"
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .noInternet, rssi: -45),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Built-in")
        )
        let sources = IconSourceSnapshot(
            availability: [CenterSource.connectedBluetoothDevice.rawValue: .available],
            connectedBluetoothDeviceSymbol: "keyboard",
            connectedBluetoothDeviceIsAudio: false
        )

        var uncolored = resolve(snapshot, configuration: configuration, sources: sources)
        XCTAssertEqual(uncolored.trace.center.reason, .primary)
        XCTAssertEqual(uncolored.scene.center, .symbol(IconSymbolState(
            source: .symbol(name: "keyboard", variableValue: nil, fallback: BluetoothDeviceRowIcon.genericSymbol),
            color: .bluetooth,
            scale: configuration.behaviors.bluetoothAudioCenter.symbolScale
        )))

        configuration.behaviors.bluetoothAudioCenter.usesVolumeColor = true
        let volumeColoredSetting = resolve(snapshot, configuration: configuration, sources: sources)
        XCTAssertEqual(volumeColoredSetting.scene.center, uncolored.scene.center)

        let muted = StatusSnapshot(
            battery: snapshot.battery, wifi: snapshot.wifi, connection: snapshot.connection,
            volume: VolumeStatus(scalar: 0.5, isMuted: true, deviceName: "Built-in")
        )
        let mutedOutput = resolve(muted, configuration: configuration, sources: sources)
        XCTAssertEqual(mutedOutput.scene.center, uncolored.scene.center)
        // Keep the mutable binding explicit: these comparisons pin non-audio
        // semantics against both system-volume states and the preference toggle.
        uncolored = volumeColoredSetting
        XCTAssertEqual(uncolored.scene.center, mutedOutput.scene.center)
    }

    func testUnavailableSpecifiedAudioDeviceUsesConfiguredFallback() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .connectedBluetoothDevice, fallback: .network)
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -40),
            connection: .wifi,
            volume: .placeholder
        )
        let output = resolve(snapshot, configuration: configuration, sources: IconSourceSnapshot(
            availability: [CenterSource.connectedBluetoothDevice.rawValue: .unavailable(.disconnected)]
        ))

        XCTAssertEqual(output.trace.center.role, .fallback)
        XCTAssertEqual(output.trace.center.selectedSourceID, CenterSource.network.rawValue)
    }

    func testExplicitNetworkSourceDoesNotUseLegacyBatteryPercentagePrecedence() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network)
        configuration.behaviors.networkCenter.showsBatteryPercentageInConnectionSlot = true
        let snapshot = StatusSnapshot(
            battery: BatteryStatus(rawPercentage: 45, isPresent: true, isCharging: false,
                                   isLowPowerMode: false, isConnectedToPower: false),
            wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
        )

        let output = resolve(snapshot, configuration: configuration)

        XCTAssertNotEqual(output.scene.center, .text(IconTextState(text: "45", color: .primary, scale: 1)))
        XCTAssertEqual(output.trace.center.selectedSourceID, CenterSource.network.rawValue)
    }

    private func resolve(
        _ snapshot: StatusSnapshot,
        configuration: IconConfigurationV1,
        sources: IconSourceSnapshot = .empty
    ) -> IconResolutionOutput {
        IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
                sources: sources
            ),
            configuration: configuration
        )
    }
}
