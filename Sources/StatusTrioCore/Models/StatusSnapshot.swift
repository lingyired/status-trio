import Foundation

struct BatteryStatus: Equatable, Sendable {
    let rawPercentage: Int?
    let isPresent: Bool
    let isCharging: Bool
    let isCharged: Bool
    let timeToFullChargeMinutes: Int?
    let isLowPowerMode: Bool
    let isConnectedToPower: Bool

    init(
        rawPercentage: Int?,
        isPresent: Bool,
        isCharging: Bool,
        isCharged: Bool = false,
        timeToFullChargeMinutes: Int? = nil,
        isLowPowerMode: Bool,
        isConnectedToPower: Bool
    ) {
        self.rawPercentage = rawPercentage
        self.isPresent = isPresent
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.timeToFullChargeMinutes = timeToFullChargeMinutes
        self.isLowPowerMode = isLowPowerMode
        self.isConnectedToPower = isConnectedToPower
    }

    var percentage: Int {
        guard isPresent else { return 100 }
        let value = rawPercentage ?? 100
        return min(100, max(0, value))
    }

    static let placeholder = BatteryStatus(
        rawPercentage: 100,
        isPresent: true,
        isCharging: false,
        isLowPowerMode: false,
        isConnectedToPower: false
    )
}

enum WiFiState: Equatable, Sendable {
    case connected
    case notAssociated
    case off
    case noInternet
    case hotspot
    case temporary
    case shared
    case unavailable

    var isNetworkAssociated: Bool {
        switch self {
        case .connected, .noInternet, .hotspot, .temporary, .shared:
            true
        case .notAssociated, .off, .unavailable:
            false
        }
    }
}

enum WiFiNameAccess: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

struct WiFiStatus: Equatable, Sendable {
    let state: WiFiState
    let rssi: Int?
    let ssid: String?
    let nameAccess: WiFiNameAccess
    let band: WiFiFrequencyBand?

    init(
        state: WiFiState,
        rssi: Int?,
        ssid: String? = nil,
        nameAccess: WiFiNameAccess = .notDetermined,
        band: WiFiFrequencyBand? = nil
    ) {
        self.state = state
        self.rssi = rssi
        self.ssid = ssid
        self.nameAccess = nameAccess
        self.band = band
    }

    static let placeholder = WiFiStatus(state: .unavailable, rssi: nil)
}

extension WiFiStatus {
    /// True while a network name is expected but not known yet: the popover shows
    /// no subtitle until the fresh read delivers the name, instead of flashing the
    /// generic state text first.
    var isAwaitingName: Bool {
        state.isNetworkAssociated
            && nameAccess == .authorized
            && (ssid ?? "").isEmpty
    }
}

enum VolumeControlSource: Equatable, Sendable {
    case unavailable
    case native
    case directDDC
    case betterDisplay
}

struct VolumeStatus: Equatable, Sendable {
    let scalar: Double?
    let isMuted: Bool
    let muteState: VolumeMuteState
    let deviceName: String?
    let currentDevice: AudioOutputDevice?
    let outputDevices: [AudioOutputDevice]
    let canSetVolume: Bool
    let canMute: Bool
    let controlSource: VolumeControlSource
    let externalVolumeTransitionGeneration: UInt64

    init(
        scalar: Double?,
        isMuted: Bool,
        deviceName: String?,
        currentDevice: AudioOutputDevice? = nil,
        outputDevices: [AudioOutputDevice] = [],
        canSetVolume: Bool? = nil,
        canMute: Bool? = nil,
        muteState: VolumeMuteState? = nil,
        externalVolumeTransitionGeneration: UInt64 = 0,
        controlSource: VolumeControlSource = .unavailable
    ) {
        self.scalar = scalar
        self.isMuted = isMuted
        self.muteState = muteState ?? (isMuted ? .muted : .unmuted)
        self.deviceName = deviceName
        self.currentDevice = currentDevice
        self.outputDevices = outputDevices
        self.canSetVolume = canSetVolume ?? (scalar != nil)
        self.canMute = canMute ?? (scalar != nil)
        self.controlSource = controlSource
        self.externalVolumeTransitionGeneration =
            externalVolumeTransitionGeneration
    }

    static let placeholder = VolumeStatus(
        scalar: nil,
        isMuted: false,
        deviceName: nil
    )
}

extension VolumeStatus {
    func replacingExternalVolumeTransitionGeneration(
        _ generation: UInt64,
        controlSource: VolumeControlSource? = nil
    ) -> VolumeStatus {
        VolumeStatus(
            scalar: scalar,
            isMuted: isMuted,
            deviceName: deviceName,
            currentDevice: currentDevice,
            outputDevices: outputDevices,
            canSetVolume: canSetVolume,
            canMute: canMute,
            muteState: muteState,
            externalVolumeTransitionGeneration: generation,
            controlSource: controlSource ?? self.controlSource
        )
    }
}

struct StatusSnapshot: Equatable, Sendable {
    let battery: BatteryStatus
    let wifi: WiFiStatus
    let connection: NetworkConnection
    let volume: VolumeStatus

    init(
        battery: BatteryStatus,
        wifi: WiFiStatus,
        connection: NetworkConnection = .unknown,
        volume: VolumeStatus
    ) {
        self.battery = battery
        self.wifi = wifi
        self.connection = connection
        self.volume = volume
    }

    static let placeholder = StatusSnapshot(
        battery: .placeholder,
        wifi: .placeholder,
        volume: .placeholder
    )
}
