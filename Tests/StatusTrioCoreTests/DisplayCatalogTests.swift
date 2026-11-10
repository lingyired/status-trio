import CoreGraphics
import XCTest
@testable import StatusTrioCore

@MainActor
final class DisplayCatalogTests: XCTestCase {
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

    func testZeroIDNeverReturnsTheMainDisplayUUID() {
        XCTAssertEqual(LiveDisplayCatalog.displayUUIDString(0), "display-0")
    }

    func testExternalDescriptorCarriesTheRealCGDisplayIDNotZero() {
        let descriptor = LiveDisplayCatalog.mappedExternalDescriptor(
            edidUUID: "0472C106-0000-0000-151E-0104B53C2278",
            name: "XV272U",
            vendorID: 1138,
            productID: 1729,
            serialNumber: 9001,
            among: [
                online(1, vendor: 1552, product: 41040, serial: 7001, builtin: true),
                online(5),
            ]
        )
        XCTAssertEqual(descriptor.displayID, 5, "External descriptors must carry the real CG id")
        XCTAssertNotEqual(descriptor.displayID, 0)
        XCTAssertEqual(descriptor.id, "0472C106-0000-0000-151E-0104B53C2278",
                       "DDC identity stays the EDID UUID")
        XCTAssertFalse(descriptor.isBuiltin)
    }

    func testUnmappedExternalDescriptorKeepsZeroSentinel() {
        let descriptor = LiveDisplayCatalog.mappedExternalDescriptor(
            edidUUID: "EDID", name: "Unknown", vendorID: 1138, productID: 1729,
            serialNumber: 9001, among: []
        )
        XCTAssertEqual(descriptor.displayID, 0, "No unique match leaves the display unresolved")
    }

    func testExternalDescriptorRejectsZeroDisplayIDCandidate() {
        let descriptor = LiveDisplayCatalog.mappedExternalDescriptor(
            edidUUID: "EDID", name: "Unknown", vendorID: 1138, productID: 1729,
            serialNumber: 9001, among: [online(0)]
        )
        XCTAssertEqual(descriptor.displayID, 0)
    }

    func testZeroSerialSingleExternalDescriptorResolvesViaFallback() {
        // Issue #313: Mac mini with one external panel reporting serial 0.
        let descriptor = LiveDisplayCatalog.mappedExternalDescriptor(
            edidUUID: "EDID", name: "Redmi 27 NU", vendorID: 0, productID: 0,
            serialNumber: 0, among: [online(7, serial: 0)]
        )
        XCTAssertEqual(descriptor.displayID, 7, "Single external must resolve via the safe fallback")
        XCTAssertFalse(descriptor.isBuiltin)
    }

    func testZeroSerialWithBuiltinDescriptorStaysUnresolved() {
        let descriptor = LiveDisplayCatalog.mappedExternalDescriptor(
            edidUUID: "EDID", name: "Redmi 27 NU", vendorID: 0, productID: 0,
            serialNumber: 0,
            among: [online(1, builtin: true), online(7, serial: 0)]
        )
        XCTAssertEqual(descriptor.displayID, 0, "A built-in online must keep the fail-closed sentinel")
    }
}
