import Foundation

struct SettingsSurfaceVisibility: Equatable {
    static let legacyOwner = "legacy"
    static let settingsOwner = "settings-window"
    static let designerOwner = "icon-designer-window"

    private(set) var owners: Set<String> = []

    var isVisible: Bool { !owners.isEmpty }

    mutating func setVisible(_ visible: Bool, owner: String) {
        if visible {
            owners.insert(owner)
        } else {
            owners.remove(owner)
        }
    }
}
