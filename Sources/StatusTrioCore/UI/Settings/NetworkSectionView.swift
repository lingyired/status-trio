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
            // Permission notices come first, then the panel show/hide group.
            if statusStore.snapshot.wifi.nameAccess != .authorized {
                wifiPermissionNotice
            }
            panelGroup
        }
    }

    /// Shown at the top of the pane whenever Wi-Fi name access is not granted.
    /// macOS reads a Wi-Fi name through location services, so the notice mirrors
    /// the Bluetooth permission banner's look; `.notDetermined` offers to raise
    /// the system prompt, `.denied`/`.restricted` send the user to Settings.
    @ViewBuilder
    private var wifiPermissionNotice: some View {
        switch statusStore.snapshot.wifi.nameAccess {
        case .authorized:
            EmptyView()
        case .notDetermined:
            SettingsPermissionNotice(
                title: localization.string(.settingsNetworkPermissionNotDeterminedTitle),
                description: .settingsNetworkPermissionNotDeterminedDescription,
                buttonKey: .wifiActionRequestNameAccess,
                action: { requestLocationPermission() }
            )
        case .denied, .restricted:
            SettingsPermissionNotice(
                title: localization.string(.settingsNetworkPermissionDeniedTitle),
                description: .settingsNetworkPermissionDeniedDescription,
                buttonKey: .wifiActionOpenLocationSettings,
                action: { statusStore.openLocationSettings() }
            )
        }
    }

    private func requestLocationPermission() {
        if statusStore.requestWiFiNameAccess() == .openLocationSettings {
            statusStore.openLocationSettings()
        }
    }

    /// What the network row itself reports, as opposed to how the status icon
    /// draws it. Kept in its own group because the icon options above describe
    /// the menu bar artwork and this decides the panel's second line.
    private var panelGroup: some View {
        SettingsGroup(localization.string(.settingsNetworkPanelGroup)) {
            // The "show in status panel" toggle leads the pane.
            SettingsToggleRow(
                symbol: PopupSection.network.systemImage,
                tint: .blue,
                title: localization.string(.settingsPanelShowNetwork),
                subtitle: localization.string(.settingsPanelShowItemDescription),
                isOn: Binding(
                    get: { store.enabledPopupSections.contains(.network) },
                    set: { store.setPopupSection(.network, enabled: $0) }
                )
            )

            if WiFiPowerControlVisibility.showsSettingsControl(state: statusStore.snapshot.wifi.state) {
                SettingsDivider()
                SettingsToggleRow(
                    symbol: "power.circle",
                    tint: .blue,
                    title: localization.string(.settingsNetworkPowerControl),
                    subtitle: localization.string(.settingsNetworkPowerControlDescription),
                    isOn: $store.showsWiFiPowerControl
                )
            }

            SettingsDivider()

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
