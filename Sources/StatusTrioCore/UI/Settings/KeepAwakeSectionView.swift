import AppKit
import SwiftUI

/// Dedicated Settings → 保持唤醒 page. Grouped so the keep-screen pill and the
/// lid-sleep pill (plus its battery options) are clearly separate concerns.
struct KeepAwakeSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject private var helper: PrivilegedHelperManager = .shared
    @EnvironmentObject private var localization: Localization

    private var sectionEnabled: Bool {
        store.enabledPopupSections.contains(.quickActions)
    }

    var body: some View {
        SettingsPage {
            masterGroup
            keepScreenGroup
            lidGroup
        }
    }

    /// Master visibility + the privileged-helper setup.
    private var masterGroup: some View {
        SettingsGroup(localization.string(.settingsPopupOrderQuickActions)) {
            SettingsToggleRow(
                symbol: "moon.zzz",
                tint: .indigo,
                title: localization.string(.settingsKeepAwakeShowInPanel),
                isOn: Binding(
                    get: { sectionEnabled },
                    set: { store.setPopupSection(.quickActions, enabled: $0) }
                )
            )
        }
    }

    private var keepScreenGroup: some View {
        SettingsGroup(localization.string(.quickActionsDisplaySleep)) {
            SettingsToggleRow(
                symbol: "lightbulb.fill",
                tint: .orange,
                title: localization.string(.settingsKeepAwakeShowButton),
                isOn: $store.showsKeepScreenButton
            )
            .disabled(!sectionEnabled)
        }
    }

    private var lidGroup: some View {
        SettingsGroup(localization.string(.quickActionsLidSleep)) {
            SettingsToggleRow(
                symbol: "moon.zzz.fill",
                tint: .blue,
                title: localization.string(.settingsKeepAwakeShowButton),
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
            helperStatus
        }
    }

    @ViewBuilder
    private var helperStatus: some View {
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
