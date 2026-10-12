import SwiftUI

struct NetworkSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @Binding var previewIsDark: Bool
    var onOpenIconDesigner: (IconSlot) -> Void = { _ in }
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage(pinnedHeader: {
            StatusIconPreviewCard(
                store: store,
                statusStore: statusStore,
                isDarkBackground: $previewIsDark,
                content: .menuBarOnly
            )
        }) {
            IconDesignerEntryRow(title: localization.string(.settingsNetworkDesignerEntry)) {
                onOpenIconDesigner(.center)
            }

            connectionIconsGroup
        }
    }

    private var connectionIconsGroup: some View {
        SettingsGroup(localization.string(.settingsNetworkConnectionIcons)) {
            SettingsHintRow(text: localization.string(.settingsNetworkConnectionIconsDescription))

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
}
