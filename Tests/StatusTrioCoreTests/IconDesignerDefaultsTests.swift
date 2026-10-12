import Foundation
import XCTest
@testable import StatusTrioCore

final class IconDesignerDefaultsTests: XCTestCase {
    func testDesignerDefaultNeverRestoresAutomaticLegacySources() {
        let value = IconDesignerDefaults.configuration()

        XCTAssertEqual(value.composition.outerRing.primary, .systemBattery)
        XCTAssertEqual(value.composition.center.primary, .network)
        XCTAssertEqual(value.composition.footer.primary, .systemVolume)
        XCTAssertEqual(value.behaviors.airPodsRing, .dual)
        XCTAssertNil(value.composition.outerRing.fallback)
        XCTAssertNil(value.composition.center.fallback)
        XCTAssertNil(value.composition.footer.fallback)
        XCTAssertEqual(value.schemaVersion, 1)
        var expectedBehaviors = IconConfigurationV1.classic.behaviors
        expectedBehaviors.airPodsRing = .dual
        XCTAssertEqual(value.behaviors, expectedBehaviors)
        var expectedAppearance = IconConfigurationV1.classic.appearance
        expectedAppearance.center.normalizedSizePercentage = 1.0
        XCTAssertEqual(value.appearance, expectedAppearance)
        XCTAssertNil(IconConfigurationV1.classic.appearance.center.normalizedSizePercentage)
        var sourceSwitched = value
        for source in [CenterSource.bluetoothAudioOutput, .network] {
            XCTAssertTrue(IconDesignerEditingModel.setPrimary(.center(source), for: .center, in: &sourceSwitched))
            XCTAssertEqual(sourceSwitched.appearance.center.normalizedSizePercentage, 1.0)
        }
    }


    func testExplicitCenterResetUsesUnifiedSizeAcrossNetworkAndBluetoothSources() {
        var legacy = IconConfigurationV1.classic
        legacy.composition.center = SlotSelection(primary: .bluetoothAudioOutput, fallback: .network)
        legacy.appearance.center.effectiveSymbolScale = 5.2
        legacy.appearance.center.normalizedPercentageScale = 1.7

        var reset = IconDesignerDefaults.resetting(.center, in: legacy)

        XCTAssertEqual(reset.appearance.center.normalizedSizePercentage, 1.0)
        XCTAssertNil(reset.appearance.center.effectiveSymbolScale)
        XCTAssertNil(reset.appearance.center.normalizedPercentageScale)
        XCTAssertEqual(reset.composition.center.primary, .network)
        for source in [CenterSource.bluetoothAudioOutput, .network] {
            XCTAssertTrue(IconDesignerEditingModel.setPrimary(.center(source), for: .center, in: &reset))
            XCTAssertEqual(reset.appearance.center.normalizedSizePercentage, 1.0)
        }
    }

    func testResetSlotPreservesOtherSlotsAndUsesExplicitDesignerDefault() {
        var value = IconConfigurationV1.classic
        value.composition.outerRing = SlotSelection(primary: .airPodsBattery, fallback: .systemBattery)
        value.composition.center = SlotSelection(primary: .systemBatteryPercentage)
        value.appearance.center.symbolScale = 2.2

        let reset = IconDesignerDefaults.resetting(.outerRing, in: value)

        XCTAssertEqual(reset.composition.outerRing, SlotSelection(primary: .systemBattery))
        XCTAssertEqual(reset.composition.center, value.composition.center)
        XCTAssertEqual(reset.appearance.center, value.appearance.center)
        XCTAssertEqual(reset.composition.footer, value.composition.footer)
        XCTAssertEqual(reset.behaviors.airPodsRing, .dual)
    }

    func testChoosingAirPodsSourcePreservesAnExplicitSingleRingChoice() {
        var value = IconDesignerDefaults.configuration()
        value.behaviors.airPodsRing = .single

        XCTAssertTrue(IconDesignerEditingModel.setPrimary(.ring(.airPodsBattery), for: .outerRing, in: &value))

        XCTAssertEqual(value.behaviors.airPodsRing, .single)
        XCTAssertEqual(value.composition.outerRing.fallback, .systemBattery)
    }

    func testChoosingAirPodsAddsMacBatteryFallbackOnlyWhenNeeded() {
        var firstChoice = IconDesignerDefaults.configuration()
        XCTAssertTrue(IconDesignerEditingModel.setPrimary(.ring(.airPodsBattery), for: .outerRing, in: &firstChoice))
        XCTAssertEqual(firstChoice.composition.outerRing.fallback, .systemBattery)

        XCTAssertTrue(IconDesignerEditingModel.setFallback(nil, for: .outerRing, in: &firstChoice))
        XCTAssertTrue(IconDesignerEditingModel.setPrimary(.ring(.airPodsBattery), for: .outerRing, in: &firstChoice))
        XCTAssertNil(firstChoice.composition.outerRing.fallback, "Re-selecting AirPods must preserve an explicit None fallback.")

        var existingFallback = IconConfigurationV1.classic
        existingFallback.composition.outerRing = SlotSelection(primary: .automaticLegacy, fallback: .systemBattery)
        XCTAssertTrue(IconDesignerEditingModel.setPrimary(.ring(.airPodsBattery), for: .outerRing, in: &existingFallback))
        XCTAssertEqual(existingFallback.composition.outerRing.fallback, .systemBattery)

        var anotherSource = IconDesignerDefaults.configuration()
        anotherSource.composition.outerRing = SlotSelection(primary: .automaticLegacy, fallback: .airPodsBattery)
        XCTAssertTrue(IconDesignerEditingModel.setPrimary(.ring(.systemBattery), for: .outerRing, in: &anotherSource))
        XCTAssertEqual(anotherSource.composition.outerRing.fallback, .airPodsBattery)
        XCTAssertTrue(IconDesignerEditingModel.setPrimary(.ring(.none), for: .outerRing, in: &anotherSource))
        XCTAssertNil(anotherSource.composition.outerRing.fallback)
    }

    func testLegacySourcesAreDisplayedAsPreservedButNotOfferedAsChoices() {
        var value = IconConfigurationV1.classic
        value.composition.outerRing = SlotSelection(primary: .automaticLegacy)
        value.composition.center = SlotSelection(primary: .automaticLegacy)

        XCTAssertEqual(IconDesignerSourceSelection.centerChoices,
                       [.network, .bluetoothDevice, .macBatteryPercentage, .none])
        XCTAssertNil(IconDesignerSourceSelection.choice(for: .automaticLegacy))
        XCTAssertFalse(IconDesignerEditingModel.currentSource(for: .center, in: value).isSelectable)
        XCTAssertTrue(IconDesignerEditingModel.currentSource(for: .center, in: value).isLegacy)
        XCTAssertEqual(value.composition.center.primary, .automaticLegacy)
        XCTAssertEqual(value.composition.outerRing.primary, .automaticLegacy)
    }

    @MainActor
    func testOpeningDesignerPreservesLegacyPayloadBytes() throws {
        let suiteName = "StatusTrioCoreTests.IconDesignerDefaults.Legacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestUserDefaults.removeSuite(named: suiteName) }

        var legacy = IconConfigurationV1.classic
        legacy.composition.outerRing = SlotSelection(primary: .automaticLegacy)
        legacy.composition.center = SlotSelection(primary: .automaticLegacy)
        legacy.behaviors.networkCenter.wifiScale = 1
        legacy.wifiScaleMigrationVersion = 1
        let payload = try IconConfigurationCodec.encode(legacy)
        defaults.set(payload, forKey: SettingsStore.iconConfigurationDefaultsKey)
        let store = SettingsStore(defaults: defaults)

        _ = IconDesignerEditingModel.currentSource(for: .outerRing, in: store.iconConfiguration)
        _ = IconDesignerEditingModel.currentSource(for: .center, in: store.iconConfiguration)
        _ = IconDesignerSourceSelection.choice(for: store.iconConfiguration.composition.center.primary)

        XCTAssertEqual(defaults.data(forKey: SettingsStore.iconConfigurationDefaultsKey), payload)
        XCTAssertEqual(store.iconConfiguration.composition.center.primary, .automaticLegacy)
        XCTAssertNil(store.iconConfiguration.appearance.center.normalizedSizePercentage)
        XCTAssertNil(store.iconConfiguration.appearance.center.effectiveSymbolScale)
    }

    func testPinnedGlyphRemainsUnboundAndRetainsItsSymbolUntilExplicitSelection() {
        var value = IconConfigurationV1.classic
        value.composition.center = SlotSelection(primary: .pinnedBluetoothGlyph)
        value.behaviors.bluetoothAudioCenter.networkIconSymbolOverride = "headphones"

        let current = IconDesignerEditingModel.currentSource(for: .center, in: value)

        XCTAssertFalse(current.isSelectable)
        XCTAssertEqual(current.id, CenterSource.pinnedBluetoothGlyph.rawValue)
        XCTAssertEqual(value.behaviors.bluetoothAudioCenter.networkIconSymbolOverride, "headphones")
        XCTAssertNil(IconDesignerSourceSelection.choice(for: .pinnedBluetoothGlyph))
    }
}
