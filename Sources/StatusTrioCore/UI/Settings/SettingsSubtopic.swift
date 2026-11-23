import SwiftUI

/// A selectable leaf beneath an expandable Settings category.
///
/// Only **App Icon** exposes subtopics. Battery, Bluetooth and Audio are single
/// panes now: their controls are grouped by card inside one page, so they never
/// enter this type. A subtopic carries its own localized title and parent
/// category, which drive both the expanded sidebar rows and the detail routing.
enum SettingsSubtopic: Hashable, Identifiable, CaseIterable {
    case appIconAppearance
    case appIconRing
    case appIconMiddleIcon
    case appIconBottomIndicator

    var id: SettingsSubtopic { self }

    /// The sidebar category that owns this subtopic.
    var section: SettingsView.Section {
        switch self {
        case .appIconAppearance, .appIconRing, .appIconMiddleIcon, .appIconBottomIndicator:
            return .appIcon
        }
    }

    /// The first subtopic shown when a category first expands.
    var isDefault: Bool {
        switch self {
        case .appIconAppearance:
            return true
        default:
            return false
        }
    }

    @MainActor
    func title(_ localization: Localization) -> String {
        switch self {
        case .appIconAppearance:      return localization.string(.settingsSubtopicAppIconAppearance)
        case .appIconRing:            return localization.string(.settingsSubtopicAppIconRing)
        case .appIconMiddleIcon:      return localization.string(.settingsSubtopicAppIconMiddleIcon)
        case .appIconBottomIndicator: return localization.string(.settingsSubtopicAppIconBottomIndicator)
        }
    }
}
