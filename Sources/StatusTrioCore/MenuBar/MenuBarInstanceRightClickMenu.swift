import Foundation

enum MenuBarMenuEntry: Equatable {
    case action(id: String, titleKey: LocalizationKey, enabled: Bool)
    case separator
}

/// Builds the right-click menu for one instance: the configured quick action
/// first, then a separator, then "Disable". Deleting an instance is only ever
/// available in Settings, never from this menu.
enum MenuBarInstanceRightClickMenu {
    static let disableID = "menubar.instance.disable"

    static func entries(
        rightClick: InstanceRightClick,
        resolvedTitleKey: LocalizationKey,
        resolvedEnabled: Bool
    ) -> [MenuBarMenuEntry] {
        let first: MenuBarMenuEntry
        switch rightClick {
        case .quickAction(let id):
            first = .action(id: id, titleKey: resolvedTitleKey, enabled: resolvedEnabled)
        case .sameAsMainIcon:
            first = .action(id: "mainIcon", titleKey: resolvedTitleKey, enabled: resolvedEnabled)
        }
        return [
            first,
            .separator,
            .action(id: disableID, titleKey: .menuBarInstanceDisable, enabled: true),
        ]
    }
}
