import SwiftUI

struct VPNStatusView: View {
    let state: PanelSummaryState

    var body: some View {
        HStack(spacing: 10) {
            PanelSymbolView(source: state.symbol)
                .foregroundStyle(state.tint.color(caution: .orange))
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(state.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityValue(state.accessibilityValue)
    }
}
