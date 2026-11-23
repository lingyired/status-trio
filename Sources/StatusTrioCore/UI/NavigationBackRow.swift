import SwiftUI

/// Whether the current detail page is hosted in the attached side window.
/// The shared navigation row then reads as a close action instead of back.
private struct StatusPanelDetailHostKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var statusPanelDetailHost: Bool {
        get { self[StatusPanelDetailHostKey.self] }
        set { self[StatusPanelDetailHostKey.self] = newValue }
    }
}

/// The shared detail-page header: a back/close action plus an optional trailing
/// control (for example the hardware pages' "Open Activity Monitor" button).
///
/// The back/close action and the trailing control live side by side as separate
/// hit targets, so tapping the trailing control never triggers the row's own
/// navigation. The back row still spans the remaining width, keeping its
/// full-width hit area.
struct NavigationBackRow<Trailing: View>: View {
    @Environment(\.statusPanelBoldTextEnabled) private var panelBoldText
    @Environment(\.statusPanelDetailHost) private var isDetailHost
    @EnvironmentObject private var localization: Localization
    let accessibilityLabel: String
    let title: String
    let action: () -> Void
    let trailing: Trailing

    init(accessibilityLabel: String,
         title: String,
         action: @escaping () -> Void,
         @ViewBuilder trailing: () -> Trailing) {
        self.accessibilityLabel = accessibilityLabel
        self.title = title
        self.action = action
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: action) {
                HStack(alignment: .center, spacing: 8) {
                    PanelActionGlyph(systemName: isDetailHost ? "xmark" : "chevron.backward", size: isDetailHost ? 24 : 32)
                    Text(title)
                        .font(.headline.weight(panelBoldText ? .semibold : .regular))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDetailHost ? localization.string(.commonCloseDetail) : accessibilityLabel)

            trailing
        }
    }
}

extension NavigationBackRow where Trailing == EmptyView {
    /// A plain back/close row with no trailing control.
    init(accessibilityLabel: String,
         title: String,
         action: @escaping () -> Void) {
        self.init(accessibilityLabel: accessibilityLabel, title: title, action: action) {
            EmptyView()
        }
    }
}
