import Foundation

/// What a right-click on the menu-bar icon ultimately does once availability is
/// resolved. Kept separate from the persisted selection so the mapping stays a
/// pure, testable function and cannot fall through silently.
enum MenuBarRightClickOutcome: Equatable {
    case showContextMenu
    case toggleLowPowerMode
    case toggleChargeToFullNow
    case toggleMute
}

/// A snapshot of which quick actions can run right now.
///
/// Each flag is resolved by the caller from the owning subsystem so the router
/// itself stays free of AppKit/state dependencies:
/// - `lowPowerMode`: privileged helper ready and the feature opted in.
/// - `chargeToFullNow`: the charge-to-full capability is supported on this Mac.
/// - `mute`: the current output device can be muted.
struct MenuBarQuickActionAvailability: Equatable {
    var lowPowerMode: Bool
    var chargeToFullNow: Bool
    var mute: Bool

    func isAvailable(_ action: MenuBarRightClickAction) -> Bool {
        switch action {
        case .contextMenu: true
        case .toggleLowPowerMode: lowPowerMode
        case .chargeToFullNow: chargeToFullNow
        case .toggleMute: mute
        }
    }
}

/// Pure mapping from the persisted selection and a live availability snapshot to
/// the action to run. An unavailable action always falls back to the context
/// menu so the user never gets a silent no-op.
enum MenuBarRightClickRouter {
    static func outcome(
        for action: MenuBarRightClickAction,
        availability: MenuBarQuickActionAvailability
    ) -> MenuBarRightClickOutcome {
        guard availability.isAvailable(action) else {
            return .showContextMenu
        }
        switch action {
        case .contextMenu: return .showContextMenu
        case .toggleLowPowerMode: return .toggleLowPowerMode
        case .chargeToFullNow: return .toggleChargeToFullNow
        case .toggleMute: return .toggleMute
        }
    }
}
