import Foundation

/// A user-facing feature composed of one or more settings.
///
/// Enabling a feature produces `mutations` instead of touching UserDefaults
/// directly; its `requires` are other *feature* ids that must be enabled first.
struct SettingsFeatureDescriptor: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var description: String? = nil
    /// Parent feature ids to enable first (safe additive dependencies only).
    var requires: [String] = []
    /// Preference ids this feature directly controls.
    var preferences: [String] = []
    /// Mutations generated when the feature is enabled.
    var mutations: [SettingsMutationDescriptor] = []
    var performanceImpact: SettingsPerformanceImpact? = nil
    var accessPolicy: SettingsAccessPolicy? = nil
}

/// A capability the current environment may or may not support.
///
/// Availability is measured by a provider at runtime; `unknown` must never be
/// treated as "unsupported".
struct SettingsCapabilityDescriptor: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var description: String? = nil
    /// Optional provider hint; the registry never probes hardware itself.
    var provider: String? = nil

    enum Availability: String, Codable, CaseIterable, Sendable {
        case available
        case unavailable
        case unknown
    }
}

/// A one-shot operation (not a persisted setting).
struct SettingsActionDescriptor: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var description: String? = nil
    var systemSideEffect: Bool = false
    var accessPolicy: SettingsAccessPolicy? = nil
}

/// A semantic validation problem found in the registry itself.
struct SettingsSemanticIssue: Equatable, Sendable, CustomStringConvertible {
    enum Kind: String, Sendable {
        case duplicatePreferenceID
        case duplicateFeatureID
        case duplicateCapabilityID
        case duplicateActionID
        case unknownPreferenceReference
        case unknownFeatureReference
        case unknownCapabilityReference
        case cyclicFeatureDependency
    }

    var kind: Kind
    var detail: String

    var description: String { "[\(kind.rawValue)] \(detail)" }
}
