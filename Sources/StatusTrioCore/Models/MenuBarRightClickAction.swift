import Foundation

/// The single action performed when the user right-clicks the menu-bar icon.
///
/// Extend the quick-action surface by adding a case here: the settings picker
/// enumerates `allCases`, `MenuBarQuickActionAvailability` gains one capability
/// flag, and `MenuBarRightClickRouter` maps it to a `MenuBarRightClickOutcome`.
/// Nothing else enumerates the actions, so a new case is covered by the same
/// wiring as the existing ones.
enum MenuBarRightClickAction: String, CaseIterable, Identifiable, Sendable {
    /// Keep the historical behaviour: show the context menu.
    case contextMenu
    /// Toggle Low Power Mode on ↔ off.
    case toggleLowPowerMode
    /// Start charging to full, or cancel an in-flight charge.
    case chargeToFullNow
    /// Mute ↔ unmute the current output device.
    case toggleMute
    /// Turn the Wi-Fi radio on ↔ off.
    case toggleWiFi
    /// Refresh battery, Wi-Fi and volume readings immediately.
    case refreshStatus
    /// Open the system Settings pane for Wi-Fi.
    case openWiFiSettings
    /// Open the system Settings pane for Bluetooth.
    case openBluetoothSettings
    /// Open the system Settings pane for Battery.
    case openBatterySettings
    /// Open the system Settings pane for Sound.
    case openSoundSettings

    var id: Self { self }

    /// Localized name shown in the Settings picker.
    var titleKey: LocalizationKey {
        switch self {
        case .contextMenu: .menuBarRightClickContextMenu
        case .toggleLowPowerMode: .menuBarRightClickToggleLowPowerMode
        case .chargeToFullNow: .menuBarRightClickChargeToFullNow
        case .toggleMute: .menuBarRightClickToggleMute
        case .toggleWiFi: .menuBarRightClickToggleWiFi
        case .refreshStatus: .menuBarRightClickRefreshStatus
        case .openWiFiSettings: .menuBarRightClickOpenWiFiSettings
        case .openBluetoothSettings: .menuBarRightClickOpenBluetoothSettings
        case .openBatterySettings: .menuBarRightClickOpenBatterySettings
        case .openSoundSettings: .menuBarRightClickOpenSoundSettings
        }
    }

    /// SF Symbol used by the Settings row (only the currently selected action's
    /// glyph is shown, so the row stays compact).
    var settingsSymbol: String {
        switch self {
        case .contextMenu: "computermouse"
        case .toggleLowPowerMode: "leaf.fill"
        case .chargeToFullNow: "battery.100.bolt"
        case .toggleMute: "speaker.slash.fill"
        case .toggleWiFi: "wifi"
        case .refreshStatus: "arrow.clockwise"
        case .openWiFiSettings: "wifi"
        case .openBluetoothSettings: "dot.radiowaves.left.and.right"
        case .openBatterySettings: "battery.100"
        case .openSoundSettings: "speaker.wave.2.fill"
        }
    }
}
