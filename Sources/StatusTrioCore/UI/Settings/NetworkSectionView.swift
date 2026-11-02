import SwiftUI

/// Settings for how the network indicator is drawn in the status icon.
struct NetworkSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    var inputSourceController: InputSourceController? = nil
    @Binding var previewIsDark: Bool
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage(pinnedHeader: {
            StatusIconPreviewCard(
                store: store,
                statusStore: statusStore,
                inputSourceController: inputSourceController,
                isDarkBackground: $previewIsDark
            )
        }) {
            panelGroup
        }
    }

    /// What the network row itself reports, as opposed to how the status icon
    /// draws it. Kept in its own group because the icon options above describe
    /// the menu bar artwork and this decides the panel's second line.
    private var panelGroup: some View {
        SettingsGroup(localization.string(.settingsNetworkPanelGroup)) {
            SettingsToggleRow(
                symbol: "network",
                tint: .cyan,
                title: localization.string(.settingsNetworkShowLocalIP),
                subtitle: localization.string(.settingsNetworkShowLocalIPDescription),
                isOn: $store.showsLocalIPAddress
            )
        }
    }

}
