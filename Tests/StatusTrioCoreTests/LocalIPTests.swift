import Foundation
import XCTest
@testable import StatusTrioCore

final class LocalIPResolverTests: XCTestCase {
    func testPrefersThePrimaryInterfaceAddress() {
        let resolved = LocalIPResolver.resolve(
            primaryInterface: "en1",
            entries: [
                InterfaceAddressEntry(name: "en0", flags: UInt32(IFF_UP), ipv4Addresses: ["192.168.1.20"]),
                InterfaceAddressEntry(name: "en1", flags: UInt32(IFF_UP), ipv4Addresses: ["10.0.0.5"])
            ]
        )

        XCTAssertEqual(resolved.interfaceName, "en1")
        XCTAssertEqual(resolved.address, "10.0.0.5")
    }

    /// A VPN tunnel claims the primary interface, but the private address is
    /// what the row means, so the tunnel is skipped and the physical link
    /// underneath it is reported.
    func testAVPNHoldingThePrimaryInterfaceStillReportsThePhysicalLink() {
        let resolved = LocalIPResolver.resolve(
            primaryInterface: "utun4",
            entries: [
                InterfaceAddressEntry(name: "utun4", flags: UInt32(IFF_UP), ipv4Addresses: ["10.8.0.6"]),
                InterfaceAddressEntry(name: "en0", flags: UInt32(IFF_UP), ipv4Addresses: ["192.168.1.20"])
            ]
        )

        XCTAssertEqual(resolved.interfaceName, "en0")
        XCTAssertEqual(resolved.address, "192.168.1.20")
    }

    func testSkipsLoopbackAndTunnelsWhenNoPrimaryInterfaceIsKnown() {
        let resolved = LocalIPResolver.resolve(
            primaryInterface: nil,
            entries: [
                InterfaceAddressEntry(name: "lo0", flags: UInt32(IFF_UP), ipv4Addresses: ["127.0.0.1"]),
                InterfaceAddressEntry(name: "utun0", flags: UInt32(IFF_UP), ipv4Addresses: ["10.8.0.6"]),
                InterfaceAddressEntry(name: "gif0", flags: UInt32(IFF_UP), ipv4Addresses: ["10.9.0.1"]),
                InterfaceAddressEntry(name: "en0", flags: UInt32(IFF_UP), ipv4Addresses: ["192.168.1.20"])
            ]
        )

        XCTAssertEqual(resolved.interfaceName, "en0")
        XCTAssertEqual(resolved.address, "192.168.1.20")
    }

    func testAnInterfaceHoldingOnlyALinkLocalAddressIsNotTheLANAddress() {
        let resolved = LocalIPResolver.resolve(
            primaryInterface: "en0",
            entries: [
                InterfaceAddressEntry(name: "en0", flags: UInt32(IFF_UP), ipv4Addresses: ["169.254.10.4"]),
                InterfaceAddressEntry(name: "en1", flags: UInt32(IFF_UP), ipv4Addresses: ["192.168.1.20"])
            ]
        )

        XCTAssertEqual(resolved.interfaceName, "en1")
        XCTAssertEqual(resolved.address, "192.168.1.20")
    }

    func testNoUsableInterfaceResolvesUnavailable() {
        let resolved = LocalIPResolver.resolve(
            primaryInterface: "en0",
            entries: [
                InterfaceAddressEntry(name: "lo0", flags: UInt32(IFF_UP), ipv4Addresses: ["127.0.0.1"]),
                InterfaceAddressEntry(name: "en0", flags: UInt32(IFF_UP), ipv4Addresses: [])
            ]
        )

        XCTAssertEqual(resolved, .unavailable)
    }
}

final class NetworkRowSubtitleTests: XCTestCase {
    func testTheAddressLeadsTheLine() {
        XCTAssertEqual(
            NetworkRowSubtitle.prepending("192.168.1.20", to: "5 GHz · -48 dBm"),
            "192.168.1.20 · 5 GHz · -48 dBm"
        )
    }

    func testTheAddressStandsAloneWhenTheRowHasNothingElse() {
        XCTAssertEqual(NetworkRowSubtitle.prepending("192.168.1.20", to: nil), "192.168.1.20")
        XCTAssertEqual(NetworkRowSubtitle.prepending("192.168.1.20", to: ""), "192.168.1.20")
    }

    func testAnAbsentAddressLeavesTheRowUnchanged() {
        XCTAssertEqual(NetworkRowSubtitle.prepending(nil, to: "5 GHz · -48 dBm"), "5 GHz · -48 dBm")
        XCTAssertNil(NetworkRowSubtitle.prepending(nil, to: nil))
        XCTAssertNil(NetworkRowSubtitle.prepending("", to: ""))
    }
}

@MainActor
final class LocalIPControllerTests: XCTestCase {
    func testInactiveControllerIgnoresAResultThatArrivesAfterDeactivation() async {
        let reader = DeferredLocalIPReader()
        let controller = LocalIPController(reader: reader, periodicRefreshInterval: .seconds(600))

        controller.activate()
        controller.deactivate()
        reader.answer(LocalIPDetails(interfaceName: "en0", address: "192.168.1.20"))

        // Give the rejected completion a chance to land before asserting.
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(controller.details, .unavailable)
    }

    func testActivationReadsAndPublishes() async {
        let reader = DeferredLocalIPReader()
        let controller = LocalIPController(reader: reader, periodicRefreshInterval: .seconds(600))

        controller.activate()
        reader.answer(LocalIPDetails(interfaceName: "en0", address: "192.168.1.20"))

        for _ in 0..<200 where controller.details.address != "192.168.1.20" {
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(controller.details, LocalIPDetails(interfaceName: "en0", address: "192.168.1.20"))
    }
}

private final class DeferredLocalIPReader: LocalIPReading, @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (LocalIPDetails) -> Void)?

    func read(completion: @escaping @Sendable (LocalIPDetails) -> Void) {
        lock.withLock { self.completion = completion }
    }

    func answer(_ details: LocalIPDetails) {
        let completion = lock.withLock { self.completion }
        completion?(details)
    }
}
