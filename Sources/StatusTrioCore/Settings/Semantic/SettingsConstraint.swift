import Foundation

/// How a violated constraint is resolved when a candidate change is applied.
enum SettingsConstraintResolution: String, Codable, CaseIterable, Sendable {
    /// Reject the illegal combination; no partial write.
    case reject
    /// Automatically exchange the two settings (e.g. dual-ring primary/secondary).
    case swap
    /// Replace the conflicting option with a valid one.
    case replace
    /// Transform the configuration into a legal equivalent.
    case normalize
    /// Keep a temporarily inactive configuration instead of dropping it.
    case preserveInactive
    /// Require explicit user confirmation before applying.
    case requireConfirmation
    /// Only report the conflict; never mutate.
    case reportOnly
}

/// A data / cross-setting constraint attached to a preference or feature.
///
/// A constraint never mutates anything by itself; the mutation engine in Phase 2
/// interprets `resolution` and produces a change plan.
struct SettingsConstraint: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// This value must differ from `other` (optionally only `when`).
        case distinctValues
        /// This setting requires `other` to be enabled/present.
        case requires
        /// This setting conflicts with `other`.
        case conflicts
        /// Value must fall inside `min...max` (numeric settings).
        case numericRange
        /// Collection must keep at least `min` elements.
        case minimumCount
        /// Collection may keep at most `max` elements.
        case maximumCount
        /// A named rule resolved by domain code.
        case custom
    }

    var kind: Kind
    /// Related preference id (for distinctValues/requires/conflicts).
    var other: String? = nil
    /// Optional guard; the constraint only applies when this holds.
    var when: SettingsCondition? = nil
    var resolution: SettingsConstraintResolution
    var message: String? = nil
    var min: Int? = nil
    var max: Int? = nil
}
