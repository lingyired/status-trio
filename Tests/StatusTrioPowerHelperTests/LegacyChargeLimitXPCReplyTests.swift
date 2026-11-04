import XCTest
import PowerHelperProtocol

/// Phase 3: typed replies must survive NSXPC secure-coding round-trips so the
/// daemon and app exchange typed facts, never raw SMC keys. This does not touch
/// real hardware or the XPC listener.
final class LegacyChargeLimitXPCReplyTests: XCTestCase {
    private func roundTrip<T: NSObject & NSSecureCoding>(_ value: T) -> T? {
        let data = try? NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: T.self, from: data)
    }

    func testProbeReplyRoundTrips() {
        let probe = SMLegacyChargeLimitProbeReply(
            hasInternalBattery: true,
            intelBCLMPresent: false,
            siliconPairPresent: true,
            siliconCHTEPresent: false,
            architectureName: "appleSilicon",
            osBandName: "thirteenToFourteen",
            errorCode: .none,
            errorDescription: nil
        )

        guard let decoded = roundTrip(probe) else {
            return XCTFail("probe reply did not round-trip")
        }
        XCTAssertTrue(decoded.hasInternalBattery)
        XCTAssertFalse(decoded.intelBCLMPresent)
        XCTAssertTrue(decoded.siliconPairPresent)
        XCTAssertFalse(decoded.siliconCHTEPresent)
        XCTAssertEqual(decoded.architectureName, "appleSilicon")
        XCTAssertEqual(decoded.osBandName, "thirteenToFourteen")
        XCTAssertEqual(decoded.errorCode, .none)
        XCTAssertNil(decoded.errorDescription)
    }

    func testFailureProbeReplyRoundTrips() {
        let probe = SMLegacyChargeLimitProbeReply(
            hasInternalBattery: false,
            intelBCLMPresent: false,
            siliconPairPresent: false,
            siliconCHTEPresent: false,
            architectureName: "unsupported",
            osBandName: "unknown",
            errorCode: .unsupportedHardware,
            errorDescription: "no battery"
        )
        guard let decoded = roundTrip(probe) else {
            return XCTFail("probe failure did not round-trip")
        }
        XCTAssertEqual(decoded.errorCode, .unsupportedHardware)
        XCTAssertEqual(decoded.errorDescription, "no battery")
    }

    func testWriteReplyRoundTrips() {
        let write = SMLegacyChargeLimitWriteReply(
            succeeded: true,
            observedLimit: NSNumber(value: 80),
            verified: true,
            errorCode: .none,
            errorDescription: nil
        )
        guard let decoded = roundTrip(write) else {
            return XCTFail("write reply did not round-trip")
        }
        XCTAssertTrue(decoded.succeeded)
        XCTAssertEqual(decoded.observedLimit?.intValue, 80)
        XCTAssertTrue(decoded.verified)
        XCTAssertEqual(decoded.errorCode, .none)
    }

    func testWriteFailureRoundTrips() {
        let write = SMLegacyChargeLimitWriteReply(
            succeeded: false,
            observedLimit: NSNumber(value: 100),
            verified: false,
            errorCode: .ownershipConflict,
            errorDescription: "another controller changed the key"
        )
        guard let decoded = roundTrip(write) else {
            return XCTFail("write failure did not round-trip")
        }
        XCTAssertFalse(decoded.succeeded)
        XCTAssertEqual(decoded.errorCode, .ownershipConflict)
        XCTAssertFalse(decoded.verified)
    }

    func testUnknownErrorCodeMapsToUnknown() {
        let raw = SMLegacyChargeLimitErrorCode(rawValue: 999)
        XCTAssertNil(raw)
    }
}