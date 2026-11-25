import Foundation

/// A read-only view of current settings keyed by logical preference id.
///
/// The planner never touches UserDefaults; it receives a snapshot and returns a
/// plan. A later service layer supplies the snapshot and commits the plan.
struct SettingsSnapshot: Sendable, Equatable {
    var values: [String: SettingsTransferValue]
    /// Features the caller has already declared/observed as enabled.
    var enabledFeatures: Set<String>

    init(values: [String: SettingsTransferValue] = [:], enabledFeatures: Set<String> = []) {
        self.values = values
        self.enabledFeatures = enabledFeatures
    }

    func value(_ id: String) -> SettingsTransferValue? { values[id] }
}

/// A problem found while planning a change.
struct SettingsPlanIssue: Equatable, Sendable, CustomStringConvertible {
    enum Severity: String, Sendable { case error, warning }
    var severity: Severity
    var message: String
    var preferenceID: String? = nil

    var description: String {
        let prefix = severity == .error ? "ERROR" : "WARN"
        if let p = preferenceID { return "[\(prefix)] \(p): \(message)" }
        return "[\(prefix)] \(message)"
    }
}

/// Why an operation is in the plan.
enum SettingsOperationSource: String, Sendable, Equatable {
    /// Directly requested by the caller.
    case requested
    /// Added because a required parent feature must be enabled first.
    case dependency
    /// Added by a connected `onChange` rule (e.g. bold-text weight pair).
    case connected
    /// Added by constraint resolution (e.g. dual-ring primary/secondary swap).
    case constraint
}

struct SettingsPlannedOperation: Equatable, Sendable {
    var preferenceID: String
    /// Always `.set` for the normalized plan, except collection edits which keep
    /// their `add`/`remove` operation when the caller issued one.
    var operation: SettingsMutationDescriptor.Operation
    var value: SettingsTransferValue?
    var source: SettingsOperationSource
}

/// The deterministic result of planning a change against a state.
struct SettingsChangePlan: Sendable, Equatable {
    var operations: [SettingsPlannedOperation]
    var issues: [SettingsPlanIssue]

    var isApplicable: Bool { !issues.contains { $0.severity == .error } }
    var errors: [SettingsPlanIssue] { issues.filter { $0.severity == .error } }
}

/// Pure planner: resolves feature dependencies, connected `onChange` rules and
/// value/constraint conflicts into a deterministic change plan without touching
/// live state. Applying the plan is the service layer's job.
struct SettingsPlanner {
    let registry: SettingsSemanticRegistry

    init(registry: SettingsSemanticRegistry) {
        self.registry = registry
    }

    // MARK: - Public entry points

    func plan(enableFeature id: String, snapshot state: SettingsSnapshot) -> SettingsChangePlan {
        guard registry.feature(id) != nil else {
            return SettingsChangePlan(operations: [], issues: [
                .init(severity: .error, message: "未知功能：\(id)")
            ])
        }
        let ordered = featureClosure(target: id)
        var requests: [(SettingsMutationDescriptor, SettingsOperationSource)] = []
        for featureID in ordered {
            guard let feature = registry.feature(featureID) else { continue }
            let source: SettingsOperationSource = featureID == id ? .requested : .dependency
            for mutation in feature.mutations { requests.append((mutation, source)) }
        }
        return finalize(requests: requests, snapshot: state)
    }

    func plan(setPreference id: String, to value: SettingsTransferValue, snapshot state: SettingsSnapshot) -> SettingsChangePlan {
        guard registry.preference(id) != nil else {
            return SettingsChangePlan(operations: [], issues: [
                .init(severity: .error, message: "未知设置：\(id)", preferenceID: id)
            ])
        }
        let request = SettingsMutationDescriptor(id: id, operation: .set, value: value)
        return finalize(requests: [(request, .requested)], snapshot: state)
    }

    func plan(mutations: [SettingsMutationDescriptor], snapshot state: SettingsSnapshot) -> SettingsChangePlan {
        finalize(requests: mutations.map { ($0, .requested) }, snapshot: state)
    }

    /// Plan a combined change: enable features (with their dependency closure),
    /// set individual preferences, and apply explicit collection mutations.
    /// This is the entry point a development profile uses.
    func plan(
        features: [String],
        preferences: [String: SettingsTransferValue],
        mutations: [SettingsMutationDescriptor],
        snapshot state: SettingsSnapshot
    ) -> SettingsChangePlan {
        var requests: [(SettingsMutationDescriptor, SettingsOperationSource)] = []
        var seenFeatures = Set<String>()
        for root in features {
            for featureID in featureClosure(target: root) {
                guard seenFeatures.insert(featureID).inserted else { continue }
                guard let feature = registry.feature(featureID) else { continue }
                let source: SettingsOperationSource = featureID == root ? .requested : .dependency
                for mutation in feature.mutations { requests.append((mutation, source)) }
            }
        }
        for id in preferences.keys.sorted() {
            let value = preferences[id]!
            requests.append((SettingsMutationDescriptor(id: id, operation: .set, value: value), .requested))
        }
        for mutation in mutations { requests.append((mutation, .requested)) }
        return finalize(requests: requests, snapshot: state)
    }

    // MARK: - Feature dependency closure

    /// Parents before children, deduplicated, cycle-tolerant.
    private func featureClosure(target: String) -> [String] {
        var order: [String] = []
        var visiting = Set<String>()
        var visited = Set<String>()

        func visit(_ id: String) {
            if visited.contains(id) { return }
            if visiting.contains(id) { return }  // cycle: stop, not fatal here
            visiting.insert(id)
            if let feature = registry.feature(id) {
                for parent in feature.requires { visit(parent) }
            }
            visiting.remove(id)
            visited.insert(id)
            order.append(id)
        }

        visit(target)
        return order
    }

    // MARK: - Core pipeline

    private func finalize(
        requests: [(SettingsMutationDescriptor, SettingsOperationSource)],
        snapshot state: SettingsSnapshot
    ) -> SettingsChangePlan {
        var issues: [SettingsPlanIssue] = []
        var candidate = state.values
        var sources: [String: SettingsOperationSource] = [:]
        var requestedCollections: [String: SettingsMutationDescriptor.Operation] = [:]

        // 1. Apply the base requests in order.
        for (mutation, source) in requests {
            guard let descriptor = registry.preference(mutation.id) else {
                issues.append(.init(severity: .error, message: "未知设置：\(mutation.id)", preferenceID: mutation.id))
                continue
            }
            if let issue = validateType(mutation.value, for: descriptor) {
                issues.append(issue)
            }
            apply(mutation, to: &candidate)
            sources[mutation.id] = source
            if mutation.operation == .add || mutation.operation == .remove {
                requestedCollections[mutation.id] = mutation.operation
            }
        }

        // 2. Expand connected `onChange` rules (bounded, loop-safe).
        expandConnectedRules(&candidate, snapshot: state, sources: &sources, issues: &issues)

        // 3. Resolve constraints on changed preferences.
        resolveConstraints(&candidate, snapshot: state, sources: &sources, issues: &issues)

        // 4. Validate ranges/types of the resulting values for changed prefs.
        for (id, value) in candidate where value != state.value(id) {
            guard let descriptor = registry.preference(id) else { continue }
            if let issue = validateRange(value, for: descriptor) {
                issues.append(issue)
            }
        }

        // 5. Emit a deterministic diff (sorted by preference id).
        var operations: [SettingsPlannedOperation] = []
        for id in candidate.keys.sorted() {
            guard let newValue = candidate[id] else { continue }
            if newValue == state.value(id) { continue }
            let op = requestedCollections[id] == .remove ? SettingsMutationDescriptor.Operation.remove : .set
            operations.append(SettingsPlannedOperation(
                preferenceID: id,
                operation: op,
                value: newValue,
                source: sources[id] ?? .requested
            ))
        }

        return SettingsChangePlan(operations: operations, issues: issues)
    }

    // MARK: - Connected rules

    private func expandConnectedRules(
        _ candidate: inout [String: SettingsTransferValue],
        snapshot state: SettingsSnapshot,
        sources: inout [String: SettingsOperationSource],
        issues: inout [SettingsPlanIssue]
    ) {
        var expanded = Set<String>()
        var queue = candidate.keys.filter { candidate[$0] != state.value($0) }
        var guardCount = 0
        while let id = queue.popLast(), guardCount < 512 {
            guardCount += 1
            guard !expanded.contains(id) else { continue }
            expanded.insert(id)
            guard let descriptor = registry.preference(id), let rules = descriptor.onChange else { continue }
            let triggerValue = candidate[id]
            for rule in rules {
                // A `nil` mutation value mirrors the triggering value (virtual toggles).
                let resolvedValue = rule.value ?? triggerValue
                let mutation = SettingsMutationDescriptor(id: rule.id, operation: rule.operation, value: resolvedValue)
                if registry.preference(rule.id) == nil {
                    issues.append(.init(severity: .error, message: "onChange 指向未知设置：\(rule.id)", preferenceID: id))
                    continue
                }
                apply(mutation, to: &candidate)
                if sources[rule.id] == nil { sources[rule.id] = .connected }
                if candidate[rule.id] != state.value(rule.id) { queue.append(rule.id) }
            }
        }
    }

    // MARK: - Constraints

    private func resolveConstraints(
        _ candidate: inout [String: SettingsTransferValue],
        snapshot state: SettingsSnapshot,
        sources: inout [String: SettingsOperationSource],
        issues: inout [SettingsPlanIssue]
    ) {
        for descriptor in registry.preferences {
            guard candidate[descriptor.id] != nil,
                  candidate[descriptor.id] != state.value(descriptor.id),
                  let constraints = descriptor.constraints else { continue }
            for constraint in constraints {
                if let when = constraint.when, !conditionHolds(when, candidate) { continue }
                switch constraint.kind {
                case .distinctValues:
                    guard let other = constraint.other,
                          candidate[descriptor.id] == candidate[other] else { break }
                    switch constraint.resolution {
                    case .swap:
                        // The other slot takes this setting's previous value.
                        candidate[other] = state.value(descriptor.id)
                        sources[other] = .constraint
                    default:
                        issues.append(.init(severity: .error, message: constraint.message ?? "值必须与 \(other) 不同", preferenceID: descriptor.id))
                    }
                case .minimumCount:
                    if let min = constraint.min, arrayCount(candidate[descriptor.id]) < min {
                        issues.append(.init(severity: .error, message: constraint.message ?? "至少保留 \(min) 项", preferenceID: descriptor.id))
                    }
                case .maximumCount:
                    if let max = constraint.max, arrayCount(candidate[descriptor.id]) > max {
                        issues.append(.init(severity: .error, message: constraint.message ?? "最多 \(max) 项", preferenceID: descriptor.id))
                    }
                case .requires:
                    if let other = constraint.other, !isTruthy(candidate[other]) {
                        issues.append(.init(severity: .error, message: constraint.message ?? "需要先启用 \(other)", preferenceID: descriptor.id))
                    }
                case .numericRange:
                    if let min = constraint.min, let max = constraint.max, let number = numericValue(candidate[descriptor.id]),
                       Double(number) < Double(min) || Double(number) > Double(max) {
                        issues.append(.init(severity: .error, message: constraint.message ?? "数值超出范围", preferenceID: descriptor.id))
                    }
                case .conflicts, .custom:
                    break
                }
            }
        }
    }

    // MARK: - Application helpers

    private func apply(_ mutation: SettingsMutationDescriptor, to candidate: inout [String: SettingsTransferValue]) {
        switch mutation.operation {
        case .set, .merge, .move:
            if let value = mutation.value {
                candidate[mutation.id] = value
            }
        case .reset:
            candidate[mutation.id] = registry.preference(mutation.id)?.defaultValue
        case .add:
            var items = arrayValues(candidate[mutation.id])
            if let value = mutation.value, !items.contains(value) { items.append(value) }
            candidate[mutation.id] = .array(items)
        case .remove:
            var items = arrayValues(candidate[mutation.id])
            if let value = mutation.value { items.removeAll { $0 == value } }
            candidate[mutation.id] = .array(items)
        }
    }

    // MARK: - Validation

    private func validateType(_ value: SettingsTransferValue?, for descriptor: SettingsPreferenceDescriptor) -> SettingsPlanIssue? {
        guard let value else { return nil }
        if value == .null { return nil }
        let ok: Bool
        switch descriptor.type {
        case .boolean: if case .bool = value { ok = true } else { ok = false }
        case .integer: if case .number(let n) = value { ok = n.rounded() == n } else { ok = false }
        case .number: if case .number = value { ok = true } else { ok = false }
        case .string, .enumeration, .color, .deviceReference, .pluginReference, .taggedUnion:
            if case .string = value { ok = true } else { ok = false }
        case .set, .orderedList:
            if case .array = value { ok = true } else { ok = false }
        case .map, .object:
            if case .object = value { ok = true } else { ok = false }
        case .nullable: ok = true
        }
        return ok ? nil : .init(severity: .error, message: "类型不匹配（期望 \(descriptor.type.rawValue)）", preferenceID: descriptor.id)
    }

    private func validateRange(_ value: SettingsTransferValue, for descriptor: SettingsPreferenceDescriptor) -> SettingsPlanIssue? {
        guard let range = descriptor.range, let number = numericValue(value) else { return nil }
        let double = Double(number)
        if double < range.min || double > range.max {
            return .init(severity: .error, message: "数值 \(number) 超出范围 \(range.min)...\(range.max)", preferenceID: descriptor.id)
        }
        return nil
    }

    // MARK: - Value helpers

    private func arrayValues(_ value: SettingsTransferValue?) -> [SettingsTransferValue] {
        if case .array(let items)? = value { return items }
        return []
    }

    private func arrayCount(_ value: SettingsTransferValue?) -> Int {
        if case .array(let items)? = value { return items.count }
        return 0
    }

    private func numericValue(_ value: SettingsTransferValue?) -> Double? {
        if case .number(let n)? = value { return n }
        return nil
    }

    private func isTruthy(_ value: SettingsTransferValue?) -> Bool {
        if case .bool(true)? = value { return true }
        if case .number(let n)? = value { return n != 0 }
        if case .array(let items)? = value { return !items.isEmpty }
        return false
    }

    // MARK: - Condition evaluation (for constraint guards)

    private func conditionHolds(_ condition: SettingsCondition, _ values: [String: SettingsTransferValue]) -> Bool {
        evaluate(condition, values) ?? true  // unknown capability does not block planning
    }

    private func evaluate(_ condition: SettingsCondition, _ values: [String: SettingsTransferValue]) -> Bool? {
        switch condition {
        case .allOf(let xs):
            var unknown = false
            for x in xs {
                switch evaluate(x, values) {
                case .some(false): return false
                case .none: unknown = true
                case .some(true): break
                }
            }
            return unknown ? nil : true
        case .anyOf(let xs):
            var unknown = false
            for x in xs {
                switch evaluate(x, values) {
                case .some(true): return true
                case .none: unknown = true
                case .some(false): break
                }
            }
            return unknown ? nil : false
        case .not(let x):
            return evaluate(x, values).map { !$0 }
        case .equals(let p, let v):
            guard let current = values[p] else { return false }
            return current == v
        case .contains(let p, let v):
            if case .array(let items)? = values[p] { return items.contains(v) }
            return false
        case .exists(let p):
            return values[p] != nil
        case .compare(let p, let op, let v):
            guard let lhs = numericValue(values[p]), case .number(let rhs) = v else { return false }
            return op.evaluate(lhs, rhs)
        case .featureEnabled(let id):
            guard let feature = registry.feature(id) else { return false }
            return featureSatisfied(feature, values)
        case .capability:
            return nil
        }
    }

    private func featureSatisfied(_ feature: SettingsFeatureDescriptor, _ values: [String: SettingsTransferValue]) -> Bool {
        for mutation in feature.mutations {
            if mutation.operation == .set, let expected = mutation.value {
                if values[mutation.id] != expected { return false }
            }
        }
        return true
    }
}
