import XCTest
@testable import StatusTrioCore

final class DDCVolumeReplyTests: XCTestCase {
    private let valid: [UInt8] = [110, 136, 2, 0, 98, 0, 0, 100, 0, 100, 214]

    func testDecodesMeasuredXV272UReplyAsFullVolume() {
        let reply = DDCVolumeReply.decode(valid)

        XCTAssertEqual(reply?.current, 100)
        XCTAssertEqual(reply?.maximum, 100)
        XCTAssertEqual(reply?.scalar, 1)
    }

    func testRejectsInvalidResultCode() {
        XCTAssertNil(DDCVolumeReply.decode(reply(changing: 3, to: 1)))
    }

    func testRejectsUnexpectedEchoedCode() {
        XCTAssertNil(DDCVolumeReply.decode(reply(changing: 4, to: 0x8D)))
    }

    func testRejectsWrongLength() {
        XCTAssertNil(DDCVolumeReply.decode(Array(valid.dropLast())))
    }

    func testRejectsBadChecksum() {
        var malformed = valid
        malformed[10] ^= 1

        XCTAssertNil(DDCVolumeReply.decode(malformed))
    }

    func testRejectsZeroMaximum() {
        XCTAssertNil(DDCVolumeReply.decode(reply(changing: 6, to: 0, and: 7, to: 0)))
    }

    func testRejectsCurrentAboveMaximum() {
        XCTAssertNil(DDCVolumeReply.decode(reply(changing: 9, to: 101)))
    }

    func testRoundsAndClampsTargetValue() {
        let reply = DDCVolumeReply(current: 50, maximum: 100)

        XCTAssertEqual(reply.targetValue(for: 0.955), 96)
        XCTAssertEqual(reply.targetValue(for: -0.1), 0)
        XCTAssertEqual(reply.targetValue(for: 1.1), 100)
    }

    // MARK: - Classification (issue #115 diagnostics)

    func testClassifiesValidReply() {
        XCTAssertEqual(DDCVolumeReply.classify(valid), .valid(DDCVolumeReply(current: 100, maximum: 100)))
    }

    func testClassifiesAnAllZeroBufferAsZeros() {
        XCTAssertEqual(DDCVolumeReply.classify([UInt8](repeating: 0, count: 11)), .zeros)
    }

    func testClassifiesAnUnwrittenFFBufferAsUntouched() {
        XCTAssertEqual(DDCVolumeReply.classify([UInt8](repeating: 0xFF, count: 11)), .untouched)
    }

    func testShortBuffersStillDistinguishZerosAndUntouched() {
        XCTAssertEqual(DDCVolumeReply.classify([0, 0, 0, 0]), .zeros)
        XCTAssertEqual(DDCVolumeReply.classify([0xFF, 0xFF]), .untouched)
        XCTAssertEqual(DDCVolumeReply.classify([0x6E, 0x88]), .wrongLength)
        XCTAssertEqual(DDCVolumeReply.classify([]), .wrongLength)
    }

    func testClassifiesWrongHeader() {
        XCTAssertEqual(DDCVolumeReply.classify(reply(changing: 0, to: 0x51)), .wrongHeader)
    }

    func testClassifiesExplicitVCPRefusalSeparatelyFromOtherFailures() {
        // Result code 1 is the monitor answering "I do not support this VCP".
        // It must never be confused with a timeout or accepted as data.
        XCTAssertEqual(DDCVolumeReply.classify(reply(changing: 3, to: 1)), .vcpRefused)
    }

    func testClassifiesWrongVCP() {
        XCTAssertEqual(DDCVolumeReply.classify(reply(changing: 4, to: 0x8D)), .wrongVCP)
    }

    func testClassifiesBadChecksum() {
        var malformed = valid
        malformed[10] ^= 1

        XCTAssertEqual(DDCVolumeReply.classify(malformed), .badChecksum)
    }

    func testClassifiesInvalidRange() {
        XCTAssertEqual(
            DDCVolumeReply.classify(reply(changing: 6, to: 0, and: 7, to: 0)),
            .invalidRange
        )
        XCTAssertEqual(DDCVolumeReply.classify(reply(changing: 9, to: 101)), .invalidRange)
    }

    // MARK: - Issue #115: result code 1 is a refusal only on a fully valid frame

    func testResultCodeOneWithAWrongEchoedVCPIsNotARefusal() {
        // A stale or unrelated frame can carry result code 1 while echoing a
        // different VCP. Calling that "the display refused 0x62" ends the
        // compatibility probe before P2-P4 are ever tried, so the monitor is
        // reported unavailable for the wrong reason.
        XCTAssertEqual(
            DDCVolumeReply.classify(reply(changing: 3, to: 1, and: 4, to: 0x8D)),
            .wrongVCP
        )
    }

    func testResultCodeOneWithABadChecksumIsNotARefusal() {
        var malformed = reply(changing: 3, to: 1)
        malformed[10] ^= 0xFF

        XCTAssertEqual(DDCVolumeReply.classify(malformed), .badChecksum)
    }

    func testResultCodeOneOnATruncatedBufferIsNotARefusal() {
        XCTAssertEqual(DDCVolumeReply.classify(Array(valid.prefix(6))), .wrongLength)
    }

    func testResultCodeOneOnAFullValidFrameIsStillARefusal() {
        XCTAssertEqual(DDCVolumeReply.classify(reply(changing: 3, to: 1)), .vcpRefused)
    }

    func testUnknownNonZeroResultCodeIsNeverSupportEvidence() {
        // Result codes other than 0/1 are not portable. They must not be
        // accepted as data, and must not be reported as "unsupported VCP".
        XCTAssertEqual(DDCVolumeReply.classify(reply(changing: 3, to: 3)), .displayReportedError(3))
        XCTAssertNil(DDCVolumeReply.decode(reply(changing: 3, to: 3)))
    }

    func testDiagnosticNamesAreIdentifierFreeAndDistinct() {
        let names = [
            DDCVolumeReplyKind.valid(DDCVolumeReply(current: 1, maximum: 1)).diagnosticName,
            DDCVolumeReplyKind.zeros.diagnosticName,
            DDCVolumeReplyKind.untouched.diagnosticName,
            DDCVolumeReplyKind.wrongLength.diagnosticName,
            DDCVolumeReplyKind.wrongHeader.diagnosticName,
            DDCVolumeReplyKind.wrongVCP.diagnosticName,
            DDCVolumeReplyKind.vcpRefused.diagnosticName,
            DDCVolumeReplyKind.displayReportedError(3).diagnosticName,
            DDCVolumeReplyKind.badChecksum.diagnosticName,
            DDCVolumeReplyKind.invalidRange.diagnosticName
        ]

        XCTAssertEqual(Set(names).count, names.count, "Every failure shape needs its own diagnostic name")
        XCTAssertEqual(DDCVolumeReplyKind.zeros.diagnosticName, "zeros")
        XCTAssertEqual(DDCVolumeReplyKind.vcpRefused.diagnosticName, "vcpRefused")
    }

    private func reply(changing index: Int, to value: UInt8) -> [UInt8] {
        reply(changing: index, to: value, and: nil, to: nil)
    }

    private func reply(
        changing firstIndex: Int,
        to firstValue: UInt8,
        and secondIndex: Int? = nil,
        to secondValue: UInt8? = nil
    ) -> [UInt8] {
        var bytes = valid
        bytes[firstIndex] = firstValue
        if let secondIndex, let secondValue {
            bytes[secondIndex] = secondValue
        }
        bytes[10] = bytes.prefix(10).reduce(UInt8(0x50), ^)
        return bytes
    }
}
