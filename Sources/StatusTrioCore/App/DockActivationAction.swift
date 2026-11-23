enum DockActivationAction: String, Equatable {
    case showPopover = "Popover"
    case openSettings = "Settings"
    case none = "None"

    static func resolve(
        event: AppleEventActivation,
        showsPersistentDockIcon: Bool,
        backgroundUITesting: BackgroundUITestingConfiguration = .disabled,
        hasVisibleOnboarding: Bool = false
    ) -> DockActivationAction {
        // Native attachment sends reopen even when it only intends to inspect
        // a window. Keep physical Dock and other launchers on their normal route.
        if backgroundUITesting.isEnabled, event.kind == .reopen,
           event.senderBundleIdentifier == "com.openai.sky.CUAService" {
            return hasVisibleOnboarding ? .none : .openSettings
        }
        return resolve(
            isReopenEvent: event.kind == .reopen, sender: event.sender,
            showsPersistentDockIcon: showsPersistentDockIcon
        )
    }

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
