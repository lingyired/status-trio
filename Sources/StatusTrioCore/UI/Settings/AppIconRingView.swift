import SwiftUI

/// The "Ring" leaf under **App Icon**: how the battery arc / ring is drawn.
///
/// These controls used to sit in the Battery category, but they only describe
/// the icon's appearance, so they now live with the icon. The page is split into
/// top markers, progress, colours and animations. The actual charging controls
/// (temporary full charge, restore limit) stay in Battery → Charging.
struct AppIconRingView: View {
    @ObservedObject var store: SettingsStore
    /// Whether the Mac actually has a battery. A desktop (e.g. Mac mini) has no
    /// real level, so the ring controls collapse to a decorative top marker.
    var hasBattery: Bool = true
    @EnvironmentObject private var localization: Localization

    /// The battery presence this page draws with. In a development build the
    /// no-battery simulation forces the battery-less layout so the UI can be
    /// checked on a Mac that has a battery.
    private var effectiveHasBattery: Bool {
        hasBattery && !store.isNoBatterySimulationActive
    }

    var body: some View {
        if store.isDevelopmentBuild {
            noBatterySimulationGroup
        }
        topMarkersGroup
        if effectiveHasBattery {
            // Progress, colour and charging-effect controls all address a real
            // battery level, so a battery-less Mac (e.g. Mac mini) shows only the
            // decorative top-marker control.
            progressGroup
            colorsGroup
            effectsGroup
        }
    }

    // MARK: Developer preview

    /// Developer-only helper: force the battery-less layout so a Mac with a
    /// battery can preview how this page looks without one. A packaged release
    /// never shows this (`store.isDevelopmentBuild`) and never simulates.
    private var noBatterySimulationGroup: some View {
        SettingsGroup(localization.string(.settingsBatteryDeveloperPreview)) {
            SettingsToggleRow(
                symbol: "eyeglasses",
                tint: .gray,
                title: localization.string(.settingsBatterySimulateNoBattery),
                subtitle: localization.string(.settingsBatterySimulateNoBatteryDescription),
                isOn: $store.simulatesNoBattery
            )
        }
    }

    // MARK: Top markers

    private var topMarkersGroup: some View {
        SettingsGroup(localization.string(.settingsBatteryGroupTopMarkers)) {
            if effectiveHasBattery {
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
            } else {
                // A Mac with no battery: the percentage is a placeholder, so the
                // only top marker to configure is a decorative bolt or plug. The
                // toggle turns that marker on/off; turning it off keeps the ring
                // closed.
                SettingsToggleRow(
                    symbol: "bolt.fill",
                    tint: .yellow,
                    title: localization.string(.settingsBatteryNoBatteryTopIndicator),
                    subtitle: localization.string(.settingsBatteryNoBatteryTopIndicatorDescription),
                    isOn: $store.showsChargingIndicator
                )
            }

            if showsConnectedIndicatorMenu {
                SettingsDivider()

                SettingsMenuRow(
                    symbol: "powerplug.portrait.fill",
                    tint: .teal,
                    title: localization.string(
                        effectiveHasBattery ? .settingsBatteryConnectedIndicator : .settingsBatteryNoBatteryGapIcon
                    ),
                    subtitle: effectiveHasBattery
                        ? localization.string(.settingsBatteryConnectedIndicatorDescription)
                        : nil,
                    selection: $store.batteryConnectedIndicator,
                    options: effectiveHasBattery ? BatteryConnectedIndicator.allCases : [.plug, .bolt],
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
                                set: { store.setBatterySymbolScaleFromSlider(($0 * 20).rounded() / 20) }
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
        .onAppear {
            normalizeNoBatteryIndicator()
        }
    }

    /// The connected-indicator picker is only meaningful while the top marker is
    /// on. A no-battery Mac ignores the percentage toggle, so that toggle does not
    /// gate the picker the way it does for a real battery.
    private var showsConnectedIndicatorMenu: Bool {
        guard store.showsChargingIndicator else { return false }
        return effectiveHasBattery ? store.showsBatteryPercentage : true
    }

    /// A no-battery Mac never offers the percentage marker. Coerce a legacy
    /// `.percentage` choice to the plug so the picker always has a valid tag.
    private func normalizeNoBatteryIndicator() {
        guard !hasBattery, store.batteryConnectedIndicator == .percentage else { return }
        store.batteryConnectedIndicator = .plug
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
            // #309: a one-tap way to reach the monochrome look instead of
            // asking the user to piece together several switches. It only
            // turns the state colouring off; the top marker, centre icon and
            // bottom indicator keep their own settings.
            SettingsRow(
                "circle.lefthalf.filled",
                tint: .gray,
                title: localization.string(.settingsBatteryMonochromeArc),
                subtitle: localization.string(.settingsBatteryMonochromeArcDescription)
            ) {
                Button(
                    store.isMonochromeBatteryArcActive
                        ? localization.string(.settingsBatteryMonochromeArcApplied)
                        : localization.string(.settingsBatteryMonochromeArcApply)
                ) {
                    store.applyMonochromeBatteryArcPreset()
                }
                .buttonStyle(.bordered)
                .disabled(store.isMonochromeBatteryArcActive)
            }

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
