import SwiftUI

/// The state-dependent parts of the popover footer, kept as plain data so the
/// settings label can be asserted without rendering a view.
enum PopoverFooterPresentation {
    /// The settings button carries the development codename inline, where it has
    /// always been. The running version is deliberately not part of this label:
    /// it is a separate element at the trailing edge of the row, so the button
    /// stays short and readable in every language.
    static func settingsLabel(title: String, developmentSuffix: String?) -> String {
        guard let developmentSuffix, !developmentSuffix.isEmpty else { return title }
        return "\(title) · \(developmentSuffix)"
    }
}

struct PopoverFooterView: View {
    @EnvironmentObject private var localization: Localization
    let openSettings: () -> Void
    let quit: () -> Void

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
            Text(AppMetadata.versionDisplayString)
                .lineLimit(1)
                .fixedSize()

            Menu {
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
