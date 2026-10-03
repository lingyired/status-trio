import Foundation
import Testing
@testable import StatusTrioCore

struct MobileBatterySnapshotTests {
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

    @Test func rejectsBlankIdentifiersAndMissingWatchParent() throws {
        #expect(try decode(device(id: "   ", model: "iPhone17,1", level: "50")).snapshots.isEmpty)
        #expect(try decode(device(id: "w", model: "Watch7,1", level: "50")).snapshots.isEmpty)
        #expect(try decode(device(id: "tablet", model: "iPad11,1", level: "50")).snapshots.isEmpty)
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
