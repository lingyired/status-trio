import Foundation

/// A security classification deliberately derived from CoreWLAN's stable raw
/// values. Keeping it independent from `CWSecurity` makes scan results safe to
/// cross the serial CoreWLAN worker boundary.
enum WiFiSecurityKind: Int, CaseIterable, Equatable, Hashable, Sendable {
    case unknown = -1
    case open = 0
    case wep = 1
    case wpaPersonal = 2
    case wpaPersonalMixed = 3
    case wpa2Personal = 4
    case personal = 5
    case dynamicWEP = 6
    case wpaEnterprise = 7
    case wpaEnterpriseMixed = 8
    case wpa2Enterprise = 9
    case enterprise = 10
    case wpa3Personal = 11
    case wpa3Enterprise = 12
    case wpa3Transition = 13
    case owe = 14
    case oweTransition = 15

    init(coreWLANRawValue: Int) {
        self = Self(rawValue: coreWLANRawValue) ?? .unknown
    }

    var requiresPassword: Bool {
        self != .open && self != .owe && self != .oweTransition && self != .unknown
    }
}

struct WiFiNetworkIdentity: Equatable, Hashable, Sendable {
    /// This is intentionally the unmodified SSID returned by CoreWLAN. In
    /// particular, leading/trailing whitespace is a part of an SSID identity.
    let ssid: String
    let security: WiFiSecurityKind
}

struct WiFiNetworkCandidate: Equatable, Hashable, Sendable {
    let identity: WiFiNetworkIdentity
    let bssid: String?
    let rssi: Int?
    let channel: Int?
    let security: WiFiSecurityKind

    init(
        ssid: String,
        bssid: String?,
        rssi: Int?,
        channel: Int?,
        security: WiFiSecurityKind
    ) {
        identity = WiFiNetworkIdentity(ssid: ssid, security: security)
        self.bssid = bssid
        self.rssi = rssi
        self.channel = channel
        self.security = security
    }
}

struct WiFiNetwork: Identifiable, Equatable, Sendable {
    let identity: WiFiNetworkIdentity
    let candidates: [WiFiNetworkCandidate]
    let connectedBSSID: String?
    let isKnown: Bool

    init(
        identity: WiFiNetworkIdentity,
        candidates: [WiFiNetworkCandidate],
        connectedBSSID: String?,
        isKnown: Bool = false
    ) {
        self.identity = identity
        self.candidates = candidates
        self.connectedBSSID = connectedBSSID
        self.isKnown = isKnown
    }

    var id: WiFiNetworkIdentity { identity }
    var ssid: String { identity.ssid }
    var security: WiFiSecurityKind { identity.security }

    /// The selected candidate is presentation-only. The associated AP always
    /// comes from `WiFiConnectionDetails`, never from this strongest candidate.
    var preferredCandidate: WiFiNetworkCandidate? {
        candidates.sorted(by: Self.candidateComesFirst).first
    }

    var isConnected: Bool {
        guard let connectedBSSID else { return false }
        return candidates.contains { candidate in
            guard let candidateBSSID = candidate.bssid else { return false }
            return candidateBSSID.caseInsensitiveCompare(connectedBSSID) == .orderedSame
        }
    }

    var rssi: Int? { preferredCandidate?.rssi }

    static func merge(
        _ candidates: [WiFiNetworkCandidate],
        connectedBSSID: String?,
        knownSSIDs: Set<String> = []
    ) -> [WiFiNetwork] {
        let groups = Dictionary(grouping: candidates, by: \.identity)
        return groups.map { identity, values in
            WiFiNetwork(
                identity: identity,
                candidates: values.sorted(by: candidateComesFirst),
                connectedBSSID: connectedBSSID,
                isKnown: knownSSIDs.contains(identity.ssid)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isConnected != rhs.isConnected { return lhs.isConnected }
            let leftRSSI = lhs.rssi ?? Int.min
            let rightRSSI = rhs.rssi ?? Int.min
            if leftRSSI != rightRSSI { return leftRSSI > rightRSSI }
            if lhs.ssid != rhs.ssid { return lhs.ssid.localizedCaseInsensitiveCompare(rhs.ssid) == .orderedAscending }
            return lhs.security.rawValue < rhs.security.rawValue
        }
    }

    private static func candidateComesFirst(
        _ lhs: WiFiNetworkCandidate,
        _ rhs: WiFiNetworkCandidate
    ) -> Bool {
        let leftRSSI = lhs.rssi ?? Int.min
        let rightRSSI = rhs.rssi ?? Int.min
        if leftRSSI != rightRSSI { return leftRSSI > rightRSSI }
        return (lhs.bssid ?? "") < (rhs.bssid ?? "")
    }
}

enum WiFiNetworkRowAction: Equatable, Sendable {
    case none
    case openSettings
}

enum WiFiNetworkPresentation {
    static func grouped(
        _ networks: [WiFiNetwork]
    ) -> (known: [WiFiNetwork], other: [WiFiNetwork]) {
        (
            known: networks.filter { $0.isKnown || $0.isConnected },
            other: networks.filter { !$0.isKnown && !$0.isConnected }
        )
    }

    /// Status Trio never joins a network itself, so every row other than the
    /// current connection hands the job to the system Wi-Fi pane.
    static func action(for network: WiFiNetwork) -> WiFiNetworkRowAction {
        network.isConnected ? .none : .openSettings
    }

    /// The details row names the action it performs, so its caption and its
    /// accessibility label both flip once the details are open.
    static func detailsToggleTitleKey(isExpanded: Bool) -> LocalizationKey {
        isExpanded ? .wifiDetailsHide : .wifiDetailsShow
    }

    static func detailsToggleSymbol(isExpanded: Bool) -> String {
        isExpanded ? "chevron.up" : "info.circle"
    }
}

struct WiFiConnectionDetails: Equatable, Sendable {
    let ssid: String?
    let bssid: String?
    let band: String?
    let channel: Int?
    let channelWidth: String?
    let rssi: Int?
    let noise: Int?
    let phyMode: String?
    let transmitRateMbps: Double?
    let security: WiFiSecurityKind
    let countryCode: String?
    let interfaceName: String?
    let ipv4Addresses: [String]
    let ipv6Addresses: [String]
    let router: String?
    let dnsServers: [String]

    var signalToNoiseRatio: Int? {
        guard let rssi, let noise, rssi < 0, noise < 0, rssi >= noise else { return nil }
        return rssi - noise
    }

    static let unavailable = WiFiConnectionDetails(
        ssid: nil,
        bssid: nil,
        band: nil,
        channel: nil,
        channelWidth: nil,
        rssi: nil,
        noise: nil,
        phyMode: nil,
        transmitRateMbps: nil,
        security: .unknown,
        countryCode: nil,
        interfaceName: nil,
        ipv4Addresses: [],
        ipv6Addresses: [],
        router: nil,
        dnsServers: []
    )
}

enum WiFiListState: Equatable, Sendable {
    case idle
    case scanning
    case ready
    case poweredOff
    case noInterface
    case permissionDenied
    case failed

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }

    /// Keep the refresh affordance in sync with the controller's scan gate.
    var allowsRefresh: Bool { !isScanning }
}

struct AsyncRequestGate: Sendable {
    private(set) var current: UInt64 = 0

    mutating func advance() -> UInt64 {
        current &+= 1
        return current
    }

    func accepts(_ request: UInt64) -> Bool {
        request == current
    }
}

enum BluetoothAvailability: Equatable, Sendable {
    case idle
    case initializing
    case authorizationNotDetermined
    case authorizationDenied
    case authorizationRestricted
    case available
    case poweredOff
    case unavailable
    case failed
}

enum BluetoothAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case allowed
    case denied
    case restricted
}

enum BluetoothManagerState: Equatable, Sendable {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

enum BluetoothAvailabilityMapper {
    static func preliminary(
        authorization: BluetoothAuthorizationStatus,
        managerState: BluetoothManagerState
    ) -> BluetoothAvailability {
        switch authorization {
        case .denied:
            return .authorizationDenied
        case .restricted:
            return .authorizationRestricted
        case .notDetermined:
            return .authorizationNotDetermined
        case .allowed:
            switch managerState {
            case .unknown, .resetting:
                return .initializing
            case .unsupported:
                return .unavailable
            case .unauthorized:
                return .authorizationDenied
            case .poweredOff:
                return .poweredOff
            case .poweredOn:
                return .available
            }
        }
    }
}

/// The `0x200F` / `0x004C` hexadecimal strings the system report carries for a
/// device's vendor and product ID. The paired-device reader keeps both IDs on
/// the device and the AirPods model table is keyed by the product ID, so the
/// parse of that text lives in one place rather than in each of them.
enum BluetoothHexIdentifier {
    static func value(from text: String?) -> Int? {
        var digits = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if digits.hasPrefix("0x") {
            digits.removeFirst(2)
        }
        guard !digits.isEmpty, digits.allSatisfy(\.isHexDigit) else { return nil }
        return Int(digits, radix: 16)
    }
}

struct BluetoothDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let kind: BluetoothDeviceKind
    let isConnected: Bool
    /// A conservative diagnostic captured from the same profiler row. The
    /// controller reports it after a successful read; it does not affect UI.
    let appleBluetoothAudioDiagnostic: AppleBluetoothAudioDiagnosticRecord?
    /// The AirPods model the device's own Bluetooth product ID names, read from
    /// the profiler's `device_productID` / `device_vendorID` pair. It survives a
    /// rename, which the name cannot.
    let airPodsModel: AirPodsModel?
    /// The `device_vendorID` / `device_productID` pair the report carries, kept
    /// as numbers because they are the identity a reading from another source is
    /// matched to this device by: the pair survives a rename, and unlike the name
    /// it names one model. A report entry without the pair stays `nil`, which is
    /// what makes the name the fallback rather than the first choice.
    let vendorID: Int?
    let productID: Int?
    /// Whether the profiler reported this device with no device class at all —
    /// neither `device_minorType` nor `device_minorClassOfDevice_string`. Such a
    /// device is a scanned-but-never-paired entry the system settings does not
    /// list: a "ghost". The panel drops it unless the user turns the matching
    /// option off. A device the stack has classified always carries one of those
    /// two keys, so their joint absence is the signal.
    let isUnpairedGhost: Bool
    /// Whether this row exists because an external read supplied device
    /// information, rather than because the paired-device report described a
    /// device the user has. This covers both nearby Bluetooth reads and devices
    /// observed through a trusted phone.
    ///
    /// Such a row is read-only: an external reading can report a battery level,
    /// but it cannot supply the Mac's connection state or a paired Bluetooth
    /// address for this app to connect or disconnect. The provider identity may
    /// come from a Bluetooth peripheral or from a trusted phone.
    let isReadOverTheAir: Bool

    init(
        id: String,
        name: String,
        kind: BluetoothDeviceKind,
        isConnected: Bool,
        airPodsModel: AirPodsModel? = nil,
        vendorID: Int? = nil,
        productID: Int? = nil,
        appleBluetoothAudioDiagnostic: AppleBluetoothAudioDiagnosticRecord? = nil,
        isUnpairedGhost: Bool = false,
        isReadOverTheAir: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isConnected = isConnected
        self.appleBluetoothAudioDiagnostic = appleBluetoothAudioDiagnostic
        self.airPodsModel = airPodsModel
        self.vendorID = vendorID
        self.productID = productID
        self.isUnpairedGhost = isUnpairedGhost
        self.isReadOverTheAir = isReadOverTheAir
    }

    /// A copy of the device with a class another source established.
    ///
    /// Only the class changes: every other field comes from the profiler report
    /// and must keep coming from it, so a correction can never carry a name or
    /// a connection state with it.
    func replacingKind(with kind: BluetoothDeviceKind) -> BluetoothDevice {
        BluetoothDevice(
            id: id,
            name: name,
            kind: kind,
            isConnected: isConnected,
            airPodsModel: airPodsModel,
            vendorID: vendorID,
            productID: productID,
            appleBluetoothAudioDiagnostic: appleBluetoothAudioDiagnostic,
            isUnpairedGhost: isUnpairedGhost,
            isReadOverTheAir: isReadOverTheAir
        )
    }

    /// A copy of the device as the BLE read identified it.
    ///
    /// Three fields change together. The class comes from the model string the
    /// Device Information Service answered with, and the ghost flag is cleared
    /// because that flag means the profiler could not classify the device — and
    /// the model just did. The panel hides unclassified devices by default, so
    /// leaving the flag set would hide the very row the level was folded onto,
    /// which is the one shape this correction exists for.
    ///
    /// The row then belongs to the reading rather than to the report, so the
    /// connection state goes with it. The report's answer here is one this app
    /// produced: it calls the device connected because the read connected to it,
    /// and takes it back when the panel closes and the read ends.
    ///
    /// The name and the address are still the report's. An advertised name and a
    /// CoreBluetooth identifier are not, so they are not carried here.
    func identifiedByModel(_ kind: BluetoothDeviceKind) -> BluetoothDevice {
        BluetoothDevice(
            id: id,
            name: name,
            kind: kind,
            isConnected: false,
            airPodsModel: airPodsModel,
            vendorID: vendorID,
            productID: productID,
            appleBluetoothAudioDiagnostic: appleBluetoothAudioDiagnostic,
            isUnpairedGhost: false,
            isReadOverTheAir: true
        )
    }

    /// Whether this is an AirPods, which is what decides the order: AirPods lead
    /// the row and the list whatever they are called.
    ///
    /// The battery claim no longer needs this — the row reports the level the
    /// report carries for every connected device — but the order does: a renamed
    /// AirPods would otherwise land wherever its name happens to collate, and the
    /// system's collation differs per language. The product ID identifies the
    /// model after a rename; the name covers a model the table does not carry yet.
    var isAirPods: Bool {
        guard kind.isAudio else { return false }
        return airPodsModel != nil || name.lowercased().contains("airpods")
    }
}

/// What tapping the Bluetooth row does. The Wi-Fi row has the same shape — its
/// whole row is a button whose action comes from the state — so both rows send
/// the user somewhere only while the state has somewhere to send them.
enum BluetoothSummaryRowAction: Equatable, Sendable {
    case requestAuthorization
    case openPermissionSettings
}

/// One device's entry in the popover's Bluetooth row: the name, and the level
/// the report holds for it when it holds one.
struct BluetoothSummaryEntry: Equatable, Sendable {
    let name: String
    /// The level as the pieces the row draws, or `nil` for a device macOS can
    /// read no level for — the entry is then its name alone.
    let level: [BluetoothBatterySegment]?
}

/// What the popover's Bluetooth row reports. Deriving the text from state
/// keeps the summary testable without rendering SwiftUI.
enum BluetoothSummary: Equatable, Sendable {
    case requestAuthorization
    case initializing
    case authorizationDenied
    case authorizationRestricted
    case poweredOff
    case unavailable
    case readFailed
    case noConnectedDevices
    /// The connected devices, in the order the row lists them. Each carries the
    /// level the report holds for it, when it holds one.
    case devices([BluetoothSummaryEntry])

    /// The entries as one run of drawing pieces, separators included, or `nil`
    /// when the row is not listing devices.
    ///
    /// The row draws this, and `deviceNames` is its text-only rendering: the
    /// visible line and the value a screen reader reads are one derivation
    /// rather than two that could drift.
    var deviceSegments: [BluetoothBatterySegment]? {
        guard case .devices(let entries) = self else { return nil }
        var pieces: [BluetoothBatterySegment] = []
        for entry in entries {
            if !pieces.isEmpty {
                pieces.append(.text(Self.deviceSeparator))
            }
            pieces.append(.text(entry.name))
            guard let level = entry.level else { continue }
            pieces.append(.text(Self.nameLevelSeparator))
            pieces.append(contentsOf: level)
        }
        return pieces
    }

    var deviceNames: String? {
        deviceSegments?.plainText
    }

    /// Whether the row reports at least one connected device, which is what makes
    /// reading levels worth a claim.
    var hasConnectedDevices: Bool {
        deviceSegments != nil
    }

    /// Between two devices, matching the name lists the panel's other rows use.
    private static let deviceSeparator = "、"
    /// Between a device's name and its level. The middle dot marks the level as
    /// a property of that device rather than another device in the list.
    private static let nameLevelSeparator = " · "

    /// What the row does when tapped, or `nil` when tapping it does nothing.
    ///
    /// A refused grant is the case this exists for: the row has to take the user
    /// to the pane where it can be given back, the way the Wi-Fi row does for
    /// location. A grant that is *restricted* — a managed Mac or parental
    /// controls — is deliberately left out: the user cannot lift it, so offering
    /// to take them somewhere would be a promise the system will not keep.
    var rowAction: BluetoothSummaryRowAction? {
        switch self {
        case .requestAuthorization: .requestAuthorization
        case .authorizationDenied: .openPermissionSettings
        case .initializing, .authorizationRestricted, .poweredOff, .unavailable,
             .readFailed, .noConnectedDevices, .devices:
            nil
        }
    }

    static func presentation(
        availability: BluetoothAvailability,
        devices: [BluetoothDevice],
        batteryLevels: [String: BluetoothBatteryLevel]
    ) -> BluetoothSummary {
        switch availability {
        case .authorizationNotDetermined:
            return .requestAuthorization
        case .authorizationDenied:
            return .authorizationDenied
        case .authorizationRestricted:
            return .authorizationRestricted
        case .poweredOff:
            return .poweredOff
        case .unavailable:
            return .unavailable
        case .failed:
            return .readFailed
        // An idle controller has not read anything yet; saying so would only
        // repeat the initializing state it is about to enter.
        case .idle, .initializing:
            return .initializing
        case .available:
            let connected = BluetoothDevicePresentation.grouped(devices).connected
            guard !connected.isEmpty else { return .noConnectedDevices }
            return .devices(connected.map { entry(for: $0, batteryLevels: batteryLevels) })
        }
    }

    /// One device's entry in the row: its name, plus the level the report carries
    /// for it when there is one. A device macOS cannot read keeps its name alone,
    /// so a row that mixes both kinds stays readable.
    private static func entry(
        for device: BluetoothDevice,
        batteryLevels: [String: BluetoothBatteryLevel]
    ) -> BluetoothSummaryEntry {
        BluetoothSummaryEntry(
            name: device.name,
            level: BluetoothDevicePresentation.batteryLevelSegments(
                for: device,
                batteryLevels: batteryLevels
            )
        )
    }
}

/// Starting the Bluetooth state monitor is what raises the system permission
/// prompt, so the popover may only activate an app that already has the grant.
enum BluetoothPanelActivation {
    static func shouldActivate(authorization: BluetoothAuthorizationStatus) -> Bool {
        authorization == .allowed
    }
}

/// How a device row lays out its battery level.
///
/// The decision comes from the level data, never from the device's brand or
/// model: any device macOS reports a component channel for — left, right, or
/// charging case — gets its level on a second line, so true-wireless headphones
/// from any vendor share the layout without a per-model check.
enum BluetoothBatteryLayout: Equatable, Sendable {
    /// The whole-device level shares the name's line.
    case inline
    /// Component levels get a line of their own under the name.
    case components
}

enum BluetoothDevicePresentation {
    /// Connected devices first, then the paired but disconnected ones; inside each
    /// group AirPods lead and everything else follows in the system's name order.
    ///
    /// AirPods lead regardless of their name: they are the devices whose
    /// multi-channel level the row headlines, and the order must not depend on how
    /// a given language collates their name.
    static func grouped(_ devices: [BluetoothDevice]) -> (connected: [BluetoothDevice], disconnected: [BluetoothDevice]) {
        let sorted = devices.sorted { lhs, rhs in
            if lhs.isAirPods != rhs.isAirPods {
                return lhs.isAirPods
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return (
            sorted.filter(\.isConnected),
            sorted.filter { !$0.isConnected }
        )
    }

    /// The level the report carries for one device, looked up by the same
    /// normalized address the reader keys its levels by.
    ///
    /// This is the single place that normalizes the device identifier for a
    /// lookup, so the layout policy and the drawn segments cannot each grow their
    /// own copy of the rule and drift apart.
    static func batteryLevel(
        for device: BluetoothDevice,
        batteryLevels: [String: BluetoothBatteryLevel]
    ) -> BluetoothBatteryLevel? {
        let address = BluetoothBatteryReader.normalizedAddress(device.id)
        return batteryLevels[address]
    }

    /// The level for one detail row as the pieces the row draws, or nil when the
    /// report carries no level for that device.
    ///
    /// A row without a level renders nothing at all: the page stays quiet for
    /// the devices macOS cannot read instead of repeating a placeholder on
    /// every line. A report that could not be read is a different state, and
    /// `BluetoothDeviceController.batteryLevelsReadFailed` reports it once for
    /// the whole list.
    static func batteryLevelSegments(
        for device: BluetoothDevice,
        batteryLevels: [String: BluetoothBatteryLevel]
    ) -> [BluetoothBatterySegment]? {
        batteryLevel(for: device, batteryLevels: batteryLevels)?.segments
    }

    /// Which layout a device's row uses, decided by its level data alone.
    ///
    /// Any component channel routes the level to its own line. A single
    /// component is enough: TWS data arrives incrementally, so a row that only
    /// went two-line once two channels were present would jump between one and
    /// two lines as a partner earbud or the case reported in. `main` plus a
    /// component is also `.components`, because the component deserves the whole
    /// second line regardless of the aggregate level the report also carries.
    static func batteryLayout(
        for device: BluetoothDevice,
        batteryLevels: [String: BluetoothBatteryLevel]
    ) -> BluetoothBatteryLayout {
        guard let level = batteryLevel(for: device, batteryLevels: batteryLevels) else {
            return .inline
        }
        if level.left != nil || level.right != nil || level.caseLevel != nil {
            return .components
        }
        return .inline
    }
}
