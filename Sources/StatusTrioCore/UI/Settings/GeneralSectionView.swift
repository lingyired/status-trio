import SwiftUI

struct GeneralSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var localization: Localization
    @ObservedObject private var launchAtLogin: LaunchAtLoginManager = .shared
    @ObservedObject private var updaterManager: UpdaterManager = .shared

    var body: some View {
        SettingsPage {
            systemGroup
            placementGroup
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
        }
    }

    private var placementGroup: some View {
        SettingsGroup(localization.string(.settingsAppIconPlacement)) {
            SettingsRow(
                title: localization.string(.settingsAppIconPlacement),
                subtitle: localization.string(.settingsAppIconPlacementDescription),
                leading: { SettingsIcon(symbol: "macwindow.on.rectangle", tint: .indigo) },
                trailing: {
                    Picker(
                        localization.string(.settingsAppIconPlacement),
                        selection: $store.appIconPlacement
                    ) {
                        Text(localization.string(.settingsAppIconPlacementMenuBar))
                            .tag(AppIconPlacement.menuBar)
                        Text(localization.string(.settingsAppIconPlacementDock))
                            .tag(AppIconPlacement.dock)
                        Text(localization.string(.settingsAppIconPlacementBoth))
                            .tag(AppIconPlacement.both)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            )

            if store.appIconPlacement != .menuBar {
                SettingsDivider()

                SettingsRow(
                    title: localization.string(.settingsDockIconBackground),
                    subtitle: localization.string(.settingsDockIconBackgroundDescription),
                    leading: { SettingsIcon(symbol: "dock.rectangle", tint: .purple) },
                    trailing: {
                        Picker(
                            localization.string(.settingsDockIconBackground),
                            selection: $store.dockIconBackgroundPreference
                        ) {
                            Text(localization.string(.settingsDockIconBackgroundSystem))
                                .tag(DockIconBackgroundPreference.system)
                            Text(localization.string(.settingsDockIconBackgroundDark))
                                .tag(DockIconBackgroundPreference.dark)
                            Text(localization.string(.settingsDockIconBackgroundLight))
                                .tag(DockIconBackgroundPreference.light)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                )
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
}
