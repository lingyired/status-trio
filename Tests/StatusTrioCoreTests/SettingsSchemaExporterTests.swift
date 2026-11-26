import Foundation
import Testing
@testable import StatusTrioCore

@Suite("Settings schema exporter")
struct SettingsSchemaExporterTests {

    private func exporter() -> SettingsSchemaExporter {
        SettingsSchemaExporter(registry: SettingsSemanticCatalog.makeRegistry(appVersion: "1.0.0"))
    }

    @Test("Export produces the five documented documents")
    func documentsPresent() throws {
        let names = Set(try exporter().documents().map(\.name))
        #expect(names == ["settings-schema.json", "feature-registry.json", "capability-registry.json", "action-registry.json", "dev-profile.schema.json"])
    }

    @Test("Every document is valid JSON")
    func documentsAreValidJSON() throws {
        for document in try exporter().documents() {
            let object = try JSONSerialization.jsonObject(with: document.data)
            #expect(object is [String: Any] || object is [Any], "\(document.name) is not a JSON container")
        }
    }

    @Test("Export is byte-stable across runs")
    func exportIsDeterministic() throws {
        let a = try exporter().documents()
        let b = try exporter().documents()
        #expect(a.map(\.name) == b.map(\.name))
        for (lhs, rhs) in zip(a, b) {
            #expect(lhs.data == rhs.data, "\(lhs.name) changed between runs")
        }
    }

    @Test("Settings schema records schema version and app version")
    func settingsSchemaMetadata() throws {
        let data = try exporter().settingsSchemaData()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["schemaVersion"] as? Int == SettingsSemanticCatalog.currentSchemaVersion)
        #expect(object?["appVersion"] as? String == "1.0.0")
        let preferences = object?["preferences"] as? [[String: Any]]
        #expect((preferences?.count ?? 0) > 0)
    }

    @Test("dev-profile.schema.json is a JSON Schema distinct from settings-schema.json")
    func devProfileSchemaShape() throws {
        let data = try exporter().devProfileSchemaData()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["$schema"] as? String != nil)
        #expect(object?["type"] as? String == "object")
        let properties = object?["properties"] as? [String: Any]
        #expect(properties?["schemaVersion"] != nil)
        #expect(properties?["applyMode"] != nil)
    }

    @Test("Module markdown is generated per module")
    func moduleDocuments() {
        let modules = SettingsSchemaExporter(registry: SettingsSemanticCatalog.makeRegistry()).moduleDocuments()
        #expect(modules.count >= 6)
        #expect(modules.allSatisfy { !$0.markdown.isEmpty })
    }
}
