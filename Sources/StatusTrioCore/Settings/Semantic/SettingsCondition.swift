import Foundation

/// Numeric comparison operators for `SettingsCondition.compare`.
enum SettingsComparisonOperator: String, Codable, CaseIterable, Sendable {
    case lessThan = "lt"
    case lessThanOrEqual = "lte"
    case greaterThan = "gt"
    case greaterThanOrEqual = "gte"

    func evaluate(_ lhs: Double, _ rhs: Double) -> Bool {
        switch self {
        case .lessThan: return lhs < rhs
        case .lessThanOrEqual: return lhs <= rhs
        case .greaterThan: return lhs > rhs
        case .greaterThanOrEqual: return lhs >= rhs
        }
    }
}

/// A strongly-typed, composable condition.
///
/// Conditions are used for several distinct questions (visibility, operability,
/// effective state, system availability). The owning descriptor field decides
/// which question a condition answers; the condition type itself never mixes
/// them. The registry keeps conditions as pure data so they can be validated,
/// exported and (later) evaluated without executing any script engine.
indirect enum SettingsCondition: Equatable, Sendable {
    case allOf([SettingsCondition])
    case anyOf([SettingsCondition])
    case not(SettingsCondition)
    case equals(preference: String, value: SettingsTransferValue)
    case contains(preference: String, value: SettingsTransferValue)
    case featureEnabled(String)
    case capability(String)
    case exists(preference: String)
    case compare(preference: String, op: SettingsComparisonOperator, value: SettingsTransferValue)

    // MARK: - Reference collection (for validation)

    /// Preference ids this condition reads from.
    var referencedPreferences: Set<String> {
        switch self {
        case .allOf(let xs), .anyOf(let xs):
            return xs.reduce(into: []) { $0.formUnion($1.referencedPreferences) }
        case .not(let x):
            return x.referencedPreferences
        case .equals(let p, _), .contains(let p, _), .exists(let p), .compare(let p, _, _):
            return [p]
        case .featureEnabled, .capability:
            return []
        }
    }

    /// Feature ids this condition gates on.
    var referencedFeatures: Set<String> {
        switch self {
        case .allOf(let xs), .anyOf(let xs):
            return xs.reduce(into: []) { $0.formUnion($1.referencedFeatures) }
        case .not(let x):
            return x.referencedFeatures
        case .featureEnabled(let f):
            return [f]
        default:
            return []
        }
    }

    /// Capability ids this condition gates on.
    var referencedCapabilities: Set<String> {
        switch self {
        case .allOf(let xs), .anyOf(let xs):
            return xs.reduce(into: []) { $0.formUnion($1.referencedCapabilities) }
        case .not(let x):
            return x.referencedCapabilities
        case .capability(let c):
            return [c]
        default:
            return []
        }
    }
}

extension SettingsCondition: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case conditions
        case condition
        case preference
        case value
        case feature
        case capability
        case op
    }

    private enum Kind: String, Codable {
        case allOf, anyOf, not, equals, contains, featureEnabled, capability, exists, compare
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .allOf:
            self = .allOf(try container.decode([SettingsCondition].self, forKey: .conditions))
        case .anyOf:
            self = .anyOf(try container.decode([SettingsCondition].self, forKey: .conditions))
        case .not:
            self = .not(try container.decode(SettingsCondition.self, forKey: .condition))
        case .equals:
            self = .equals(
                preference: try container.decode(String.self, forKey: .preference),
                value: try container.decode(SettingsTransferValue.self, forKey: .value)
            )
        case .contains:
            self = .contains(
                preference: try container.decode(String.self, forKey: .preference),
                value: try container.decode(SettingsTransferValue.self, forKey: .value)
            )
        case .featureEnabled:
            self = .featureEnabled(try container.decode(String.self, forKey: .feature))
        case .capability:
            self = .capability(try container.decode(String.self, forKey: .capability))
        case .exists:
            self = .exists(preference: try container.decode(String.self, forKey: .preference))
        case .compare:
            self = .compare(
                preference: try container.decode(String.self, forKey: .preference),
                op: try container.decode(SettingsComparisonOperator.self, forKey: .op),
                value: try container.decode(SettingsTransferValue.self, forKey: .value)
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allOf(let xs):
            try container.encode(Kind.allOf, forKey: .type)
            try container.encode(xs, forKey: .conditions)
        case .anyOf(let xs):
            try container.encode(Kind.anyOf, forKey: .type)
            try container.encode(xs, forKey: .conditions)
        case .not(let x):
            try container.encode(Kind.not, forKey: .type)
            try container.encode(x, forKey: .condition)
        case .equals(let p, let v):
            try container.encode(Kind.equals, forKey: .type)
            try container.encode(p, forKey: .preference)
            try container.encode(v, forKey: .value)
        case .contains(let p, let v):
            try container.encode(Kind.contains, forKey: .type)
            try container.encode(p, forKey: .preference)
            try container.encode(v, forKey: .value)
        case .featureEnabled(let f):
            try container.encode(Kind.featureEnabled, forKey: .type)
            try container.encode(f, forKey: .feature)
        case .capability(let c):
            try container.encode(Kind.capability, forKey: .type)
            try container.encode(c, forKey: .capability)
        case .exists(let p):
            try container.encode(Kind.exists, forKey: .type)
            try container.encode(p, forKey: .preference)
        case .compare(let p, let op, let v):
            try container.encode(Kind.compare, forKey: .type)
            try container.encode(p, forKey: .preference)
            try container.encode(op, forKey: .op)
            try container.encode(v, forKey: .value)
        }
    }
}
