import SwiftUI

/// Shared "Top markers" group for the system battery ring (#315 / #362).
///
/// Rendered by both App Icon -> This Mac's Battery (embedded in the ring-content
/// card) and Battery -> Status & Colors (its own card). Both copies bind to the
/// same SettingsStore fields, so editing either one updates the other — they are
/// a mirror, not two settings.
struct BatteryTopMarkersGroup: View {
    @ObservedObject var store: SettingsStore
    /// Whether the Mac actually has a battery. A desktop shows only the
    /// decorative plug/bolt choice.
    let hasBattery: Bool
    /// When `true` the view draws its own `SettingsGroup` card. The App Icon page
    /// embeds it inside the ring-content card, so it passes `false` to avoid a
    /// nested card.
    var embedsInGroup: Bool = true
    @EnvironmentObject private var localization: Localization

    var body: some View {
        if embedsInGroup {
            SettingsGroup(localization.string(.settingsTopMarkerGroup)) {
                content
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if hasBattery {
            // #315: one plain choice per power state, so the plug and bolt no
            // longer hide behind a "show percentage" toggle or a combined
            // "connected without charging" option.
            markerRow(
                symbol: "percent",
                tint: .green,
                title: .settingsBatteryMarkerOnBattery,
                selection: $store.batteryOnBatteryMarker,
                options: BatteryTopMarker.onBatteryOptions
            )

            SettingsDivider()

            markerRow(
                symbol: "bolt.fill",
                tint: .yellow,
                title: .settingsBatteryMarkerCharging,
                selection: $store.batteryChargingMarker,
                options: BatteryTopMarker.onPowerOptions
            )

            SettingsDivider()

            markerRow(
                symbol: "powerplug.portrait.fill",
                tint: .teal,
                title: .settingsBatteryMarkerConnected,
                selection: $store.batteryConnectedMarker,
                options: BatteryTopMarker.onPowerOptions
            )
        } else {
            // A Mac with no battery: the only top marker to configure is a
            // decorative plug / bolt (or nothing).
            markerRow(
                symbol: "bolt.fill",
                tint: .yellow,
                title: .settingsBatteryNoBatteryTopIndicator,
                selection: $store.batteryNoBatteryMarker,
                options: BatteryTopMarker.noBatteryOptions
            )
        }
    }

    private func markerRow(
        symbol: String,
        tint: Color,
        title: LocalizationKey,
        selection: Binding<BatteryTopMarker>,
        options: [BatteryTopMarker]
    ) -> some View {
        SettingsMenuRow(
            symbol: symbol,
            tint: tint,
            title: localization.string(title),
            selection: selection,
            options: options,
            label: markerLabel
        )
    }

    private func markerLabel(_ marker: BatteryTopMarker) -> String {
        switch marker {
        case .percentage:
            localization.string(.settingsBatteryConnectedIndicatorPercentage)
        case .bolt:
            localization.string(.settingsBatteryConnectedIndicatorBolt)
        case .plug:
            localization.string(.settingsBatteryConnectedIndicatorPlug)
        case .hidden:
            localization.string(.settingsBatteryMarkerHidden)
        }
    }
}
