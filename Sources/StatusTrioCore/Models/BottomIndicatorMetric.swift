/// The bottom indicator has its own metric selection so system pressure is
/// never offered as a percentage-based ring or monitor metric.
enum BottomIndicatorMetric: String, CaseIterable, Identifiable, Sendable {
    case cpuUsage
    case gpuUsage
    case memoryUsage
    case memoryPressure
    case cpuTemperature
    case gpuTemperature
    case batteryTemperature
    case fan
    case downloadSpeed
    case uploadSpeed
    // Accepted from existing local settings; the footer has separate sources for these.
    case volume
    case wifiSignal
    case batteryLevel

    var id: Self { self }

    var hardwareMetric: HardwareMonitorMetric? {
        self == .memoryPressure ? nil : HardwareMonitorMetric(rawValue: rawValue)
    }

    var withoutCPUGPUTemperature: Self {
        switch self {
        case .cpuTemperature: .cpuUsage
        case .gpuTemperature: .gpuUsage
        default: self
        }
    }

    var titleKey: LocalizationKey { hardwareMetric?.titleKey ?? .hardwareDetailPressure }
    var systemImage: String { hardwareMetric?.systemImage ?? "memorychip" }
}
