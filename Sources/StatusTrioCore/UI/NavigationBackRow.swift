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

struct NavigationBackRow: View {
    @Environment(\.statusPanelBoldTextEnabled) private var panelBoldText
    @Environment(\.statusPanelDetailHost) private var isDetailHost
    @EnvironmentObject private var localization: Localization
    let accessibilityLabel: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                PanelActionGlyph(systemName: isDetailHost ? "xmark" : "chevron.backward", size: 32)
                Text(title)
                    .font(.headline.weight(panelBoldText ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDetailHost ? localization.string(.commonCloseDetail) : accessibilityLabel)
    }
}
