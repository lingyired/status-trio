import XCTest
@testable import StatusTrioCore

final class IconDesignerEditingTests: XCTestCase {
    func testEffectiveCenterScaleBindingPreservesLegacyNilUntilExplicitEdit() {
        var configuration = IconDesignerDefaults.configuration()
        XCTAssertNil(configuration.appearance.center.effectiveSymbolScale)
        let legacyScale = IconDesignerEditingModel.effectiveCenterScale(in: configuration)
        XCTAssertEqual(legacyScale, configuration.legacyPresentationConfiguration.connection.wifiScale, accuracy: 0.001)

        IconDesignerEditingModel.settingEffectiveCenterScale(5.5, in: &configuration)
        XCTAssertEqual(configuration.appearance.center.effectiveSymbolScale, 5.5)
        IconDesignerEditingModel.settingEffectiveCenterScale(20, in: &configuration)
        XCTAssertEqual(configuration.appearance.center.effectiveSymbolScale, 6)
    }

    func testAirPodsFocusPresetConfiguresDualBatteryRingWithoutChangingOtherSlotsOrAppearance() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network, fallback: .bluetoothAudioOutput)
        configuration.composition.footer = SlotSelection(primary: .none)
        configuration.appearance.outerRing.strokeScale = 1.6
        let center = configuration.composition.center
        let footer = configuration.composition.footer
        let appearance = configuration.appearance

        let focused = IconDesignerEditingModel.applyingAirPodsFocus(to: configuration)

        XCTAssertEqual(focused.composition.outerRing, SlotSelection(primary: .airPodsBattery, fallback: .systemBattery))
        XCTAssertEqual(focused.behaviors.airPodsRing, .dual)
        XCTAssertEqual(focused.composition.center, center)
        XCTAssertEqual(focused.composition.footer, footer)
        XCTAssertEqual(focused.appearance, appearance)
    }

    func testEditingFallbackDoesNotChangePrimary() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network)

        XCTAssertTrue(IconDesignerEditingModel.setFallback(.center(.bluetoothAudioOutput), for: .center, in: &configuration))

        XCTAssertEqual(configuration.composition.center.primary, .network)
        XCTAssertEqual(configuration.composition.center.fallback, .bluetoothAudioOutput)
    }

    func testChangingPrimaryRetainsBehaviorForBothConfiguredSources() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network, fallback: .bluetoothAudioOutput)
        configuration.appearance.center.symbolScale = 2.72
        configuration.behaviors.bluetoothAudioCenter.symbolScale = 2.1
        let behaviors = configuration.behaviors

        XCTAssertTrue(IconDesignerEditingModel.setPrimary(.center(.bluetoothAudioOutput), for: .center, in: &configuration))

        XCTAssertEqual(configuration.composition.center.primary, .bluetoothAudioOutput)
        XCTAssertNil(configuration.composition.center.fallback)
        XCTAssertEqual(configuration.behaviors, behaviors)
        XCTAssertEqual(configuration.behaviors.bluetoothAudioCenter.symbolScale, 2.1)
        XCTAssertEqual(configuration.behaviors.networkCenter.wifiScale, 1)
        XCTAssertEqual(configuration.appearance.center.symbolScale, 2.72)
    }

    func testSwappingPrimaryAndFallbackRetainsBothSourcesAndBehaviors() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network, fallback: .bluetoothAudioOutput)
        configuration.appearance.center.symbolScale = 2.72
        configuration.behaviors.bluetoothAudioCenter.symbolScale = 2.1
        let behaviors = configuration.behaviors

        XCTAssertTrue(IconDesignerEditingModel.swapPrimaryAndFallback(for: .center, in: &configuration))

        XCTAssertEqual(configuration.composition.center, SlotSelection(primary: .bluetoothAudioOutput, fallback: .network))
        XCTAssertEqual(configuration.behaviors, behaviors)
        XCTAssertEqual(configuration.appearance.center.symbolScale, 2.72)
    }

    func testBluetoothSymbolOverrideCanOnlyBeEditedForBluetoothPrimary() {
        var configuration = IconConfigurationV1.classic
        XCTAssertFalse(IconDesignerEditingModel.setBluetoothSymbolOverride("headphones", in: &configuration))
        configuration.composition.center.primary = .bluetoothAudioOutput

        XCTAssertTrue(IconDesignerEditingModel.setBluetoothSymbolOverride("headphones", in: &configuration))
        XCTAssertEqual(configuration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride, "headphones")
    }

    @MainActor
    func testUnifiedBluetoothGlyphAutomationRestoresTrueAutoDetection() throws {
        let suiteName = "StatusTrioCoreTests.IconDesignerEditing.BluetoothGlyph.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestUserDefaults.removeSuite(named: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let model = IconDesignerEditorModel(store: store)
        store.updateIconConfiguration { $0.composition.center.primary = .bluetoothAudioOutput }
        store.bluetoothAudioIconChoice = .airpods
        store.updateIconConfiguration { $0.behaviors.bluetoothAudioCenter.networkIconSymbolOverride = "headphones" }
        let editingModel = IconDesignerEditorModel(store: store)

        editingModel.perform {
            store.updateIconConfiguration { configuration in
                _ = IconDesignerEditingModel.setBluetoothSymbolOverride(
                    nil, for: .primary, in: &configuration,
                    bluetoothTarget: .currentAudioOutput, devices: []
                )
            }
            store.bluetoothAudioIconChoice = .automatic
        }

        XCTAssertNil(store.iconConfiguration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride)
        XCTAssertEqual(store.bluetoothAudioIconChoice, .automatic)

        editingModel.undo()
        XCTAssertEqual(store.iconConfiguration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride, "headphones")
        XCTAssertEqual(store.bluetoothAudioIconChoice, .airpods)
        _ = model
    }

    func testNonAudioBluetoothTargetDoesNotExposeVolumeColor() {
        let keyboard = BluetoothDevice(
            id: "11:22:33:44:55:66", name: "Keyboard", kind: .peripheral(.keyboard), isConnected: true
        )
        let target = IconDesignerBluetoothTarget.connectedDevice(address: keyboard.id)

        let capabilities = IconDesignerEditingModel.behaviors(
            for: .center, source: .center(.connectedBluetoothDevice),
            bluetoothTarget: target, devices: [keyboard]
        )

        XCTAssertFalse(capabilities.contains(.bluetoothOutputAppearance))
    }

    func testSpecifiedOnlineAudioTargetAllowsBluetoothSymbolAndNetworkOverride() {
        let airPods = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:FF", name: "AirPods", kind: .audio, isConnected: true
        )
        let target = IconDesignerBluetoothTarget.connectedDevice(address: "aa-bb-cc-dd-ee-ff")
        var configuration = IconConfigurationV1.classic
        configuration.composition.center.primary = .connectedBluetoothDevice

        XCTAssertTrue(IconDesignerEditingModel.setBluetoothSymbolOverride(
            "airpods.pro", for: .primary, in: &configuration,
            bluetoothTarget: target, devices: [airPods]
        ))
        XCTAssertTrue(IconDesignerEditingModel.allowsNetworkProblemOverride(
            in: configuration, bluetoothTarget: target, devices: [airPods]
        ))
        XCTAssertEqual(configuration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride, "airpods.pro")
    }

    func testSpecifiedNonAudioBluetoothTargetDoesNotExposeAudioOverrides() {
        let keyboard = BluetoothDevice(
            id: "11:22:33:44:55:66", name: "Keyboard", kind: .peripheral(.keyboard), isConnected: true
        )
        let target = IconDesignerBluetoothTarget.connectedDevice(address: keyboard.id)
        var configuration = IconConfigurationV1.classic
        configuration.composition.center.primary = .connectedBluetoothDevice

        XCTAssertFalse(IconDesignerEditingModel.setBluetoothSymbolOverride(
            "keyboard", for: .primary, in: &configuration,
            bluetoothTarget: target, devices: [keyboard]
        ))
        XCTAssertFalse(IconDesignerEditingModel.allowsNetworkProblemOverride(
            in: configuration, bluetoothTarget: target, devices: [keyboard]
        ))
        XCTAssertNil(configuration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride)
    }

    func testAirPodsIsAnAvailableRingChoiceInTheDesigner() {
        XCTAssertTrue(IconDesignerEditingModel.selectableSources(for: .outerRing, phaseFiveEnabled: false)
            .contains(.ring(.airPodsBattery)))
    }

    func testConfiguredAirPodsSourceRemainsVisibleAsCurrentSelection() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .airPodsBattery)

        let current = IconDesignerEditingModel.currentSource(for: .outerRing, in: configuration)

        XCTAssertEqual(current.id, "airPodsBattery")
        XCTAssertTrue(current.isSelectable)
    }

    func testSlotResetPreservesOtherSlotsAndOnlyChangesIconConfiguration() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .systemBattery)
        configuration.composition.center = SlotSelection(primary: .network, fallback: .bluetoothAudioOutput)
        configuration.appearance.center.symbolScale = 1.5
        configuration.behaviors.systemVolumeFooter.displayStyle = .arc
        let reset = configuration.resetting(.center)

        XCTAssertEqual(reset.composition.outerRing, configuration.composition.outerRing)
        XCTAssertEqual(reset.composition.footer, configuration.composition.footer)
        XCTAssertEqual(reset.behaviors.systemVolumeFooter, configuration.behaviors.systemVolumeFooter)
        XCTAssertEqual(reset.behaviors.airPodsRing, configuration.behaviors.airPodsRing,
                       "Resetting a different slot must preserve the AirPods ring behavior.")
        XCTAssertEqual(reset.appearance.center, IconDesignerDefaults.configuration().appearance.center)
        XCTAssertEqual(reset.composition.center, SlotSelection(primary: .network))
    }

    func testDuplicatePrimaryCannotBeCommittedAsFallback() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network, fallback: .bluetoothAudioOutput)

        XCTAssertFalse(IconDesignerEditingModel.setFallback(.center(.network), for: .center, in: &configuration))
        XCTAssertEqual(configuration.composition.center, SlotSelection(primary: .network, fallback: .bluetoothAudioOutput))
    }
}

@MainActor
extension IconDesignerEditingTests {
    func testOuterRingResetRestoresAirPodsRingBehaviorWithoutChangingOtherSlots() {
        var configuration = IconConfigurationV1.classic
        configuration.behaviors.airPodsRing = .single
        configuration.composition.center.primary = .network
        configuration.composition.footer.primary = .systemVolume

        let reset = configuration.resetting(.outerRing)

        XCTAssertEqual(reset.behaviors.airPodsRing, .dual)
        XCTAssertEqual(reset.composition.center.primary, .network)
        XCTAssertEqual(reset.composition.footer.primary, .systemVolume)
    }

    func testOuterRingSlotResetLeavesDockAndAirPodsReadPreferencesUntouched() throws {
        let suiteName = "StatusTrioCoreTests.IconDesignerEditing.OuterRingReset.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestUserDefaults.removeSuite(named: suiteName) }
        let store = SettingsStore(defaults: defaults)
        store.dockIconBackgroundPreference = .light
        store.refreshesAirPodsBatteryForIcon = true
        store.updateIconConfiguration { configuration in
            configuration.behaviors.airPodsRing = .single
            configuration.composition.outerRing.primary = .airPodsBattery
        }

        store.updateIconConfiguration { $0 = $0.resetting(.outerRing) }

        XCTAssertEqual(store.iconConfiguration.behaviors.airPodsRing, .dual)
        XCTAssertEqual(store.dockIconBackgroundPreference, .light)
        XCTAssertTrue(store.refreshesAirPodsBatteryForIcon)
    }

    func testClassicResetPreservesDockBackgroundAndBackgroundPermission() {
        let suiteName = "StatusTrioCoreTests.IconDesignerEditing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { TestUserDefaults.removeSuite(named: suiteName) }
        let store = SettingsStore(defaults: defaults)
        store.dockIconBackgroundPreference = .dark
        store.refreshesAppleBatteriesInBackground = false
        store.updateIconConfiguration { $0.composition.center.primary = .network }

        store.resetIconConfiguration()

        XCTAssertEqual(store.iconConfiguration, .classic)
        XCTAssertEqual(store.dockIconBackgroundPreference, .dark)
        XCTAssertFalse(store.refreshesAppleBatteriesInBackground)
    }
}
