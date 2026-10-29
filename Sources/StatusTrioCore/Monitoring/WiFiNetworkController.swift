import CoreWLAN
import Foundation
import SystemConfiguration

struct WiFiServiceNetworkConfiguration {
    let ipv4Addresses: [String]
    let ipv6Addresses: [String]
    let router: String?
    let dnsServers: [String]

    static let unavailable = Self(ipv4Addresses: [], ipv6Addresses: [], router: nil, dnsServers: [])

    /// The Wi-Fi link's addresses. Service selection lives in
    /// `NetworkServiceResolver`, which the wired link resolves through as well,
    /// so both links pick a service by the same rule.
    static func resolve(interface: String, snapshot: [String: [String: Any]]) -> Self {
        guard let configuration = NetworkServiceResolver.resolve(
            interface: interface,
            snapshot: snapshot
        ) else {
            return .unavailable
        }
        return Self(
            ipv4Addresses: configuration.ipv4Addresses,
            ipv6Addresses: configuration.ipv6Addresses,
            router: configuration.router,
            dnsServers: configuration.dnsServers
        )
    }
}

struct WiFiScanPayload: Sendable {
    let networks: [WiFiNetwork]
    let details: WiFiConnectionDetails
}

enum WiFiScanWorkerResult: Sendable {
    case success(WiFiScanPayload)
    case poweredOff
    case noInterface
    case failed
}

/// The scan and power calls the network list needs. CoreWLAN is synchronous and
/// serialized on the worker's own queue; the protocol exists so a test can
/// answer instantly and count the scans, which is how the cadence is observable
/// without sweeping every channel.
protocol WiFiNetworkScanning: AnyObject {
    func scan(completion: @escaping @Sendable (WiFiScanWorkerResult) -> Void)
    func setPower(_ isOn: Bool, completion: @escaping @Sendable (Bool) -> Void)
}

/// CoreWLAN exposes synchronous scan APIs. This worker owns a serial queue so
/// those calls never run on the main actor and cannot overlap.
final class CoreWLANNetworkWorker: @unchecked Sendable, WiFiNetworkScanning {
    private let queue = DispatchQueue(label: "StatusTrio.CoreWLANNetworkWorker")
    private let knownNetworkProvider: any WiFiKnownNetworkProviding

    init(
        knownNetworkProvider: any WiFiKnownNetworkProviding = UnavailableWiFiKnownNetworkProvider()
    ) {
        self.knownNetworkProvider = knownNetworkProvider
    }

    func scan(completion: @escaping @Sendable (WiFiScanWorkerResult) -> Void) {
        queue.async { [self] in
            completion(scanSynchronously())
        }
    }

    func setPower(
        _ isOn: Bool,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        queue.async {
            guard let interface = CWWiFiClient.shared().interface() else {
                completion(false)
                return
            }
            do {
                try interface.setPower(isOn)
                completion(true)
            } catch {
                completion(false)
            }
        }
    }

    private func scanSynchronously() -> WiFiScanWorkerResult {
        guard let interface = CWWiFiClient.shared().interface() else { return .noInterface }
        guard interface.powerOn() else { return .poweredOff }

        do {
            let rawNetworks = try interface.scanForNetworks(withSSID: nil)
            let associatedBSSID = interface.bssid()
            let candidates = rawNetworks.compactMap(projectCandidate)
            let knownSSIDs = interface.interfaceName.map {
                knownNetworkProvider.preferredNetworkSSIDs(interface: $0)
            } ?? []
            let actualNetwork = rawNetworks.first {
                bssid($0.bssid, matches: associatedBSSID)
            }
            return .success(
                WiFiScanPayload(
                    networks: WiFiNetwork.merge(
                        candidates,
                        connectedBSSID: associatedBSSID,
                        knownSSIDs: knownSSIDs
                    ),
                    details: makeDetails(interface: interface, actualNetwork: actualNetwork)
                )
            )
        } catch {
            return .failed
        }
    }

    private func securityKind(for network: CWNetwork) -> WiFiSecurityKind {
        let preferredKinds: [(CWSecurity, WiFiSecurityKind)] = [
            (.wpa3Transition, .wpa3Transition),
            (.wpa3Enterprise, .wpa3Enterprise),
            (.wpa3Personal, .wpa3Personal),
            (.oweTransition, .oweTransition),
            (.OWE, .owe),
            (.wpa2Enterprise, .wpa2Enterprise),
            (.wpaEnterpriseMixed, .wpaEnterpriseMixed),
            (.wpaEnterprise, .wpaEnterprise),
            (.enterprise, .enterprise),
            (.wpa2Personal, .wpa2Personal),
            (.wpaPersonalMixed, .wpaPersonalMixed),
            (.wpaPersonal, .wpaPersonal),
            (.personal, .personal),
            (.dynamicWEP, .dynamicWEP),
            (.WEP, .wep),
            (.none, .open)
        ]
        return preferredKinds.first { network.supportsSecurity($0.0) }?.1 ?? .unknown
    }

    private func projectCandidate(_ network: CWNetwork) -> WiFiNetworkCandidate? {
        guard let ssid = network.ssid else { return nil }
        return WiFiNetworkCandidate(
            ssid: ssid,
            bssid: network.bssid,
            rssi: normalizedMeasurement(network.rssiValue),
            channel: network.wlanChannel?.channelNumber,
            security: securityKind(for: network)
        )
    }

    private func makeDetails(
        interface: CWInterface,
        actualNetwork: CWNetwork?
    ) -> WiFiConnectionDetails {
        let interfaceName = interface.interfaceName
        let configuration = interfaceName.map(networkConfiguration(interface:)) ?? .unavailable
        let channel = interface.wlanChannel()
        let transmitRate = interface.transmitRate()

        return WiFiConnectionDetails(
            ssid: interface.ssid(),
            bssid: interface.bssid(),
            band: displayBand(channel?.channelBand.rawValue),
            channel: channel?.channelNumber,
            channelWidth: displayChannelWidth(channel?.channelWidth.rawValue),
            rssi: normalizedMeasurement(interface.rssiValue()),
            noise: actualNetwork.flatMap { normalizedMeasurement($0.noiseMeasurement) },
            phyMode: displayPHY(interface.activePHYMode().rawValue),
            transmitRateMbps: transmitRate.isFinite && transmitRate > 0 ? transmitRate : nil,
            security: WiFiSecurityKind(coreWLANRawValue: interface.security().rawValue),
            countryCode: actualNetwork?.countryCode,
            interfaceName: interfaceName,
            ipv4Addresses: configuration.ipv4Addresses,
            ipv6Addresses: configuration.ipv6Addresses,
            router: configuration.router,
            dnsServers: configuration.dnsServers
        )
    }

    private func networkConfiguration(interface: String) -> WiFiServiceNetworkConfiguration {
        guard let store = SCDynamicStoreCreate(nil, "StatusTrio" as CFString, nil, nil),
              let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/.*" as CFString) as? [String] else {
            return .unavailable
        }
        var snapshot: [String: [String: Any]] = [:]
        for key in keys where key == "State:/Network/Global/IPv4" || key.hasPrefix("State:/Network/Service/") {
            if let value = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] {
                snapshot[key] = value
            }
        }
        return WiFiServiceNetworkConfiguration.resolve(interface: interface, snapshot: snapshot)
    }

    private func normalizedMeasurement(_ value: Int) -> Int? {
        value < 0 ? value : nil
    }

    private func bssid(_ lhs: String?, matches rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private func displayBand(_ rawValue: Int?) -> String? {
        guard let rawValue else { return nil }
        return switch rawValue {
        case 1: "2.4 GHz"
        case 2: "5 GHz"
        case 3: "6 GHz"
        default: nil
        }
    }

    private func displayChannelWidth(_ rawValue: Int?) -> String? {
        guard let rawValue else { return nil }
        return switch rawValue {
        case 1: "20 MHz"
        case 2: "40 MHz"
        case 3: "80 MHz"
        case 4: "160 MHz"
        default: nil
        }
    }

    private func displayPHY(_ rawValue: Int) -> String? {
        return switch rawValue {
        case 1: "802.11a"
        case 2: "802.11b"
        case 3: "802.11g"
        case 4: "802.11n"
        case 5: "802.11ac"
        case 6: "802.11ax"
        default: nil
        }
    }
}

@MainActor
final class WiFiNetworkController: ObservableObject {
    @Published private(set) var networks: [WiFiNetwork] = []
    @Published private(set) var details = WiFiConnectionDetails.unavailable
    @Published private(set) var state: WiFiListState = .idle
    private let worker: any WiFiNetworkScanning
    private let now: () -> Date
    /// A full scan sweeps every channel, so the automatic path may not run one
    /// more often than this. Explicit user actions bypass it.
    private let minimumScanInterval: TimeInterval
    private let periodicRefreshInterval: Duration
    private let periodicRefreshSleep: @Sendable (Duration) async throws -> Void
    private var scanGate = AsyncRequestGate()
    private(set) var isActive = false
    /// When the last scan started, which is what the interval is measured from.
    private var lastScanStartedAt: Date?
    private var periodicRefreshTask: Task<Void, Never>?
    private var lastNameAccess: WiFiNameAccess = .notDetermined

    init(
        scanWorker: any WiFiNetworkScanning = CoreWLANNetworkWorker(),
        now: @escaping () -> Date = Date.init,
        minimumScanInterval: TimeInterval = 30,
        periodicRefreshInterval: Duration = .seconds(30),
        periodicRefreshSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.worker = scanWorker
        self.now = now
        self.minimumScanInterval = minimumScanInterval
        self.periodicRefreshInterval = periodicRefreshInterval
        self.periodicRefreshSleep = periodicRefreshSleep
    }
    deinit {
        periodicRefreshTask?.cancel()
    }

    func activate(nameAccess: WiFiNameAccess) {
        lastNameAccess = nameAccess
        guard !isActive else { return }
        isActive = true
        schedulePeriodicRefresh()
        refresh()
    }
    func deactivate() {
        guard isActive else { return }
        isActive = false
        _ = scanGate.advance()
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        // A scan that is in flight now has a completion that the `isActive`
        // guard above will drop, so leaving the scan on `.scanning` would block
        // every later `refresh`/`refreshNow` through `startScan`'s
        // `!state.isScanning` guard. Clearing the floor timestamp as well makes
        // the next `activate` start a clean cadence instead of inheriting this
        // session's scan.
        if state.isScanning {
            state = .idle
        }
        lastScanStartedAt = nil
    }

    /// The automatic path: the periodic loop and every Wi-Fi status yield come
    /// through here. Inside the interval the cached list is kept, because the
    /// list only changes when the radio changes, and that path calls
    /// `refreshNow(nameAccess:)`.
    func refresh(nameAccess: WiFiNameAccess? = nil) {
        if let nameAccess { lastNameAccess = nameAccess }
        guard hasScanElapsed else { return }
        startScan()
    }

    /// The explicit path: the refresh button and the radio toggle. A user asked
    /// for this, so it scans even inside the interval.
    func refreshNow(nameAccess: WiFiNameAccess? = nil) {
        if let nameAccess { lastNameAccess = nameAccess }
        startScan()
    }

    private var hasScanElapsed: Bool {
        guard let lastScanStartedAt else { return true }
        return now().timeIntervalSince(lastScanStartedAt) >= minimumScanInterval
    }

    private func startScan() {
        guard isActive, state.allowsRefresh else { return }

        let request = scanGate.advance()
        lastScanStartedAt = now()
        state = .scanning
        worker.scan { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, self.scanGate.accepts(request) else { return }
                self.receiveScanResult(result)
            }
        }
    }
    func setPower(_ enabled: Bool) {
        guard isActive else { return }

        _ = scanGate.advance()
        worker.setPower(enabled) { [weak self] changed in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                if changed {
                    self.state = .ready
                    self.refreshNow()
                } else {
                    self.state = .failed
                }
            }
        }
    }

    private func receiveScanResult(_ result: WiFiScanWorkerResult) {
        switch result {
        case let .success(payload):
            details = payload.details
            networks = payload.networks
            if payload.networks.isEmpty,
               lastNameAccess == .denied || lastNameAccess == .restricted {
                state = .permissionDenied
            } else {
                state = .ready
            }
        case .poweredOff:
            details = .unavailable
            networks = []
            state = .poweredOff
        case .noInterface:
            details = .unavailable
            networks = []
            state = .noInterface
        case .failed:
            state = lastNameAccess == .denied || lastNameAccess == .restricted
                ? .permissionDenied
                : .failed
        }
    }

    private func schedulePeriodicRefresh() {
        periodicRefreshTask?.cancel()
        let interval = periodicRefreshInterval
        let sleep = periodicRefreshSleep
        periodicRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
                guard let self, self.isActive else { return }
                self.refresh()
            }
        }
    }

}
