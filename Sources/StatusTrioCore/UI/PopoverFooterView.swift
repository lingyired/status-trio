import AppKit
import SwiftUI

/// The state-dependent parts of the popover footer, kept as plain data so the
/// settings label can be asserted without rendering a view.
enum PopoverFooterPresentation {
    /// Keep development identity in Settings About, not in the compact menu.
    static func settingsLabel(title: String, developmentSuffix _: String?) -> String {
        title
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
                HStack(spacing: 6) {
                    Label(settingsTitle, systemImage: "gearshape")
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let developmentCodename = AppMetadata.developmentCodename {
                        Text(developmentCodename)
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityLabel(settingsTitle)

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
                    updaterManager.checkForUpdates(preference: .githubFirst)
                }
                // Sparkle reports `canCheckForUpdates == false` while a check is
                // in flight, which is exactly the disabled window the footer
                // wants; while idle it enables itself again.
                .disabled(!updaterManager.canCheckForUpdates)

                Button(localization.string(.menuCheckViaGitee)) {
                    dismissPanel()
                    updaterManager.checkForUpdates(preference: .giteeFirst)
                }
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
