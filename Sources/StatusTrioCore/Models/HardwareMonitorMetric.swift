import Foundation

/// Settings-facing, persistable identity of a hardware-monitor tile.
///
/// Kept separate from `HardwareMetricID` (which carries a fan index) so the
/// stored preference is a stable, human-readable string and unknown future
/// values can be filtered safely on downgrade.
enum HardwareMonitorMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpuUsage
    case gpuUsage
    case memoryUsage
    case cpuTemperature
    case gpuTemperature
    case batteryTemperature
    case fan
    case downloadSpeed
    case uploadSpeed
    /// Output volume (0–100%). Offered for the ring arcs and top marker; never a
    /// card tile, because it comes from the audio stack, not the sampler.
    case volume
    /// Wi-Fi signal strength (0–100%). Offered for the ring arcs and top marker.
    case wifiSignal
    /// Mac battery level (0–100%). Offered for the ring arcs and top marker; read
    /// from the battery snapshot, never a card tile or a hardware sample.
    case batteryLevel

    var id: Self { self }

    /// Metrics offered in the ring's shared "Other" arc group. CPU and GPU are
    /// listed separately by the settings view.
    static let otherArcMetrics: [HardwareMonitorMetric] = [
        .memoryUsage, .batteryTemperature, .batteryLevel, .fan,
        .downloadSpeed, .uploadSpeed, .volume, .wifiSignal,
    ]

    /// Arc metrics whose colour is user-editable. Battery follows the
    /// system-battery ring's status colour, so it is edited there, not here.
    static var colorEditableArcMetrics: [HardwareMonitorMetric] {
        otherArcMetrics.filter { $0 != .batteryLevel }
    }

    /// Metrics shown by default on the card / enabled in the 监控 tab. Network
    /// speed is opt-in (it needs a broadband cap and a 1s sampler); the
    /// top-marker-only readings are never card tiles.
    static var defaultCardMetrics: [HardwareMonitorMetric] {
        // GPU temperature is offered for the outer ring and colours, but the
        // legacy card keeps its original tile set.
        allCases.filter { !$0.isSpeedMetric && $0 != .gpuTemperature && !$0.usesStatusSnapshot }
    }

    static var defaultEnabledMetrics: Set<HardwareMonitorMetric> {
        Set(defaultCardMetrics)
    }

    /// `true` for readings sourced from the general status snapshot (volume,
    /// Wi-Fi signal) rather than the hardware-metrics sampler. They can fill the
    /// ring arcs or the top marker, but are never card tiles.
    var usesStatusSnapshot: Bool {
        self == .volume || self == .wifiSignal || self == .batteryLevel
    }

    /// The metric this tile reads. The card shows the hottest fan.
    var metricID: HardwareMetricID {
        switch self {
        case .cpuUsage: .cpuUsage
        case .gpuUsage: .gpuUsage
        case .memoryUsage: .memoryUsage
        case .cpuTemperature: .cpuTemperature
        case .gpuTemperature: .gpuTemperature
        case .batteryTemperature: .batteryTemperature
        case .fan: .fanRPM(index: 0)
        case .downloadSpeed: .networkDownload
        case .uploadSpeed: .networkUpload
        case .volume: .volume
        case .wifiSignal: .wifiSignal
        case .batteryLevel: .batteryLevel
        }
    }

    var titleKey: LocalizationKey {
        switch self {
        case .cpuUsage: .hardwareMonitorCPU
        case .gpuUsage: .hardwareMonitorGPU
        case .memoryUsage: .hardwareMonitorMemory
        case .cpuTemperature: .hardwareMonitorTemperature
        case .gpuTemperature: .hardwareMonitorGPUTemperature
        case .batteryTemperature: .hardwareMonitorBatteryTemperature
        case .fan: .hardwareMonitorFan
        case .downloadSpeed: .hardwareMonitorDownload
        case .uploadSpeed: .hardwareMonitorUpload
        case .volume: .hardwareMonitorVolume
        case .wifiSignal: .hardwareMonitorSignalStrength
        case .batteryLevel: .settingsHardwareRingTopBatteryPercentage
        }
    }

    var systemImage: String {
        switch self {
        case .cpuUsage: "cpu"
        case .gpuUsage: "display"
        case .memoryUsage: "memorychip"
        case .cpuTemperature: "thermometer.medium"
        case .gpuTemperature: "thermometer.medium"
        case .batteryTemperature: SymbolFallback.name("battery.100percent", "battery.100")
        case .fan: "fanblades"
        case .downloadSpeed: "arrow.down.circle"
        case .uploadSpeed: "arrow.up.circle"
        case .volume: "speaker.wave.2.fill"
        case .wifiSignal: "wifi"
        case .batteryLevel: SymbolFallback.name("battery.100percent", "battery.100")
        }
    }

    /// Throughput metrics are scaled by a broadband cap rather than a display
    /// range, and have no meaningful warning/critical threshold.
    var isSpeedMetric: Bool {
        self == .downloadSpeed || self == .uploadSpeed
    }
}
