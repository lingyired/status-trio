import Foundation

/// An immutable, queryable catalog of settings semantics.
///
/// The registry is pure data: it never reads UserDefaults, never probes hardware
/// and never mutates state. It is sorted by id so listing and export are
/// deterministic regardless of authoring order.
struct SettingsSemanticRegistry: Sendable {
    var schemaVersion: Int
    var appVersion: String?
    var preferences: [SettingsPreferenceDescriptor]
    var features: [SettingsFeatureDescriptor]
    var capabilities: [SettingsCapabilityDescriptor]
    var actions: [SettingsActionDescriptor]

    private var preferenceIndex: [String: SettingsPreferenceDescriptor] = [:]
    private var featureIndex: [String: SettingsFeatureDescriptor] = [:]
    private var capabilityIndex: [String: SettingsCapabilityDescriptor] = [:]
    private var actionIndex: [String: SettingsActionDescriptor] = [:]

    init(
        schemaVersion: Int = 1,
        appVersion: String? = nil,
        preferences: [SettingsPreferenceDescriptor],
        features: [SettingsFeatureDescriptor] = [],
        capabilities: [SettingsCapabilityDescriptor] = [],
        actions: [SettingsActionDescriptor] = []
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.preferences = preferences.sorted { $0.id < $1.id }
        self.features = features.sorted { $0.id < $1.id }
        self.capabilities = capabilities.sorted { $0.id < $1.id }
        self.actions = actions.sorted { $0.id < $1.id }
        self.preferenceIndex = Dictionary(self.preferences.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.featureIndex = Dictionary(self.features.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.capabilityIndex = Dictionary(self.capabilities.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.actionIndex = Dictionary(self.actions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Lookup

    func preference(_ id: String) -> SettingsPreferenceDescriptor? { preferenceIndex[id] }
    func feature(_ id: String) -> SettingsFeatureDescriptor? { featureIndex[id] }
    func capability(_ id: String) -> SettingsCapabilityDescriptor? { capabilityIndex[id] }
    func action(_ id: String) -> SettingsActionDescriptor? { actionIndex[id] }

    func listPreferences() -> [SettingsPreferenceDescriptor] { preferences }
    func listFeatures() -> [SettingsFeatureDescriptor] { features }
    func listCapabilities() -> [SettingsCapabilityDescriptor] { capabilities }
    func listActions() -> [SettingsActionDescriptor] { actions }

    var preferenceIDs: Set<String> { Set(preferences.map(\.id)) }
    var featureIDs: Set<String> { Set(features.map(\.id)) }
    var capabilityIDs: Set<String> { Set(capabilities.map(\.id)) }
    var actionIDs: Set<String> { Set(actions.map(\.id)) }

    // MARK: - Validation

    /// Structural validation of the registry itself: unique ids, resolvable
    /// references, and acyclic feature dependencies. Deterministic order.
    func validate() -> [SettingsSemanticIssue] {
        var issues: [SettingsSemanticIssue] = []

        appendDuplicates(preferences.map(\.id), kind: .duplicatePreferenceID, into: &issues)
        appendDuplicates(features.map(\.id), kind: .duplicateFeatureID, into: &issues)
        appendDuplicates(capabilities.map(\.id), kind: .duplicateCapabilityID, into: &issues)
        appendDuplicates(actions.map(\.id), kind: .duplicateActionID, into: &issues)

        let prefIDs = preferenceIDs
        let featIDs = featureIDs
        let capIDs = capabilityIDs

        func checkCondition(_ condition: SettingsCondition, owner: String) {
            for p in condition.referencedPreferences.sorted() where !prefIDs.contains(p) {
                issues.append(.init(kind: .unknownPreferenceReference, detail: "\(owner) condition -> \(p)"))
            }
            for f in condition.referencedFeatures.sorted() where !featIDs.contains(f) {
                issues.append(.init(kind: .unknownFeatureReference, detail: "\(owner) condition -> feature \(f)"))
            }
            for c in condition.referencedCapabilities.sorted() where !capIDs.contains(c) {
                issues.append(.init(kind: .unknownCapabilityReference, detail: "\(owner) condition -> capability \(c)"))
            }
        }

        for p in preferences {
            for r in (p.requires ?? []) where !prefIDs.contains(r) {
                issues.append(.init(kind: .unknownPreferenceReference, detail: "\(p.id) requires -> \(r)"))
            }
            for r in (p.conflictsWith ?? []) where !prefIDs.contains(r) {
                issues.append(.init(kind: .unknownPreferenceReference, detail: "\(p.id) conflictsWith -> \(r)"))
            }
            if let replaced = p.replacedBy, !prefIDs.contains(replaced) {
                issues.append(.init(kind: .unknownPreferenceReference, detail: "\(p.id) replacedBy -> \(replaced)"))
            }
            for m in (p.onChange ?? []) where !prefIDs.contains(m.id) {
                issues.append(.init(kind: .unknownPreferenceReference, detail: "\(p.id) onChange -> \(m.id)"))
            }
            for c in (p.constraints ?? []) {
                if let other = c.other, !prefIDs.contains(other) {
                    issues.append(.init(kind: .unknownPreferenceReference, detail: "\(p.id) constraint -> \(other)"))
                }
                if let when = c.when { checkCondition(when, owner: p.id) }
            }
            for condition in [p.visibleWhen, p.enabledWhen, p.effectiveWhen, p.availableWhen].compactMap({ $0 }) {
                checkCondition(condition, owner: p.id)
            }
        }

        for f in features {
            for r in f.requires where !featIDs.contains(r) {
                issues.append(.init(kind: .unknownFeatureReference, detail: "\(f.id) requires -> \(r)"))
            }
            for r in f.preferences where !prefIDs.contains(r) {
                issues.append(.init(kind: .unknownPreferenceReference, detail: "\(f.id) preferences -> \(r)"))
            }
            for m in f.mutations where !prefIDs.contains(m.id) {
                issues.append(.init(kind: .unknownPreferenceReference, detail: "\(f.id) mutation -> \(m.id)"))
            }
        }

        issues.append(contentsOf: detectFeatureCycles())
        return issues
    }

    /// Depth-first search over feature `requires` edges; reports each cycle once.
    private func detectFeatureCycles() -> [SettingsSemanticIssue] {
        var issues: [SettingsSemanticIssue] = []
        var visiting = Set<String>()
        var visited = Set<String>()

        func visit(_ id: String, path: [String]) {
            if visited.contains(id) { return }
            if visiting.contains(id) {
                issues.append(.init(kind: .cyclicFeatureDependency, detail: (path + [id]).joined(separator: " -> ")))
                return
            }
            visiting.insert(id)
            if let feature = featureIndex[id] {
                for parent in feature.requires {
                    visit(parent, path: path + [id])
                }
            }
            visiting.remove(id)
            visited.insert(id)
        }

        for feature in features { visit(feature.id, path: []) }
        return issues
    }

    private func appendDuplicates(
        _ ids: [String],
        kind: SettingsSemanticIssue.Kind,
        into issues: inout [SettingsSemanticIssue]
    ) {
        var seen = Set<String>()
        var reported = Set<String>()
        for id in ids {
            if seen.contains(id), !reported.contains(id) {
                issues.append(.init(kind: kind, detail: id))
                reported.insert(id)
            }
            seen.insert(id)
        }
    }
}
