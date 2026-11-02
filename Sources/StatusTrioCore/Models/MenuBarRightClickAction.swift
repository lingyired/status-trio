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

    var id: Self { self }

    /// Localized name shown in the Settings picker.
    var titleKey: LocalizationKey {
        switch self {
        case .contextMenu: .menuBarRightClickContextMenu
        case .toggleLowPowerMode: .menuBarRightClickToggleLowPowerMode
        case .chargeToFullNow: .menuBarRightClickChargeToFullNow
        case .toggleMute: .menuBarRightClickToggleMute
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
        }
    }
}
