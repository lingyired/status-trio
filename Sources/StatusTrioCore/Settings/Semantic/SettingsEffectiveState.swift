import Foundation

/// The runtime state of a setting, distinct from its saved value.
///
/// - `active`: saved value is in effect.
/// - `disabled`: explicitly turned off (e.g. a boolean `false`).
/// - `inactive`: saved value exists but is not currently in effect (guard false).
/// - `unavailable`: the environment/hardware cannot support it now.
/// - `overridden`: a higher-priority override is in effect (e.g. accessibility).
/// - `unknown`: a required capability is unknown; never treat as unsupported.
enum SettingsEffectiveState: String, Sendable, CaseIterable {
    case active
    case disabled
    case inactive
    case unavailable
    case overridden
    case unknown
}

/// Supplies capability availability for state evaluation. It must not probe
/// hardware synchronously; a system provider should read existing caches or
/// cheap flags and report `unknown` when it cannot answer.
protocol SettingsCapabilityProvider {
    func availability(for capabilityID: String) -> SettingsCapabilityDescriptor.Availability
}

/// A value-semantics capability provider, useful for tests and for a system
/// provider to publish a snapshot.
struct SettingsCapabilitySnapshot: SettingsCapabilityProvider, Sendable {
    var values: [String: SettingsCapabilityDescriptor.Availability]

    init(_ values: [String: SettingsCapabilityDescriptor.Availability] = [:]) {
        self.values = values
    }

    func availability(for capabilityID: String) -> SettingsCapabilityDescriptor.Availability {
        values[capabilityID] ?? .unknown
    }
}

/// Evaluates the effective state of a preference from a snapshot + capabilities
/// without touching live state.
struct SettingsStateEvaluator {
    let registry: SettingsSemanticRegistry
    let capabilities: SettingsCapabilityProvider

    init(registry: SettingsSemanticRegistry, capabilities: SettingsCapabilityProvider = SettingsCapabilitySnapshot()) {
        self.registry = registry
        self.capabilities = capabilities
    }

    func state(of id: String, in snapshot: SettingsSnapshot) -> SettingsEffectiveState {
        guard let descriptor = registry.preference(id) else { return .unknown }

        if let available = descriptor.availableWhen {
            switch evaluate(available, snapshot) {
            case .some(false): return .unavailable
            case .none: return .unknown
            case .some(true): break
            }
        }
        if let effective = descriptor.effectiveWhen {
            switch evaluate(effective, snapshot) {
            case .some(false): return .inactive
            case .none: return .unknown
            case .some(true): break
            }
        }
        guard let value = snapshot.value(id) else { return .inactive }
        if case .bool(false) = value { return .disabled }
        if let enabled = descriptor.enabledWhen {
            switch evaluate(enabled, snapshot) {
            case .some(false): return .disabled
            case .none: return .unknown
            case .some(true): break
            }
        }
        return .active
    }

    /// All preference states in one pass, sorted by id.
    func states(in snapshot: SettingsSnapshot) -> [String: SettingsEffectiveState] {
        var result: [String: SettingsEffectiveState] = [:]
        for descriptor in registry.listPreferences() {
            result[descriptor.id] = state(of: descriptor.id, in: snapshot)
        }
        return result
    }

    // MARK: - Tri-state condition evaluation

    private func evaluate(_ condition: SettingsCondition, _ snapshot: SettingsSnapshot) -> Bool? {
        switch condition {
        case .allOf(let items):
            var unknown = false
            for item in items {
                switch evaluate(item, snapshot) {
                case .some(false): return false
                case .none: unknown = true
                case .some(true): break
                }
            }
            return unknown ? nil : true
        case .anyOf(let items):
            var unknown = false
            for item in items {
                switch evaluate(item, snapshot) {
                case .some(true): return true
                case .none: unknown = true
                case .some(false): break
                }
            }
            return unknown ? nil : false
        case .not(let inner):
            return evaluate(inner, snapshot).map { !$0 }
        case .equals(let id, let expected):
            return snapshot.value(id).map { $0 == expected } ?? false
        case .contains(let id, let expected):
            if case .array(let items)? = snapshot.value(id) { return items.contains(expected) }
            return false
        case .exists(let id):
            return snapshot.value(id) != nil
        case .compare(let id, let op, let expected):
            guard case .number(let lhs)? = snapshot.value(id), case .number(let rhs) = expected else { return false }
            return op.evaluate(lhs, rhs)
        case .featureEnabled(let id):
            if snapshot.enabledFeatures.contains(id) { return true }
            if let feature = registry.feature(id) { return featureSatisfied(feature, snapshot) }
            return false
        case .capability(let id):
            switch capabilities.availability(for: id) {
            case .available: return true
            case .unavailable: return false
            case .unknown: return nil
            }
        }
    }

    private func featureSatisfied(_ feature: SettingsFeatureDescriptor, _ snapshot: SettingsSnapshot) -> Bool {
        for mutation in feature.mutations where mutation.operation == .set {
            if let expected = mutation.value, snapshot.value(mutation.id) != expected { return false }
        }
        return true
    }
}
