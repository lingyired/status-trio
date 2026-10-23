import Foundation

enum MenuBarHelpSettingsTier: Equatable {
    /// macOS 26 and later name the pane Menu Bar, although it still loads the
    /// `ControlCenter-Settings` extension that macOS 13 through 25 list as
    /// Control Center.
    case menuBarSettings
    /// macOS 13 through 25 expose the same extension as Control Center.
    case controlCenterSettings
}

struct MenuBarHelpPolicy: Equatable {
    let majorVersion: Int

    init(majorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) {
        self.majorVersion = majorVersion
    }

    var tier: MenuBarHelpSettingsTier {
        majorVersion >= 26 ? .menuBarSettings : .controlCenterSettings
    }

    /// macOS 27 is the first release whose menu bar exposes the native overflow
    /// indicator. Later releases inherit it.
    var showsNativeOverflowEntry: Bool {
        majorVersion >= 27
    }

    var stepKeys: [LocalizationKey] {
        if showsNativeOverflowEntry {
            return [
                .guideMenuBarHelpOverflowStep,
                .guideMenuBarHelpMenuBarSettingsStep,
                .guideMenuBarHelpMoveStep
            ]
        }

        return [
            tier == .menuBarSettings
                ? .guideMenuBarHelpMenuBarSettingsStep
                : .guideMenuBarHelpControlCenterStep,
            .guideMenuBarHelpFindStatusTrioStep,
            .guideMenuBarHelpMoveStep
        ]
    }

    var systemSettingsButtonKey: LocalizationKey {
        majorVersion >= 26
            ? .guideMenuBarHelpOpenMenuBarSettings
            : .guideMenuBarHelpOpenSystemSettings
    }

    var systemSettingsURLs: [URL] {
        // One extension serves this pane on every supported release: it is
        // Control Center on macOS 13 through 25 and Menu Bar from 26. The
        // identifier is not version-specific, so it stays first with no
        // `majorVersion` branch, matching the other Settings pane routes.
        [Self.controlCenterSettingsURL, Self.systemSettingsAppURL]
    }

    static let controlCenterSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
    )!

    static let systemSettingsAppURL = URL(string: "x-apple.systempreferences:")!

    static let allLocalizationKeys: [LocalizationKey] = [
        .guideMenuBarHelpPrompt,
        .guideMenuBarHelpOpen,
        .guideMenuBarHelpTitle,
        .guideMenuBarHelpReason,
        .guideMenuBarHelpOverflowStep,
        .guideMenuBarHelpMenuBarSettingsStep,
        .guideMenuBarHelpControlCenterStep,
        .guideMenuBarHelpFindStatusTrioStep,
        .guideMenuBarHelpMoveStep,
        .guideMenuBarHelpOpenMenuBarSettings,
        .guideMenuBarHelpOpenSystemSettings,
        .guideMenuBarHelpReopen,
        .guideMenuBarHelpLearnMore,
        .guideMenuBarHelpClose
    ]
}

struct MenuBarHelpPresentation: Equatable {
    var isPresented = false

    mutating func toggle() {
        isPresented.toggle()
    }

    mutating func close() {
        isPresented = false
    }

    mutating func prepareForPageChange() {
        close()
    }
}
