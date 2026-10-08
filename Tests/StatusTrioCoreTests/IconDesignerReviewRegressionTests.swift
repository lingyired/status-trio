import XCTest
@testable import StatusTrioCore

final class IconDesignerReviewRegressionTests: XCTestCase {
    func testConnectedBluetoothSourceStaysHiddenUntilItsProviderIsImplemented() {
        XCTAssertFalse(IconDesignerEditingModel.selectableSources(for: .center, phaseFiveEnabled: false)
            .contains(.center(.connectedBluetoothDevice)))
        XCTAssertTrue(IconDesignerEditingModel.selectableSources(for: .center, phaseFiveEnabled: true)
            .contains(.center(.connectedBluetoothDevice)))
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
