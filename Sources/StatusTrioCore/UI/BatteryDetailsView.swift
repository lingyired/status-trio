import SwiftUI

struct BatteryDetailsView: View {
    @EnvironmentObject private var localization: Localization
    let state: PanelDetailState
    let onBack: () -> Void
    let onOpenBatterySettings: () -> Void
    let onCopyValue: (String) -> Void
    let onAppear: () -> Void

    private var detailRows: [PanelDetailRow] { state.rows }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationBackRow(
                accessibilityLabel: localization.string(.commonBack),
                title: state.title,
                action: onBack
            )

            VStack(alignment: .leading, spacing: 6) {
                if state.isLoading {
                    Text(localization.string(.batteryDetailsLoading))
                        .foregroundStyle(.secondary)
                }
                PanelDetailRowsView(detailRows: detailRows, onCopyValue: onCopyValue)
                if let explanation = state.explanation {
                    Text(explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.caption)
            .monospacedDigit()

            Divider()
            Button(localization.string(.batteryActionOpenSettings), action: onOpenBatterySettings)
                .buttonStyle(.plain)
        }
        .task(id: state.lifecycleIdentity) { onAppear() }
    }
}
