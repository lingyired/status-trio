import Foundation

enum MenuBarInstanceResolvedAction: Equatable {
    case noop
    case followMainIcon
    case showPanel(routeRaw: String)
    case openAppSettings
    case openActivityMonitor
    case openSystemSettings(SystemSettingsPane)
}

/// Pure mapping from a configured activation to an action. Hover never launches
/// external apps, so those activations degrade to `.noop` in hover mode.
enum MenuBarInstanceActivationResolver {
    static func resolve(_ activation: InstanceActivation, forHover: Bool) -> MenuBarInstanceResolvedAction {
        switch activation {
        case .none:
            return .noop
        case .sameAsMainIcon:
            return .followMainIcon
        case .panel(let raw):
            return .showPanel(routeRaw: raw)
        case .openAppSettings:
            return forHover ? .noop : .openAppSettings
        case .openActivityMonitor:
            return forHover ? .noop : .openActivityMonitor
        case .openSystemSettings(let pane):
            return forHover ? .noop : .openSystemSettings(pane)
        }
    }
}
