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
    case hardwareMonitor
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
    static let rssiRange = (-100)...(-30)
    var kind = IconPreviewNetworkKind.wifi
    var rssi = -48

    var clampedRSSI: Int {
        min(Self.rssiRange.upperBound, max(Self.rssiRange.lowerBound, rssi))
    }
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

/// Deterministic hardware metrics for the ring preview.
struct HardwareMonitorPreviewSample: Equatable, Sendable {
    var isAvailable = true
    var cpuUsage = 45.0
    var gpuUsage = 30.0
    var memoryUsage = 62.0
    var cpuTemperature = 55.0
    var batteryTemperature = 32.0
    var fanRPM = 1200.0
    var fanMaximumRPM: Double? = 6000
}

struct IconPreviewSampleValues: Equatable, Sendable {
    var macBattery = MacBatteryPreviewSample()
    var airPods = CustomAirPodsPreviewSample()
    var network = NetworkPreviewSample()
    var bluetoothTarget = BluetoothTargetPreviewSample()
    var systemVolume = VolumePreviewSample()
    var inputSource = InputSourcePreviewSample()
    var hardwareMonitor = HardwareMonitorPreviewSample()
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
