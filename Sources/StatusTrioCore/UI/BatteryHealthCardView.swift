import SwiftUI

/// Compact, static health summary drawn below the existing power flow. It has
/// no animation, timer, or sampling of its own: it only renders the localized
/// values the details snapshot already produced, so a closed page costs nothing.
struct BatteryHealthCardView: View {
    @EnvironmentObject private var localization: Localization
    let state: BatteryHealthCardState

    private let columns = [
        GridItem(.flexible(), spacing: 12, alignment: .leading),
        GridItem(.flexible(), spacing: 12, alignment: .leading)
    ]

    private var cells: [BatteryHealthCardState.Metric] {
        var cells = state.metrics
        cells.append(BatteryHealthCardState.Metric(
            id: "chargeTime",
            label: state.chargeTimeLabel,
            value: state.chargeTimeValue
        ))
        return cells
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.title)
                .font(.caption)
                .fontWeight(.semibold)
                .help(state.footnote ?? "")
                .accessibilityHint(state.footnote ?? "")

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(cells) { cell in
                    VStack(alignment: .leading, spacing: 1) {
                        // Long shipped translations must wrap, not truncate:
                        // the label is the only thing that names the value.
                        Text(cell.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(cell.value)
                            .font(.caption)
                            .monospacedDigit()
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(cell.accessibilityValue)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
