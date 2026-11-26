import Foundation
import Testing
@testable import StatusTrioCore

/// Guards the committed skill/reference artifacts against drifting from the
/// semantic catalog. `SettingsSchemaExporterTests` only checks that an in-memory
/// export is deterministic; this compares the on-disk files the skill reads with
/// a fresh export, so a catalog change without regeneration fails here.
@Suite("Settings schema artifacts stay in sync with the catalog")
struct SettingsSchemaArtifactConsistencyTests {
    /// `Tests/StatusTrioCoreTests/<file>` → repository root.
    private static var referencesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // StatusTrioCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
            .appendingPathComponent(".agents/skills/status-trio-settings/references")
    }

    /// The committed schema records the release the artifacts were generated
    /// for. Reuse it so a version bump that regenerates the files still matches.
    private func committedAppVersion() throws -> String? {
        let url = Self.referencesDirectory.appendingPathComponent("settings-schema.json")
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["appVersion"] as? String
    }

    @Test("Committed JSON documents match a fresh export")
    func jsonDocumentsMatchExport() throws {
        let exporter = SettingsSchemaExporter(
            registry: SettingsSemanticCatalog.makeRegistry(appVersion: try committedAppVersion())
        )
        for document in try exporter.documents() {
            let url = Self.referencesDirectory.appendingPathComponent(document.name)
            let committed = try Data(contentsOf: url)
            #expect(
                committed == document.data,
                "\(document.name) is stale; regenerate the settings skill references."
            )
        }
    }

    @Test("Committed per-module Markdown matches a fresh export")
    func moduleDocumentsMatchExport() throws {
        let exporter = SettingsSchemaExporter(
            registry: SettingsSemanticCatalog.makeRegistry(appVersion: try committedAppVersion())
        )
        for module in exporter.moduleDocuments() {
            let url = Self.referencesDirectory
                .appendingPathComponent("modules/\(module.module).md")
            let committed = try String(contentsOf: url, encoding: .utf8)
            #expect(
                committed == module.markdown,
                "modules/\(module.module).md is stale; regenerate the settings skill references."
            )
        }
    }
}
