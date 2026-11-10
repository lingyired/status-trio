import XCTest
@testable import StatusTrioCore

final class AirPodsDirectProtocolTests: XCTestCase {
    func testHardwareSupportDoesNotDependOnPlaybackState() {
        for uid in ["2002 4c", "200f 4c"] {
            XCTAssertEqual(AirPodsFeatureSupport(modelUID: uid).spatial, false)
            XCTAssertEqual(AirPodsFeatureSupport(modelUID: uid).conversation, false)
        }
        for uid in ["2013 4c", "2019 4c", "200e 4c", "200a 4c", "201f 4c"] {
            XCTAssertEqual(AirPodsFeatureSupport(modelUID: uid).spatial, true)
            XCTAssertEqual(AirPodsFeatureSupport(modelUID: uid).conversation, false)
        }
        for uid in ["201b 4c", "2014 4c", "2024 4c", "2027 4c", "202d 4c"] {
            XCTAssertEqual(AirPodsFeatureSupport(modelUID: uid).spatial, true)
            XCTAssertNil(AirPodsFeatureSupport(modelUID: uid).conversation)
        }
        XCTAssertNil(AirPodsFeatureSupport(modelUID: "ffff 4c").spatial)
        XCTAssertNil(AirPodsFeatureSupport(modelUID: nil).conversation)
    }

    func testUnsupportedConversationDiffersFromOffAndFailedRead() throws {
        let decoder = JSONDecoder()
        let unsupported = try decoder.decode(AirPodsAudioHelper.Snapshot.self,
            from: Data(#"{"conversationSupported":false}"#.utf8))
        XCTAssertEqual(unsupported.conversationSupported, false)
        XCTAssertNil(unsupported.conversation)
        let off = try decoder.decode(AirPodsAudioHelper.Snapshot.self,
            from: Data(#"{"conversationSupported":true,"conversation":false}"#.utf8))
        XCTAssertEqual(off.conversationSupported, true)
        XCTAssertEqual(off.conversation, false)
        XCTAssertNil(try decoder.decode(AirPodsAudioHelper.Snapshot.self, from: Data("{}".utf8)).conversationSupported)
        XCTAssertThrowsError(try decoder.decode(AirPodsAudioHelper.Snapshot.self,
            from: Data(#"{"conversationSupported":1}"#.utf8)))
    }

    func testHelperProtocolRejectsNonBooleanState() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(AirPodsAudioHelper.Snapshot.self, from: Data(#"{"conversation":true}"#.utf8)).conversation, true)
        XCTAssertNil(try decoder.decode(AirPodsAudioHelper.Snapshot.self, from: Data("{}".utf8)).conversation)
        for malformed in [#"{"conversation":1}"#, #"{"conversation":"true"}"#, "invalid"] {
            XCTAssertThrowsError(try decoder.decode(AirPodsAudioHelper.Snapshot.self, from: Data(malformed.utf8)))
        }
    }

    func testOnlyCompleteValidatedControlFramesAreAccepted() {
        let valid: [UInt8] = [4,0,4,0,9,0,0x2e,50,0,0,0]
        XCTAssertEqual(AirPodsControlPacket.values(in: Data(valid))[0x2e], 50)
        XCTAssertEqual(AirPodsControlPacket.values(in: Data([0,1] + valid + [4,0,4,0,9,0,0x28,1,0,0,0]))[0x28], 1)
        XCTAssertTrue(AirPodsControlPacket.values(in: Data(valid.dropLast())).isEmpty)
        XCTAssertTrue(AirPodsControlPacket.values(in: Data([4,0,4,0,9,0,0x2e,101,0,0,0])).isEmpty)
        XCTAssertTrue(AirPodsControlPacket.values(in: Data([4,0,4,0,9,0,0x28,0,0,0,0])).isEmpty)
        XCTAssertNil(AirPodsControlPacket.command(0x2e, value: 101))
        XCTAssertNil(AirPodsControlPacket.command(0x0d, value: 1))
        XCTAssertEqual(AirPodsControlPacket.command(0x2e, value: 50), valid)
    }
}
