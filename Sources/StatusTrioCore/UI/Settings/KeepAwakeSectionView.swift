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
        let needsApproval = helper.requiresApproval && !helper.isReady
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
            SettingsDivider()
            SettingsToggleRow(
                symbol: "lock.shield",
                tint: .green,
                title: localization.string(.settingsKeepAwakeHelper),
                isOn: helper.isEnabledBinding
            )
            .disabled(!helper.isAvailable)
            if helper.isAvailable {
                Button {
                    helper.openLoginItemsSettings()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: needsApproval ? "exclamationmark.triangle.fill" : "info.circle")
                            .foregroundStyle(needsApproval ? Color.orange : Color.secondary)
                        Text(localization.string(
                            needsApproval ? .lowPowerModeRequiresApproval
                            : (helper.isReady ? .lowPowerModeOpenLoginItems : .lowPowerModeApprovalHint)
                        ))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, SettingsMetrics.rowPaddingH)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
