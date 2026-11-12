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
    case batteryTemperature
    case fan
    case downloadSpeed
    case uploadSpeed

    var id: Self { self }

    /// Metrics shown by default on the card / enabled in the 监控 tab. Network
    /// speed is opt-in (it needs a broadband cap and a 1s sampler).
    static var defaultCardMetrics: [HardwareMonitorMetric] {
        allCases.filter { !$0.isSpeedMetric }
    }

    static var defaultEnabledMetrics: Set<HardwareMonitorMetric> {
        Set(defaultCardMetrics)
    }

    /// The metric this tile reads. The card shows the hottest fan.
    var metricID: HardwareMetricID {
        switch self {
        case .cpuUsage: .cpuUsage
        case .gpuUsage: .gpuUsage
        case .memoryUsage: .memoryUsage
        case .cpuTemperature: .cpuTemperature
        case .batteryTemperature: .batteryTemperature
        case .fan: .fanRPM(index: 0)
        case .downloadSpeed: .networkDownload
        case .uploadSpeed: .networkUpload
        }
    }

    var titleKey: LocalizationKey {
        switch self {
        case .cpuUsage: .hardwareMonitorCPU
        case .gpuUsage: .hardwareMonitorGPU
        case .memoryUsage: .hardwareMonitorMemory
        case .cpuTemperature: .hardwareMonitorTemperature
        case .batteryTemperature: .hardwareMonitorBatteryTemperature
        case .fan: .hardwareMonitorFan
        case .downloadSpeed: .hardwareMonitorDownload
        case .uploadSpeed: .hardwareMonitorUpload
        }
    }

    var systemImage: String {
        switch self {
        case .cpuUsage: "cpu"
        case .gpuUsage: "display"
        case .memoryUsage: "memorychip"
        case .cpuTemperature: "thermometer.medium"
        case .batteryTemperature: SymbolFallback.name("battery.100percent", "battery.100")
        case .fan: "fanblades"
        case .downloadSpeed: "arrow.down.circle"
        case .uploadSpeed: "arrow.up.circle"
        }
    }

    /// Throughput metrics are scaled by a broadband cap rather than a display
    /// range, and have no meaningful warning/critical threshold.
    var isSpeedMetric: Bool {
        self == .downloadSpeed || self == .uploadSpeed
    }
}