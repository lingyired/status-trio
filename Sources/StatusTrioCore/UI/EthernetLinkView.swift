import SwiftUI

struct EthernetLinkView: View {
    @EnvironmentObject private var localization: Localization
    let state: PanelDetailState
    let onBack: () -> Void
    let onOpenNetworkSettings: () -> Void
    let onOpenSharingSettings: () -> Void
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
            VStack(alignment: .leading, spacing: 6) {
                Button(localization.string(.ethernetActionOpenSettings), action: onOpenNetworkSettings)
                    .buttonStyle(.plain)

                // Internet Sharing needs root to toggle and has no public API, so
                // this hands the user to the Sharing pane rather than writing the
                // system's network configuration from the app.
                Button(localization.string(.networkActionShareInternet), action: onOpenSharingSettings)
                    .buttonStyle(.plain)
                    .help(localization.string(.networkActionShareInternetHelp))
            }
        }
    }
}
