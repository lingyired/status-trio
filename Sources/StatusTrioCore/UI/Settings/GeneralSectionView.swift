import SwiftUI

struct GeneralSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var localization: Localization
    var globalShortcutController: GlobalShortcutController? = nil
    /// Used only to report which quick actions are available right now. Optional
    /// so previews/tests can render the pane without the full app graph.
    var statusStore: SystemStatusStore? = nil
    var chargeToFullNow: ChargeToFullNowController? = nil
    @ObservedObject private var launchAtLogin: LaunchAtLoginManager = .shared
    @ObservedObject private var updaterManager: UpdaterManager = .shared
    @ObservedObject private var helper: PrivilegedHelperManager = .shared

    var body: some View {
        SettingsPage {
            systemGroup
            analyticsGroup
            if updaterManager.canCheckForUpdates {
                updatesGroup
            }
        }
        .onAppear {
            launchAtLogin.refresh()
        }
    }

    private var systemGroup: some View {
        // The pane is already "General", so the first card carries no repeated
        // section title.
        SettingsGroup {
            // Language
            SettingsRow(
                title: localization.string(.settingsLanguage),
                subtitle: localization.string(.settingsLanguageDescription),
                leading: { SettingsIcon(symbol: "globe", tint: .blue) },
                trailing: {
                    Picker(
                        localization.string(.settingsLanguage),
                        selection: Binding(
                            get: { localization.preference },
                            set: { localization.setPreference($0) }
                        )
                    ) {
                        Text(localization.string(.settingsLanguageFollowSystem))
                            .tag(LanguagePreference.system)

                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.nativeName)
                                .tag(LanguagePreference.language(lang))
                        }
                    }
                    .labelsHidden()
                    .settingsMenuPickerWidth()
                }
            )

            SettingsDivider()

            // Launch at Login
            VStack(alignment: .leading, spacing: 6) {
                SettingsToggleRow(
                    symbol: "power",
                    tint: .cyan,
                    title: localization.string(.settingsLaunchAtLogin),
                    subtitle: localization.string(.settingsLaunchAtLoginDescription),
                    isOn: launchAtLogin.isEnabledBinding
                )
                .disabled(!launchAtLogin.isAvailable)

                if launchAtLogin.status == .requiresApproval {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(localization.string(.settingsLaunchAtLoginRequiresApproval))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(localization.string(.settingsLaunchAtLoginOpenLoginItems)) {
                            launchAtLogin.openLoginItemsSettings()
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, SettingsMetrics.rowPaddingH)
                    .padding(.bottom, 6)
                }

                if launchAtLogin.didFailLastOperation {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundStyle(.red)
                        Text(localization.string(.settingsLaunchAtLoginFailure))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, SettingsMetrics.rowPaddingH)
                    .padding(.bottom, 6)
                }
            }

            SettingsDivider()

            if let globalShortcutController {
                ShortcutSettingsRow(
                    store: store,
                    controller: globalShortcutController,
                    localization: localization
                )

                SettingsDivider()
            }

            rightClickActionRow

            SettingsDivider()

            // Status refresh interval
            SettingsRow(
                "arrow.clockwise",
                tint: .orange,
                title: localization.string(.settingsRefreshInterval),
                subtitle: localization.string(.settingsRefreshIntervalDescription)
            ) {
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { store.refreshIntervalSeconds },
                            set: { store.refreshIntervalSeconds = ($0 / 5).rounded() * 5 }
                        ),
                        in: SettingsStore.refreshIntervalRange
                    )
                    .frame(width: 130)
                    .controlSize(.small)
                    .accessibilityLabel(localization.string(.settingsRefreshInterval))
                    .accessibilityValue(
                        localization.format(
                            .settingsRefreshIntervalValue,
                            Int(store.refreshIntervalSeconds)
                        )
                    )

                    Text(
                        localization.format(
                            .settingsRefreshIntervalValue,
                            Int(store.refreshIntervalSeconds)
                        )
                    )
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }

    private var rightClickActionAvailability: MenuBarQuickActionAvailability {
        MenuBarQuickActionAvailability(
            lowPowerMode: store.controlsLowPowerMode && helper.isReady,
            chargeToFullNow: chargeToFullNow?.isSettingAvailable ?? false,
            mute: statusStore?.liveVolume.canMute ?? false,
            wifi: (statusStore?.snapshot.wifi.state ?? .unavailable) != .unavailable
        )
    }

    /// Single-select right-click action (#209). The selected action's glyph is
    /// the row's tile; an unavailable selection shows a hint that a right-click
    /// will fall back to the menu rather than doing nothing.
    private var rightClickActionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsRow(
                store.menuBarRightClickAction.settingsSymbol,
                tint: .blue,
                title: localization.string(.menuBarRightClickAction),
                subtitle: localization.string(.menuBarRightClickActionDescription)
            ) {
                Picker(
                    localization.string(.menuBarRightClickAction),
                    selection: $store.menuBarRightClickAction
                ) {
                    ForEach(MenuBarRightClickAction.allCases) { action in
                        Text(localization.string(action.titleKey)).tag(action)
                    }
                }
                .labelsHidden()
                .settingsMenuPickerWidth()
            }

            if !rightClickActionAvailability.isAvailable(store.menuBarRightClickAction) {
                SettingsHintRow(text: localization.string(.menuBarRightClickUnavailableHint))
            }
        }
    }

    private var updatesGroup: some View {
        SettingsGroup(localization.string(.settingsUpdatesTitle)) {
            SettingsToggleRow(
                symbol: "arrow.triangle.2.circlepath",
                tint: .green,
                title: localization.string(.settingsUpdatesAutomatic),
                isOn: updaterManager.automaticallyChecksForUpdatesBinding
            )
        }
    }

    private var analyticsGroup: some View {
        SettingsGroup(localization.string(.settingsAnalyticsTitle)) {
            SettingsToggleRow(
                symbol: "chart.bar.xaxis",
                tint: .purple,
                title: localization.string(.onboardingAnalyticsToggle),
                subtitle: localization.string(.settingsAnalyticsDescription),
                isOn: Binding(
                    get: { store.sharesAnonymousAnalytics },
                    set: { store.setSharesAnonymousAnalytics($0) }
                )
            )

            SettingsDivider()

            Link(
                localization.string(.settingsAnalyticsPrivacyDetails),
                destination: URL(string: "https://github.com/lingyired/status-trio/blob/main/docs/privacy-telemetry.md")!
            )
            .font(.system(size: 11))
            .padding(.horizontal, SettingsMetrics.rowPaddingH)
            .padding(.vertical, 9)
        }
    }
}
