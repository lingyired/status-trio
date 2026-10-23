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
            return index < outcomes.count ? outcomes[index] : .replyReadFailed
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
        let (selection, visited) = run([.requestWriteFailed, .reply(.valid(validReply))])

        XCTAssertEqual(selection.profile?.label, "P2")
        XCTAssertEqual(visited, ["P1", "P2"])
    }

    func testLegacyProfileKeepsTheAcerZeroFailurePathAlive() {
        let (selection, visited) = run([
            .replyReadFailed,
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
            .requestWriteFailed,
            .reply(.zeros),
            .reply(.untouched),
            .reply(.badChecksum)
        ])

        XCTAssertNil(selection.profile)
        XCTAssertFalse(selection.refused)
        XCTAssertEqual(visited, ["P1", "P2", "P3", "P4"])
        XCTAssertEqual(selection.attempts.map(\.outcome.diagnosticName), [
            "requestWriteFailed", "zeros", "untouched", "badChecksum"
        ])
        XCTAssertEqual(
            selection.attempts.map(\.outcome.diagnosticStage),
            ["requestWrite", "validate", "validate", "validate"]
        )
        XCTAssertEqual(selection.failure, .replyRejected(.badChecksum))
    }

    func testFailureStageSurvivesInsteadOfBeingReportedAsUnsupportedVCP() {
        // Every failure used to surface as "unsupportedVolumeVCP", including a
        // host-side I2C failure the display never saw.
        let allCandidates = { (outcome: DDCProbeOutcome) in Array(repeating: outcome, count: 4) }
        XCTAssertEqual(run(allCandidates(.requestWriteFailed)).selection.failure, .requestWriteFailed)
        XCTAssertEqual(run(allCandidates(.replyReadFailed)).selection.failure, .replyReadFailed)
        XCTAssertEqual(run(allCandidates(.reply(.zeros))).selection.failure, .replyRejected(.zeros))
        XCTAssertNil(run([.reply(.valid(validReply))]).selection.failure)
    }

    func testAStrayResultByteInAnInvalidFrameDoesNotEndTheProbe() {
        // Result code 1 only means "unsupported VCP" on a frame that also has
        // the right length, header, echoed VCP and checksum. A garbled frame
        // that happens to carry `01` must keep P2-P4 alive.
        var stale = validReplyBytes(changingResult: 1)
        stale[4] = 0x8D
        stale[10] = stale.prefix(10).reduce(UInt8(0x50), ^)

        XCTAssertEqual(DDCVolumeReply.classify(stale), .wrongVCP)

        let selection = DDCReadProfileProbe.select { profile in
            profile.label == "P4" ? .reply(.valid(validReply)) : .reply(DDCVolumeReply.classify(stale))
        }

        XCTAssertEqual(selection.profile?.label, "P4", "Only a validated refusal may stop the probe")
        XCTAssertFalse(selection.refused)
        XCTAssertEqual(selection.attempts.map(\.profile.label), ["P1", "P2", "P3", "P4"])
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

    /// The measured Acer XV272U frame with a replaced result byte and a
    /// recomputed checksum, so the frame stays internally consistent.
    private func validReplyBytes(changingResult result: UInt8) -> [UInt8] {
        var bytes: [UInt8] = [110, 136, 2, result, 98, 0, 0, 100, 0, 100, 214]
        bytes[10] = bytes.prefix(10).reduce(UInt8(0x50), ^)
        return bytes
    }
}
