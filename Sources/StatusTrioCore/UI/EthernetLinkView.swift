import SwiftUI

struct EthernetLinkView: View {
    @EnvironmentObject private var localization: Localization
    let state: PanelDetailState
    let onBack: () -> Void
    let onOpenNetworkSettings: () -> Void
    let onCopyValue: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationBackRow(
                accessibilityLabel: localization.string(.commonBack),
                title: state.title,
                action: onBack
            )

            PanelDetailRowsView(
                detailRows: state.rows,
                leadingInset: 26,
                onCopyValue: onCopyValue
            )
            .font(.caption)

            Divider()
            Button(localization.string(.ethernetActionOpenSettings), action: onOpenNetworkSettings)
                .buttonStyle(.plain)
        }
    }
}
