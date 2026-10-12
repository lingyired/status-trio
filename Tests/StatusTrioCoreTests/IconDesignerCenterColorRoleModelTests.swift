import XCTest
@testable import StatusTrioCore

final class IconDesignerCenterColorRoleModelTests: XCTestCase {
    func testNetworkExposesOnlyPrimaryAndConnectedZeroBarRoles() {
        let options = roleOptions(for: .network)

        XCTAssertEqual(options.map(\.role), [.primary, .inactive])
        XCTAssertEqual(options[0].meanings, [
            .init(
                scope: .primary,
                localizationKey: .iconDesignerCenterColorMeaningNetworkPrimary,
                helpLocalizationKey: .iconDesignerCenterColorHelpNetworkPrimary
            )
        ])
        XCTAssertEqual(options[1].meanings, [
            .init(
                scope: .primary,
                localizationKey: .iconDesignerCenterColorMeaningWiFiZeroBars,
                helpLocalizationKey: .iconDesignerCenterColorHelpWiFiZeroBars
            )
        ])
    }

    func testBluetoothVolumeRolesMatchRendererColorBranches() {
        var configuration = configuration(primary: .bluetoothAudioOutput)
        configuration.behaviors.bluetoothAudioCenter.usesVolumeColor = false
        XCTAssertEqual(
            IconDesignerCenterColorRoleModel.options(in: configuration, connectedBluetoothDeviceIsAudio: false).map(\.role),
            [.bluetooth]
        )

        configuration.behaviors.bluetoothAudioCenter.usesVolumeColor = true
        let options = IconDesignerCenterColorRoleModel.options(in: configuration, connectedBluetoothDeviceIsAudio: false)
        XCTAssertEqual(options.map(\.role), [.primary, .bluetooth])
        XCTAssertEqual(options[0].meanings, [
            .init(
                scope: .primary,
                localizationKey: .iconDesignerCenterColorMeaningBluetoothMutedZeroOrUnavailable,
                helpLocalizationKey: .iconDesignerCenterColorHelpBluetoothMutedZeroOrUnavailable
            )
        ])
        XCTAssertEqual(options[1].meanings, [
            .init(
                scope: .primary,
                localizationKey: .iconDesignerCenterColorMeaningBluetoothVolumeAboveZero,
                helpLocalizationKey: .iconDesignerCenterColorHelpBluetoothVolumeAboveZero
            )
        ])
    }

    func testConnectedBluetoothCapabilityAndPinnedGlyphHaveOnlyReachableRoles() {
        var configuration = configuration(primary: .connectedBluetoothDevice)
        configuration.behaviors.bluetoothAudioCenter.usesVolumeColor = true
        XCTAssertEqual(
            IconDesignerCenterColorRoleModel.options(in: configuration, connectedBluetoothDeviceIsAudio: false).map(\.role),
            [.bluetooth]
        )
        XCTAssertEqual(
            IconDesignerCenterColorRoleModel.options(in: configuration, connectedBluetoothDeviceIsAudio: true).map(\.role),
            [.primary, .bluetooth]
        )

        configuration.composition.center.primary = .pinnedBluetoothGlyph
        XCTAssertEqual(
            IconDesignerCenterColorRoleModel.options(in: configuration, connectedBluetoothDeviceIsAudio: true).map(\.role),
            [.bluetooth]
        )
    }

    func testBatteryNoneAndLegacyExposeOnlyRolesTheirRendererCanProduce() {
        XCTAssertEqual(roleOptions(for: .systemBatteryPercentage).map(\.role), [.primary])
        XCTAssertTrue(roleOptions(for: .none, fallback: .network).isEmpty)
        XCTAssertNil(IconDesignerCenterColorRoleModel.effectiveRole(.primary, options: []))

        XCTAssertEqual(
            roleOptions(for: .automaticLegacy).map(\.role),
            [.primary, .inactive, .bluetooth]
        )
    }

    func testFallbackAndNetworkOverrideMeaningsAreIncludedWithoutChangingStoredRoles() {
        var fallbackConfiguration = configuration(primary: .systemBatteryPercentage, fallback: .network)
        let fallbackOptions = IconDesignerCenterColorRoleModel.options(
            in: fallbackConfiguration,
            connectedBluetoothDeviceIsAudio: false
        )
        XCTAssertEqual(fallbackOptions.map(\.role), [.primary, .inactive])
        XCTAssertEqual(fallbackOptions[0].meanings.map(\.scope), [.primary, .fallback])
        XCTAssertEqual(fallbackOptions[1].meanings.map(\.scope), [.fallback])

        fallbackConfiguration.composition.center = SlotSelection(primary: .none, fallback: .network)
        let noSource = IconDesignerCenterColorRoleModel.options(
            in: fallbackConfiguration,
            connectedBluetoothDeviceIsAudio: false
        )
        XCTAssertTrue(noSource.isEmpty)
        XCTAssertNil(fallbackConfiguration.normalized().composition.center.fallback)

        var overrideConfiguration = configuration(primary: .bluetoothAudioOutput)
        overrideConfiguration.behaviors.bluetoothAudioCenter.usesVolumeColor = true
        overrideConfiguration.composition.centerOverride.networkProblemOverridesPrimary = true
        let overrideOptions = IconDesignerCenterColorRoleModel.options(
            in: overrideConfiguration,
            connectedBluetoothDeviceIsAudio: false
        )
        let primaryMeanings = overrideOptions.first { $0.role == .primary }?.meanings
        XCTAssertTrue(primaryMeanings?.contains(.init(
            scope: .networkOverride,
            localizationKey: .iconDesignerCenterColorMeaningNetworkPrimary,
            helpLocalizationKey: .iconDesignerCenterColorHelpNetworkPrimary
        )) == true)
    }

    func testEffectiveRoleImmediatelyRejectsStaleSelectionAndAcceptsAvailableRole() {
        let options = roleOptions(for: .pinnedBluetoothGlyph)
        XCTAssertEqual(IconDesignerCenterColorRoleModel.effectiveRole(.primary, options: options), .bluetooth)
        XCTAssertEqual(IconDesignerCenterColorRoleModel.effectiveRole(.bluetooth, options: options), .bluetooth)
    }

    func testResolverRolesMatchNetworkBluetoothBatteryAndFallbackDescriptions() throws {
        let zeroBar = resolvedCenter(primary: .network, wifi: WiFiStatus(state: .connected, rssi: -89))
        XCTAssertEqual(symbolColor(zeroBar), .inactive)
        let noInternet = resolvedCenter(primary: .network, wifi: WiFiStatus(state: .noInternet, rssi: -55))
        XCTAssertEqual(symbolColor(noInternet), .primary)
        let off = resolvedCenter(primary: .network, wifi: WiFiStatus(state: .off, rssi: nil))
        XCTAssertEqual(symbolColor(off), .primary)

        XCTAssertEqual(symbolColor(resolvedCenter(primary: .bluetoothAudioOutput, scalar: 0.5)), .bluetooth)
        XCTAssertEqual(symbolColor(resolvedCenter(primary: .bluetoothAudioOutput, scalar: 0)), .primary)
        XCTAssertEqual(symbolColor(resolvedCenter(primary: .bluetoothAudioOutput, scalar: nil)), .primary)
        XCTAssertEqual(symbolColor(resolvedCenter(primary: .pinnedBluetoothGlyph)), .bluetooth)
        XCTAssertEqual(textColor(resolvedCenter(primary: .systemBatteryPercentage)), .primary)

        let fallback = resolvedCenter(
            primary: .bluetoothAudioOutput,
            fallback: .network,
            scalar: nil,
            bluetoothAvailable: false,
            wifi: WiFiStatus(state: .connected, rssi: -89)
        )
        XCTAssertEqual(fallback.trace.center.role, .fallback)
        XCTAssertEqual(symbolColor(fallback), .inactive)

        let overridden = resolvedCenter(
            primary: .bluetoothAudioOutput,
            scalar: 0.5,
            wifi: WiFiStatus(state: .noInternet, rssi: -55),
            networkOverride: true
        )
        XCTAssertEqual(overridden.trace.center.reason, .overridden(.networkProblem))
        XCTAssertEqual(symbolColor(overridden), .primary)
    }

    private func roleOptions(for source: CenterSource, fallback: CenterSource? = nil) -> [IconDesignerCenterColorRoleOption] {
        IconDesignerCenterColorRoleModel.options(
            in: configuration(primary: source, fallback: fallback),
            connectedBluetoothDeviceIsAudio: false
        )
    }

    private func configuration(primary: CenterSource, fallback: CenterSource? = nil) -> IconConfigurationV1 {
        var configuration = IconDesignerDefaults.configuration()
        configuration.composition.center = SlotSelection(primary: primary, fallback: fallback)
        return configuration
    }

    private func resolvedCenter(
        primary: CenterSource,
        fallback: CenterSource? = nil,
        scalar: Double? = 0.5,
        isMuted: Bool = false,
        bluetoothAvailable: Bool = true,
        wifi: WiFiStatus = WiFiStatus(state: .connected, rssi: -55),
        networkOverride: Bool = false
    ) -> IconResolutionOutput {
        var configuration = configuration(primary: primary, fallback: fallback)
        configuration.behaviors.bluetoothAudioCenter.usesVolumeColor = true
        configuration.composition.centerOverride.networkProblemOverridesPrimary = networkOverride
        let snapshot = StatusSnapshot(
            battery: PresentationFixtures.snapshot().battery,
            wifi: wifi,
            connection: .wifi,
            volume: VolumeStatus(
                scalar: scalar,
                isMuted: isMuted,
                deviceName: "Headphones",
                currentDevice: PresentationFixtures.bluetoothDevice
            )
        )
        let sources = IconSourceSnapshot(
            availability: [
                CenterSource.bluetoothAudioOutput.rawValue: bluetoothAvailable ? .available : .unavailable(.disconnected),
                CenterSource.network.rawValue: .available
            ],
            connectedBluetoothDeviceSymbol: "headphones",
            connectedBluetoothDeviceIsAudio: true
        )
        return IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
                sources: sources
            ),
            configuration: configuration
        )
    }

    private func symbolColor(_ output: IconResolutionOutput) -> IconColorRole? {
        guard case let .symbol(symbol)? = output.scene.center else { return nil }
        return symbol.color
    }

    private func textColor(_ output: IconResolutionOutput) -> IconColorRole? {
        guard case let .text(text)? = output.scene.center else { return nil }
        return text.color
    }
}
