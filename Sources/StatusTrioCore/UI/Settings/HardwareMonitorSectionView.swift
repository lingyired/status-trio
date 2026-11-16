import SwiftUI

/// Settings → 监控: whether the module appears, its refresh cadence, and which
/// of the two blocks (the four rings / the bottom data row) are shown. The
/// individual-metric toggles are gone because the panel always samples a fixed
/// set; only the two blocks are user-selectable.
struct HardwareMonitorSectionView: View {
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage {
            placementGroup
            refreshGroup
            displayGroup
        }
    }

    private var placementGroup: some View {
        SettingsGroup(
            localization.string(.settingsTabPanel),
            footnote: localization.string(.hardwareMonitorSettingsShowInPanelDescription)
        ) {
            SettingsToggleRow(
                symbol: "rectangle.bottomthird.inset.filled",
                tint: .blue,
                title: localization.string(.hardwareMonitorSettingsShowInPanel),
                subtitle: nil,
                isOn: Binding(
                    get: { store.enabledPopupSections.contains(.hardwareMonitor) },
                    set: { store.setPopupSection(.hardwareMonitor, enabled: $0) }
                )
            )
        }
    }

    private var refreshGroup: some View {
        SettingsGroup {
            SettingsRow(
                "speedometer",
                tint: .blue,
                title: localization.string(.hardwareMonitorSettingsPanelRefresh),
                subtitle: localization.string(.hardwareMonitorSettingsPanelRefreshDescription)
            ) {
                Picker(localization.string(.hardwareMonitorSettingsPanelRefresh),
                       selection: Binding(
                        get: { store.hardwarePanelRefreshSeconds },
                        set: { store.hardwarePanelRefreshSeconds = $0 })) {
                    ForEach(SettingsStore.hardwarePanelRefreshOptions, id: \.self) { seconds in
                        Text(localization.format(.hardwareMonitorBackgroundSeconds, seconds))
                            .tag(seconds)
                    }
                }
                .labelsHidden()
                .settingsMenuPickerWidth()
            }

            SettingsRow(
                "clock.arrow.circlepath",
                tint: .green,
                title: localization.string(.hardwareMonitorSettingsBackground),
                subtitle: localization.string(.hardwareMonitorSettingsBackgroundDescription)
            ) {
                Picker(localization.string(.hardwareMonitorSettingsBackground),
                       selection: Binding(
                        get: { store.hardwareBackgroundRefreshSeconds },
                        set: { store.hardwareBackgroundRefreshSeconds = $0 })) {
                    Text(localization.string(.hardwareMonitorBackgroundOff))
                        .tag(SettingsStore.defaultHardwareBackgroundRefreshSeconds)
                    ForEach(SettingsStore.hardwareBackgroundRefreshOptions.filter { $0 > 0 }, id: \.self) { seconds in
                        Text(localization.format(.hardwareMonitorBackgroundSeconds, seconds))
                            .tag(seconds)
                    }
                }
                .labelsHidden()
                .settingsMenuPickerWidth()
            }
        }
    }

    private var displayGroup: some View {
        SettingsGroup {
            SettingsToggleRow(
                symbol: "circle.dashed",
                tint: .blue,
                title: localization.string(.hardwareMonitorSettingsShowRings),
                subtitle: localization.string(.hardwareMonitorSettingsShowRingsDescription),
                isOn: Binding(
                    get: { store.showsHardwareRings },
                    set: { store.showsHardwareRings = $0 }
                )
            )
            SettingsToggleRow(
                symbol: "chart.bar",
                tint: .green,
                title: localization.string(.hardwareMonitorSettingsShowSummaryRow),
                subtitle: localization.string(.hardwareMonitorSettingsShowSummaryRowDescription),
                isOn: Binding(
                    get: { store.showsHardwareSummaryRow },
                    set: { store.showsHardwareSummaryRow = $0 }
                )
            )
        }
    }
}
