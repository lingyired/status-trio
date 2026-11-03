import AppKit
import SwiftUI

/// The state-dependent parts of the popover footer, kept as plain data so the
/// settings label can be asserted without rendering a view.
enum PopoverFooterPresentation {
    /// The settings button carries the development codename inline, where it has
    /// always been. The running version is deliberately not part of this label:
    /// it now lives in the standard About panel, so the button stays short and
    /// readable in every language.
    static func settingsLabel(title: String, developmentSuffix: String?) -> String {
        guard let developmentSuffix, !developmentSuffix.isEmpty else { return title }
        return "\(title) · \(developmentSuffix)"
    }

    /// Opens the Menu Bar pane in System Settings. One extension serves the pane
    /// on every supported release (Control Center on macOS 13–25, Menu Bar from
    /// 26), so the ordered URL list needs no version branch. Kept as a small
    /// helper so the view and any future footer action share the same route.
    static func openMenuBarSettings(
        workspace: NSWorkspace = .shared,
        urls: [URL] = MenuBarHelpPolicy().systemSettingsURLs
    ) {
        for url in urls where workspace.open(url) {
            return
        }
    }
}

struct PopoverFooterView: View {
    @EnvironmentObject private var localization: Localization
    @ObservedObject private var updaterManager: UpdaterManager = .shared
    let openSettings: () -> Void
    let quit: () -> Void
    /// Closes the status panel before an action opens another window. The panel
    /// sits above normal windows, so About / updates / System Settings must not
    /// be left behind it.
    var dismissPanel: () -> Void = {}

    private var settingsTitle: String {
        PopoverFooterPresentation.settingsLabel(
            title: localization.string(.menuSettings),
            developmentSuffix: AppMetadata.developmentCodename
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: openSettings) {
                Label(settingsTitle, systemImage: "gearshape")
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)

            // The version sits at the trailing edge rather than inside the
            // button's label, which has to stay readable in every language.
            // It stays visible here even though About also shows it: the footer
            // is where the running build is checked while testing.
            Text(AppMetadata.versionDisplayString)
                .lineLimit(1)
                .fixedSize()

            Menu {
                Button(localization.string(.menuCheckForUpdates)) {
                    dismissPanel()
                    updaterManager.checkForUpdates()
                }
                // Sparkle reports `canCheckForUpdates == false` while a check is
                // in flight, which is exactly the disabled window the footer
                // wants; while idle it enables itself again.
                .disabled(!updaterManager.canCheckForUpdates)

                Button(localization.format(.menuAbout, AppMetadata.name)) {
                    dismissPanel()
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                }

                Button(localization.string(.menuOpenMenuBarSettings)) {
                    dismissPanel()
                    PopoverFooterPresentation.openMenuBarSettings()
                }

                Divider()

                Button(localization.string(.menuQuit), action: quit)
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                PanelActionGlyph(systemName: "ellipsis.circle")
                    .accessibilityLabel(localization.string(.menuMore))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(localization.string(.menuMore))
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}
