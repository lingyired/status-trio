import Foundation

struct IconBehaviorConfiguration: Codable, Equatable, Sendable {
    var systemBatteryRing: SystemBatteryRingBehavior
    var networkCenter: NetworkCenterBehavior
    var bluetoothAudioCenter: BluetoothAudioCenterBehavior
    var systemVolumeFooter: SystemVolumeFooterBehavior

    static let classic = Self(
        systemBatteryRing: .classic,
        networkCenter: .classic,
        bluetoothAudioCenter: .classic,
        systemVolumeFooter: .classic
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
        showsPercentage: BatteryIconOptions.standard.showsPercentage,
        showsChargingIndicator: BatteryIconOptions.standard.showsChargingIndicator,
        showsChargingEffect: BatteryIconOptions.standard.showsChargingEffect,
        showsChargingBoltHeartbeat: BatteryIconOptions.standard.showsChargingBoltHeartbeat,
        usesStatusColors: BatteryIconOptions.standard.usesStatusColors,
        showsPercentageWhenConnected: BatteryIconOptions.standard.showsPercentageWhenConnected,
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
