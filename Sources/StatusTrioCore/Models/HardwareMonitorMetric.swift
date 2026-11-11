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

    var id: Self { self }

    /// The metric this tile reads. The card shows the hottest fan.
    var metricID: HardwareMetricID {
        switch self {
        case .cpuUsage: .cpuUsage
        case .gpuUsage: .gpuUsage
        case .memoryUsage: .memoryUsage
        case .cpuTemperature: .cpuTemperature
        case .batteryTemperature: .batteryTemperature
        case .fan: .fanRPM(index: 0)
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
        }
    }
}