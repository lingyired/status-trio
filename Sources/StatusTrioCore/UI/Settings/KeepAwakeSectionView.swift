import AppKit
import SwiftUI

/// Dedicated Settings → 保持唤醒 page: one master switch for whether the section
/// shows in the status panel, the privileged-helper setup, and each of the two
/// pills toggled independently.
struct KeepAwakeSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject private var helper: PrivilegedHelperManager = .shared
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage {
            keepAwakeGroup
        }
    }

    private var keepAwakeGroup: some View {
        let sectionEnabled = store.enabledPopupSections.contains(.quickActions)
        return SettingsGroup(localization.string(.settingsPopupOrderQuickActions)) {
            SettingsToggleRow(
                symbol: "moon.zzz",
                tint: .indigo,
                title: localization.string(.settingsKeepAwakeShowInPanel),
                isOn: Binding(
                    get: { store.enabledPopupSections.contains(.quickActions) },
                    set: { store.setPopupSection(.quickActions, enabled: $0) }
                )
            )
            SettingsDivider()
            SettingsToggleRow(
                symbol: "lightbulb.fill",
                tint: .orange,
                title: localization.string(.quickActionsDisplaySleep),
                subtitle: localization.string(.quickActionsDisplaySleepDescription),
                isOn: $store.showsKeepScreenButton
            )
            .disabled(!sectionEnabled)
            SettingsToggleRow(
                symbol: "moon.zzz.fill",
                tint: .blue,
                title: localization.string(.quickActionsLidSleep),
                subtitle: localization.string(.quickActionsLidSleepDescription),
                isOn: $store.showsLidSleepButton
            )
            .disabled(!sectionEnabled)
            SettingsToggleRow(
                symbol: "powerplug",
                tint: .green,
                title: localization.string(.settingsKeepAwakeAllowBattery),
                isOn: $store.allowLidSleepOnBattery
            )
            .disabled(!sectionEnabled)
            SettingsToggleRow(
                symbol: "battery.25",
                tint: .orange,
                title: localization.string(.settingsKeepAwakeAutoOff),
                isOn: $store.autoDisableLidSleepOnLowBattery
            )
            .disabled(!sectionEnabled)
            SettingsDivider()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.green)
                    Text(localization.string(.settingsKeepAwakeHelper))
                        .font(.callout)
                }
                Text(localization.string(
                    helper.isReady ? .settingsKeepAwakeHelperReady : .settingsKeepAwakeHelperHint
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                if helper.requiresApproval {
                    Button {
                        helper.openLoginItemsSettings()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(localization.string(.lowPowerModeRequiresApproval))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, SettingsMetrics.rowPaddingH)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
