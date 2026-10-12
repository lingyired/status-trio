import SwiftUI

/// Settings for how the battery indicator is drawn in the status icon.
struct BatterySectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @Binding var previewIsDark: Bool
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage(pinnedHeader: {
            StatusIconPreviewCard(
                store: store,
                statusStore: statusStore,
                isDarkBackground: $previewIsDark
            )
        }) {
            batteryGroup
        }
    }

    private var batteryGroup: some View {
        SettingsGroup(localization.string(.settingsBatteryTitle)) {
            // Show Percentage Switch
            SettingsToggleRow(
                symbol: "percent",
                tint: .green,
                title: localization.string(.settingsBatteryShowPercentage),
                isOn: $store.showsBatteryPercentage
            )

            SettingsDivider()

            SettingsToggleRow(
                symbol: "number",
                tint: .teal,
                title: localization.string(.settingsBatteryShowPercentageInConnectionSlot),
                subtitle: localization.string(
                    .settingsBatteryShowPercentageInConnectionSlotDescription
                ),
                isOn: $store.showsBatteryPercentageInConnectionSlot
            )

            SettingsDivider()

            // Charging Bolt Switch
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
                symbol: "bolt.fill",
                tint: .yellow,
                title: localization.string(.settingsBatteryChargingBoltHeartbeat),
                subtitle: localization.string(.settingsBatteryChargingBoltHeartbeatDescription),
                isOn: $store.showsChargingBoltHeartbeat
            )
            .disabled(!store.showsChargingEffect || !store.showsChargingIndicator)

            if ChargingEffectTestMode.isAvailable() {
                SettingsDivider()

                SettingsToggleRow(
                    symbol: SymbolFallback.name("flask.fill", "testtube.2"),
                    tint: .orange,
                    title: localization.string(.settingsBatteryChargingEffectTest),
                    subtitle: localization.string(.settingsBatteryChargingEffectTestDescription),
                    isOn: Binding(
                        get: { store.testsChargingEffect },
                        set: { store.setChargingEffectTestEnabled($0) }
                    )
                )
            }

            if store.showsChargingIndicator && store.showsBatteryPercentage {
                SettingsDivider()

                SettingsToggleRow(
                    symbol: "number",
                    tint: .teal,
                    title: localization.string(.settingsBatteryPercentageWhenConnected),
                    subtitle: localization.string(
                        .settingsBatteryPercentageWhenConnectedDescription
                    ),
                    isOn: $store.showsPercentageWhenConnected
                )
            }

            // Symbol Scale (Inline compact slider)
            if store.isBatterySymbolSizeEnabled {
                SettingsDivider()

                SettingsRow(
                    "textformat.size",
                    tint: .blue,
                    title: localization.string(.settingsBatterySymbolScale),
                    subtitle: localization.string(.settingsBatterySymbolScaleDescription)
                ) {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { store.batterySymbolScale },
                                set: { store.batterySymbolScale = ($0 * 20).rounded() / 20 }
                            ),
                            in: SettingsStore.batterySymbolScaleRange
                        )
                        .frame(width: 130)
                        .controlSize(.small)
                        .accessibilityLabel(
                            localization.string(.settingsBatterySymbolScaleAccessibility)
                        )
                        .accessibilityValue("\(Int(store.batterySymbolScale * 100))%")

                        Text("\(Int(store.batterySymbolScale * 100))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            SettingsDivider()

            // Status Colors Switch
            SettingsToggleRow(
                symbol: "paintpalette.fill",
                tint: .orange,
                title: localization.string(.settingsBatteryStatusColors),
                subtitle: localization.string(.settingsBatteryStatusColorsDescription),
                isOn: $store.usesBatteryStatusColors
            )

            // Critical Threshold (Inline compact slider)
            if store.usesBatteryStatusColors {
                SettingsDivider()

                SettingsRow(
                    "exclamationmark.triangle.fill",
                    tint: .red,
                    title: localization.string(.settingsBatteryCriticalThreshold),
                    subtitle: localization.string(.settingsBatteryCriticalThresholdDescription)
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

            SettingsDivider()

            // Full Ring Level (#105)
            //
            // The slider row is byte-for-byte the low-battery threshold row
            // above it, so the percentage lands on the same baseline as every
            // other slider on the pane.
            //
            // The "use the system value" action is a link in the description
            // rather than a button of its own: it is a one-shot convenience, not
            // a setting, and a second row for it would spend a whole row on an
            // action nobody looks for. As a link it reads as part of the
            // explanation — "here is when you would want this, and here is how
            // to fill it in".
            SettingsRow(
                "battery100.bolt",
                tint: .green,
                title: localization.string(.settingsBatteryFullThreshold),
                subtitle: localization.string(.settingsBatteryFullThresholdDescription),
                subtitleLink: Text(
                    localization.string(.settingsBatteryFullThresholdUseChargeLimit)
                )
                .foregroundColor(Color.accentColor),
                // Fills the slider in from the system. A one-shot action, not a
                // mode: the level stays editable afterwards, and nothing
                // re-reads the plist behind the user's back.
                //
                // Accent colour rather than `.link`, which is macOS 14+ and
                // this app still ships macOS 13.
                subtitleLinkAction: {
                    store.applySystemChargeLimit()
                },
                trailing: {
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { store.batteryFullThreshold },
                            set: { store.batteryFullThreshold = $0.rounded() }
                        ),
                        in: SettingsStore.batteryFullThresholdRange
                    )
                    .frame(width: 130)
                    .controlSize(.small)
                    .accessibilityLabel(
                        localization.string(.settingsBatteryFullThreshold)
                    )
                    .accessibilityValue("\(Int(store.batteryFullThreshold))%")

                    Text("\(Int(store.batteryFullThreshold))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            )

            if !store.canReadSystemChargeLimit {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.secondary)
                    Text(localization.string(
                        .settingsBatteryFullThresholdSystemUnavailable
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, SettingsMetrics.rowPaddingH)
                .padding(.bottom, 6)
            }
        }
    }
}
