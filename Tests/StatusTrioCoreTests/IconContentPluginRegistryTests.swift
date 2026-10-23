import Foundation
import Testing
@testable import StatusTrioCore

struct IconContentPluginRegistryTests {
    private func plugin(_ id: String, slot: IconSlot = .center, selectable: Bool = true) -> TestIconContentPlugin {
        TestIconContentPlugin(descriptor: .init(id: id, presentations: [
            .init(id: "value", slot: slot, title: .iconDesignerSourceNetwork, isSelectable: selectable)
        ]))
    }

    @Test func rejectsDuplicateAndEmptyIDs() {
        #expect(throws: IconContentRegistryError.self) {
            try IconContentPluginRegistry(plugins: [plugin("same"), plugin("same")])
        }
        #expect(throws: IconContentRegistryError.self) {
            try IconContentPluginRegistry(plugins: [plugin("")])
        }
        let presentation = IconContentPresentation(id: "same", slot: .center, title: .iconDesignerSourceNetwork, isSelectable: true)
        #expect(throws: IconContentRegistryError.self) {
            try IconContentPluginRegistry(plugins: [TestIconContentPlugin(descriptor: .init(id: "one", presentations: [presentation, presentation]))])
        }
        #expect(throws: IconContentRegistryError.self) {
            try IconContentPluginRegistry(plugins: [TestIconContentPlugin(descriptor: .init(id: "one", presentations: [
                .init(id: "", slot: .center, title: .iconDesignerSourceNetwork, isSelectable: true)
            ]))])
        }
    }

    @Test func filteringPreservesRegistrationOrderAndHiddenEntries() throws {
        let registry = try IconContentPluginRegistry(plugins: [plugin("two"), plugin("ring", slot: .outerRing), plugin("hidden", selectable: false), plugin("one")])
        #expect(registry.presentations(for: .center).map(\.binding.pluginID) == ["two", "one"])
        #expect(registry.presentation(for: .init(pluginID: "hidden", presentationID: "value")) != nil)
        #expect(registry.presentations(for: .outerRing).count == 1)
    }

    @Test func unknownOrWrongSlotCannotRender() throws {
        let registry = try IconContentPluginRegistry(plugins: [plugin("center")])
        let configuration = IconDesignerDefaults.configuration()
        let now = Date(timeIntervalSince1970: 1_000)
        let inputs = IconPreviewInputBuilder.simulated(samples: .init(), configuration: configuration, target: .currentAudioOutput, now: now)
        let context = IconContentContext(inputs: inputs, configuration: configuration, legacy: configuration.compositionLegacyPresentationConfiguration, now: now)
        #expect(registry.resolve(.init(pluginID: "missing", presentationID: "value"), for: .center, context: context) == .unavailable(.unavailable))
        #expect(registry.resolve(.init(pluginID: "center", presentationID: "value"), for: .footer, context: context) == .unavailable(.unavailable))
        let wrongPayload = TestIconContentPlugin(descriptor: plugin("wrong").descriptor, result: .available(.footer(nil)))
        let wrongRegistry = try IconContentPluginRegistry(plugins: [wrongPayload])
        #expect(wrongRegistry.resolve(.init(pluginID: "wrong", presentationID: "value"), for: .center, context: context) == .unavailable(.unavailable))
    }
}
