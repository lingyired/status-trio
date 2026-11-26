import Foundation

/// Full semantic metadata for a single user-visible setting.
///
/// Simple settings may leave most fields `nil`; complex settings must fully
/// describe their real constraints. Fields are intentionally optional so the
/// registry stays honest about what is actually known rather than inventing
/// placeholder semantics.
struct SettingsPreferenceDescriptor: Codable, Equatable, Sendable, Identifiable {
    // Identity & copy
    /// Stable logical id, e.g. `general.language`. Never a UserDefaults key.
    var id: String
    var title: String
    var description: String? = nil
    /// Owning module, e.g. `icon`, `battery`, `panel`.
    var category: String
    /// Where this appears in the Settings UI.
    var uiPath: String? = nil

    // Shape
    var type: SettingsValueType
    /// Static default, or `nil` when resolved at runtime.
    var defaultValue: SettingsTransferValue? = nil
    var options: [SettingsOptionDescriptor]? = nil
    /// Named dynamic option source (resolved by a provider).
    var optionsProvider: String? = nil
    var range: SettingsNumericRange? = nil
    var step: Double? = nil
    var unit: String? = nil

    // Discovery
    var keywords: [String]? = nil
    var recommendedFor: [String]? = nil

    // Relationships
    var requires: [String]? = nil
    var conflictsWith: [String]? = nil
    var visibleWhen: SettingsCondition? = nil
    var enabledWhen: SettingsCondition? = nil
    var effectiveWhen: SettingsCondition? = nil
    var availableWhen: SettingsCondition? = nil
    var constraints: [SettingsConstraint]? = nil
    /// Connected mutations applied when this setting changes.
    var onChange: [SettingsMutationDescriptor]? = nil
    var affects: [String]? = nil

    // Cost & policy
    var performanceImpact: SettingsPerformanceImpact? = nil
    var requiresRestart: Bool? = nil
    var accessPolicy: SettingsAccessPolicy? = nil
    var sinceVersion: String? = nil
    var deprecated: Bool? = nil
    var replacedBy: String? = nil

    // Runtime linkage (not exported as public semantics; used by the service)
    /// Underlying UserDefaults key, when the provider is core settings.
    var storageKey: String? = nil
    /// Domain provider that reads/writes this setting, e.g. `core`, `launchAtLogin`.
    var provider: String? = nil

    /// Compact initializer. All non-identity fields have defaults, so a caller
    /// sets only what it knows. Declared explicitly so the memberwise argument
    /// order does not leak into every call site; use a mutation closure for the
    /// optional metadata.
    init(
        id: String,
        title: String,
        category: String,
        type: SettingsValueType,
        description: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.type = type
        self.description = description
    }
}
