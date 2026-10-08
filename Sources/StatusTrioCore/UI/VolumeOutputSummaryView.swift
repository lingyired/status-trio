import SwiftUI

/// Keeps the active output visible even when it falls outside the user's list limit.
struct VolumeOutputSummaryView: View {
    let state: VolumePanelState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PanelSymbolView(source: state.summary.symbol, size: 17, weight: .semibold)
                .frame(width: 24, height: 24)
                .foregroundStyle(state.summary.tint.color())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.summary.title)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(state.summary.title)

                Text(state.summary.subtitle)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.summary.accessibilityLabel)
        .accessibilityValue(state.summary.accessibilityValue)
    }
}
