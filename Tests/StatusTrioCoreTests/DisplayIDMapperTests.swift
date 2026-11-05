import CoreGraphics
import XCTest
@testable import StatusTrioCore

/// Pure correlation between an external framebuffer's EDID identity and the
/// real `CGDirectDisplayID` it belongs to.
///
/// The bug this guards: externals used to carry `displayID = 0`, and
/// `CGDisplayCreateUUIDFromDisplayID(0)` resolves to the *main* (built-in)
/// display, so BetterDisplay and DisplayServices wrote to the wrong screen.
final class DisplayIDMapperTests: XCTestCase {
    private func identity(
        vendor: UInt32 = 1138,
        product: UInt32 = 1729,
        serial: UInt32 = 9001,
        edid: String = "0472C106-0000-0000-151E-0104B53C2278"
    ) -> DisplayIDMapper.ExternalIdentity {
        DisplayIDMapper.ExternalIdentity(
            vendorID: vendor, productID: product, serialNumber: serial, edidUUID: edid
        )
    }

    private func online(
        _ displayID: CGDirectDisplayID,
        vendor: UInt32 = 1138,
        product: UInt32 = 1729,
        serial: UInt32 = 9001,
        builtin: Bool = false
    ) -> DisplayIDMapper.OnlineDisplay {
        DisplayIDMapper.OnlineDisplay(
            displayID: displayID,
            vendorID: vendor,
            productID: product,
            serialNumber: serial,
            isBuiltin: builtin
        )
    }

    func testRealExternalMapsToItsNonZeroDisplayID() {
        let displays = [
            online(1, vendor: 1552, product: 41040, serial: 7001, builtin: true),
            online(5),
        ]
        XCTAssertEqual(
            DisplayIDMapper.uniqueDisplayID(for: identity(), among: displays),
            5,
            "The real external must resolve to its own non-zero CG display id"
        )
    }

    func testZeroDisplayIDCandidateIsNeverReturned() {
        let displays = [online(0)]
        XCTAssertNil(
            DisplayIDMapper.uniqueDisplayID(for: identity(), among: displays),
            "displayID 0 is not a real screen and must be rejected, never used"
        )
    }

    func testNoMatchFailsClosed() {
        let displays = [online(5, vendor: 1552, product: 41040, serial: 7001, builtin: true)]
        XCTAssertNil(DisplayIDMapper.uniqueDisplayID(for: identity(), among: displays))
    }

    func testAmbiguousIdenticalMonitorsFailClosed() {
        // Two units of the same model that report the same EDID serial cannot be
        // told apart, so neither may be targeted.
        let displays = [online(5), online(7)]
        XCTAssertNil(DisplayIDMapper.uniqueDisplayID(for: identity(), among: displays))
    }

    func testZeroSerialCannotIdentifyAPhysicalUnit() {
        let displays = [online(5, serial: 0)]
        XCTAssertNil(
            DisplayIDMapper.uniqueDisplayID(for: identity(serial: 0), among: displays),
            "A zero serial is not a unique per-unit identity"
        )
    }

    func testDifferentSerialsDistinguishSameModelUnits() {
        let displays = [online(5, serial: 9001), online(7, serial: 9002)]
        XCTAssertEqual(
            DisplayIDMapper.uniqueDisplayID(for: identity(serial: 9001), among: displays), 5
        )
        XCTAssertEqual(
            DisplayIDMapper.uniqueDisplayID(for: identity(serial: 9002), among: displays), 7
        )
    }

    func testTwoZeroSerialUnitsFailClosed() {
        let displays = [online(5, serial: 0), online(7, serial: 0)]
        XCTAssertNil(
            DisplayIDMapper.uniqueDisplayID(for: identity(serial: 0), among: displays),
            "Two units of the same model with no serial cannot be told apart"
        )
    }

    func testBuiltInCandidateIsNeverMatched() {
        let displays = [online(1, builtin: true)]
        XCTAssertNil(DisplayIDMapper.uniqueDisplayID(for: identity(), among: displays))
    }

    func testEmptyIdentityNeverMatches() {
        let displays = [online(5, vendor: 0, product: 0, serial: 0)]
        XCTAssertNil(DisplayIDMapper.uniqueDisplayID(for: identity(vendor: 0, product: 0, serial: 0), among: displays))
    }
}
