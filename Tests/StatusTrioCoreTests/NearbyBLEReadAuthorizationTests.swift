import Foundation
import Testing
@testable import StatusTrioCore

struct NearbyBLEReadAuthorizationTests {
    @Test func reselectingDoesNotAcceptAnOldRead() {
        let id = UUID()
        var gate = NearbyBLEReadAuthorization()
        _ = gate.update([id])
        let token = gate.token(for: id)
        #expect(token.map { gate.accepts(id, token: $0) } == true)
        let revoked = gate.update([])
        #expect(revoked == [id])
        _ = gate.update([id])
        #expect(token.map { !gate.accepts(id, token: $0) } == true)
    }

    @Test func revokingOneIDLeavesAnotherReadAuthorized() {
        let first = UUID()
        let second = UUID()
        var gate = NearbyBLEReadAuthorization()
        _ = gate.update([first, second])
        let firstToken = gate.token(for: first)

        let revoked = gate.update([second])
        #expect(revoked == [first])
        #expect(firstToken.map { !gate.accepts(first, token: $0) } == true)
        #expect(gate.token(for: second) != nil)
    }

    @Test func unchangedPermissionsKeepActiveReadTokens() {
        let id = UUID()
        var gate = NearbyBLEReadAuthorization()
        _ = gate.update([id])
        let token = gate.token(for: id)

        let revoked = gate.update([id])
        #expect(revoked.isEmpty)
        #expect(token.map { gate.accepts(id, token: $0) } == true)
    }

    @Test func unknownIDsAndMissingTokensAreNeverAuthorized() {
        var gate = NearbyBLEReadAuthorization()
        let id = UUID()

        #expect(gate.token(for: id) == nil)
        #expect(!gate.permits(id, token: nil))
        _ = gate.update([id])
        #expect(!gate.permits(id, token: nil))
    }

    @Test func retainedGrantsTrackOnlyCurrentAllowlist() {
        var gate = NearbyBLEReadAuthorization()
        for _ in 0..<10_000 {
            let id = UUID()
            _ = gate.update([id])
        }
        let current = UUID()
        _ = gate.update([current])

        #expect(gate.grantCount == 1)
        #expect(gate.token(for: current) != nil)
        #expect(gate.token(for: UUID()) == nil)
    }
}
