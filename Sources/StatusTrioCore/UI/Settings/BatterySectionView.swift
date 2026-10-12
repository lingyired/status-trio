import SwiftUI

struct BatterySectionView: View {
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
            IconDesignerEntryRow(title: localization.string(.settingsBatteryDesignerEntry)) {
                onOpenIconDesigner(.outerRing)
            }

            macBatteryBehaviorGroup
        }
    }

    private var macBatteryBehaviorGroup: some View {
        SettingsGroup(localization.string(.settingsBatteryMacBehavior)) {
            SettingsHintRow(text: localization.string(.settingsBatteryMacBehaviorDescription))

            SettingsDivider()

            SettingsToggleRow(
                symbol: "percent",
                tint: .green,
                title: localization.string(.settingsBatteryShowPercentage),
                isOn: $store.showsBatteryPercentage
            )

            SettingsDivider()

            SettingsToggleRow(
                symbol: "bolt.fill",
                tint: .yellow,
                title: localization.string(.settingsBatteryShowChargingIndicator),
                subtitle: localization.string(.settingsBatteryChargingDescription),
                isOn: $store.showsChargingIndicator
            )

            SettingsDivider()

            SettingsToggleRow(
                symbol: "sparkles",
                tint: .green,
                title: localization.string(.settingsBatteryChargingEffect),
                subtitle: localization.string(.settingsBatteryChargingEffectDescription),
                isOn: $store.showsChargingEffect
            )

            SettingsDivider()

            SettingsToggleRow(
                symbol: "number",
                tint: .teal,
                title: localization.string(.settingsBatteryPercentageWhenConnected),
                subtitle: localization.string(.settingsBatteryPercentageWhenConnectedDescription),
                isOn: $store.showsPercentageWhenConnected
            )
        }
    }
}
