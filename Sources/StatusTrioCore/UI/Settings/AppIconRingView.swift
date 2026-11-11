import AppKit
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
    /// no-battery simulation forces the battery-less look so the UI can be
    /// checked on a Mac that has a battery.
    private var effectiveHasBattery: Bool {
        hasBattery && !store.isNoBatterySimulationActive
    }

    var body: some View {
        if store.isDevelopmentBuild {
            noBatterySimulationGroup
        }
        if !effectiveHasBattery {
            noBatteryHintGroup
        }
        outerRingContentGroup
        if store.outerRingContent == .airPodsBattery {
            airPodsRingGroup
        } else {
            // #309: every battery ring control stays visible without a battery.
            // The settings are kept; the ring colour still follows connected
            // power and Low/High Power Mode, while the level and charging marker
            // do not apply. The hint above says so.
            topMarkersGroup
            progressGroup
            colorsGroup
            effectsGroup
        }
    }

    // MARK: Outer ring content

    /// Chooses what the ring shows: the Mac battery (with all the existing
    /// battery options below it) or the AirPods battery. Presented as a row of
    /// picture tiles, matching the middle-icon source picker.
    private var outerRingContentGroup: some View {
        SettingsGroup(localization.string(.settingsRingContentGroupTitle)) {
            VStack(alignment: .leading, spacing: 10) {
                Text(localization.string(.settingsRingContentRowDescription))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 8) {
                    ForEach(OuterRingContent.allCases) { content in
                        let selected = store.outerRingContent == content
                        Button {
                            store.outerRingContent = content
                        } label: {
                            VStack(spacing: 5) {
                                OuterRingContentPreview(content: content)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                    )
                                    .selectionRing(selected, cornerRadius: 6)
                                Text(ringContentLabel(content))
                                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(ringContentLabel(content))
                        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : [.isButton])
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(localization.string(.settingsRingContentRowTitle))
            }
        }
    }

    private func ringContentLabel(_ content: OuterRingContent) -> String {
        switch content {
        case .systemBattery: return localization.string(.settingsRingContentSystemBattery)
        case .airPodsBattery: return localization.string(.settingsRingContentAirPodsBattery)
        }
    }

    /// AirPods-ring options: two-arc layout, the small top glyph, and whether an
    /// unavailable AirPods ring falls back to the Mac battery ring.
    private var airPodsRingGroup: some View {
        SettingsGroup(localization.string(.settingsRingAirPodsGroup)) {
            SettingsToggleRow(
                symbol: "airpods",
                tint: .blue,
                title: localization.string(.settingsRingAirPodsDualRing),
                subtitle: localization.string(.settingsRingAirPodsDualRingDescription),
                isOn: $store.airPodsRingUsesDualRing
            )
            SettingsDivider()
            SettingsToggleRow(
                symbol: "airpods",
                tint: .blue,
                title: localization.string(.settingsRingAirPodsTopSymbol),
                subtitle: localization.string(.settingsRingAirPodsTopSymbolDescription),
                isOn: $store.showsAirPodsTopSymbolInRing
            )
            SettingsDivider()
            SettingsToggleRow(
                symbol: "battery.100",
                tint: .green,
                title: localization.string(.settingsRingAirPodsFallback),
                subtitle: localization.string(.settingsRingAirPodsFallbackDescription),
                isOn: $store.airPodsRingFallsBackToBattery
            )
        }
    }

    // MARK: Developer preview

    /// Developer-only helper: force the battery-less look so a Mac with a
    /// battery can preview this page without one. A packaged release never shows
    /// this and never simulates.
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

    /// Explains what still applies on a battery-less Mac (ring colour follows
    /// connected power and Low/High Power Mode) and what does not (percentage,
    /// charging marker), so the kept controls are not misleading.
    private var noBatteryHintGroup: some View {
        SettingsGroup {
            SettingsHintRow(text: localization.string(.settingsBatteryNoBatteryHiddenOptions))
        }
    }

    // MARK: Top markers

    private var topMarkersGroup: some View {
        SettingsGroup(localization.string(.settingsBatteryGroupTopMarkers)) {
            if effectiveHasBattery {
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
        // Shown only after the user pressed “使用充电上限” and the private plist
        // could not be read. Not proactive: an idle page stays quiet.
        if store.batteryFullThresholdReadFailed {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.secondary)
                (
                    Text(localization.string(
                        .settingsBatteryFullThresholdSystemUnavailable
                    ))
                    + Text(" ")
                    + Text(localization.string(
                        .settingsBatteryFullThresholdOpenSystemSettings
                    ))
                    .foregroundColor(Color.accentColor)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture { openBatteryChargeSettings() }
                .accessibilityAddTraits(.isLink)
            }
            .padding(.horizontal, SettingsMetrics.rowPaddingH)
            .padding(.bottom, 6)
        }
    }

    /// Opens System Settings at Battery → Charging, where the user can read the
    /// real charge limit that this machine does not expose through a public API.
    private func openBatteryChargeSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Battery-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.battery"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    // MARK: Colours

    private var colorsGroup: some View {
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
                    get: { store.monochromeChargingRing ?? !effectiveHasBattery },
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
            .disabled(!store.showsChargingEffect || store.batteryChargingMarker != .bolt)

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

/// A small picture tile for the ring-content picker: a single battery arc, or
/// two AirPods arcs with the AirPods glyph above them.
private struct OuterRingContentPreview: View {
    let content: OuterRingContent

    var body: some View {
        ZStack {
            switch content {
            case .systemBattery:
                Circle()
                    .trim(from: 0.12, to: 0.88)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .padding(6)
                Image(systemName: "battery.100")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            case .airPodsBattery:
                Circle()
                    .trim(from: 0.06, to: 0.44)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .padding(6)
                Circle()
                    .trim(from: 0.56, to: 0.94)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .padding(6)
                Image(systemName: "airpods")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
}
