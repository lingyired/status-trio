import Foundation

struct IconBehaviorConfiguration: Codable, Equatable, Sendable {
    var systemBatteryRing: SystemBatteryRingBehavior
    var networkCenter: NetworkCenterBehavior
    var bluetoothAudioCenter: BluetoothAudioCenterBehavior
    var systemVolumeFooter: SystemVolumeFooterBehavior
    var airPodsRing: AirPodsRingBehavior
    var showsAirPodsTopSymbol: Bool
    /// Per-power-state top marker choices (#315), mirroring the merged
    /// `BatteryIconOptions` marker model.
    var batteryMarkers: BatteryMarkerBehavior
    /// Whether a top gap with content splits the visible arc across it (#205).
    var splitGapProgress: Bool

    enum CodingKeys: String, CodingKey {
        case systemBatteryRing, networkCenter, bluetoothAudioCenter, systemVolumeFooter, airPodsRing, showsAirPodsTopSymbol
        case batteryMarkers, splitGapProgress
    }

    init(
        systemBatteryRing: SystemBatteryRingBehavior,
        networkCenter: NetworkCenterBehavior,
        bluetoothAudioCenter: BluetoothAudioCenterBehavior,
        systemVolumeFooter: SystemVolumeFooterBehavior,
        airPodsRing: AirPodsRingBehavior = .single,
        showsAirPodsTopSymbol: Bool = false,
        batteryMarkers: BatteryMarkerBehavior = .classic,
        splitGapProgress: Bool = false
    ) {
        self.systemBatteryRing = systemBatteryRing
        self.networkCenter = networkCenter
        self.bluetoothAudioCenter = bluetoothAudioCenter
        self.systemVolumeFooter = systemVolumeFooter
        self.airPodsRing = airPodsRing
        self.showsAirPodsTopSymbol = showsAirPodsTopSymbol
        self.batteryMarkers = batteryMarkers
        self.splitGapProgress = splitGapProgress
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        systemBatteryRing = try container.decode(SystemBatteryRingBehavior.self, forKey: .systemBatteryRing)
        networkCenter = try container.decode(NetworkCenterBehavior.self, forKey: .networkCenter)
        bluetoothAudioCenter = try container.decode(BluetoothAudioCenterBehavior.self, forKey: .bluetoothAudioCenter)
        systemVolumeFooter = try container.decode(SystemVolumeFooterBehavior.self, forKey: .systemVolumeFooter)
        airPodsRing = try container.decodeIfPresent(AirPodsRingBehavior.self, forKey: .airPodsRing) ?? .single
        showsAirPodsTopSymbol = try container.decodeIfPresent(Bool.self, forKey: .showsAirPodsTopSymbol) ?? false
        batteryMarkers = try container.decodeIfPresent(BatteryMarkerBehavior.self, forKey: .batteryMarkers) ?? .classic
        splitGapProgress = try container.decodeIfPresent(Bool.self, forKey: .splitGapProgress) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(systemBatteryRing, forKey: .systemBatteryRing)
        try container.encode(networkCenter, forKey: .networkCenter)
        try container.encode(bluetoothAudioCenter, forKey: .bluetoothAudioCenter)
        try container.encode(systemVolumeFooter, forKey: .systemVolumeFooter)
        try container.encode(airPodsRing, forKey: .airPodsRing)
        try container.encode(showsAirPodsTopSymbol, forKey: .showsAirPodsTopSymbol)
        try container.encode(batteryMarkers, forKey: .batteryMarkers)
        try container.encode(splitGapProgress, forKey: .splitGapProgress)
    }

    static let classic = Self(
        systemBatteryRing: .classic,
        networkCenter: .classic,
        bluetoothAudioCenter: .classic,
        systemVolumeFooter: .classic,
        airPodsRing: .single,
        showsAirPodsTopSymbol: false
    )
}

struct SystemBatteryRingBehavior: Codable, Equatable, Sendable {
    var showsPercentage: Bool
    var showsChargingIndicator: Bool
    var showsChargingEffect: Bool
    var showsChargingBoltHeartbeat: Bool
    var usesStatusColors: Bool
    var showsPercentageWhenConnected: Bool
    var criticalThreshold: Int
    var textScale: Double

    static let classic = Self(
        showsPercentage: true,
        showsChargingIndicator: true,
        showsChargingEffect: BatteryIconOptions.standard.showsChargingEffect,
        showsChargingBoltHeartbeat: BatteryIconOptions.standard.showsChargingBoltHeartbeat,
        usesStatusColors: BatteryIconOptions.standard.usesStatusColors,
        showsPercentageWhenConnected: false,
        criticalThreshold: BatteryIconOptions.standard.criticalThreshold,
        textScale: BatteryIconOptions.standard.textScale
    )
}

struct NetworkCenterBehavior: Codable, Equatable, Sendable {
    var showsWiFiIconForEthernet: Bool
    var showsWiFiIconForHotspot: Bool
    var showsWiFiIconForTemporaryConnection: Bool
    var showsWiFiIconForInternetSharing: Bool
    var showsBatteryPercentageInConnectionSlot: Bool
    var wifiScale: Double

    static let classic = Self(
        showsWiFiIconForEthernet: false,
        showsWiFiIconForHotspot: false,
        showsWiFiIconForTemporaryConnection: false,
        showsWiFiIconForInternetSharing: false,
        showsBatteryPercentageInConnectionSlot: false,
        wifiScale: 1
    )
}

struct BluetoothAudioCenterBehavior: Codable, Equatable, Sendable {
    var replacesNetworkIcon: Bool
    var usesVolumeColor: Bool
    var prioritizesNetworkErrors: Bool
    var symbolScale: Double
    var networkIconSymbolOverride: String?

    static let classic = Self(
        replacesNetworkIcon: false,
        usesVolumeColor: false,
        prioritizesNetworkErrors: true,
        symbolScale: BluetoothAudioIconOptions.defaultSymbolScale,
        networkIconSymbolOverride: nil
    )
}

struct SystemVolumeFooterBehavior: Codable, Equatable, Sendable {
    var displayStyle: VolumeDisplayStyle

    static let classic = Self(displayStyle: .dots)
}


/// Per-power-state top marker choices (#315) carried by the V1 schema.
struct BatteryMarkerBehavior: Codable, Equatable, Sendable {
    var onBattery: BatteryTopMarker
    var charging: BatteryTopMarker
    var connected: BatteryTopMarker
    var noBattery: BatteryTopMarker

    static let classic = Self(
        onBattery: .percentage,
        charging: .bolt,
        connected: .plug,
        noBattery: .plug
    )
}

extension BatteryTopMarker: Codable {}
