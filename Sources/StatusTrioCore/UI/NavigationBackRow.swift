import SwiftUI

struct NavigationBackRow: View {
    @Environment(\.statusPanelBoldTextEnabled) private var panelBoldText
    let accessibilityLabel: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                PanelActionGlyph(systemName: "chevron.backward", size: 32)
                Text(title)
                    .font(.headline.weight(panelBoldText ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
