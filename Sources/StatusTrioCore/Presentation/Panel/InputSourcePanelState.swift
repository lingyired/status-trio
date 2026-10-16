import Foundation

/// Presentation-ready snapshot of the input-source section.
///
/// Values are already localized; the view only lays them out and routes
/// intents, so no view ever touches TIS or the controller.
struct InputSourcePanelState: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        let id: String
        let name: String
        /// The source's own icon, when it ships one.
        let iconURL: URL?
        /// The 1-2 grapheme marker drawn when there is no icon.
        let marker: String?
        let isCurrent: Bool
    }

    let title: String
    let currentName: String?
    let rows: [Row]
    let emptyMessage: String?
    let failureText: String?
    let openSettingsLabel: String

    @MainActor
    static func empty(localization: Localization) -> InputSourcePanelState {
        InputSourcePanelState(
            title: localization.string(.inputSourceTitle),
            currentName: nil,
            rows: [],
            emptyMessage: nil,
            failureText: nil,
            openSettingsLabel: localization.string(.inputSourceOpenSettings)
        )
    }
}
