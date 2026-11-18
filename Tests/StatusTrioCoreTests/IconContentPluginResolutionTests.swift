import Foundation
import Testing
@testable import StatusTrioCore

struct IconContentPluginResolutionTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func context(_ configuration: IconConfigurationV1) -> IconContentContext {
        .init(inputs: IconPreviewInputBuilder.simulated(samples: .init(), configuration: configuration, target: .currentAudioOutput, now: now),
              configuration: configuration, legacy: configuration.compositionLegacyPresentationConfiguration, now: now)
    }

    @Test func injectedFailureChangesRealComposition() throws {
        let configuration = IconDesignerDefaults.configuration()
        let fake = TestIconContentPlugin(descriptor: .init(id: "builtin.system-battery", presentations: [
            .init(id: "ring", slot: .outerRing, title: .iconDesignerSourceSystemBattery, isSelectable: true)
        ]), result: .unavailable(.permissionDenied))
        let registry = try IconContentPluginRegistry(plugins: [fake])
        let output = IconCompositionResolver.resolve(inputs: context(configuration).inputs, configuration: configuration, now: now, registry: registry)
        #expect(output.scene.outerRing == nil)
        #expect(output.trace.outerRing.primaryFailure == .permissionDenied)
    }

    @Test func arbitraryRegisteredPluginResolvesAndFallbackKeepsPrimaryReason() throws {
        let fallback = IconContentBinding(pluginID: "test.custom", presentationID: "text")
        let text = CenterState.text(IconTextState(text: "T", color: .primary, scale: 1))
        let plugin = TestIconContentPlugin(descriptor: .init(id: fallback.pluginID, presentations: [
            .init(id: fallback.presentationID, slot: .center, title: .iconDesignerSourceNetwork, isSelectable: true)
        ]), result: .available(.center(text)))
        let registry = try IconContentPluginRegistry(plugins: [plugin])
        let output = IconPluginSlotResolver.resolve(primary: .init(pluginID: "missing", presentationID: "text"), fallback: fallback,
            slot: .center, context: context(.classic), registry: registry)
        #expect(output.payload == .center(text))
        #expect(output.binding == fallback)
        #expect(output.trace.role == .fallback)
        #expect(output.trace.primaryFailure == .unavailable)
        let hidden = IconPluginSlotResolver.resolve(primary: nil, fallback: fallback, slot: .center, context: context(.classic), registry: registry)
        #expect(hidden.payload == nil)
        #expect(hidden.trace == .empty)
    }

    @Test func builtInCompatibilityEntriesAreNeverOfferedAsNewChoices() {
        let registry = BuiltinIconPlugins.makeRegistry()
        #expect(registry.presentations(for: .center).map(\.binding.presentationID).contains("pinned-glyph") == false)
        #expect(registry.presentations(for: .outerRing).map(\.binding.pluginID).contains("builtin.legacy") == false)
        #expect(registry.presentations(for: .center).count == 5)
    }

    @Test func networkOverrideUsesRegisteredNetworkContent() throws {
        var configuration = IconDesignerDefaults.configuration()
        configuration.composition.center = SlotSelection(primary: .none)
        configuration.composition.centerOverride.networkProblemOverridesPrimary = true
        var samples = IconPreviewSampleValues()
        samples.network.kind = .noInternet
        let inputs = IconPreviewInputBuilder.simulated(samples: samples, configuration: configuration, target: .currentAudioOutput, now: now)
        let replacement = CenterState.text(IconTextState(text: "N", color: .primary, scale: 1))
        let fake = TestIconContentPlugin(descriptor: .init(id: "builtin.network", presentations: [
            .init(id: "center", slot: .center, title: .iconDesignerSourceNetwork, isSelectable: true)
        ]), result: .available(.center(replacement)))
        let output = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration, now: now,
            registry: try IconContentPluginRegistry(plugins: [fake]))
        #expect(output.trace.center.reason == .overridden(.networkProblem))
        guard case let .text(text) = output.scene.center else { Issue.record("Registered override was bypassed"); return }
        #expect(text.text == "N")
    }

    @Test func networkAlertStillDrawsWhenNormalNetworkSourceIsUnavailable() {
        var configuration = IconDesignerDefaults.configuration()
        configuration.composition.center = SlotSelection(primary: .inputSource)
        configuration.composition.centerOverride.networkProblemOverridesPrimary = true
        var samples = IconPreviewSampleValues()
        samples.network.kind = .off
        let inputs = IconPreviewInputBuilder.simulated(samples: samples, configuration: configuration, target: .currentAudioOutput, now: now)
        let output = IconCompositionResolver.resolve(inputs: inputs, configuration: configuration, now: now)
        #expect(output.trace.center.reason == .overridden(.networkProblem))
        #expect(output.scene.center != nil)
    }
}
