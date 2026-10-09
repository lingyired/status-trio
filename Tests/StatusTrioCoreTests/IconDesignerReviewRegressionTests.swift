import XCTest
@testable import StatusTrioCore

final class IconDesignerReviewRegressionTests: XCTestCase {
    func testImplementedConnectedBluetoothSourceIsSelectableAndItsPickerStaysConfigured() {
        XCTAssertTrue(IconDesignerEditingModel.supportsImplementedSources(for: .center))
        XCTAssertTrue(IconDesignerEditingModel.selectableSources(for: .center, phaseFiveEnabled: true)
            .contains(.center(.connectedBluetoothDevice)))

        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .connectedBluetoothDevice, fallback: .network)
        XCTAssertTrue(IconDesignerEditingModel.requiresConnectedBluetoothDevice(in: configuration))
        configuration.composition.center = SlotSelection(primary: .network, fallback: .connectedBluetoothDevice)
        XCTAssertTrue(IconDesignerEditingModel.requiresConnectedBluetoothDevice(in: configuration),
                      "The configured connected-device fallback must keep its picker available.")
    }

    @MainActor
    func testConnectedBluetoothAddressPersistsIntoProductionResolverAndDisconnectKeepsSelection() throws {
        let suiteName = "StatusTrioCoreTests.ConnectedBluetoothIconSource.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestUserDefaults.removeSuite(named: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let address = "AA:BB:CC:DD:EE:40"
        store.connectedBluetoothIconDeviceAddress = address
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .connectedBluetoothDevice, fallback: .network)

        let device = BluetoothDevice(id: address, name: "Keyboard", kind: .peripheral(.keyboard), isConnected: true)
        let status = PresentationFixtures.snapshot(rssi: -40)
        let freshSources = IconPresentationResourceResolver.sourceSnapshot(
            snapshot: status, bluetoothDevices: [device], selectedConnectedDeviceAddress: store.connectedBluetoothIconDeviceAddress
        )
        let fresh = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(system: IconPresentationResourceResolver.inputs(snapshot: status), sources: freshSources),
            configuration: configuration
        )
        XCTAssertEqual(fresh.trace.center.selectedSourceID, CenterSource.connectedBluetoothDevice.rawValue)
        XCTAssertNotNil(fresh.scene.center)

        let disconnected = BluetoothDevice(id: address, name: "Keyboard", kind: .peripheral(.keyboard), isConnected: false)
        let disconnectedSources = IconPresentationResourceResolver.sourceSnapshot(
            snapshot: status, bluetoothDevices: [disconnected], selectedConnectedDeviceAddress: store.connectedBluetoothIconDeviceAddress
        )
        let unavailable = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(system: IconPresentationResourceResolver.inputs(snapshot: status), sources: disconnectedSources),
            configuration: configuration
        )
        XCTAssertEqual(store.connectedBluetoothIconDeviceAddress, address)
        XCTAssertEqual(unavailable.trace.center.selectedSourceID, CenterSource.network.rawValue)
        XCTAssertEqual(unavailable.trace.center.role, SlotResolutionRole.fallback)
    }

    func testBehaviorEditorOffersConfiguredPrimaryAndFallbackAsTargets() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network, fallback: .bluetoothAudioOutput)
        XCTAssertEqual(
            IconDesignerEditingModel.behaviorTargets(for: .center, in: configuration),
            [.primary, .fallback]
        )
        XCTAssertEqual(
            IconDesignerEditingModel.source(for: .fallback, slot: .center, in: configuration),
            .center(.bluetoothAudioOutput)
        )
    }

    func testPinnedGlyphFallbackCanEditGlyphWithoutChangingComposition() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network, fallback: .pinnedBluetoothGlyph)
        let originalComposition = configuration.composition
        XCTAssertTrue(IconDesignerEditingModel.setBluetoothSymbolOverride(
            "airpodspro", for: .fallback, in: &configuration
        ))
        XCTAssertEqual(configuration.composition, originalComposition)
        XCTAssertEqual(configuration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride, "airpodspro")
    }

    func testNetworkErrorOverrideIsOnlyAvailableForBluetoothPrimary() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center.primary = .pinnedBluetoothGlyph
        XCTAssertFalse(IconDesignerEditingModel.allowsNetworkProblemOverride(in: configuration))
        configuration.composition.center.primary = .bluetoothAudioOutput
        XCTAssertTrue(IconDesignerEditingModel.allowsNetworkProblemOverride(in: configuration))
    }

    func testPinnedGlyphPickerCanEditGlyphWithoutChangingComposition() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center.primary = .pinnedBluetoothGlyph
        let originalComposition = configuration.composition
        XCTAssertTrue(IconDesignerEditingModel.setBluetoothSymbolOverride("airpodspro", in: &configuration))
        XCTAssertEqual(configuration.composition, originalComposition)
        XCTAssertEqual(configuration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride, "airpodspro")
    }

    func testBehaviorEditorFallsBackToPrimaryWhenFallbackIsRemovedOrClassicResets() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network, fallback: .bluetoothAudioOutput)
        XCTAssertEqual(
            IconDesignerEditingModel.validatedBehaviorTarget(.fallback, slot: .center, in: configuration),
            .fallback
        )

        configuration.composition.center.fallback = nil
        XCTAssertEqual(
            IconDesignerEditingModel.validatedBehaviorTarget(.fallback, slot: .center, in: configuration),
            .primary
        )

        configuration = .classic
        XCTAssertEqual(
            IconDesignerEditingModel.validatedBehaviorTarget(.fallback, slot: .center, in: configuration),
            .primary
        )

        configuration.composition.center = SlotSelection(primary: .bluetoothAudioOutput, fallback: .network)
        configuration.composition.center.fallback = nil
        let effectiveTarget = IconDesignerEditingModel.effectiveBehaviorTarget(
            .fallback, slot: .center, in: configuration
        )
        XCTAssertEqual(effectiveTarget, .primary)
        XCTAssertTrue(IconDesignerEditingModel.setBluetoothSymbolOverride(
            "airpodspro", for: effectiveTarget, in: &configuration
        ), "The stale hidden fallback selection must edit the current primary after removal")
    }

    @MainActor
    func testChargingPreviewResolvesMockedChargingSceneAndKeepsEffectPhase() {
        let realSnapshot = StatusSnapshot(
            battery: BatteryStatus(rawPercentage: 62, isPresent: true, isCharging: false,
                                   isLowPowerMode: false, isConnectedToPower: false),
            wifi: .placeholder, connection: .offline, volume: .placeholder
        )
        let testModeStatus = ChargingEffectTestMode.status(MenuBarStatus(snapshot: realSnapshot), enabled: true)
        let testModeOutput = StatusIconPreviewCard.resolveDisplayedPreviewScene(
            status: testModeStatus, basedOn: realSnapshot, bluetoothDevices: [], batteryLevels: [:], batteryLevelsUpdatedAt: nil,
            selectedAirPodsAddress: nil, selectedConnectedDeviceAddress: nil,
            configuration: .classic, scenario: .live
        )
        XCTAssertEqual(testModeOutput.scene.outerRing?.segments.first?.progress, 0.62)
        XCTAssertNotNil(testModeOutput.scene.outerRing?.effect)
        XCTAssertNotNil(StatusIconPreviewCard.livePhase(
            battery: testModeStatus.battery, enabled: true, reduceMotion: false,
            phase: ChargingEffectPhase(step: 1, stepsPerCycle: 10, kind: .steady)
        ))

        let localPreview = StatusIconPreviewCard.chargingPreviewStatus(for: realSnapshot)
        let localOutput = StatusIconPreviewCard.resolveDisplayedPreviewScene(
            status: localPreview, basedOn: realSnapshot, bluetoothDevices: [], batteryLevels: [:], batteryLevelsUpdatedAt: nil,
            selectedAirPodsAddress: nil, selectedConnectedDeviceAddress: nil,
            configuration: .classic, scenario: .live
        )
        XCTAssertEqual(localOutput.scene.outerRing?.segments.first?.progress, 0.62)
        XCTAssertNotNil(localOutput.scene.outerRing?.effect)
    }

    func testDesignerPreviewUsesProductionResolverForFallback() {
        let live = IconResolutionInputs(
            system: IconPresentationInputs(snapshot: PresentationFixtures.snapshot(), audioIcon: nil),
            sources: IconSourceSnapshot(availability: [
                CenterSource.bluetoothAudioOutput.rawValue: .unavailable(.disconnected),
                CenterSource.network.rawValue: .available
            ])
        )
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .bluetoothAudioOutput, fallback: .network)

        let preview = IconDesignerPreviewResolver.resolve(inputs: live, configuration: configuration)
        let production = IconCompositionResolver.resolve(inputs: live, configuration: configuration)

        XCTAssertEqual(preview, production)
        XCTAssertEqual(preview.trace.center.role, .fallback)
        XCTAssertEqual(preview.trace.center.selectedSourceID, CenterSource.network.rawValue)
    }

    func testNetworkPrimaryDoesNotExposeLegacyOnlyBatteryPercentageBehavior() {
        XCTAssertFalse(IconDesignerEditingModel.behaviors(for: .center, source: .center(.network))
            .contains(.legacyBatteryPercentageInCenter))
        XCTAssertTrue(IconDesignerEditingModel.behaviors(for: .center, source: .center(.automaticLegacy))
            .contains(.legacyBatteryPercentageInCenter))
    }

    func testDesignerPreviewUsesProductionResolverForNoneAndCustomAppearance() {
        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(snapshot: PresentationFixtures.snapshot(), audioIcon: nil),
            sources: IconSourceSnapshot(availability: [:])
        )
        var config = IconConfigurationV1.classic
        config.composition.outerRing = SlotSelection(primary: .none)
        config.appearance.center.color = SlotColorStyle.fixed(IconRGBA(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))

        let preview = IconDesignerPreviewResolver.resolve(inputs: inputs, configuration: config)
        let production = IconCompositionResolver.resolve(inputs: inputs, configuration: config)
        XCTAssertEqual(preview, production)
        XCTAssertNil(preview.scene.outerRing)
        XCTAssertEqual(preview.scene.center, production.scene.center)
    }
}
