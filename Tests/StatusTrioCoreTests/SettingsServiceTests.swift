import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
private final class InMemorySettingsProvider: SettingsStateProvider {
    var values: [String: SettingsTransferValue]
    var features: Set<String>

    init(_ values: [String: SettingsTransferValue] = [:], features: Set<String> = []) {
        self.values = values
        self.features = features
    }

    func value(for id: String) -> SettingsTransferValue? { values[id] }
    func setValue(_ value: SettingsTransferValue, for id: String) { values[id] = value }
    func removeValue(for id: String) { values.removeValue(forKey: id) }
    func isFeatureEnabled(_ id: String) -> Bool { features.contains(id) }
}

@MainActor
@Suite("Settings service")
struct SettingsServiceTests {

    private func makeService(_ values: [String: SettingsTransferValue] = [:]) -> (SettingsService, InMemorySettingsProvider) {
        let provider = InMemorySettingsProvider(values)
        let service = SettingsService(registry: SettingsSemanticCatalog.makeRegistry(), provider: provider)
        return (service, provider)
    }

    @Test("Preview does not mutate the provider")
    func previewDoesNotMutate() {
        let (service, provider) = makeService()
        _ = service.preview(enableFeature: "hardware.panel.gpu.temperature")
        #expect(provider.values.isEmpty)
    }

    @Test("Apply writes the plan and restore reverts every touched preference")
    func applyThenRestore() throws {
        let (service, provider) = makeService()
        let result = try service.apply(enableFeature: "hardware.panel.gpu.temperature")
        #expect(provider.value(for: "hardware.temperature.enabled") == .bool(true))
        #expect(provider.value(for: "icon.outerRing.source") == .string("hardwareMonitor"))
        service.restore(result)
        #expect(provider.values.isEmpty, "restore should remove all newly written keys")
    }

    @Test("An inapplicable plan throws and writes nothing")
    func inapplicablePlanDoesNotWrite() {
        let (service, provider) = makeService(["icon.outerRing.hardware.ringSlots": .array([.string("cpu")])])
        let plan = service.preview(mutations: [
            SettingsMutationDescriptor(id: "icon.outerRing.hardware.ringSlots", operation: .remove, value: .string("cpu")),
        ])
        #expect(!plan.isApplicable)
        #expect(throws: SettingsServiceError.self) {
            try service.apply(plan)
        }
        // No partial write: the set is untouched.
        #expect(provider.value(for: "icon.outerRing.hardware.ringSlots") == .array([.string("cpu")]))
    }

    @Test("Snapshot reflects provider values")
    func snapshotReflectsProvider() {
        let (service, _) = makeService([
            "panel.behavior.showOnHover": .bool(true),
            "general.iconSize": .number(28),
        ])
        let snapshot = service.snapshot()
        #expect(snapshot.value("panel.behavior.showOnHover") == .bool(true))
        #expect(snapshot.value("general.iconSize") == .number(28))
        #expect(snapshot.value("panel.appearance.backgroundStyle") == nil)
    }

    @Test("Unknown preference set throws")
    func unknownPreferenceThrows() {
        let (service, _) = makeService()
        #expect(throws: SettingsServiceError.self) {
            try service.apply(setPreference: "does.not.exist", to: .bool(true))
        }
    }
}
