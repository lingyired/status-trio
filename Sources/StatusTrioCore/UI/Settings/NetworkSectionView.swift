import SwiftUI

struct NetworkSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    var inputSourceController: InputSourceController? = nil
    @Binding var previewIsDark: Bool
    var onOpenIconDesigner: (IconSlot) -> Void = { _ in }
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage(pinnedHeader: {
            StatusIconPreviewCard(
                store: store,
                statusStore: statusStore,
                isDarkBackground: $previewIsDark,
                inputSourceController: inputSourceController,
                content: .menuBarOnly
            )
        }) {
            IconDesignerEntryRow(title: localization.string(.settingsNetworkDesignerEntry)) {
                onOpenIconDesigner(.center)
            }

            connectionIconsGroup
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

    private var connectionIconsGroup: some View {
        SettingsGroup(localization.string(.settingsNetworkConnectionIcons)) {
            SettingsHintRow(text: localization.string(.settingsNetworkConnectionIconsDescription))
            SettingsHintRow(text: localization.string(.settingsNetworkConnectionIconsDescription))
            SettingsMenuRow(
                symbol: "keyboard",
                tint: .indigo,
                title: localization.string(.settingsNetworkCenterSource),
                subtitle: localization.string(.settingsNetworkCenterSourceDescription),
                selection: $store.connectionCenterSource,
                options: ConnectionCenterSource.allCases,
                label: centerSourceLabel
            )

            if store.connectionCenterSource == .inputSource {
                SettingsDivider()

                SettingsToggleRow(
                    symbol: "wifi.exclamationmark",
                    tint: .orange,
                    title: localization.string(.settingsNetworkCenterSourceNetworkWarnings),
                    subtitle: localization.string(.settingsNetworkCenterSourceNetworkWarningsDescription),
                    isOn: $store.prioritizesNetworkErrorsOverInputSource
                )

                SettingsDivider()

                SettingsHintRow(
                    text: localization.string(.settingsNetworkCenterSourceBluetoothFallback)
                )
            }

            SettingsDivider()

            SettingsToggleRow(
                symbol: "cable.connector",
                tint: .teal,
                title: localization.string(.settingsNetworkWiFiIconForEthernet),
                isOn: $store.showsWiFiIconForEthernet
            )

            SettingsDivider()

            SettingsToggleRow(
                symbol: "personalhotspot",
                tint: .blue,
                title: localization.string(.settingsNetworkWiFiIconForHotspot),
                isOn: $store.showsWiFiIconForHotspot
            )

            SettingsDivider()

            SettingsToggleRow(
                symbol: "network",
                tint: .purple,
                title: localization.string(.settingsNetworkWiFiIconForTemporaryConnection),
                isOn: $store.showsWiFiIconForTemporaryConnection
            )

            SettingsDivider()

            SettingsToggleRow(
                symbol: "antenna.radiowaves.left.and.right",
                tint: .indigo,
                title: localization.string(.settingsNetworkWiFiIconForInternetSharing),
                isOn: $store.showsWiFiIconForInternetSharing
            )

            if store.iconConfiguration.composition.center.primary == .automaticLegacy {
                SettingsDivider()

                SettingsToggleRow(
                    symbol: "number",
                    tint: .teal,
                    title: localization.string(.settingsBatteryShowPercentageInConnectionSlot),
                    subtitle: localization.string(.settingsBatteryShowPercentageInConnectionSlotDescription),
                    isOn: $store.showsBatteryPercentageInConnectionSlot
                )
            }
        }
    }

    private func centerSourceLabel(_ source: ConnectionCenterSource) -> String {
        switch source {
        case .automatic:
            localization.string(.settingsNetworkCenterSourceAutomatic)
        case .inputSource:
            localization.string(.settingsNetworkCenterSourceInputSource)
        }
    }
}
