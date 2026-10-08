import SwiftUI

struct GeneralSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var localization: Localization
    @ObservedObject private var launchAtLogin: LaunchAtLoginManager = .shared
    @ObservedObject private var updaterManager: UpdaterManager = .shared

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
        SettingsGroup(localization.string(.settingsPageGeneral)) {
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
                    .fixedSize()
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
