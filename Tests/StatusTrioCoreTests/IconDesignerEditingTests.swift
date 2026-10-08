import XCTest
@testable import StatusTrioCore

final class IconDesignerEditingTests: XCTestCase {
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
        configuration.behaviors.networkCenter.wifiScale = 1.7
        configuration.behaviors.bluetoothAudioCenter.symbolScale = 2.1
        let behaviors = configuration.behaviors

        XCTAssertTrue(IconDesignerEditingModel.setPrimary(.center(.bluetoothAudioOutput), for: .center, in: &configuration))

        XCTAssertEqual(configuration.composition.center.primary, .bluetoothAudioOutput)
        XCTAssertNil(configuration.composition.center.fallback)
        XCTAssertEqual(configuration.behaviors, behaviors)
        XCTAssertEqual(configuration.behaviors.bluetoothAudioCenter.symbolScale, 2.1)
        XCTAssertEqual(configuration.behaviors.networkCenter.wifiScale, 1.7)
    }

    func testSwappingPrimaryAndFallbackRetainsBothSourcesAndBehaviors() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network, fallback: .bluetoothAudioOutput)
        configuration.behaviors.networkCenter.wifiScale = 1.7
        configuration.behaviors.bluetoothAudioCenter.symbolScale = 2.1
        let behaviors = configuration.behaviors

        XCTAssertTrue(IconDesignerEditingModel.swapPrimaryAndFallback(for: .center, in: &configuration))

        XCTAssertEqual(configuration.composition.center, SlotSelection(primary: .bluetoothAudioOutput, fallback: .network))
        XCTAssertEqual(configuration.behaviors, behaviors)
    }

    func testBluetoothSymbolOverrideCanOnlyBeEditedForBluetoothPrimary() {
        var configuration = IconConfigurationV1.classic
        XCTAssertFalse(IconDesignerEditingModel.setBluetoothSymbolOverride("headphones", in: &configuration))
        configuration.composition.center.primary = .bluetoothAudioOutput

        XCTAssertTrue(IconDesignerEditingModel.setBluetoothSymbolOverride("headphones", in: &configuration))
        XCTAssertEqual(configuration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride, "headphones")
    }

    func testUnsupportedAirPodsSourceIsNotSelectableBeforePhaseFive() {
        XCTAssertFalse(IconDesignerEditingModel.selectableSources(for: .outerRing, phaseFiveEnabled: false)
            .contains(.ring(.airPodsBattery)))
    }

    func testConfiguredButUnsupportedSourceRemainsVisibleAsCurrentSelection() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .airPodsBattery)

        let current = IconDesignerEditingModel.currentSource(for: .outerRing, in: configuration)

        XCTAssertEqual(current.id, "airPodsBattery")
        XCTAssertFalse(current.isSelectable)
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
        XCTAssertEqual(reset.appearance.center, IconConfigurationV1.classic.appearance.center)
        XCTAssertEqual(reset.composition.center, IconConfigurationV1.classic.composition.center)
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
