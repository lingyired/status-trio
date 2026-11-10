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

    func testNonAudioConnectedDeviceKeepsStaticColorRegardlessOfVolumeState() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .connectedBluetoothDevice)
        configuration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride = "airpods.pro"
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -45),
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

    func testGlobalNetworkOverrideAppliesToNonAudioConnectedDeviceToo() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .connectedBluetoothDevice)
        configuration.composition.centerOverride.networkProblemOverridesPrimary = true
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

        let output = resolve(snapshot, configuration: configuration, sources: sources)

        XCTAssertEqual(output.trace.center.reason, .overridden(.networkProblem))
        XCTAssertEqual(output.scene.center, .symbol(IconSymbolState(
            source: .symbol(name: "wifi.exclamationmark", variableValue: 1, fallback: nil),
            color: .primary, scale: 1.0
        )))
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

    // MARK: - Explicit inputSource + global network override

    func testExplicitInputSourceDrawsItsIconOrShortLabelAndIgnoresRuntimeNetworkSwap() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .inputSource)
        let snapshot = Self.connectedSnapshot
        // A stale legacy "network slot is really the input source" flag must no
        // longer be able to hijack an explicit V1 network centre.
        let staleRuntime = IconPresentationRuntimeOptions(
            connectionCenterSource: .inputSource,
            prioritizesNetworkErrorsOverInputSource: true,
            batteryFullThreshold: 80,
            bluetoothAudioIconChoice: .automatic
        )

        let labelOnly = resolve(
            snapshot, configuration: configuration,
            inputSource: Self.shortLabelOnlyDescriptor, runtimeOptions: staleRuntime
        )
        XCTAssertEqual(labelOnly.trace.center.selectedSourceID, CenterSource.inputSource.rawValue)
        XCTAssertEqual(labelOnly.scene.center, .text(IconTextState(text: "E", color: .primary, scale: 1)))

        let iconBacked = resolve(
            snapshot, configuration: configuration,
            inputSource: Self.imageBackedDescriptor, runtimeOptions: staleRuntime
        )
        XCTAssertEqual(iconBacked.scene.center, .symbol(IconSymbolState(
            source: .image(url: Self.descriptorURL, fallbackSymbol: "keyboard"),
            color: .primary, scale: 1
        )))
    }

    func testNetworkCentreIgnoresStaleRuntimeInputSourceFlag() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network)
        let staleRuntime = IconPresentationRuntimeOptions(
            connectionCenterSource: .inputSource,
            prioritizesNetworkErrorsOverInputSource: true,
            batteryFullThreshold: 80,
            bluetoothAudioIconChoice: .automatic
        )

        let output = resolve(
            Self.connectedSnapshot, configuration: configuration,
            inputSource: Self.shortLabelOnlyDescriptor, runtimeOptions: staleRuntime
        )

        XCTAssertEqual(output.trace.center.selectedSourceID, CenterSource.network.rawValue)
        XCTAssertEqual(output.scene.center, .symbol(IconSymbolState(
            source: .symbol(name: "wifi", variableValue: 1, fallback: nil), color: .primary, scale: 1.0
        )))
    }

    func testInputSourceUnavailableUsesConfiguredFallback() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .inputSource, fallback: .network)

        let output = resolve(Self.connectedSnapshot, configuration: configuration, inputSource: nil)

        XCTAssertEqual(output.trace.center.role, .fallback)
        XCTAssertEqual(output.trace.center.selectedSourceID, CenterSource.network.rawValue)
    }

    func testGlobalNetworkOverrideAppliesToEveryCentreSourceAndNone() {
        let problem = Self.snapshot(wifi: .noInternet)
        let healthy = Self.connectedSnapshot

        let cases: [(String, CenterSource, CenterSource?)] = [
            ("inputSource", .inputSource, nil),
            ("network", .network, nil),
            ("batteryPercentage", .systemBatteryPercentage, nil),
            ("bluetoothAudio", .bluetoothAudioOutput, nil),
            ("pinnedGlyph", .pinnedBluetoothGlyph, nil),
            ("automaticLegacy", .automaticLegacy, nil),
            ("none", .none, nil),
            ("fallbackNetwork", .inputSource, .network),
        ]

        for (name, primary, fallback) in cases {
            var configuration = IconConfigurationV1.classic
            configuration.composition.center = SlotSelection(primary: primary, fallback: fallback)
            configuration.composition.centerOverride.networkProblemOverridesPrimary = true

            let broken = resolve(
                problem, configuration: configuration,
                sources: Self.bluetoothAvailableSources,
                inputSource: Self.shortLabelOnlyDescriptor
            )
            XCTAssertEqual(broken.trace.center.reason, .overridden(.networkProblem), name)
            XCTAssertEqual(broken.trace.center.selectedSourceID, CenterSource.network.rawValue, name)
            XCTAssertEqual(broken.scene.center, .symbol(IconSymbolState(
                source: .symbol(name: "wifi.exclamationmark", variableValue: 1, fallback: nil),
                color: .primary, scale: 1.0
            )), name)

            // Recovery returns to the original resolution.
            let recovered = resolve(
                healthy, configuration: configuration,
                sources: Self.bluetoothAvailableSources,
                inputSource: Self.shortLabelOnlyDescriptor
            )
            XCTAssertNotEqual(recovered.trace.center.reason, .overridden(.networkProblem), name)
        }
    }

    func testGlobalNetworkOverrideNeverFiresWhenWiredIsHealthy() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .inputSource)
        configuration.composition.centerOverride.networkProblemOverridesPrimary = true
        let wiredHealthy = StatusSnapshot(
            battery: Self.connectedSnapshot.battery,
            wifi: WiFiStatus(state: .off, rssi: nil),
            connection: .ethernet,
            volume: Self.connectedSnapshot.volume
        )

        let output = resolve(
            wiredHealthy, configuration: configuration,
            inputSource: Self.shortLabelOnlyDescriptor
        )

        XCTAssertEqual(output.trace.center.selectedSourceID, CenterSource.inputSource.rawValue)
        XCTAssertEqual(output.trace.center.reason, .primary)
    }

    func testGlobalNetworkOverrideAnomalyMatrix() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .inputSource)
        configuration.composition.centerOverride.networkProblemOverridesPrimary = true

        let cases: [(String, WiFiState, NetworkConnection, Bool)] = [
            ("offline connection", .off, .offline, true),
            ("wifi not associated", .notAssociated, .wifi, true),
            ("wifi no internet", .noInternet, .wifi, true),
            ("wifi off", .off, .wifi, true),
            ("wifi unavailable", .unavailable, .wifi, true),
            ("wifi connected", .connected, .wifi, false),
            ("wifi hotspot", .hotspot, .wifi, false),
            ("wifi shared", .shared, .wifi, false),
            ("wired ethernet with wifi off", .off, .ethernet, false),
            ("other connection with wifi off", .off, .other, false),
        ]

        for (name, wifiState, connection, expected) in cases {
            let snapshot = StatusSnapshot(
                battery: Self.connectedSnapshot.battery,
                wifi: WiFiStatus(state: wifiState, rssi: -45),
                connection: connection,
                volume: Self.connectedSnapshot.volume
            )
            let output = resolve(
                snapshot, configuration: configuration,
                inputSource: Self.shortLabelOnlyDescriptor
            )
            XCTAssertEqual(
                output.trace.center.reason == .overridden(.networkProblem),
                expected,
                name
            )
        }
    }

    func testV1GlobalFalseKeepsInputSourceAndBluetoothEvenWhenLegacyPriorityFlagsAreOn() {
        // A migrated V1 config with the global rule off must not be re-overridden
        // by the old independent store flags.
        let legacyPriorityRuntime = IconPresentationRuntimeOptions(
            connectionCenterSource: .inputSource,
            prioritizesNetworkErrorsOverInputSource: true,
            batteryFullThreshold: 80,
            bluetoothAudioIconChoice: .automatic
        )
        let offline = Self.snapshot(wifi: .noInternet)

        var inputConfiguration = IconConfigurationV1.classic
        inputConfiguration.composition.center = SlotSelection(primary: .inputSource)
        inputConfiguration.composition.centerOverride.networkProblemOverridesPrimary = false
        let inputOutput = resolve(
            offline, configuration: inputConfiguration,
            inputSource: Self.shortLabelOnlyDescriptor, runtimeOptions: legacyPriorityRuntime
        )
        XCTAssertEqual(inputOutput.scene.center, .text(IconTextState(text: "E", color: .primary, scale: 1)))
        XCTAssertEqual(inputOutput.trace.center.reason, .primary)

        var bluetoothConfiguration = IconConfigurationV1.classic
        bluetoothConfiguration.composition.center = SlotSelection(primary: .bluetoothAudioOutput)
        bluetoothConfiguration.composition.centerOverride.networkProblemOverridesPrimary = false
        bluetoothConfiguration.behaviors.bluetoothAudioCenter.prioritizesNetworkErrors = true
        let bluetoothOutput = resolve(
            offline, configuration: bluetoothConfiguration,
            sources: Self.bluetoothAvailableSources, runtimeOptions: legacyPriorityRuntime
        )
        XCTAssertEqual(bluetoothOutput.trace.center.selectedSourceID, CenterSource.bluetoothAudioOutput.rawValue)
        XCTAssertNotEqual(bluetoothOutput.trace.center.reason, .overridden(.networkProblem))
    }

    func testAutomaticLegacyGlobalRulePreemptsTheBluetoothReplacementWhenOn() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .automaticLegacy)
        configuration.composition.centerOverride.networkProblemOverridesPrimary = true
        configuration.behaviors.bluetoothAudioCenter.replacesNetworkIcon = true
        configuration.behaviors.bluetoothAudioCenter.prioritizesNetworkErrors = true

        let output = resolve(
            Self.snapshot(wifi: .noInternet), configuration: configuration,
            sources: Self.bluetoothAvailableSources
        )

        XCTAssertEqual(output.trace.center.reason, .overridden(.networkProblem))
        XCTAssertEqual(output.trace.center.selectedSourceID, CenterSource.network.rawValue)
    }

    func testAutomaticLegacyFallbackFollowsTheGlobalRule() {
        // The automaticLegacy source reached as a configured fallback (primary
        // input source unavailable) must obey the same single global rule.
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .inputSource, fallback: .automaticLegacy)
        configuration.behaviors.bluetoothAudioCenter.replacesNetworkIcon = true
        configuration.behaviors.bluetoothAudioCenter.prioritizesNetworkErrors = true

        let offline = Self.snapshot(wifi: .noInternet)
        configuration.composition.centerOverride.networkProblemOverridesPrimary = false
        let withoutGlobal = resolve(offline, configuration: configuration)
        XCTAssertEqual(withoutGlobal.trace.center.selectedSourceID, CenterSource.automaticLegacy.rawValue)
        XCTAssertEqual(withoutGlobal.trace.center.role, .fallback)
        XCTAssertNotEqual(withoutGlobal.trace.center.reason, .overridden(.networkProblem))

        configuration.composition.centerOverride.networkProblemOverridesPrimary = true
        let withGlobal = resolve(offline, configuration: configuration)
        XCTAssertEqual(withGlobal.trace.center.reason, .overridden(.networkProblem))
        XCTAssertEqual(withGlobal.trace.center.selectedSourceID, CenterSource.network.rawValue)
    }

    private static let connectedSnapshot = StatusSnapshot(
        battery: .placeholder,
        wifi: WiFiStatus(state: .connected, rssi: -45),
        connection: .wifi,
        volume: VolumeStatus(
            scalar: 0.5, isMuted: false, deviceName: "AirPods",
            currentDevice: PresentationFixtures.bluetoothDevice
        )
    )

    private static func snapshot(wifi: WiFiState) -> StatusSnapshot {
        StatusSnapshot(
            battery: connectedSnapshot.battery,
            wifi: WiFiStatus(state: wifi, rssi: -45),
            connection: .wifi,
            volume: connectedSnapshot.volume
        )
    }

    private static let bluetoothAvailableSources = IconSourceSnapshot(availability: [
        CenterSource.bluetoothAudioOutput.rawValue: .available
    ])

    private static let descriptorURL = URL(fileURLWithPath: "/tmp/input-source-test.png")

    private static let shortLabelOnlyDescriptor = InputSourceDescriptor(
        id: "com.example.input-source",
        localizedName: "Example Input Source",
        primaryLanguage: "en",
        iconURL: nil,
        shortLabel: "E"
    )

    private static let imageBackedDescriptor = InputSourceDescriptor(
        id: "com.example.input-source.image",
        localizedName: "Example Input Source",
        primaryLanguage: "en",
        iconURL: descriptorURL,
        shortLabel: nil
    )

    private func resolve(
        _ snapshot: StatusSnapshot,
        configuration: IconConfigurationV1,
        sources: IconSourceSnapshot = .empty,
        inputSource: InputSourceDescriptor? = nil,
        runtimeOptions: IconPresentationRuntimeOptions? = nil
    ) -> IconResolutionOutput {
        IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationInputs(
                    snapshot: snapshot, audioIcon: nil,
                    inputSource: inputSource, runtimeOptions: runtimeOptions
                ),
                sources: sources
            ),
            configuration: configuration
        )
    }
}
