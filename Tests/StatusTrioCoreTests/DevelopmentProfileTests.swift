import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
private final class ProfileTestProvider: SettingsStateProvider {
    var values: [String: SettingsTransferValue] = [:]
    func value(for id: String) -> SettingsTransferValue? { values[id] }
    func setValue(_ value: SettingsTransferValue, for id: String) { values[id] = value }
    func removeValue(for id: String) { values.removeValue(forKey: id) }
    func isFeatureEnabled(_ id: String) -> Bool { false }
}

@MainActor
@Suite("Development test profile")
struct DevelopmentProfileTests {

    private func service() -> (SettingsService, ProfileTestProvider) {
        let provider = ProfileTestProvider()
        return (SettingsService(registry: SettingsSemanticCatalog.makeRegistry(), provider: provider), provider)
    }

    private func writeTemp(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dev-profile-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("A valid onLaunch profile applies its features and preferences")
    func validProfileApplies() throws {
        let (service, provider) = service()
        let url = try writeTemp(#"{"schemaVersion":1,"features":["hardware.panel.gpu.temperature"],"preferences":{"panel.appearance.backgroundStyle":"solid"},"applyMode":"onLaunch"}"#)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = DevelopmentProfileBootstrap.run(profileURL: url, service: service)
        #expect(result.applied)
        #expect(provider.value(for: "hardware.temperature.enabled") == .bool(true))
        #expect(provider.value(for: "panel.appearance.backgroundStyle") == .string("solid"))
        #expect(!result.log.isEmpty)
    }

    @Test("Unsupported schema version is rejected without writing")
    func unsupportedSchemaRejected() throws {
        let (service, provider) = service()
        let url = try writeTemp(#"{"schemaVersion":99,"features":["panel.hardware"]}"#)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = DevelopmentProfileBootstrap.run(profileURL: url, service: service)
        guard case .rejected(let issues) = result.outcome else {
            Issue.record("expected rejection")
            return
        }
        #expect(issues.contains { $0.kind == .unsupportedSchemaVersion })
        #expect(provider.values.isEmpty)
    }

    @Test("Unknown feature is rejected")
    func unknownFeatureRejected() throws {
        let (service, _) = service()
        let url = try writeTemp(#"{"schemaVersion":1,"features":["no.such.feature"]}"#)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = DevelopmentProfileBootstrap.run(profileURL: url, service: service)
        guard case .rejected(let issues) = result.outcome else {
            Issue.record("expected rejection")
            return
        }
        #expect(issues.contains { $0.kind == .unknownFeature })
    }

    @Test("Restricted preferences are not allowed in a profile")
    func restrictedPreferenceRejected() throws {
        let (service, provider) = service()
        let url = try writeTemp(#"{"schemaVersion":1,"preferences":{"general.launchAtLogin":true}}"#)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = DevelopmentProfileBootstrap.run(profileURL: url, service: service)
        guard case .rejected(let issues) = result.outcome else {
            Issue.record("expected rejection")
            return
        }
        #expect(issues.contains { $0.kind == .preferenceNotAllowedInProfile })
        #expect(provider.values.isEmpty)
    }

    @Test("Non-onLaunch apply mode is skipped")
    func manualModeSkipped() throws {
        let (service, provider) = service()
        let url = try writeTemp(#"{"schemaVersion":1,"features":["panel.hardware"],"applyMode":"manual"}"#)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = DevelopmentProfileBootstrap.run(profileURL: url, service: service)
        guard case .skipped(let mode) = result.outcome else {
            Issue.record("expected skip")
            return
        }
        #expect(mode == .manual)
        #expect(provider.values.isEmpty)
    }

    @Test("Missing profile is a no-op")
    func missingProfileNoOp() {
        let (service, _) = service()
        let result = DevelopmentProfileBootstrap.run(profileURL: nil, service: service)
        guard case .noProfile = result.outcome else {
            Issue.record("expected noProfile")
            return
        }
    }

    @Test("Partial JSON decodes with defaults")
    func partialJSONDecodesWithDefaults() throws {
        let profile = try JSONDecoder().decode(DevelopmentTestProfile.self, from: Data("{}".utf8))
        #expect(profile.schemaVersion == 1)
        #expect(profile.features.isEmpty)
        #expect(profile.preferences.isEmpty)
        #expect(profile.applyMode == .onLaunch)
    }

    @Test("Malformed JSON fails to load cleanly")
    func malformedJSONReportsLoadFailure() throws {
        let (service, _) = service()
        let url = try writeTemp("{ not json ")
        defer { try? FileManager.default.removeItem(at: url) }
        let result = DevelopmentProfileBootstrap.run(profileURL: url, service: service)
        guard case .loadFailed = result.outcome else {
            Issue.record("expected loadFailed")
            return
        }
    }
}
