import XCTest
@testable import StatusTrioCore

final class AirPodsDirectProtocolTests: XCTestCase {
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
