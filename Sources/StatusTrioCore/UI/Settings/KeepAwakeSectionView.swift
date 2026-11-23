import AppKit
import SwiftUI

/// One helper state vocabulary for both Settings surfaces. The battery page
/// already reports an unusable helper as "无法连接或尚未验证"; the keep-awake
/// page must not keep showing a healthy lock and an install hint in that case.
enum KeepAwakeHelperStatus {
    static func textKey(isAvailable: Bool, isReady: Bool) -> LocalizationKey {
        guard isAvailable else { return .lowPowerModeHelperUnavailable }
        return isReady ? .settingsKeepAwakeHelperReady : .settingsKeepAwakeHelperHint
    }

    static func symbolName(isAvailable: Bool) -> String {
        isAvailable ? "lock.shield" : "exclamationmark.triangle.fill"
    }
}

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
        .onAppear { helper.refreshForApprovalSettings() }
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

    private func showNamed(_ key: LocalizationKey) -> String {
        String(
            format: localization.string(.settingsKeepAwakeShowNamed),
            locale: localization.resolvedLanguage.locale,
            arguments: [localization.string(key)]
        )
    }

    private var keepScreenGroup: some View {
        SettingsGroup(localization.string(.quickActionsDisplaySleep)) {
            SettingsToggleRow(
                symbol: "lightbulb.fill",
                tint: .orange,
                title: showNamed(.quickActionsDisplaySleep),
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
                title: showNamed(.quickActionsLidSleep),
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
                Image(systemName: KeepAwakeHelperStatus.symbolName(isAvailable: helper.isAvailable))
                    .foregroundStyle(helper.isAvailable ? Color.green : Color.orange)
                Text(localization.string(.settingsKeepAwakeHelper))
                    .font(.callout)
            }
            Text(localization.string(
                KeepAwakeHelperStatus.textKey(isAvailable: helper.isAvailable, isReady: helper.isReady)
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
