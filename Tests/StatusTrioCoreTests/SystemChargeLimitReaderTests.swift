import Foundation
import Testing
@testable import StatusTrioCore

/// Issue #105. The macOS charge limit has no public API — `pmset`,
/// `system_profiler`, and IOKit all omit it — so the only source is a private,
/// root-owned plist that `powerd` rewrites. These tests pin the parser against
/// recorded archives so a layout change on a future macOS fails a test here
/// instead of silently stopping the feature.
@MainActor
struct SystemChargeLimitReaderTests {
    @Test func readsTheLimitFromARecordedArchive() throws {
        let data = try makeChargeLimitPlist(limit: 80, reason: "manualChargeLimit")

        #expect(SystemChargeLimitReader.chargeLimit(in: data) == 80)
    }

    /// The reason is advisory, not a filter: a limit `powerd` derived on its own
    /// still caps the battery, so it still has to close the ring.
    @Test func readsALimitWhateverItsReason() throws {
        let data = try makeChargeLimitPlist(limit: 80, reason: "optimizedChargeLimit")

        #expect(SystemChargeLimitReader.chargeLimit(in: data) == 80)
    }

    @Test func missingPoliciesYieldsNoLimit() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["bootSessionUUID": UUID().uuidString],
            format: .binary,
            options: 0
        )

        #expect(SystemChargeLimitReader.chargeLimit(in: data) == nil)
    }

    @Test func emptyPoliciesYieldsNoLimit() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["policies": Data()],
            format: .binary,
            options: 0
        )

        #expect(SystemChargeLimitReader.chargeLimit(in: data) == nil)
    }

    @Test func garbageYieldsNoLimit() {
        #expect(SystemChargeLimitReader.chargeLimit(in: Data("not a plist".utf8)) == nil)
        #expect(SystemChargeLimitReader.chargeLimit(in: Data()) == nil)
    }

    /// A layout change must degrade to "no limit", which keeps the manual
    /// setting, rather than crash the app on a plist it no longer understands.
    @Test func unknownLayoutYieldsNoLimit() throws {
        let payload = try NSKeyedArchiver.archivedData(
            withRootObject: ["unrelated": "shape"],
            requiringSecureCoding: false
        )
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["policies": payload],
            format: .binary,
            options: 0
        )

        #expect(SystemChargeLimitReader.chargeLimit(in: data) == nil)
    }

    /// Reads the real file when the machine has one, so a regression in the
    /// live layout is caught here rather than by a user.
    @Test func readsTheLivePlistWithoutCrashing() {
        let limit = SystemChargeLimitReader.chargeLimit()

        if let limit {
            #expect((1...100).contains(limit), "A charge limit is a percentage.")
        }
    }

    @Test func missingFileYieldsNoLimit() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("plist")

        #expect(SystemChargeLimitReader.chargeLimit(from: url) == nil)
    }

    /// Builds the same shape the live plist has: a binary plist whose
    /// `policies` entry is an `NSKeyedArchiver` array of `ChargeCtrlPolicy`.
    private func makeChargeLimitPlist(limit: Int, reason: String) throws -> Data {
        let policy = ChargeCtrlPolicyPlaceholder(limit: limit, reason: reason)
        let policies = try NSKeyedArchiver.archivedData(
            withRootObject: [policy],
            requiringSecureCoding: false
        )
        return try PropertyListSerialization.data(
            fromPropertyList: [
                "bootSessionUUID": UUID().uuidString,
                "policies": policies
            ],
            format: .binary,
            options: 0
        )
    }
}
