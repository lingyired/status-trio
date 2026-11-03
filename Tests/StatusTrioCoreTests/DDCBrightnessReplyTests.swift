import XCTest
@testable import StatusTrioCore

/// Brightness (VCP `0x10`) reply parsing and packet construction.
///
/// These pin the generalization of the volume path: the reply validator now
/// takes the expected VCP instead of hardcoding `0x62`, and the request builders
/// honor a caller-supplied VCP. The volume bytes below are the previously
/// verified XV272U frame, so the same tests also guard that default behaviour
/// did not move.
final class DDCBrightnessReplyTests: XCTestCase {
    /// Same shape as the measured volume frame, echoed VCP swapped to 0x10.
    private let brightnessValid: [UInt8] = [110, 136, 2, 0, 16, 0, 0, 100, 0, 100, 164]
    private let volumeValid: [UInt8] = [110, 136, 2, 0, 98, 0, 0, 100, 0, 100, 214]

    // MARK: - Reply classification

    func testBrightnessReplyDecodesWithBrightnessExpectedVCP() {
        let reply = DDCVolumeReply.decode(brightnessValid, expectedVCP: DDCPacket.brightnessVCP)

        XCTAssertEqual(reply?.current, 100)
        XCTAssertEqual(reply?.maximum, 100)
        XCTAssertEqual(reply?.scalar, 1)
    }

    func testBrightnessReplyRejectedAsVolumeMismatch() {
        // A 0x10 reply must not be accepted as a 0x62 volume reply.
        XCTAssertNil(DDCVolumeReply.decode(brightnessValid))
        XCTAssertEqual(DDCVolumeReply.classify(brightnessValid), .wrongVCP)
    }

    func testVolumeReplyRejectedAsBrightnessMismatch() {
        XCTAssertNil(DDCVolumeReply.decode(volumeValid, expectedVCP: DDCPacket.brightnessVCP))
        XCTAssertEqual(DDCVolumeReply.classify(volumeValid, expectedVCP: DDCPacket.brightnessVCP), .wrongVCP)
    }

    func testVolumeReplyStillDecodesWithDefaultExpectedVCP() {
        // No behavior change for the volume path.
        let reply = DDCVolumeReply.decode(volumeValid)
        XCTAssertEqual(reply?.scalar, 1)
    }

    func testBrightnessRejectsInvalidRangeIndependentlyOfVCP() {
        var malformed = brightnessValid
        // maximum 0
        malformed[6] = 0
        malformed[7] = 0
        malformed[10] = Self.checksum(of: malformed)
        XCTAssertNil(DDCVolumeReply.decode(malformed, expectedVCP: DDCPacket.brightnessVCP))
    }

    func testBrightnessRejectsBadChecksum() {
        var malformed = brightnessValid
        malformed[10] ^= 1
        XCTAssertNil(DDCVolumeReply.decode(malformed, expectedVCP: DDCPacket.brightnessVCP))
    }

    func testBrightnessRefusedResultCodeMapsToVCPRefused() {
        var refused = brightnessValid
        refused[3] = 1
        refused[10] = Self.checksum(of: refused)
        XCTAssertEqual(DDCVolumeReply.classify(refused, expectedVCP: DDCPacket.brightnessVCP), .vcpRefused)
    }

    // MARK: - Packet construction

    func testGetVCPRequestUsesBrightnessFeatureCode() {
        XCTAssertEqual(
            DDCPacket.getVCPRequest(vcp: DDCPacket.brightnessVCP, checksumMode: .standard),
            [0x82, 0x01, 0x10, 0xAC]
        )
        XCTAssertEqual(
            DDCPacket.getVCPRequest(vcp: DDCPacket.brightnessVCP, checksumMode: .legacy),
            [0x82, 0x01, 0x10, 0xFD]
        )
    }

    func testSetVCPRequestUsesBrightnessFeatureCode() {
        XCTAssertEqual(
            DDCPacket.setVCPRequest(vcp: DDCPacket.brightnessVCP, value: 50),
            [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A]
        )
    }

    func testDefaultPacketBuildersStillUseVolumeVCP() {
        XCTAssertEqual(
            DDCPacket.getVCPRequest(checksumMode: .standard),
            [0x82, 0x01, 0x62, 0xDE]
        )
        XCTAssertEqual(
            DDCPacket.setVCPRequest(value: 50),
            [0x84, 0x03, 0x62, 0x00, 0x32, 0xE8]
        )
    }

    func testBrightnessVCPConstantIsMCCSBrightness() {
        XCTAssertEqual(DDCPacket.brightnessVCP, 0x10)
        XCTAssertEqual(DDCPacket.volumeVCP, 0x62)
    }

    /// DDC reply checksum: XOR of the 10 payload bytes seeded at 0x50.
    private static func checksum(of frame: [UInt8]) -> UInt8 {
        frame.prefix(10).reduce(UInt8(0x50), ^)
    }
}
