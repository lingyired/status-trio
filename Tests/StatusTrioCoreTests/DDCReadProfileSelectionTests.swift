import XCTest
@testable import StatusTrioCore

/// Issue #115 Task B: the bounded, read-only compatibility probe must be
/// ordered, stop at the first working candidate, respect an explicit refusal,
/// and cache the winner. These tests drive a scripted reader, so no IOKit or
/// I2C is involved and the "zero writes" property is structural.
final class DDCReadProfileSelectionTests: XCTestCase {
    private let validReply = DDCVolumeReply(current: 40, maximum: 100)

    private func run(_ outcomes: [DDCProbeOutcome]) -> (selection: DDCProbeSelection, visited: [String]) {
        var index = 0
        var visited: [String] = []
        let selection = DDCReadProfileProbe.select { profile in
            visited.append(profile.label)
            defer { index += 1 }
            return index < outcomes.count ? outcomes[index] : .transportFailure
        }
        return (selection, visited)
    }

    func testCandidateOrderIsTheDocumentedP1ToP4Table() {
        XCTAssertEqual(DDCReadProfile.candidates.map(\.label), ["P1", "P2", "P3", "P4"])
        XCTAssertEqual(
            DDCReadProfile.candidates,
            [
                DDCReadProfile(label: "P1", checksumMode: .standard, readAddress: 0x51),
                DDCReadProfile(label: "P2", checksumMode: .standard, readAddress: 0x00),
                DDCReadProfile(label: "P3", checksumMode: .legacy, readAddress: 0x51),
                DDCReadProfile(label: "P4", checksumMode: .legacy, readAddress: 0x00)
            ]
        )
    }

    func testFirstCandidateWinsAndNothingElseRuns() {
        let (selection, visited) = run([.reply(.valid(validReply))])

        XCTAssertEqual(selection.profile?.label, "P1")
        XCTAssertEqual(selection.reply, validReply)
        XCTAssertEqual(visited, ["P1"], "A working P1 must stop the probe immediately")
    }

    func testSecondCandidateIsUsedWhenTheFirstFails() {
        let (selection, visited) = run([.transportFailure, .reply(.valid(validReply))])

        XCTAssertEqual(selection.profile?.label, "P2")
        XCTAssertEqual(visited, ["P1", "P2"])
    }

    func testLegacyProfileKeepsTheAcerZeroFailurePathAlive() {
        let (selection, visited) = run([
            .transportFailure,
            .reply(.zeros),
            .reply(.valid(validReply))
        ])

        XCTAssertEqual(selection.profile?.label, "P3")
        XCTAssertEqual(selection.profile?.checksumMode, .legacy)
        XCTAssertEqual(selection.profile?.readAddress, 0x51)
        XCTAssertEqual(visited, ["P1", "P2", "P3"])
    }

    func testExplicitVCPRefusalStopsTheProbe() {
        let (selection, visited) = run([.reply(.vcpRefused), .reply(.valid(validReply))])

        XCTAssertNil(selection.profile)
        XCTAssertNil(selection.reply)
        XCTAssertTrue(selection.refused)
        XCTAssertEqual(visited, ["P1"], "An explicit refusal means the monitor understood the request")
    }

    func testEveryCandidateFailingReportsUnavailable() {
        let (selection, visited) = run([
            .transportFailure,
            .reply(.zeros),
            .reply(.untouched),
            .reply(.badChecksum)
        ])

        XCTAssertNil(selection.profile)
        XCTAssertFalse(selection.refused)
        XCTAssertEqual(visited, ["P1", "P2", "P3", "P4"])
        XCTAssertEqual(selection.attempts.map(\.outcome.diagnosticName), [
            "transportFailure", "zeros", "untouched", "badChecksum"
        ])
    }

    func testMalformedRepliesNeverSelectAProfile() {
        for kind in [DDCVolumeReplyKind.zeros, .untouched, .wrongLength, .wrongHeader, .wrongVCP, .badChecksum, .invalidRange] {
            let (selection, _) = run([.reply(kind), .reply(kind), .reply(kind), .reply(kind)])
            XCTAssertNil(selection.profile, "\(kind.diagnosticName) must not unlock a profile")
            XCTAssertFalse(selection.refused)
        }
    }

    func testProbeIsNeverRunTwiceWhileAProfileIsCached() {
        XCTAssertFalse(DDCReadProfilePolicy.shouldRunProbe(
            cachedProfile: DDCReadProfile.candidates[0],
            readsSinceLastProbe: 1_000
        ))
        XCTAssertFalse(DDCReadProfilePolicy.shouldRunProbe(cachedProfile: nil, readsSinceLastProbe: 0))
        XCTAssertFalse(DDCReadProfilePolicy.shouldRunProbe(cachedProfile: nil, readsSinceLastProbe: 5))
        XCTAssertTrue(DDCReadProfilePolicy.shouldRunProbe(
            cachedProfile: nil,
            readsSinceLastProbe: DDCReadProfilePolicy.readsBetweenProbes
        ))
    }
}
