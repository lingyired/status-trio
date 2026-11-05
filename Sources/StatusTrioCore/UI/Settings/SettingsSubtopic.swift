import SwiftUI

/// A selectable leaf beneath an expandable Settings category.
///
/// Only the complex categories (App Icon, Battery, Audio, Bluetooth) expose
/// subtopics; the simple categories remain single-pane and never enter this
/// type. A subtopic carries its own localized title and parent category, which
/// drive both the expanded sidebar rows and the detail-pane routing.
enum SettingsSubtopic: Hashable, Identifiable, CaseIterable {
    case appIconAppearance
    case appIconRing
    case appIconMiddleIcon
    case appIconBottomIndicator

    case batteryCharging
    case batteryPowerMode
    case batteryEnergy

    case audioVolumeControl
    case audioAudioDevices
    case audioDisplayVolume

    case bluetoothListeningMode
    case bluetoothDeviceBattery
    case bluetoothDeviceManagement

    var id: SettingsSubtopic { self }

    /// The sidebar category that owns this subtopic.
    var section: SettingsView.Section {
        switch self {
        case .appIconAppearance, .appIconRing, .appIconMiddleIcon, .appIconBottomIndicator:
            return .appIcon
        case .batteryCharging, .batteryPowerMode, .batteryEnergy:
            return .battery
        case .audioVolumeControl, .audioAudioDevices, .audioDisplayVolume:
            return .audio
        case .bluetoothListeningMode, .bluetoothDeviceBattery, .bluetoothDeviceManagement:
            return .bluetooth
        }
    }

    /// The first subtopic shown when a category first expands.
    var isDefault: Bool {
        switch self {
        case .appIconAppearance, .batteryCharging, .audioVolumeControl, .bluetoothListeningMode:
            return true
        default:
            return false
        }
    }

    @MainActor
    func title(_ localization: Localization) -> String {
        switch self {
        // App Icon
        case .appIconAppearance:      return localization.string(.settingsSubtopicAppIconAppearance)
        case .appIconRing:            return localization.string(.settingsSubtopicAppIconRing)
        case .appIconMiddleIcon:      return localization.string(.settingsSubtopicAppIconMiddleIcon)
        case .appIconBottomIndicator: return localization.string(.settingsSubtopicAppIconBottomIndicator)

        // Battery
        case .batteryCharging:   return localization.string(.settingsSubtopicBatteryCharging)
        case .batteryPowerMode:  return localization.string(.settingsSubtopicBatteryPowerMode)
        case .batteryEnergy:     return localization.string(.settingsSubtopicBatteryEnergy)

        // Audio
        case .audioVolumeControl:  return localization.string(.settingsSubtopicAudioVolumeControl)
        case .audioAudioDevices:   return localization.string(.settingsSubtopicAudioAudioDevices)
        case .audioDisplayVolume:  return localization.string(.settingsSubtopicAudioDisplayVolume)

        // Bluetooth
        case .bluetoothListeningMode:     return localization.string(.settingsSubtopicBluetoothListeningMode)
        case .bluetoothDeviceBattery:     return localization.string(.settingsSubtopicBluetoothDeviceBattery)
        case .bluetoothDeviceManagement:  return localization.string(.settingsSubtopicBluetoothDeviceManagement)
        }
    }
}
