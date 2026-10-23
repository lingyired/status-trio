enum DockActivationAction: String, Equatable {
    case showPopover = "Popover"
    case openSettings = "Settings"
    case none = "None"

    /// Prefer the user's persistent Dock choice when the sender is ambiguous.
    /// Some launchers share Dock's sender process and cannot be distinguished
    /// from a tile click using public Apple Event metadata.
    static func resolve(
        isReopenEvent: Bool,
        sender: AppleEventSender,
        showsPersistentDockIcon: Bool
    ) -> DockActivationAction {
        guard isReopenEvent else { return .none }
        switch sender {
        case .finder, .spotlight, .launcher:
            return .openSettings
        case .dock, .other, .unknown:
            return showsPersistentDockIcon ? .showPopover : .openSettings
        }
    }
}
