import XCTest
@testable import StatusTrioCore

final class PrimaryLinkResolverTests: XCTestCase {
    func testPrimaryServiceResolvesTheAddressesOnItsOwnInterface() {
        let snapshot = makeSnapshot(
            primaryService: "vpn",
            services: [
                ("ethernet", Service(device: "en0", ipv4: ["192.168.1.20"], router: "192.168.1.1")),
                ("vpn", Service(device: "utun4", ipv4: ["10.8.0.6"], dns: ["10.0.0.53"]))
            ]
        )

        let resolved = NetworkServiceResolver.resolvePrimary(snapshot: snapshot)

        XCTAssertEqual(resolved?.interfaceName, "utun4")
        XCTAssertEqual(resolved?.ipv4Addresses, ["10.8.0.6"])
        XCTAssertEqual(resolved?.dnsServers, ["10.0.0.53"])
    }

    func testMissingOrUnknownPrimaryServiceResolvesNothing() {
        let noPrimary = makeSnapshot(
            primaryService: nil,
            services: [("ethernet", Service(device: "en0", ipv4: ["192.168.1.20"]))]
        )
        XCTAssertNil(NetworkServiceResolver.resolvePrimary(snapshot: noPrimary))

        let primaryLeftNoTrace = makeSnapshot(
            primaryService: "gone",
            services: [("ethernet", Service(device: "en0", ipv4: ["192.168.1.20"]))]
        )
        XCTAssertNil(NetworkServiceResolver.resolvePrimary(snapshot: primaryLeftNoTrace))
    }

    func testWiredLinkPrefersThePrimaryServiceWhenItIsTheWiredInterface() {
        let snapshot = makeSnapshot(
            primaryService: "ethernet",
            services: [
                ("wifi", Service(device: "en1", ipv4: ["10.42.0.2"])),
                ("ethernet", Service(
                    device: "en0",
                    ipv4: ["192.168.1.20"],
                    router: "192.168.1.1",
                    ipv6: ["fe80::1"],
                    dns: ["192.168.1.1"]
                ))
            ]
        )

        let resolved = PrimaryLinkResolver.resolve(wiredInterfaces: [WiredInterface(name: "en0")], snapshot: snapshot)

        XCTAssertEqual(resolved?.interfaceName, "en0")
        XCTAssertEqual(resolved?.ipv4Addresses, ["192.168.1.20"])
        XCTAssertEqual(resolved?.ipv6Addresses, ["fe80::1"])
        XCTAssertEqual(resolved?.router, "192.168.1.1")
        XCTAssertEqual(resolved?.dnsServers, ["192.168.1.1"])
    }

    func testVPNHoldingThePrimaryServiceStillReportsTheWiredLink() {
        let snapshot = makeSnapshot(
            primaryService: "vpn",
            services: [
                ("ethernet", Service(device: "en0", ipv4: ["192.168.1.20"], router: "192.168.1.1")),
                ("vpn", Service(device: "utun4", ipv4: ["10.8.0.6"]))
            ]
        )

        let resolved = PrimaryLinkResolver.resolve(wiredInterfaces: [WiredInterface(name: "en0")], snapshot: snapshot)

        XCTAssertEqual(resolved?.interfaceName, "en0")
        XCTAssertEqual(resolved?.ipv4Addresses, ["192.168.1.20"])
        XCTAssertEqual(resolved?.router, "192.168.1.1")
    }

    func testWirelessPrimaryFallsBackToTheWiredInterface() {
        let snapshot = makeSnapshot(
            primaryService: "wifi",
            services: [
                ("wifi", Service(device: "en1", ipv4: ["10.42.0.2"])),
                ("ethernet", Service(device: "en0", ipv4: ["192.168.1.20"]))
            ]
        )

        let resolved = PrimaryLinkResolver.resolve(wiredInterfaces: [WiredInterface(name: "en0")], snapshot: snapshot)

        XCTAssertEqual(resolved?.interfaceName, "en0")
        XCTAssertEqual(resolved?.ipv4Addresses, ["192.168.1.20"])
    }

    func testSeveralWiredInterfacesPreferThePrimaryService() {
        let snapshot = makeSnapshot(
            primaryService: "dock",
            services: [
                ("built-in", Service(device: "en5", ipv4: ["192.168.1.20"])),
                ("dock", Service(device: "en7", ipv4: ["10.0.0.8"]))
            ]
        )

        let resolved = PrimaryLinkResolver.resolve(wiredInterfaces: [WiredInterface(name: "en5"), WiredInterface(name: "en7")], snapshot: snapshot)

        XCTAssertEqual(resolved?.interfaceName, "en7")
        XCTAssertEqual(resolved?.ipv4Addresses, ["10.0.0.8"])
    }

    func testWiredLinkWithoutAServiceResolvesNothing() {
        let snapshot = makeSnapshot(
            primaryService: "wifi",
            services: [("wifi", Service(device: "en1", ipv4: ["10.42.0.2"]))]
        )

        XCTAssertNil(PrimaryLinkResolver.resolve(wiredInterfaces: [WiredInterface(name: "en0")], snapshot: snapshot))
    }

    func testAmbiguousWiredServiceResolvesNothingRatherThanGuessing() {
        let snapshot = makeSnapshot(
            primaryService: "vpn",
            services: [
                ("stale", Service(device: "en0", ipv4: ["192.168.0.90"], router: "192.168.0.1")),
                ("current", Service(device: "en0", ipv4: ["192.168.1.20"], router: "192.168.1.1")),
                ("vpn", Service(device: "utun4", ipv4: ["10.8.0.6"]))
            ]
        )

        XCTAssertNil(PrimaryLinkResolver.resolve(wiredInterfaces: [WiredInterface(name: "en0")], snapshot: snapshot))
    }

    func testWiredLinkWithoutAnInterfaceNameIsNotMistakenForThePrimaryService() {
        // The service carries addresses but names no interface, so there is
        // nothing to match against the wired list and the primary service must
        // not be reported as the wired link.
        var snapshot = makeSnapshot(
            primaryService: "ethernet",
            services: [("ethernet", Service(device: "en0", ipv4: ["192.168.1.20"]))]
        )
        snapshot["State:/Network/Service/ethernet/IPv4"] = ["Addresses": ["192.168.1.20"]]

        XCTAssertNil(PrimaryLinkResolver.resolve(wiredInterfaces: [WiredInterface(name: "en0")], snapshot: snapshot))
    }

    func testServiceNameIsReadFromTheAddressDictionary() {
        // macOS 27 publishes no State:/Network/Service/<id>/Interface dictionary
        // at all; the name only exists on the address dictionaries. A snapshot
        // shaped that way must still name the link, or the wired row's Interface
        // line goes blank and the primary service stops matching the wired list.
        let snapshot = makeSnapshot(
            primaryService: "ethernet",
            services: [("ethernet", Service(device: "en5", ipv4: ["192.168.1.20"]))]
        )
        XCTAssertNil(snapshot["State:/Network/Service/ethernet/Interface"])

        let resolved = PrimaryLinkResolver.resolve(wiredInterfaces: [WiredInterface(name: "en5")], snapshot: snapshot)

        XCTAssertEqual(resolved?.interfaceName, "en5")
        XCTAssertEqual(resolved?.ipv4Addresses, ["192.168.1.20"])
    }

    func testServiceNameFallsBackToTheLegacyInterfaceDictionary() {
        var snapshot = makeSnapshot(
            primaryService: nil,
            services: [("ethernet", Service(
                device: "en5",
                ipv4: ["192.168.1.20"],
                publishesInterfaceDictionary: true
            ))]
        )
        // The address dictionary names nothing, so the service is matched and
        // named through the legacy dictionary alone.
        snapshot["State:/Network/Service/ethernet/IPv4"] = ["Addresses": ["192.168.1.20"]]

        let resolved = NetworkServiceResolver.resolve(interface: "en5", snapshot: snapshot)

        XCTAssertEqual(resolved?.interfaceName, "en5")
        XCTAssertEqual(resolved?.ipv4Addresses, ["192.168.1.20"])
    }

    func testThePortNameTravelsWithTheResolvedLink() {
        let snapshot = makeSnapshot(
            primaryService: "ethernet",
            services: [("ethernet", Service(device: "en9", ipv4: ["172.20.10.8"]))]
        )

        let resolved = PrimaryLinkResolver.resolve(
            wiredInterfaces: [WiredInterface(name: "en9", displayName: "iPhone USB")],
            snapshot: snapshot
        )

        XCTAssertEqual(resolved?.interfaceName, "en9")
        XCTAssertEqual(resolved?.interfaceDisplayName, "iPhone USB")
    }

    func testThePortNameTravelsWithTheFallbackBranchToo() {
        // The VPN branch and the wireless fallback reach the same details, so a
        // name that only survived the primary-service branch would leave the row
        // titled Ethernet exactly when the user is looking at it.
        let snapshot = makeSnapshot(
            primaryService: "vpn",
            services: [
                ("ethernet", Service(device: "en5", ipv4: ["192.168.1.20"])),
                ("vpn", Service(device: "utun4", ipv4: ["10.8.0.6"]))
            ]
        )

        let resolved = PrimaryLinkResolver.resolve(
            wiredInterfaces: [WiredInterface(name: "en5", displayName: "USB 10/100/1000 LAN")],
            snapshot: snapshot
        )

        XCTAssertEqual(resolved?.interfaceName, "en5")
        XCTAssertEqual(resolved?.interfaceDisplayName, "USB 10/100/1000 LAN")
    }

    func testAnInterfaceWithoutAPortNameCarriesNone() {
        // macOS names most interfaces, but not all of them. The absence has to
        // survive the resolver as an absence, so the row's own fallback — the
        // generic wired label — is what decides what to show.
        let snapshot = makeSnapshot(
            primaryService: "ethernet",
            services: [("ethernet", Service(device: "en0", ipv4: ["192.168.1.20"]))]
        )

        let resolved = PrimaryLinkResolver.resolve(
            wiredInterfaces: [WiredInterface(name: "en0")],
            snapshot: snapshot
        )

        XCTAssertEqual(resolved?.interfaceName, "en0")
        XCTAssertNil(resolved?.interfaceDisplayName)
    }
}

@MainActor
final class PrimaryLinkControllerTests: XCTestCase {
    func testRefreshWithoutActivationDoesNotRead() {
        let reader = FakePrimaryLinkReader()
        let controller = makeController(reader: reader)

        controller.refresh()

        XCTAssertTrue(reader.requestedInterfaces.isEmpty)
        XCTAssertNil(controller.details)
    }

    func testActivateReadsTheWiredInterfacesAndPublishesDetails() async {
        let reader = FakePrimaryLinkReader()
        let controller = makeController(reader: reader, wiredInterfaces: [WiredInterface(name: "en0")])

        controller.activate()
        XCTAssertEqual(reader.requestedInterfaces, [[WiredInterface(name: "en0")]])

        reader.complete(with: makeDetails(interface: "en0", ipv4: ["192.168.1.20"]))
        await waitUntil { controller.details != nil }

        XCTAssertEqual(controller.details?.interfaceName, "en0")
        XCTAssertEqual(controller.details?.ipv4Addresses, ["192.168.1.20"])
        controller.deactivate()
    }

    func testThePortNameReachesTheReader() {
        let reader = FakePrimaryLinkReader()
        let controller = makeController(
            reader: reader,
            wiredInterfaces: [WiredInterface(name: "en9", displayName: "iPhone USB")]
        )

        controller.activate()

        XCTAssertEqual(
            reader.requestedInterfaces,
            [[WiredInterface(name: "en9", displayName: "iPhone USB")]]
        )
        controller.deactivate()
    }

    func testDeactivateDropsTheLinkAndRejectsALateRead() {
        let reader = FakePrimaryLinkReader()
        let dispatcher = ManualPrimaryLinkCompletionDispatcher()
        let controller = makeController(
            reader: reader,
            completionDispatcher: { action in dispatcher.dispatch(action) }
        )

        controller.activate()
        controller.deactivate()

        XCTAssertNil(controller.details)
        XCTAssertFalse(controller.isActive)

        // The answer arrives after the popover closed. It must not paint the
        // address of a link the user has already left.
        reader.complete(with: makeDetails(interface: "en0", ipv4: ["192.168.1.20"]))
        XCTAssertEqual(dispatcher.pendingCount, 1)

        dispatcher.runNext()

        XCTAssertEqual(dispatcher.pendingCount, 0)
        XCTAssertNil(controller.details)
    }

    func testReactivationRejectsACompletionQueuedByThePriorSession() {
        let reader = FakePrimaryLinkReader()
        let dispatcher = ManualPrimaryLinkCompletionDispatcher()
        let controller = makeController(
            reader: reader,
            completionDispatcher: { action in dispatcher.dispatch(action) }
        )

        controller.activate()
        reader.completePending(at: 0, with: makeDetails(interface: "en0", ipv4: ["192.168.1.20"]))
        XCTAssertEqual(dispatcher.pendingCount, 1)

        controller.deactivate()
        controller.activate()

        XCTAssertTrue(controller.isActive)
        dispatcher.runNext()
        XCTAssertNil(controller.details)

        reader.complete(with: makeDetails(interface: "en0", ipv4: ["192.168.1.21"]))
        XCTAssertEqual(dispatcher.pendingCount, 1)

        dispatcher.runNext()

        XCTAssertEqual(controller.details?.ipv4Addresses, ["192.168.1.21"])
        controller.deactivate()
    }

    func testAnOlderRefreshCompletionCannotReplaceANewerRead() {
        let reader = FakePrimaryLinkReader()
        let dispatcher = ManualPrimaryLinkCompletionDispatcher()
        let controller = makeController(
            reader: reader,
            completionDispatcher: { action in dispatcher.dispatch(action) }
        )

        controller.activate()
        controller.refresh()

        reader.completePending(at: 0, with: makeDetails(interface: "en0", ipv4: ["192.168.1.20"]))
        XCTAssertEqual(dispatcher.pendingCount, 1)

        dispatcher.runNext()

        XCTAssertNil(controller.details)

        reader.complete(with: makeDetails(interface: "en0", ipv4: ["192.168.1.21"]))
        XCTAssertEqual(dispatcher.pendingCount, 1)

        dispatcher.runNext()

        XCTAssertEqual(controller.details?.ipv4Addresses, ["192.168.1.21"])
        controller.deactivate()
    }

    func testRefreshUsesTheCurrentWiredInterfaces() {
        let reader = FakePrimaryLinkReader()
        let controller = makeController(
            reader: reader,
            wiredInterfaces: [WiredInterface(name: "en5"), WiredInterface(name: "en7")]
        )

        controller.activate()
        controller.refresh()

        let expected = [
            [WiredInterface(name: "en5"), WiredInterface(name: "en7")],
            [WiredInterface(name: "en5"), WiredInterface(name: "en7")]
        ]
        XCTAssertEqual(reader.requestedInterfaces, expected)
        controller.deactivate()
    }

    func testRepeatedActivationKeepsTheFirstLoopAndItsRead() {
        let reader = FakePrimaryLinkReader()
        let controller = makeController(reader: reader)

        controller.activate()
        controller.activate()

        XCTAssertEqual(reader.requestedInterfaces.count, 1)
        controller.deactivate()
    }

    private func makeController(
        reader: FakePrimaryLinkReader,
        wiredInterfaces: [WiredInterface] = [WiredInterface(name: "en0")],
        completionDispatcher: PrimaryLinkCompletionDispatcher? = nil
    ) -> PrimaryLinkController {
        let controller = PrimaryLinkController(
            reader: reader,
            wiredInterfaces: FakeWiredInterfaces(interfaces: wiredInterfaces),
            periodicRefreshInterval: .seconds(600),
            completionDispatcher: completionDispatcher ?? { action in
                Task { @MainActor in action() }
            }
        )
        return controller
    }

    private func makeDetails(interface: String, ipv4: [String]) -> PrimaryLinkDetails {
        PrimaryLinkDetails(
            interfaceName: interface,
            ipv4Addresses: ipv4,
            ipv6Addresses: [],
            router: nil,
            dnsServers: []
        )
    }

    /// Lets the controller's main-actor completion run. Polls instead of
    /// yielding a fixed number of times, because the completion arrives through
    /// a `Task` and its scheduling is not observable from here.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}

private struct FakeWiredInterfaces: WiredInterfaceProviding {
    let interfaces: [WiredInterface]

    func wiredInterfaces() -> [WiredInterface] { interfaces }
}

private final class FakePrimaryLinkReader: PrimaryLinkReading {
    private(set) var requestedInterfaces: [[WiredInterface]] = []
    private var completions: [@Sendable (PrimaryLinkDetails?) -> Void] = []

    func read(
        wiredInterfaces: [WiredInterface],
        completion: @escaping @Sendable (PrimaryLinkDetails?) -> Void
    ) {
        requestedInterfaces.append(wiredInterfaces)
        completions.append(completion)
    }

    func complete(with value: PrimaryLinkDetails?) {
        let pending = completions
        completions.removeAll()
        for completion in pending {
            completion(value)
        }
    }

    func completePending(at index: Int, with value: PrimaryLinkDetails?) {
        let completion = completions.remove(at: index)
        completion(value)
    }
}

private final class ManualPrimaryLinkCompletionDispatcher: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [@MainActor @Sendable () -> Void] = []

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }

    func dispatch(_ action: @escaping @MainActor @Sendable () -> Void) {
        lock.lock()
        pending.append(action)
        lock.unlock()
    }

    @MainActor
    func runNext() {
        lock.lock()
        let action = pending.isEmpty ? nil : pending.removeFirst()
        lock.unlock()
        action?()
    }
}

private struct Service {
    let device: String
    var ipv4: [String] = []
    var router: String?
    var ipv6: [String] = []
    var dns: [String] = []
    /// Whether the service also publishes the legacy
    /// `State:/Network/Service/<id>/Interface` dictionary. macOS 27 does not,
    /// which is why the fixtures name the interface on the address dictionaries
    /// the way the live store does.
    var publishesInterfaceDictionary = false

    func keys(id: String) -> [String: [String: Any]] {
        let base = "State:/Network/Service/\(id)"
        var result: [String: [String: Any]] = [:]
        var ipv4Dictionary: [String: Any] = ["InterfaceName": device]
        if !ipv4.isEmpty { ipv4Dictionary["Addresses"] = ipv4 }
        if let router { ipv4Dictionary["Router"] = router }
        result[base + "/IPv4"] = ipv4Dictionary
        if !ipv6.isEmpty { result[base + "/IPv6"] = ["InterfaceName": device, "Addresses": ipv6] }
        if !dns.isEmpty { result[base + "/DNS"] = ["ServerAddresses": dns] }
        if publishesInterfaceDictionary {
            result[base + "/Interface"] = ["DeviceName": device]
        }
        return result
    }
}

private func makeSnapshot(
    primaryService: String?,
    services: [(String, Service)]
) -> [String: [String: Any]] {
    var snapshot: [String: [String: Any]] = [:]
    if let primaryService {
        snapshot["State:/Network/Global/IPv4"] = ["PrimaryService": primaryService]
    }
    for (id, service) in services {
        snapshot.merge(service.keys(id: id)) { _, new in new }
    }
    return snapshot
}
