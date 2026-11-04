import SwiftUI

/// Settings for how the battery indicator is drawn in the status icon.
struct BatterySectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @Binding var previewIsDark: Bool
    var chargeToFullNow: ChargeToFullNowController? = nil
    @EnvironmentObject private var localization: Localization
    @Environment(\.settingsScrollProxy) private var scrollProxy
    @ObservedObject private var helper: PrivilegedHelperManager = .shared


    var body: some View {
        SettingsPage(pinnedHeader: {
            StatusIconPreviewCard(
                store: store,
                statusStore: statusStore,
                isDarkBackground: $previewIsDark
            )
        }) {
            if !statusStore.snapshot.battery.isPresent {
                noBatteryNoticeGroup
            }
            sectionNavigation
            iconGroup
                .id(BatterySectionAnchor.icon.rawValue)
            colorsGroup
                .id(BatterySectionAnchor.colors.rawValue)
            chargingEffectsGroup
                .id(BatterySectionAnchor.chargingEffects.rawValue)
            chargingGroup
                .id(BatterySectionAnchor.charging.rawValue)
            if helper.isAvailable {
                powerModesGroup
                    .id(BatterySectionAnchor.powerModes.rawValue)
            }
            powerFlowGroup
                .id(BatterySectionAnchor.power.rawValue)
        }
    }

    /// Quick jumps to each group: the page is long, and a row of labels is
    /// faster than scrolling for the one setting a user came for.
    private var sectionNavigation: some View {
        SettingsGroup {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 108), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(BatterySectionAnchor.allCases) { anchor in
                    Button {
                        scrollProxy?.scrollTo(anchor.rawValue, anchor: .top)
                    } label: {
                        Text(localization.string(anchor.titleKey))
                            .font(.caption)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(SectionJumpButtonStyle())
                }
            }
            .padding(.horizontal, SettingsMetrics.rowPaddingH)
            .padding(.vertical, 8)
        }
    }

    /// A Mac without a battery reports 100 as its level; spell that out at the
    /// top of the page so nobody reads the placeholder as a real reading.
    private enum BatterySectionAnchor: String, CaseIterable, Identifiable {
        case icon
        case colors
        case chargingEffects
        case charging
        case powerModes
        case power

        var id: String { rawValue }

        var titleKey: LocalizationKey {
            switch self {
            case .icon: .settingsBatteryGroupIcon
            case .colors: .settingsBatteryGroupColors
            case .chargingEffects: .settingsBatteryGroupChargingEffects
            case .charging: .settingsBatteryGroupCharging
            case .powerModes: .settingsBatteryGroupPowerModes
            case .power: .settingsBatteryGroupPower
            }
        }
    }

    private var noBatteryNoticeGroup: some View {
        SettingsGroup {
            SettingsHintRow(text: localization.string(.settingsBatteryNoBatteryNotice))
        }
    }

    /// Everything that changes how the battery is drawn.
    private var iconGroup: some View {
        SettingsGroup(localization.string(.settingsBatteryGroupIcon)) {
            // Show Percentage Switch
            SettingsToggleRow(
                symbol: "percent",
                tint: .green,
                title: localization.string(.settingsBatteryShowPercentage),
                isOn: $store.showsBatteryPercentage
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

            // Split the visible arc when the top gap has content (#205).
            SettingsToggleRow(
                symbol: "circle.lefthalf.filled",
                tint: .blue,
                title: localization.string(.settingsBatterySplitGapProgress),
                subtitle: localization.string(.settingsBatterySplitGapProgressDescription),
                isOn: $store.batterySplitGapProgress
            )

            SettingsDivider()


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

            SettingsDivider()

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
        }
    }

    /// The customisable status colours and the level that switches to the
    /// critical colour.
    private var colorsGroup: some View {
        SettingsGroup(localization.string(.settingsBatteryGroupColors)) {
            // Status Colors Switch
            SettingsToggleRow(
                symbol: "paintpalette.fill",
                tint: .orange,
                title: localization.string(.settingsBatteryStatusColors),
                subtitle: localization.string(.settingsBatteryStatusColorsDescription),
                isOn: $store.usesBatteryStatusColors
            )

            BatteryStatusColorsView(store: store)

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
        }
    }

    /// The charging animations drawn on the menu bar and Dock icons.
    private var chargingEffectsGroup: some View {
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

    /// Charging behaviour: the temporary full-charge action, its restore target
    /// and the level that counts as a full ring.
    private var chargingGroup: some View {
        SettingsGroup(localization.string(.settingsBatteryGroupCharging)) {
            if let chargeToFullNow, chargeToFullNow.isSettingAvailable {
                SettingsToggleRow(
                    symbol: "bolt.badge.clock.fill",
                    tint: .green,
                    title: localization.string(.settingsBatteryShowChargeToFullNow),
                    subtitle: localization.string(
                        .settingsBatteryShowChargeToFullNowDescription
                    ),
                    isOn: $store.showsChargeToFullNowButton
                )

                SettingsDivider()

                // macOS removes the persisted charge limit while the native
                // override runs, so the cancel target is an explicit setting
                // rather than a guess. The link fills it in from the system
                // once; afterwards it stays a plain editable value.
                SettingsRow(
                    "arrow.uturn.backward.circle",
                    tint: .green,
                    title: localization.string(.settingsBatteryRestoreLimit),
                    subtitle: localization.string(
                        .settingsBatteryRestoreLimitDescription
                    ),
                    subtitleLink: Text(
                        localization.string(
                            .settingsBatteryFullThresholdUseChargeLimit
                        )
                    )
                    .foregroundColor(Color.accentColor),
                    subtitleLinkAction: {
                        store.applySystemChargeToFullRestoreLimit()
                    },
                    trailing: {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { store.chargeToFullRestoreLimit },
                                    set: {
                                        store.chargeToFullRestoreLimit =
                                            $0.rounded()
                                    }
                                ),
                                in: SettingsStore.chargeToFullRestoreLimitRange,
                                step: 5
                            )
                            .controlSize(.small)
                            .frame(width: 90)
                            .accessibilityLabel(
                                localization.string(.settingsBatteryRestoreLimit)
                            )
                            .accessibilityValue(
                                "\(Int(store.chargeToFullRestoreLimit))%"
                            )

                            Text("\(Int(store.chargeToFullRestoreLimit))%")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                )

                SettingsDivider()
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

    /// The privileged power-mode control and the low-battery automation.
    private var powerModesGroup: some View {
        SettingsGroup(localization.string(.settingsBatteryGroupPowerModes)) {
            lowPowerModeGroup
        }
    }

    /// Power flow and energy rankings.
    private var powerFlowGroup: some View {
        SettingsGroup(localization.string(.settingsBatteryGroupPower)) {
            SettingsToggleRow(
                symbol: "chart.bar.fill",
                tint: .teal,
                title: localization.string(.settingsBatteryPowerInfoBar),
                subtitle: localization.string(.settingsBatteryPowerInfoBarDescription),
                isOn: $store.showsBatteryPowerInfoBar
            )

            SettingsDivider()

            SettingsToggleRow(symbol: "arrow.triangle.branch", tint: .orange,
                title: localization.string(.settingsBatteryPowerFlowDiagram),
                subtitle: localization.string(.settingsBatteryPowerFlowDiagramDescription),
                isOn: $store.showsBatteryPowerFlow)
            SettingsDivider()
            SettingsToggleRow(symbol: "app", tint: .purple,
                title: localization.string(.batteryHighEnergyApps),
                subtitle: localization.string(.batteryEnergyMonitoringDescription),
                isOn: $store.showsHighEnergyApps)
            if store.showsHighEnergyApps {
                SettingsDivider()
                SettingsRow(
                    "timer",
                    tint: .purple,
                    title: localization.string(.settingsBatteryEnergyRefreshInterval),
                    subtitle: localization.string(.settingsBatteryEnergyRefreshIntervalDescription)
                ) {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { store.highEnergyAppsRefreshIntervalSeconds },
                                set: { store.highEnergyAppsRefreshIntervalSeconds = ($0 / 5).rounded() * 5 }
                            ),
                            in: SettingsStore.highEnergyAppsRefreshIntervalRange
                        )
                        .frame(width: 130)
                        .controlSize(.small)
                        .accessibilityLabel(
                            localization.string(.settingsBatteryEnergyRefreshInterval)
                        )
                        .accessibilityValue(
                            localization.format(
                                .settingsRefreshIntervalValue,
                                Int(store.highEnergyAppsRefreshIntervalSeconds)
                            )
                        )

                        Text(
                            localization.format(
                                .settingsRefreshIntervalValue,
                                Int(store.highEnergyAppsRefreshIntervalSeconds)
                            )
                        )
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                    }
                }
            }
            Text(localization.string(.settingsBatteryPowerFlowDescription))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The feature opt-in registers the helper if needed. Turning it off stops
    /// helper contact but keeps registration and system approval intact.
    private var lowPowerModeGroup: some View {
        let needsApproval = helper.requiresApproval && !helper.isReady

        return VStack(alignment: .leading, spacing: 6) {
            SettingsToggleRow(
                symbol: "leaf.fill",
                tint: .green,
                title: localization.string(.lowPowerModeControl),
                subtitle: localization.string(.lowPowerModeControlDescription),
                // Reported on the description's own line: one short state, not
                // a block of rows under the switch.
                subtitleStatus: helper.isEnabled ? lowPowerModeHelperStatus : nil,
                isOn: helper.isEnabledBinding
            )
            .disabled(!helper.isAvailable)

            // Native approval and verified helper access can differ. Keep the
            // pane accessible; only warn when approval is pending and access
            // is unverified.
            if helper.isAvailable {
                Button {
                    helper.openLoginItemsSettings()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: needsApproval
                            ? "exclamationmark.triangle.fill"
                            : "info.circle")
                            .foregroundStyle(needsApproval ? Color.orange : Color.secondary)
                        Text(localization.string(
                            needsApproval
                                ? .lowPowerModeRequiresApproval
                                : (helper.isReady ? .lowPowerModeOpenLoginItems : .lowPowerModeApprovalHint)
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localization.string(.lowPowerModeOpenLoginItems))
                .padding(.horizontal, SettingsMetrics.rowPaddingH)
                .padding(.bottom, 6)
            }

            if helper.didFailLastOperation {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localization.string(.lowPowerModeFailure))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let message = helper.lastErrorMessage {
                            Text(message)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, SettingsMetrics.rowPaddingH)
                .padding(.bottom, 6)
            }

            // #246: the automation needs the helper-backed switch, so it stays
            // visible only while the helper can run, and disabled until the
            // user has turned the Low Power Mode control on.
            if helper.isAvailable, HighPowerModeController.supportsCurrentPlatform,
               statusStore.snapshot.battery.isPresent {
                SettingsDivider()
                SettingsToggleRow(
                    symbol: "battery.25",
                    tint: .green,
                    title: localization.string(.lowPowerModeAutoEnable),
                    subtitle: localization.string(.lowPowerModeAutoEnableDescription),
                    isOn: $store.autoEnablesLowPowerMode
                )
                .disabled(!helper.isEnabled)

                // Its own threshold, separate from the critical colour level:
                // a 90% automation threshold must not paint the icon red at 90%.
                if store.autoEnablesLowPowerMode {
                    SettingsDivider()
                    SettingsRow(
                        "slider.horizontal.3",
                        tint: .green,
                        title: localization.string(.autoLowPowerThreshold),
                        subtitle: localization.string(.autoLowPowerThresholdDescription)
                    ) {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { store.autoLowPowerThreshold },
                                    set: { store.autoLowPowerThreshold = $0.rounded() }
                                ),
                                in: SettingsStore.autoLowPowerThresholdRange
                            )
                            .frame(width: 130)
                            .controlSize(.small)
                            .accessibilityLabel(
                                localization.string(.autoLowPowerThreshold)
                            )
                            .accessibilityValue("\(Int(store.autoLowPowerThreshold))%")

                            Text("\(Int(store.autoLowPowerThreshold))%")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }


    /// A capsule jump label that shows a pressed state and takes the whole capsule
/// as its hit area (a plain button only hits its text).
private struct SectionJumpButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(
                Color.secondary.opacity(configuration.isPressed ? 0.26 : 0.12),
                in: Capsule()
            )
            .contentShape(Capsule())
    }
}

/// One state, carried by the description instead of a line of its own.
    ///
    /// The native approval value is deliberately not repeated here: it can stay
    /// "pending" on a system where the helper already answers, and the approval
    /// hint below the row already asks for the one thing the user can do about
    /// it.
    private var lowPowerModeHelperStatus: Text {
        Text(localization.string(
            helper.isReady ? .lowPowerModeHelperReady : .lowPowerModeHelperUnavailable
        ))
        .foregroundColor(helper.isReady ? Color.green : Color.secondary)
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

