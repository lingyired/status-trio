import Foundation
import Testing
@testable import StatusTrioCore

struct MobileBatterySnapshotTests {
    @Test func decodesMetadataOnlyDiscoveryIntoSourceQualifiedCandidates() throws {
        let json = Data(#"{"schemaVersion":1,"candidates":[{"id":"ipad-1","name":"Tablet","model":"iPad14,3","transport":"usb","trustRequired":false},{"id":"watch-1","parentID":"phone-1","name":"Watch","model":"Watch7,4","transport":"network","trustRequired":false}],"failures":[]}"#.utf8)
        let candidates = try MobileBatteryWire.decodeDiscovery(json, expectedParentID: "phone-1")
        #expect(candidates.map(\.id) == [.trustedDevice("ipad-1"), .trustedWatch(parentID: "phone-1", id: "watch-1")])
        #expect(candidates[0].evidence == .verifiedAppleModel)
        #expect(candidates[1].evidence == .verifiedAppleModel)
        let selectable = candidates.map { $0.isVerifiedTrustedAppleDevice }
        #expect(selectable == [true, true])
    }

    @Test func discoveryRejectsForeignParentAndDoesNotInferAppleFromName() throws {
        let json = Data(#"{"schemaVersion":1,"candidates":[{"id":"watch-1","parentID":"other-phone","name":"Apple Watch","model":"Watch7,4","transport":"usb","trustRequired":false},{"id":"unknown","name":"iPhone","model":"Unknown,1","transport":"network","trustRequired":false}],"failures":[]}"#.utf8)
        let candidates = try MobileBatteryWire.decodeDiscovery(json, expectedParentID: "phone-1")
        #expect(candidates.isEmpty)
    }

    @Test func discoveryRejectsUnsupportedSchemaAndDeduplicatesCandidates() throws {
        let duplicate = #"{"schemaVersion":1,"candidates":[{"id":"p","name":"Phone","model":"iPhone18,1","transport":"usb","trustRequired":false},{"id":"p","name":"Other","model":"iPhone18,1","transport":"network","trustRequired":false}],"failures":[]}"#
        let decoded = try MobileBatteryWire.decodeDiscovery(Data(duplicate.utf8), expectedParentID: "p")
        #expect(decoded.count == 1)
        #expect(throws: (any Error).self) {
            try MobileBatteryWire.decodeDiscovery(Data(#"{"schemaVersion":2,"candidates":[],"failures":[]}"#.utf8), expectedParentID: nil)
        }
    }

    @Test func discoveryRejectsBatteryFieldsInMetadataEnvelope() throws {
        let json = #"{"schemaVersion":1,"candidates":[{"id":"phone-1","model":"iPhone18,1","transport":"usb","trustRequired":false,"batteryLevel":73}],"failures":[]}"#
        let decoded = try MobileBatteryWire.decodeDiscovery(Data(json.utf8), expectedParentID: nil)
        #expect(decoded.isEmpty)
    }

    @Test func untrustedUnknownRouteCanExplainTrustWithoutBecomingSelectable() throws {
        let json = #"{"schemaVersion":1,"candidates":[{"id":"unknown","name":"iPhone","model":"Unknown,1","transport":"usb","trustRequired":true}],"failures":[]}"#
        let candidates = try MobileBatteryWire.decodeDiscovery(Data(json.utf8), expectedParentID: nil)
        #expect(candidates.count == 1)
        #expect(candidates[0].trustRequired)
        #expect(!candidates[0].isVerifiedTrustedAppleDevice)
    }

    @Test func untrustedParentRouteWithoutModelSurvivesAsHintOnly() throws {
        let json = #"{"schemaVersion":1,"candidates":[{"id":"phone-1","transport":"usb","trustRequired":true}],"failures":[{"id":"phone-1","error":"trust-required"}]}"#
        let candidates = try MobileBatteryWire.decodeDiscovery(Data(json.utf8), expectedParentID: nil)
        #expect(candidates.count == 1)
        #expect(candidates[0].trustRequired)
        #expect(!candidates[0].isVerifiedTrustedAppleDevice)
    }
    @Test func realZeroSurvivesValidation() throws {
        let json = Data(#"{"schemaVersion":1,"devices":[{"id":"w","parentID":"p","name":null,"model":"Watch7,1","batteryLevel":0,"isCharging":null,"transport":"usb"}],"failures":[]}"#.utf8)
        let result = try MobileBatteryWire.decode(json, expectedParentID: "p", observedAt: .distantPast)
        #expect(result.snapshots.first?.batteryLevel == 0)
        #expect(result.snapshots.first?.observedAt == .distantPast)
    }

    @Test func acceptsFullBatteryAndUnicodeName() throws {
        let result = try decode(device(id: "p", model: "iPhone17,1", level: "100", name: #""東京 📱""#))
        #expect(result.snapshots.first?.batteryLevel == 100)
        #expect(result.snapshots.first?.name == "東京 📱")
    }

    @Test(arguments: ["-1", "101", #""72""#, "true", "72.5", "72.0"])
    func rejectsInvalidBatteryPercentages(_ value: String) throws {
        let result = try decode(device(id: "p", model: "iPhone17,1", level: value))
        #expect(result.snapshots.isEmpty)
        #expect(result.failures.count == 1)
    }

    @Test func rejectsMissingBatteryPercentage() throws {
        let result = try decode(#"{"schemaVersion":1,"devices":[{"id":"p","parentID":null,"model":"iPhone17,1","transport":"usb"}],"failures":[]}"#)
        #expect(result.snapshots.isEmpty)
        #expect(result.failures.count == 1)
    }

    @Test func rejectsBlankIdentifiersAndMissingWatchParentButAcceptsIPad() throws {
        #expect(try decode(device(id: "   ", model: "iPhone17,1", level: "50")).snapshots.isEmpty)
        #expect(try decode(device(id: "w", model: "Watch7,1", level: "50")).snapshots.isEmpty)
        #expect(try decode(device(id: "tablet", model: "iPad11,1", level: "50")).snapshots.count == 1)
    }

    @Test func rejectsUnknownSchemaVersion() throws {
        #expect(throws: (any Error).self) {
            try decode(#"{"schemaVersion":2,"devices":[],"failures":[]}"#)
        }
    }

    @Test func rejectsWrongWatchParentAndIncompatibleFamily() throws {
        let wrongParent = try MobileBatteryWire.decode(
            Data(device(id: "w", model: "Watch7,1", level: "50", parentID: #""other""#).utf8),
            expectedParentID: "phone",
            observedAt: .now
        )
        let incompatible = try decode(device(id: "p", model: "Watch7,1", level: "50"))
        #expect(wrongParent.snapshots.isEmpty)
        #expect(incompatible.snapshots.isEmpty)
    }

    @Test func invalidDeviceDoesNotDiscardValidSibling() throws {
        let json = #"{"schemaVersion":1,"devices":[{"id":"bad","parentID":null,"name":null,"model":"iPhone17,1","batteryLevel":101,"isCharging":false,"transport":"usb"},{"id":"good","parentID":null,"name":"Phone","model":"iPhone17,1","batteryLevel":0,"isCharging":false,"transport":"usb"}],"failures":[]}"#
        let result = try decode(json)
        #expect(result.snapshots.map(\.id) == ["good"])
        #expect(!result.failures.isEmpty)
    }

    /// Discovery carries Watches inline in `--discover-device`'s `candidates`
    /// array, where `decodeDiscovery` handles them. `decodeWatchCandidates` reads
    /// the separate `watchCandidates` list that only the `--read-phone` envelope
    /// emits, so it is a read-envelope helper and not a discovery source.
    @Test func decodeWatchCandidatesReadsTheReadPhoneCompanionList() throws {
        let json = Data(#"{"schemaVersion":1,"devices":[],"failures":[],"watchCandidates":[{"id":"w1","parentID":"p","transport":"usb"},{"id":"other","parentID":"q","transport":"network"},{"id":"w2","parentID":"p","transport":"network"}]}"#.utf8)
        let routes = try MobileBatteryWire.decodeWatchCandidates(json, expectedParentID: "p")
        #expect(routes == [
            WatchRoute(id: "w1", parentID: "p", transport: .usb),
            WatchRoute(id: "w2", parentID: "p", transport: .network),
        ])
    }

    /// Diagnostic categories are whitelisted: a helper string the app does not
    /// know collapses to `other`, and a malformed failure list yields no
    /// diagnostics instead of discarding the whole discovery response.
    @Test func decodeDiscoveryFailuresUsesTheKnownCategoryWhitelist() {
        let json = Data(#"{"schemaVersion":1,"candidates":[],"failures":[{"id":"p","error":"trust-required"},{"id":"q","error":"session-unavailable"},{"id":"r","error":"unexpected-helper-string"}]}"#.utf8)
        let failures = MobileBatteryWire.decodeDiscoveryFailures(json)
        #expect(failures.map(\.category) == ["trust-required", "session-unavailable", "other"])
        #expect(MobileBatteryWire.decodeDiscoveryFailures(Data("not json".utf8)).isEmpty)
    }

    private func decode(_ json: String) throws -> MobileBatteryReadResult {
        try MobileBatteryWire.decode(Data(json.utf8), expectedParentID: nil, observedAt: .distantPast)
    }

    private func device(
        id: String,
        model: String,
        level: String,
        name: String = "null",
        parentID: String = "null"
    ) -> String {
        #"{"schemaVersion":1,"devices":[{"id":\#(String(reflecting: id)),"parentID":\#(parentID),"name":\#(name),"model":\#(String(reflecting: model)),"batteryLevel":\#(level),"isCharging":null,"transport":"usb"}],"failures":[]}"#
    }
}
