import SwiftUI

/// A selectable leaf beneath an expandable Settings category.
///
/// Only the complex categories (App Icon, Battery, Audio, Bluetooth) expose
/// subtopics; the simple categories remain single-pane and never enter this
/// type. A subtopic carries its own localized title (reused from the existing
/// group titles so no localization keys are added) and parent category, which
/// drive both the expanded sidebar rows and the detail-pane routing.
enum SettingsSubtopic: Hashable, Identifiable, CaseIterable {
    case appIconPlacementSize
    case appIconRingAndDock
    case appIconMiddleIcon

    case batteryIconDisplay
    case batteryColorsAndAnimation
    case batteryChargeManagement
    case batteryPowerAndEnergy

    case audioDisplayAndInteraction
    case audioDeviceManagement
    case audioExternalVolume

    case bluetoothDisplayAndPreview
    case bluetoothDeviceAndBattery
    case bluetoothPanelAndList

    var id: SettingsSubtopic { self }

    /// The sidebar category that owns this subtopic.
    var section: SettingsView.Section {
        switch self {
        case .appIconPlacementSize, .appIconRingAndDock, .appIconMiddleIcon:
            return .appIcon
        case .batteryIconDisplay, .batteryColorsAndAnimation,
             .batteryChargeManagement, .batteryPowerAndEnergy:
            return .battery
        case .audioDisplayAndInteraction, .audioDeviceManagement, .audioExternalVolume:
            return .audio
        case .bluetoothDisplayAndPreview, .bluetoothDeviceAndBattery, .bluetoothPanelAndList:
            return .bluetooth
        }
    }

    /// The first subtopic shown when a category first expands.
    var isDefault: Bool {
        switch self {
        case .appIconPlacementSize, .batteryIconDisplay,
             .audioDisplayAndInteraction, .bluetoothDisplayAndPreview:
            return true
        default:
            return false
        }
    }

    @MainActor
    func title(_ localization: Localization) -> String {
        switch self {
        // App Icon
        case .appIconPlacementSize: return localization.string(.settingsAppIconPlacement)
        case .appIconRingAndDock:   return localization.string(.settingsAppIconDockGroup)
        case .appIconMiddleIcon:    return localization.string(.settingsMiddleIconTitle)

        // Battery
        case .batteryIconDisplay:          return localization.string(.settingsBatteryGroupIcon)
        case .batteryColorsAndAnimation:   return localization.string(.settingsBatteryGroupColors)
        case .batteryChargeManagement:     return localization.string(.settingsBatteryGroupCharging)
        case .batteryPowerAndEnergy:       return localization.string(.settingsBatteryGroupPower)

        // Audio
        case .audioDisplayAndInteraction:  return localization.string(.settingsAudioIndicatorStyleTitle)
        case .audioDeviceManagement:       return localization.string(.settingsAudioDisplayRules)
        case .audioExternalVolume:         return localization.string(.settingsAudioExternalVolumeTitle)

        // Bluetooth
        case .bluetoothDisplayAndPreview:  return localization.string(.settingsBluetoothTitle)
        case .bluetoothDeviceAndBattery:   return localization.string(.settingsAppleDevicesAndBattery)
        case .bluetoothPanelAndList:       return localization.string(.settingsBluetoothDeviceListGroup)
        }
    }
}