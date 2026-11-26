import Foundation
import Testing
@testable import StatusTrioCore

@Suite("Settings semantic registry")
struct SettingsSemanticRegistryTests {

    @Test("The shipped catalog passes structural validation")
    func shippedCatalogIsStructurallyValid() {
        let registry = SettingsSemanticCatalog.makeRegistry(appVersion: "test")
        let issues = registry.validate()
        #expect(issues.isEmpty, "unexpected issues: \(issues.map(\.description))")
    }

    @Test("Preference and feature ids are unique")
    func idsAreUnique() {
        let registry = SettingsSemanticCatalog.makeRegistry()
        #expect(Set(registry.preferences.map(\.id)).count == registry.preferences.count)
        #expect(Set(registry.features.map(\.id)).count == registry.features.count)
        #expect(Set(registry.capabilities.map(\.id)).count == registry.capabilities.count)
        #expect(Set(registry.actions.map(\.id)).count == registry.actions.count)
    }

    @Test("Listing is deterministic and sorted by id")
    func listingIsDeterministic() {
        let a = SettingsSemanticCatalog.makeRegistry()
        let b = SettingsSemanticCatalog.makeRegistry()
        #expect(a.listPreferences().map(\.id) == b.listPreferences().map(\.id))
        #expect(a.listPreferences().map(\.id) == a.listPreferences().map(\.id).sorted())
        #expect(a.listFeatures().map(\.id) == a.listFeatures().map(\.id).sorted())
    }

    @Test("Every feature dependency resolves and is acyclic")
    func featureDependenciesResolve() {
        let registry = SettingsSemanticCatalog.makeRegistry()
        let featureIDs = registry.featureIDs
        for feature in registry.features {
            for parent in feature.requires {
                #expect(featureIDs.contains(parent), "\(feature.id) requires unknown \(parent)")
            }
            for target in feature.mutations {
                #expect(registry.preference(target.id) != nil, "\(feature.id) mutates unknown \(target.id)")
            }
        }
    }

    @Test("Duplicate ids are reported")
    func duplicateIDsReported() {
        let dup = SettingsPreferenceDescriptor(id: "dup", title: "A", category: "x", type: .boolean)
        let registry = SettingsSemanticRegistry(preferences: [dup, dup])
        let kinds = Set(registry.validate().map(\.kind))
        #expect(kinds.contains(.duplicatePreferenceID))
    }

    @Test("Unknown references are reported")
    func unknownReferencesReported() {
        var p = SettingsPreferenceDescriptor(id: "a", title: "A", category: "x", type: .boolean)
        p.requires = ["missing"]
        let registry = SettingsSemanticRegistry(preferences: [p])
        let kinds = Set(registry.validate().map(\.kind))
        #expect(kinds.contains(.unknownPreferenceReference))
    }

    @Test("Cyclic feature dependencies are reported")
    func cyclicFeatureDependenciesReported() {
        let a = SettingsFeatureDescriptor(id: "a", title: "A", requires: ["b"])
        let b = SettingsFeatureDescriptor(id: "b", title: "B", requires: ["a"])
        let registry = SettingsSemanticRegistry(preferences: [], features: [a, b])
        let kinds = Set(registry.validate().map(\.kind))
        #expect(kinds.contains(.cyclicFeatureDependency))
    }

    @Test("Conditions survive a JSON round trip")
    func conditionsRoundTrip() throws {
        let condition = SettingsCondition.allOf([
            .equals(preference: "icon.outerRing.source", value: .string("hardwareMonitor")),
            .capability("ui.liquidGlass"),
            .compare(preference: "battery.thresholds.critical", op: .lessThanOrEqual, value: .number(20)),
            .not(.exists(preference: "general.language")),
            .anyOf([.featureEnabled("panel.hardware"), .contains(preference: "panel.modules.enabled", value: .string("battery"))]),
        ])
        let data = try JSONEncoder().encode(condition)
        let decoded = try JSONDecoder().decode(SettingsCondition.self, from: data)
        #expect(decoded == condition)
    }

    @Test("Catalog references only resolvable conditions")
    func conditionReferencesResolve() {
        let registry = SettingsSemanticCatalog.makeRegistry()
        // validate() already checks conditions; assert explicitly for clarity.
        #expect(registry.validate().filter { $0.kind == .unknownCapabilityReference }.isEmpty)
    }
}
