import Foundation

/// Deterministically exports the semantic registry to JSON artifacts used by
/// documentation and the `status-trio-settings` agent skill.
///
/// The exporter never reads UserDefaults, probes hardware or touches the
/// network. All output is sorted by id/key so repeated exports are byte-stable.
struct SettingsSchemaExporter {
    let registry: SettingsSemanticRegistry

    init(registry: SettingsSemanticRegistry) {
        self.registry = registry
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    struct SettingsSchemaDocument: Encodable {
        let schemaVersion: Int
        let appVersion: String?
        let preferences: [SettingsPreferenceDescriptor]
    }

    struct FeatureRegistryDocument: Encodable {
        let schemaVersion: Int
        let features: [SettingsFeatureDescriptor]
    }

    struct CapabilityRegistryDocument: Encodable {
        let schemaVersion: Int
        let capabilities: [SettingsCapabilityDescriptor]
    }

    struct ActionRegistryDocument: Encodable {
        let schemaVersion: Int
        let actions: [SettingsActionDescriptor]
    }

    func settingsSchemaData() throws -> Data {
        try encoder().encode(SettingsSchemaDocument(
            schemaVersion: registry.schemaVersion,
            appVersion: registry.appVersion,
            preferences: registry.listPreferences()
        ))
    }

    func featureRegistryData() throws -> Data {
        try encoder().encode(FeatureRegistryDocument(schemaVersion: registry.schemaVersion, features: registry.listFeatures()))
    }

    func capabilityRegistryData() throws -> Data {
        try encoder().encode(CapabilityRegistryDocument(schemaVersion: registry.schemaVersion, capabilities: registry.listCapabilities()))
    }

    func actionRegistryData() throws -> Data {
        try encoder().encode(ActionRegistryDocument(schemaVersion: registry.schemaVersion, actions: registry.listActions()))
    }

    /// JSON Schema (draft 2020-12) describing the `.dev-profile.json` structure.
    /// Kept distinct from `settings-schema.json`, which describes settings.
    func devProfileSchemaData() throws -> Data {
        let schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "title": "Status Trio Development Test Profile",
            "description": "Per-worktree development test profile applied at launch.",
            "type": "object",
            "required": ["schemaVersion"],
            "additionalProperties": false,
            "properties": [
                "schemaVersion": [
                    "type": "integer", "minimum": 1,
                    "description": "Profile schema version; must be <= the app's supported version.",
                ],
                "features": [
                    "type": "array", "items": ["type": "string"],
                    "description": "Feature ids to enable (parents are enabled automatically).",
                ],
                "preferences": [
                    "type": "object", "additionalProperties": true,
                    "description": "Exact preference overrides keyed by logical id.",
                ],
                "mutations": [
                    "type": "array", "items": ["type": "object"],
                    "description": "Collection/local mutations: {id, operation, value}.",
                ],
                "applyMode": [
                    "type": "string", "enum": ["onLaunch", "firstLaunch", "manual"],
                    "description": "When to apply; only onLaunch is implemented in this phase.",
                ],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    func documents() throws -> [(name: String, data: Data)] {
        [
            ("settings-schema.json", try settingsSchemaData()),
            ("feature-registry.json", try featureRegistryData()),
            ("capability-registry.json", try capabilityRegistryData()),
            ("action-registry.json", try actionRegistryData()),
            ("dev-profile.schema.json", try devProfileSchemaData()),
        ]
    }

    /// One Markdown reference per module, generated from the registry so the
    /// skill docs never drift from the code.
    func moduleDocuments() -> [(module: String, markdown: String)] {
        let grouped = Dictionary(grouping: registry.listPreferences(), by: { $0.category })
        return grouped.keys.sorted().map { category in
            (category, Self.moduleMarkdown(module: category, preferences: grouped[category] ?? []))
        }
    }

    static func moduleMarkdown(module: String, preferences: [SettingsPreferenceDescriptor]) -> String {
        var lines: [String] = []
        lines.append("# Module: \(module)")
        lines.append("")
        lines.append("Generated from `SettingsSemanticCatalog`. Do not edit by hand.")
        lines.append("")
        lines.append("| id | title | type | default | storage key |")
        lines.append("|---|---|---|---|---|")
        for pref in preferences.sorted(by: { $0.id < $1.id }) {
            let def = pref.defaultValue.map(describe) ?? "—"
            let key = pref.storageKey ?? (pref.provider == "core" ? "—" : "(\(pref.provider ?? "virtual"))")
            lines.append("| `\(pref.id)` | \(pref.title) | `\(pref.type.rawValue)` | \(def) | \(key) |")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func describe(_ value: SettingsTransferValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let flag): return "\(flag)"
        case .number(let number): return "\(number)"
        case .string(let string): return "`\(string)`"
        case .array(let items): return "[\(items.count)]"
        case .object: return "{}"
        }
    }

    /// Write all documents plus per-module Markdown into a directory. Returns the
    /// written file URLs.
    @discardableResult
    func write(to directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        for document in try documents() {
            let url = directory.appendingPathComponent(document.name)
            try document.data.write(to: url)
            written.append(url)
        }
        let modulesDirectory = directory.appendingPathComponent("modules")
        try fileManager.createDirectory(at: modulesDirectory, withIntermediateDirectories: true)
        for document in moduleDocuments() {
            let url = modulesDirectory.appendingPathComponent("\(document.module).md")
            try Data(document.markdown.utf8).write(to: url)
            written.append(url)
        }
        return written
    }
}
