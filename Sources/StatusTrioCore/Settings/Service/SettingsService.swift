import Foundation

/// A domain that can read and write settings by logical preference id.
///
/// Concrete providers bridge one domain (core UserDefaults-backed settings,
/// LaunchAtLogin, Localization, icon configuration, ...) into the semantic
/// service. A provider must apply values through the domain's real setter so
/// side effects and UI/monitoring updates happen through the normal path.
@MainActor
protocol SettingsStateProvider: AnyObject {
    func value(for id: String) -> SettingsTransferValue?
    func setValue(_ value: SettingsTransferValue, for id: String)
    func removeValue(for id: String)
    func isFeatureEnabled(_ id: String) -> Bool
}

extension SettingsStateProvider {
    func isFeatureEnabled(_ id: String) -> Bool { false }
}

/// The captured before-state of a plan so the caller can undo exactly what was
/// applied, including indirect (dependency / connected / constraint) changes.
struct SettingsApplyResult {
    let plan: SettingsChangePlan
    let beforeValues: [String: SettingsTransferValue?]
}

enum SettingsServiceError: Error, Equatable {
    case planNotApplicable([SettingsPlanIssue])
    case unknownPreference(String)
}

/// The single internal entry point for describing, previewing and applying
/// settings changes. It never touches a provider during preview, and it validates
/// the whole plan before writing anything (all-or-nothing).
@MainActor
final class SettingsService {
    let registry: SettingsSemanticRegistry
    private let planner: SettingsPlanner
    private let provider: SettingsStateProvider

    init(registry: SettingsSemanticRegistry, provider: SettingsStateProvider) {
        self.registry = registry
        self.planner = SettingsPlanner(registry: registry)
        self.provider = provider
    }

    // MARK: - Describe

    func listPreferences() -> [SettingsPreferenceDescriptor] { registry.listPreferences() }
    func describePreference(id: String) -> SettingsPreferenceDescriptor? { registry.preference(id) }
    func listFeatures() -> [SettingsFeatureDescriptor] { registry.listFeatures() }
    func listCapabilities() -> [SettingsCapabilityDescriptor] { registry.listCapabilities() }
    func listActions() -> [SettingsActionDescriptor] { registry.listActions() }

    func snapshot() -> SettingsSnapshot {
        var values: [String: SettingsTransferValue] = [:]
        for descriptor in registry.preferences {
            if let value = provider.value(for: descriptor.id) {
                values[descriptor.id] = value
            }
        }
        let enabled = Set(registry.features.filter { provider.isFeatureEnabled($0.id) }.map(\.id))
        return SettingsSnapshot(values: values, enabledFeatures: enabled)
    }

    // MARK: - Preview (never mutates)

    func preview(enableFeature id: String) -> SettingsChangePlan {
        planner.plan(enableFeature: id, snapshot: snapshot())
    }

    func preview(setPreference id: String, to value: SettingsTransferValue) -> SettingsChangePlan {
        planner.plan(setPreference: id, to: value, snapshot: snapshot())
    }

    func preview(mutations: [SettingsMutationDescriptor]) -> SettingsChangePlan {
        planner.plan(mutations: mutations, snapshot: snapshot())
    }

    // MARK: - Apply / restore

    @discardableResult
    func apply(_ plan: SettingsChangePlan) throws -> SettingsApplyResult {
        guard plan.isApplicable else {
            throw SettingsServiceError.planNotApplicable(plan.errors)
        }
        var before: [String: SettingsTransferValue?] = [:]
        var touched = Set<String>()
        for operation in plan.operations {
            if !touched.contains(operation.preferenceID) {
                touched.insert(operation.preferenceID)
                before[operation.preferenceID] = provider.value(for: operation.preferenceID)
            }
            if let value = operation.value {
                provider.setValue(value, for: operation.preferenceID)
            } else {
                provider.removeValue(for: operation.preferenceID)
            }
        }
        return SettingsApplyResult(plan: plan, beforeValues: before)
    }

    @discardableResult
    func apply(enableFeature id: String) throws -> SettingsApplyResult {
        let plan = preview(enableFeature: id)
        if registry.feature(id) == nil {
            throw SettingsServiceError.unknownPreference(id)
        }
        return try apply(plan)
    }

    @discardableResult
    func apply(setPreference id: String, to value: SettingsTransferValue) throws -> SettingsApplyResult {
        let plan = preview(setPreference: id, to: value)
        if registry.preference(id) == nil {
            throw SettingsServiceError.unknownPreference(id)
        }
        return try apply(plan)
    }

    /// Undo exactly the preferences a previous `apply` touched.
    func restore(_ result: SettingsApplyResult) {
        for id in result.beforeValues.keys.sorted() {
            if let boxed = result.beforeValues[id], let previous = boxed {
                provider.setValue(previous, for: id)
            } else {
                provider.removeValue(for: id)
            }
        }
    }
}
