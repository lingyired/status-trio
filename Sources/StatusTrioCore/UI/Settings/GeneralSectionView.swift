import SwiftUI

struct GeneralSectionPresentation: Equatable, Sendable {
    let showsAnalyticsGroup: Bool

    init(channel: DistributionChannel) {
        showsAnalyticsGroup = channel == .direct
    }
}

struct GeneralSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var localization: Localization
    var globalShortcutController: GlobalShortcutController? = nil
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @ObservedObject var updaterManager: UpdateStateFacade
    let capabilityPolicy: DistributionCapabilityPolicy

    var presentation: GeneralSectionPresentation {
        GeneralSectionPresentation(channel: capabilityPolicy.channel)
    }

    init(
        store: SettingsStore,
        localization: Localization,
        globalShortcutController: GlobalShortcutController? = nil,
        launchAtLogin: LaunchAtLoginManager = .shared,
        updaterManager: UpdateStateFacade = UpdateStateFacade(service: SystemManagedUpdateService()),
        capabilityPolicy: DistributionCapabilityPolicy = .runtimeDefault
    ) {
        self.store = store
        self.localization = localization
        self.globalShortcutController = globalShortcutController
        self.launchAtLogin = launchAtLogin
        self.updaterManager = updaterManager
        self.capabilityPolicy = capabilityPolicy
    }

    var body: some View {
        SettingsPage {
            systemGroup
            if presentation.showsAnalyticsGroup {
                analyticsGroup
            }
            if updaterManager.delivery == .systemManaged
                || updaterManager.canCheckForUpdates {
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

            if let globalShortcutController {
                ShortcutSettingsRow(
                    store: store,
                    controller: globalShortcutController,
                    localization: localization
                )

                SettingsDivider()
            }

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
            if updaterManager.delivery == .systemManaged {
                SettingsHintRow(
                    text: localization.string(.settingsUpdatesSystemManaged)
                )
            } else {
                SettingsToggleRow(
                    symbol: "arrow.triangle.2.circlepath",
                    tint: .green,
                    title: localization.string(.settingsUpdatesAutomatic),
                    isOn: Binding(
                        get: { updaterManager.automaticallyChecksForUpdates },
                        set: { updaterManager.setAutomaticallyChecksForUpdates($0) }
                    )
                )
            }
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
