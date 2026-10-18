import Foundation

enum IconPreviewDataMode: CaseIterable, Hashable, Sendable {
    case live
    case simulated
}

enum IconPreviewSampleSource: Hashable, Sendable {
    case macBattery
    case airPods
    case network
    case bluetoothTarget
    case systemVolume
    case inputSource
}

enum IconPreviewEar: Sendable {
    case left
    case right
}

enum IconDesignerBluetoothTarget: Equatable, Sendable {
    case currentAudioOutput
    case connectedDevice(address: String)
    case preservedUnboundGlyph
}

struct MacBatteryPreviewSample: Equatable, Sendable {
    var isPresent = true
    var percentage = 76
    var isCharging = false
}

enum IconPreviewNetworkKind: CaseIterable, Equatable, Sendable {
    case wifi
    case noInternet
    case off
    case ethernet
    case hotspot
    case temporary
    case shared
}

struct NetworkPreviewSample: Equatable, Sendable {
    var kind = IconPreviewNetworkKind.wifi
}

struct BluetoothTargetPreviewSample: Equatable, Sendable {
    var isOnline = true
    var isAudio = true
    var symbolName = "headphones"
}

struct VolumePreviewSample: Equatable, Sendable {
    var percentage = 62
    var isMuted = false
    var isAvailable = true
}

struct InputSourcePreviewSample: Equatable, Sendable {
    var isAvailable = true
    var shortLabel = "A"
}

struct IconPreviewSampleValues: Equatable, Sendable {
    var macBattery = MacBatteryPreviewSample()
    var airPods = CustomAirPodsPreviewSample()
    var network = NetworkPreviewSample()
    var bluetoothTarget = BluetoothTargetPreviewSample()
    var systemVolume = VolumePreviewSample()
    var inputSource = InputSourcePreviewSample()
}


enum IconPreviewQuickFill: CaseIterable, Hashable, Sendable {
    case networkHealthy
    case networkError
    case wifiOffEthernetConnected
    case batteryCharging
    case batteryCriticallyLow
    case volumeMuted
    case airPodsConnected
    case airPodsDisconnected

    var scenario: IconPreviewScenario {
        switch self {
        case .networkHealthy: .networkHealthy
        case .networkError: .networkNoInternet
        case .wifiOffEthernetConnected: .wifiOffEthernetConnected
        case .batteryCharging: .batteryCharging
        case .batteryCriticallyLow: .batteryCriticallyLow
        case .volumeMuted: .volumeMuted
        case .airPodsConnected: .airPodsConnected
        case .airPodsDisconnected: .airPodsDisconnected
        }
    }
}
