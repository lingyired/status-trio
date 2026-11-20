import SwiftUI

/// Shared "Status & Colors" group for the system battery ring.
///
/// Rendered by both App Icon -> This Mac's Battery and Battery -> Status & Colors.
/// Both copies bind to the same SettingsStore fields, so editing either one
/// updates the other (they are a mirror, not two settings).
struct BatteryStatusColorsGroup: View {
    @ObservedObject var store: SettingsStore
    let hasBattery: Bool
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsGroup(localization.string(.settingsBatteryGroupColors)) {
            // #309: use black/white for the charging / connected state, while
            // Low/High Power Mode and critical keep their own colours. nil means
            // automatic — on by default on a battery-less Mac, off otherwise.
            SettingsToggleRow(
                symbol: "circle.lefthalf.filled",
                tint: .gray,
                title: localization.string(.settingsBatteryMonochromeCharging),
                subtitle: localization.string(.settingsBatteryMonochromeChargingDescription),
                isOn: Binding(
                    get: { store.monochromeChargingRing ?? !hasBattery },
                    set: { store.monochromeChargingRing = $0 }
                )
            )

            SettingsDivider()

            SettingsToggleRow(
                symbol: "paintpalette.fill",
                tint: .orange,
                title: localization.string(.settingsBatteryStatusColors),
                subtitle: localization.string(.settingsBatteryStatusColorsDescription),
                isOn: $store.usesBatteryStatusColors
            )

            BatteryStatusColorsView(store: store)

            if store.usesBatteryStatusColors {
                SettingsDivider()

                SettingsRow(
                    "exclamationmark.triangle.fill",
                    tint: .red,
                    title: localization.string(.settingsBatteryCriticalThreshold),
                    subtitle:
                        localization.string(.settingsBatteryCriticalThresholdDescription)
                ) {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { store.batteryCriticalThreshold },
                                set: { store.batteryCriticalThreshold = $0.rounded() }
                            ),
                            in: SettingsStore.batteryCriticalThresholdRange
                        )
                        .frame(width: 130)
                        .controlSize(.small)
                        .accessibilityLabel(
                            localization.string(.settingsBatteryCriticalThreshold)
                        )
                        .accessibilityValue("\(Int(store.batteryCriticalThreshold))%")

                        Text("\(Int(store.batteryCriticalThreshold))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }
}
