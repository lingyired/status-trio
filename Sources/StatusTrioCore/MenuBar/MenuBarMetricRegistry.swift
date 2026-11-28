import Foundation

/// Display-only layer over the existing monitoring sources. It never samples;
/// it maps each menu-bar metric to a title, a value kind, a formatter and the
/// hardware metric whose colour definition it reuses.
enum MenuBarMetricValueKind: Equatable, Sendable {
    case numeric
    case text
}

struct MenuBarMetricReading: Equatable, Sendable {
    var text: String
    var value: Double?
    var availability: HardwareMetricAvailability
}

enum MenuBarMetricRegistry {
    static let all = MenuBarMetricID.allCases

    static func titleKey(for metric: MenuBarMetricID) -> LocalizationKey {
        switch metric {
        case .cpuUsage: return .hardwareMonitorCPU
        case .cpuTemperature: return .hardwareMonitorTemperature
        case .gpuUsage: return .hardwareMonitorGPU
        case .gpuTemperature: return .hardwareMonitorGPUTemperature
        case .memoryUsage: return .hardwareMonitorMemory
        case .diskReadSpeed: return .hardwareMonitorDiskRead
        case .diskWriteSpeed: return .hardwareMonitorDiskWrite
        case .networkDownload: return .hardwareMonitorDownload
        case .networkUpload: return .hardwareMonitorUpload
        case .fanRPM: return .hardwareMonitorFan
        case .batteryLevel: return .hardwareMonitorBattery
        case .wifiConnectionStatus: return .menuBarMetricWifiConnected
        case .outputVolume: return .hardwareMonitorVolume
        case .screenBrightness: return .settingsTabBrightness
        }
    }

    static func valueKind(for metric: MenuBarMetricID) -> MenuBarMetricValueKind {
        metric == .wifiConnectionStatus ? .text : .numeric
    }

    /// The hardware metric whose colour definition this menu-bar metric reuses,
    /// or nil when it has no hardware colour (text metrics / disk / brightness).
    static func hardwareMonitorMetric(for metric: MenuBarMetricID) -> HardwareMonitorMetric? {
        switch metric {
        case .cpuUsage: return .cpuUsage
        case .cpuTemperature: return .cpuTemperature
        case .gpuUsage: return .gpuUsage
        case .gpuTemperature: return .gpuTemperature
        case .memoryUsage: return .memoryUsage
        case .networkDownload: return .downloadSpeed
        case .networkUpload: return .uploadSpeed
        case .fanRPM: return .fan
        case .batteryLevel: return .batteryLevel
        case .outputVolume: return .volume
        case .diskReadSpeed, .diskWriteSpeed, .wifiConnectionStatus, .screenBrightness:
            return nil
        }
    }

    /// The hardware sampler identity, for demand registration.
    static func hardwareMetricID(for metric: MenuBarMetricID) -> HardwareMetricID? {
        switch metric {
        case .cpuUsage: return .cpuUsage
        case .cpuTemperature: return .cpuTemperature
        case .gpuUsage: return .gpuUsage
        case .gpuTemperature: return .gpuTemperature
        case .memoryUsage: return .memoryUsage
        case .diskReadSpeed: return .diskRead
        case .diskWriteSpeed: return .diskWrite
        case .networkDownload: return .networkDownload
        case .networkUpload: return .networkUpload
        case .fanRPM: return .fanRPM(index: 0)
        // These come from snapshots, not the hardware sampler.
        case .batteryLevel, .wifiConnectionStatus, .outputVolume, .screenBrightness:
            return nil
        }
    }

    static func format(_ value: Double, for metric: MenuBarMetricID) -> String {
        switch metric {
        case .cpuUsage, .gpuUsage, .memoryUsage, .batteryLevel, .outputVolume, .screenBrightness:
            return String(format: "%.0f%%", value)
        case .cpuTemperature, .gpuTemperature:
            return String(format: "%.0f°", value)
        case .fanRPM:
            return String(format: "%.0f RPM", value)
        case .diskReadSpeed, .diskWriteSpeed, .networkDownload, .networkUpload:
            return NetworkSpeedFormatter.display(bytesPerSecond: value)
        case .wifiConnectionStatus:
            return ""
        }
    }
}
