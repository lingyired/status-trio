import AppKit
import XCTest
@testable import StatusTrioCore

final class WirelessListModelsTests: XCTestCase {
    func testWiFiMergePreservesWhitespaceInSSIDIdentity() {
        let candidates = [
            WiFiNetworkCandidate(
                ssid: " Studio ",
                bssid: "00:00:00:00:00:01",
                rssi: -70,
                channel: 1,
                security: .wpa2Personal
            ),
            WiFiNetworkCandidate(
                ssid: "Studio",
                bssid: "00:00:00:00:00:02",
                rssi: -40,
                channel: 1,
                security: .wpa2Personal
            )
        ]

        let merged = WiFiNetwork.merge(candidates, connectedBSSID: nil)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(Set(merged.map(\.ssid)), [" Studio ", "Studio"])
    }

    func testWiFiMergeNeverMixesDifferentSecurityTypes() {
        let candidates = [
            WiFiNetworkCandidate(ssid: "Office", bssid: "01", rssi: -45, channel: 44, security: .wpa2Personal),
            WiFiNetworkCandidate(ssid: "Office", bssid: "02", rssi: -50, channel: 44, security: .wpa3Personal)
        ]

        let merged = WiFiNetwork.merge(candidates, connectedBSSID: nil)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(Set(merged.map(\.security)), [.wpa2Personal, .wpa3Personal])
    }

    func testCoreWLANSecurityRawValuesPreserveOpenAndWPA3Identity() {
        XCTAssertEqual(WiFiSecurityKind(coreWLANRawValue: 0), .open)
        XCTAssertEqual(WiFiSecurityKind(coreWLANRawValue: 4), .wpa2Personal)
        XCTAssertEqual(WiFiSecurityKind(coreWLANRawValue: 13), .wpa3Transition)
        XCTAssertEqual(WiFiSecurityKind(coreWLANRawValue: 14), .owe)
        XCTAssertEqual(WiFiSecurityKind(coreWLANRawValue: Int.max), .unknown)
    }

    func testCurrentBSSIDWinsOverStrongestCandidateForConnectedState() {
        let candidates = [
            WiFiNetworkCandidate(ssid: "Studio", bssid: "01", rssi: -35, channel: 149, security: .wpa2Personal),
            WiFiNetworkCandidate(ssid: "Studio", bssid: "02", rssi: -68, channel: 36, security: .wpa2Personal)
        ]

        let network = try! XCTUnwrap(WiFiNetwork.merge(candidates, connectedBSSID: "02").first)

        XCTAssertTrue(network.isConnected)
        XCTAssertEqual(network.preferredCandidate?.bssid, "01")
        XCTAssertEqual(network.connectedBSSID, "02")
    }

    func testWiFiGroupingSeparatesKnownAndUnknownScannedNetworks() {
        let candidates = [
            WiFiNetworkCandidate(ssid: "Home", bssid: "01", rssi: -40, channel: 1, security: .wpa2Personal),
            WiFiNetworkCandidate(ssid: "Cafe", bssid: "02", rssi: -50, channel: 6, security: .wpa2Personal),
            WiFiNetworkCandidate(ssid: "Office", bssid: "03", rssi: -60, channel: 11, security: .wpa2Personal)
        ]
        let networks = WiFiNetwork.merge(
            candidates,
            connectedBSSID: "03",
            knownSSIDs: ["Home", "Office"]
        )

        let grouped = WiFiNetworkPresentation.grouped(networks, wifiState: .connected)

        XCTAssertEqual(grouped.known.map(\.ssid), ["Office", "Home"])
        XCTAssertEqual(grouped.other.map(\.ssid), ["Cafe"])
    }

    func testOnlyConnectedNetworkMovesIntoPersonalHotspotSection() {
        let networks = WiFiNetwork.merge(
            [
                WiFiNetworkCandidate(ssid: "Phone", bssid: "connected-ap", rssi: -42, channel: 6, security: .wpa2Personal),
                WiFiNetworkCandidate(ssid: "Phone", bssid: "same-security-ap", rssi: -50, channel: 11, security: .wpa2Personal),
                WiFiNetworkCandidate(ssid: "Phone", bssid: "different-security-ap", rssi: -55, channel: 1, security: .wpa3Personal),
                WiFiNetworkCandidate(ssid: "Cafe", bssid: "cafe-ap", rssi: -60, channel: 1, security: .open)
            ],
            connectedBSSID: "connected-ap",
            knownSSIDs: ["Phone"]
        )

        let grouped = WiFiNetworkPresentation.grouped(networks, wifiState: .hotspot)

        XCTAssertEqual(grouped.personalHotspot.map(\.ssid), ["Phone"])
        XCTAssertEqual(grouped.personalHotspot.map(\.security), [.wpa2Personal])
        XCTAssertEqual(
            Set(grouped.known.map(\.id)),
            Set(networks.filter { $0.ssid == "Phone" && !$0.isConnected }.map(\.id))
        )
        XCTAssertEqual(grouped.other.map(\.ssid), ["Cafe"])
        XCTAssertTrue(Set(grouped.known.map(\.id)).isDisjoint(with: Set(grouped.personalHotspot.map(\.id))))

        let laggingStatus = WiFiNetworkPresentation.grouped(networks, wifiState: .connected)
        XCTAssertTrue(laggingStatus.personalHotspot.isEmpty)
        XCTAssertEqual(laggingStatus.known.map(\.id), networks.filter { $0.ssid == "Phone" }.map(\.id))
    }

    func testPersonalHotspotPresentationKeepsConnectionAndDetailsInConnectedSection() {
        let connected = WiFiNetwork.merge(
            [WiFiNetworkCandidate(ssid: "Phone", bssid: "phone-ap", rssi: -42, channel: 6, security: .wpa2Personal)],
            connectedBSSID: "phone-ap"
        )[0]
        let sameSSIDUnconnected = WiFiNetwork.merge(
            [WiFiNetworkCandidate(ssid: "Phone", bssid: "other-ap", rssi: -48, channel: 11, security: .wpa2Personal)],
            connectedBSSID: "phone-ap"
        )[0]

        XCTAssertEqual(
            WiFiNetworkPresentation.trailingSymbol(for: connected, wifiState: .hotspot),
            "personalhotspot"
        )
        XCTAssertNil(WiFiNetworkPresentation.trailingSymbol(for: sameSSIDUnconnected, wifiState: .hotspot))
        XCTAssertNil(WiFiNetworkPresentation.trailingSymbol(for: connected, wifiState: .connected))
        XCTAssertEqual(WiFiNetworkPresentation.action(for: connected, joinsInApp: false), .none)
        XCTAssertEqual(WiFiNetworkPresentation.detailsSection(for: .hotspot), .personalHotspot)
        XCTAssertEqual(WiFiNetworkPresentation.detailsSection(for: .connected), .known)
    }

    func testOpenAndPersonalRowsJoinInAppAndTheConnectedRowHasNoAction() {
        func row(_ ssid: String, _ security: WiFiSecurityKind, connected: Bool = false, known: Bool = false) -> WiFiNetwork {
            WiFiNetwork.merge(
                [WiFiNetworkCandidate(ssid: ssid, bssid: "01", rssi: -40, channel: 1, security: security)],
                connectedBSSID: connected ? "01" : nil,
                knownSSIDs: known ? [ssid] : []
            )[0]
        }

        XCTAssertEqual(WiFiNetworkPresentation.action(for: row("Home", .wpa2Personal, known: true), joinsInApp: true), .join)
        XCTAssertEqual(WiFiNetworkPresentation.action(for: row("Cafe", .wpa3Personal), joinsInApp: true), .join)
        XCTAssertEqual(WiFiNetworkPresentation.action(for: row("Lobby", .open), joinsInApp: true), .join)
        XCTAssertEqual(WiFiNetworkPresentation.action(for: row("Office", .wpa2Personal, connected: true), joinsInApp: true), .none)
    }

    /// Enterprise, WEP, OWE and unknown security need a credential shape or an
    /// entry point the in-app join was not verified for, and an unnamed network
    /// cannot be targeted by a directed scan, so these keep using System Settings.
    func testOtherSecurityKindsAndHiddenNetworksStillOpenSystemSettings() {
        for security: WiFiSecurityKind in [
            .wep, .dynamicWEP, .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise,
            .enterprise, .wpa3Enterprise, .owe, .oweTransition, .unknown
        ] {
            let network = WiFiNetwork.merge(
                [WiFiNetworkCandidate(ssid: "Net", bssid: "01", rssi: -40, channel: 1, security: security)],
                connectedBSSID: nil
            )[0]
            XCTAssertFalse(security.canJoinInApp, "\(security)")
            XCTAssertEqual(WiFiNetworkPresentation.action(for: network, joinsInApp: true), .openSettings, "\(security)")
        }

        let hidden = WiFiNetwork.merge(
            [WiFiNetworkCandidate(ssid: "", bssid: "01", rssi: -40, channel: 1, security: .wpa2Personal)],
            connectedBSSID: nil
        )[0]
        XCTAssertEqual(WiFiNetworkPresentation.action(for: hidden, joinsInApp: true), .openSettings)
    }

    /// The opt-in is off by default, and while it is off every row keeps handing
    /// off to System Settings, as before joining existed.
    func testEveryRowOpensSystemSettingsWhileTheOptInIsOff() {
        for security in WiFiSecurityKind.allCases {
            let network = WiFiNetwork.merge(
                [WiFiNetworkCandidate(ssid: "Net", bssid: "01", rssi: -40, channel: 1, security: security)],
                connectedBSSID: nil
            )[0]
            XCTAssertEqual(WiFiNetworkPresentation.action(for: network, joinsInApp: false), .openSettings, "\(security)")
        }
    }

    func testEverySecurityKindIsClassifiedForInAppJoin() {
        let joinable = WiFiSecurityKind.allCases.filter(\.canJoinInApp)
        XCTAssertEqual(
            Set(joinable),
            [.open, .wpaPersonal, .wpaPersonalMixed, .wpa2Personal, .personal, .wpa3Personal, .wpa3Transition]
        )
    }

    func testDetailsToggleStatesTheActionItPerforms() {
        XCTAssertEqual(
            WiFiNetworkPresentation.detailsToggleTitleKey(isExpanded: false),
            .wifiDetailsShow
        )
        XCTAssertEqual(WiFiNetworkPresentation.detailsToggleSymbol(isExpanded: false), "info.circle")

        XCTAssertEqual(
            WiFiNetworkPresentation.detailsToggleTitleKey(isExpanded: true),
            .wifiDetailsHide
        )
        XCTAssertEqual(WiFiNetworkPresentation.detailsToggleSymbol(isExpanded: true), "chevron.up")
    }

    func testPreferredNetworkParserSkipsHeaderAndPreservesSSIDs() {
        let output = """
        Preferred networks on en0:
        \tHome
        \tCafe 5G
        """

        XCTAssertEqual(
            WiFiPreferredNetworkOutputParser.parse(output),
            ["Home", "Cafe 5G"]
        )
    }

    func testAsyncRequestGateRejectsLateResults() {
        var gate = AsyncRequestGate()
        let firstRequest = gate.advance()
        let currentRequest = gate.advance()

        XCTAssertFalse(gate.accepts(firstRequest))
        XCTAssertTrue(gate.accepts(currentRequest))
    }

    func testScanStatesRemainExplicit() {
        XCTAssertNotEqual(WiFiListState.scanning, .ready)
        XCTAssertNotEqual(WiFiListState.poweredOff, .noInterface)
        XCTAssertNotEqual(WiFiListState.permissionDenied, .failed)
        XCTAssertNotEqual(BluetoothAvailability.poweredOff, .unavailable)
    }

    func testAllowsRefreshFollowsTheScanState() {
        XCTAssertFalse(WiFiListState.scanning.allowsRefresh)
        XCTAssertTrue(WiFiListState.idle.allowsRefresh)
        XCTAssertTrue(WiFiListState.ready.allowsRefresh)
        XCTAssertTrue(WiFiListState.poweredOff.allowsRefresh)
        XCTAssertTrue(WiFiListState.permissionDenied.allowsRefresh)
    }

    func testSignalToNoiseRatioRejectsInvalidMeasurements() {
        let valid = makeDetails(rssi: -48, noise: -92)
        let unavailableRSSI = makeDetails(rssi: nil, noise: -92)
        let misleadingNoise = makeDetails(rssi: -48, noise: -20)

        XCTAssertEqual(valid.signalToNoiseRatio, 44)
        XCTAssertNil(unavailableRSSI.signalToNoiseRatio)
        XCTAssertNil(misleadingNoise.signalToNoiseRatio)
    }

    func testBluetoothGroupingKeepsConnectedDevicesFirst() {
        let devices = [
            BluetoothDevice(id: "1", name: "Zebra", kind: .audio, isConnected: false),
            BluetoothDevice(id: "2", name: "Alpha", kind: .computer(.unclassified), isConnected: true),
            BluetoothDevice(id: "3", name: "Bravo", kind: .mobile(.phone), isConnected: true)
        ]

        let grouped = BluetoothDevicePresentation.grouped(devices)

        XCTAssertEqual(grouped.connected.map(\.name), ["Alpha", "Bravo"])
        XCTAssertEqual(grouped.disconnected.map(\.name), ["Zebra"])
    }

    func testWiFiServiceResolverUsesWiFiServiceRatherThanEthernetOrVPNGlobals() {
    let snapshot: [String: [String: Any]] = [
        "State:/Network/Global/IPv4": ["PrimaryService": "ethernet"],
        "State:/Network/Service/ethernet/Interface": ["DeviceName": "en0"],
        "State:/Network/Service/ethernet/IPv4": ["Router": "192.168.1.1"],
        "State:/Network/Service/vpn/Interface": ["DeviceName": "utun4"],
        "State:/Network/Service/vpn/DNS": ["ServerAddresses": ["10.0.0.53"]],
        "State:/Network/Service/wifi/Interface": ["DeviceName": "en1"],
        "State:/Network/Service/wifi/IPv4": ["Addresses": ["10.42.0.2"], "Router": "10.42.0.1"],
        "State:/Network/Service/wifi/IPv6": ["Addresses": ["fe80::42"]],
        "State:/Network/Service/wifi/DNS": ["ServerAddresses": ["10.42.0.1"]]
    ]
    let resolved = WiFiServiceNetworkConfiguration.resolve(interface: "en1", snapshot: snapshot)
    XCTAssertEqual(resolved.ipv4Addresses, ["10.42.0.2"])
    XCTAssertEqual(resolved.ipv6Addresses, ["fe80::42"])
    XCTAssertEqual(resolved.router, "10.42.0.1")
    XCTAssertEqual(resolved.dnsServers, ["10.42.0.1"])

    let ambiguous = WiFiServiceNetworkConfiguration.resolve(interface: "en9", snapshot: [
        "State:/Network/Service/a/Interface": ["DeviceName": "en9"],
        "State:/Network/Service/b/Interface": ["DeviceName": "en9"]
    ])
    XCTAssertNil(ambiguous.router)
    XCTAssertTrue(ambiguous.dnsServers.isEmpty)
}

func testBluetoothAvailabilityMappingKeepsAuthorizationAndAdapterStatesDistinct() {
        XCTAssertEqual(
            BluetoothAvailabilityMapper.preliminary(authorization: .notDetermined, managerState: .unknown),
            .authorizationNotDetermined
        )
        XCTAssertEqual(
            BluetoothAvailabilityMapper.preliminary(authorization: .denied, managerState: .poweredOn),
            .authorizationDenied
        )
        XCTAssertEqual(
            BluetoothAvailabilityMapper.preliminary(authorization: .restricted, managerState: .poweredOn),
            .authorizationRestricted
        )
        XCTAssertEqual(
            BluetoothAvailabilityMapper.preliminary(authorization: .allowed, managerState: .resetting),
            .initializing
        )
        XCTAssertEqual(
            BluetoothAvailabilityMapper.preliminary(authorization: .allowed, managerState: .poweredOff),
            .poweredOff
        )
        XCTAssertEqual(
            BluetoothAvailabilityMapper.preliminary(authorization: .allowed, managerState: .unsupported),
            .unavailable
        )
        XCTAssertEqual(
            BluetoothAvailabilityMapper.preliminary(authorization: .allowed, managerState: .poweredOn),
            .available
        )
    }

    @MainActor
    func testBluetoothControllerRefreshesPairedDevicesAcrossStateAndPanelLifecycle() async {
        let reader = BluetoothReaderStub(result: .success([
            BluetoothDevice(id: "connected", name: "Headphones", kind: .audio, isConnected: true),
            BluetoothDevice(id: "paired", name: "Keyboard", kind: .peripheral(.keyboard), isConnected: false)
        ]))
        let monitor = BluetoothStateMonitorStub(
            authorization: .allowed,
            managerState: .poweredOn
        )
        let notifications = NotificationCenter()
        let controller = BluetoothDeviceController(
            worker: reader,
            stateMonitor: monitor,
            notificationCenter: notifications,
            workspaceNotificationCenter: notifications
        )

        controller.activate()
        await Task.yield()

        XCTAssertEqual(controller.availability, .available)
        XCTAssertEqual(controller.connectedDevices.map(\.id), ["connected"])
        XCTAssertEqual(BluetoothDevicePresentation.grouped(controller.devices).disconnected.map(\.id), ["paired"])
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(monitor.startCount, 1)

        controller.activate()
        XCTAssertEqual(monitor.startCount, 1)

        monitor.emit(authorization: .allowed, managerState: .poweredOff)
        XCTAssertEqual(controller.availability, .poweredOff)

        monitor.emit(authorization: .allowed, managerState: .poweredOn)
        await Task.yield()
        XCTAssertEqual(controller.availability, .available)
        XCTAssertEqual(reader.readCount, 2)

        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()
        XCTAssertEqual(monitor.startCount, 2)
        XCTAssertEqual(reader.readCount, 3)

        controller.deactivate()
        XCTAssertEqual(monitor.stopCount, 1)
        notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        await Task.yield()
        XCTAssertEqual(monitor.startCount, 2)

        controller.activate()
        await Task.yield()
        XCTAssertEqual(monitor.startCount, 3)
        controller.deactivate()
        XCTAssertEqual(monitor.stopCount, 2)
    }

    private func makeDetails(rssi: Int?, noise: Int?) -> WiFiConnectionDetails {
        WiFiConnectionDetails(
            ssid: "Studio",
            bssid: "01",
            band: nil,
            channel: nil,
            channelWidth: nil,
            rssi: rssi,
            noise: noise,
            phyMode: nil,
            transmitRateMbps: nil,
            security: .wpa2Personal,
            countryCode: nil,
            interfaceName: nil,
            ipv4Addresses: [],
            ipv6Addresses: [],
            router: nil,
            dnsServers: []
        )
    }
}

private final class BluetoothReaderStub: BluetoothPairedDeviceReading {
    private let result: BluetoothWorkerResult
    private(set) var readCount = 0

    init(result: BluetoothWorkerResult) {
        self.result = result
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        readCount += 1
        completion(result)
    }
}

@MainActor
private final class BluetoothStateMonitorStub: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    var authorization: BluetoothAuthorizationStatus
    private var managerState: BluetoothManagerState
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(authorization: BluetoothAuthorizationStatus, managerState: BluetoothManagerState) {
        self.authorization = authorization
        self.managerState = managerState
    }

    func start() {
        startCount += 1
        onStateChange?(authorization, managerState)
    }

    func stop() {
        stopCount += 1
    }

    func emit(authorization: BluetoothAuthorizationStatus, managerState: BluetoothManagerState) {
        self.authorization = authorization
        self.managerState = managerState
        onStateChange?(authorization, managerState)
    }
}
