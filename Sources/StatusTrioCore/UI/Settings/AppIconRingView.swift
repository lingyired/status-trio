import SwiftUI

/// The "Ring" leaf under **App Icon**: how the battery arc / ring is drawn.
///
/// These controls used to sit in the Battery category, but they only describe
/// the icon's appearance, so they now live with the icon. The page is split into
/// top markers, progress, colours and animations. The actual charging controls
/// (temporary full charge, restore limit) stay in Battery → Charging.
struct AppIconRingView: View {
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        topMarkersGroup
        progressGroup
        colorsGroup
        effectsGroup
    }

    // MARK: Top markers

    private var topMarkersGroup: some View {
        SettingsGroup(localization.string(.settingsBatteryGroupTopMarkers)) {
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

            if store.showsChargingIndicator && store.showsBatteryPercentage {
                SettingsDivider()

                SettingsMenuRow(
                    symbol: "powerplug.portrait.fill",
                    tint: .teal,
                    title: localization.string(.settingsBatteryConnectedIndicator),
                    subtitle: localization.string(
                        .settingsBatteryConnectedIndicatorDescription
                    ),
                    selection: $store.batteryConnectedIndicator,
                    options: BatteryConnectedIndicator.allCases,
                    label: connectedIndicatorLabel
                )
            }

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
        }
    }

    // MARK: Progress

    private var progressGroup: some View {
        SettingsGroup(localization.string(.settingsBatteryGroupProgress)) {
            SettingsToggleRow(
                symbol: "circle.lefthalf.filled",
                tint: .blue,
                title: localization.string(.settingsBatterySplitGapProgress),
                subtitle: localization.string(.settingsBatterySplitGapProgressDescription),
                isOn: $store.batterySplitGapProgress
            )

            SettingsDivider()

            fullThresholdRow

            systemChargeLimitUnavailableNote
        }
    }

    /// Full-ring visual threshold (how complete the ring reads), not a charging
    /// limit. Kept apart from the real charge management controls.
    private var fullThresholdRow: some View {
        SettingsRow(
            "battery100.bolt",
            tint: .green,
            title: localization.string(.settingsBatteryFullThreshold),
            subtitle: localization.string(.settingsBatteryFullThresholdDescription),
            subtitleLink: Text(
                localization.string(.settingsBatteryFullThresholdUseChargeLimit)
            )
            .foregroundColor(Color.accentColor),
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
    }

    @ViewBuilder
    private var systemChargeLimitUnavailableNote: some View {
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

    // MARK: Colours

    private var colorsGroup: some View {
        SettingsGroup(localization.string(.settingsBatteryGroupColors)) {
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

    // MARK: Animations

    private var effectsGroup: some View {
        SettingsGroup(localization.string(.settingsBatteryGroupChargingEffects)) {
            SettingsToggleRow(
                symbol: "menubar.rectangle",
                tint: .green,
                title: localization.string(.settingsBatteryMenuBarChargingEffect),
                subtitle: localization.string(
                    .settingsBatteryMenuBarChargingEffectDescription
                ),
                isOn: $store.showsMenuBarChargingEffect
            )

            SettingsDivider()

            SettingsToggleRow(
                symbol: "dock.rectangle",
                tint: .green,
                title: localization.string(.settingsBatteryDockChargingEffect),
                subtitle: localization.string(
                    .settingsBatteryDockChargingEffectDescription
                ),
                isOn: $store.showsDockChargingEffect
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
                .disabled(!store.showsChargingEffect)
            }
        }
    }

    private func connectedIndicatorLabel(_ indicator: BatteryConnectedIndicator) -> String {
        switch indicator {
        case .plug:
            localization.string(.settingsBatteryConnectedIndicatorPlug)
        case .bolt:
            localization.string(.settingsBatteryConnectedIndicatorBolt)
        case .percentage:
            localization.string(.settingsBatteryConnectedIndicatorPercentage)
        }
    }
}
