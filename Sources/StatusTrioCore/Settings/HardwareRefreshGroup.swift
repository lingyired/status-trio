import Foundation

/// A user-facing group of hardware metrics that share one refresh-interval
/// setting. Each group owns the picker range and the title shown in Settings →
/// 监控 → 采样; the sampler and the panel projection both resolve a metric's
/// cadence through `group(for:)` so there is a single source of truth.
enum HardwareRefreshGroup: String, CaseIterable, Sendable {
    case cpuUsage
    case gpuUsage
    case memory
    case network
    case temperature
    case disk

    /// Group a sampled metric belongs to. Metrics read from other snapshots
    /// (volume / wifi / battery level) never reach the hardware sampler, so
    /// they map to `nil` and are ignored by the cadence providers.
    static func group(for id: HardwareMetricID) -> HardwareRefreshGroup? {
        switch id {
        case .cpuUsage: return .cpuUsage
        case .gpuUsage: return .gpuUsage
        case .memoryUsage, .memoryPressure: return .memory
        case .networkDownload, .networkUpload: return .network
        case .cpuTemperature, .gpuTemperature, .batteryTemperature, .fanRPM: return .temperature
        case .diskRead, .diskWrite: return .disk
        case .volume, .wifiSignal, .batteryLevel: return nil
        }
    }

    /// Fastest cadence this group can sample at — the low end of the picker.
    /// Mirrors `HardwareMetricsService.defaultMetricInterval`.
    var defaultSeconds: Int {
        switch self {
        case .cpuUsage, .gpuUsage, .memory: return 2
        case .network: return 1
        case .temperature: return 4
        case .disk: return 1
        }
    }

    /// Selectable cadences, from the metric floor up to the shared 8 s cap.
    var options: [Int] { Array(defaultSeconds...8) }

    var titleKey: LocalizationKey {
        switch self {
        case .cpuUsage: return .hardwareMonitorSettingsRefreshCPUUsage
        case .gpuUsage: return .hardwareMonitorSettingsRefreshGPUUsage
        case .memory: return .hardwareMonitorSettingsRefreshMemory
        case .network: return .hardwareMonitorSettingsRefreshNetwork
        case .temperature: return .hardwareMonitorSettingsRefreshTemperature
        case .disk: return .hardwareMonitorSettingsRefreshDisk
        }
    }
}
