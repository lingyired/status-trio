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
            colorGroup
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

    private var colorGroup: some View {
        SettingsGroup(localization.string(.hardwareMonitorSettingsColorTitle)) {
            SettingsCustomRow {
                VStack(spacing: 0) {
                    ForEach(Array(colorMetricGroups.enumerated()), id: \.offset) { groupIndex, group in
                        if groupIndex > 0 { SettingsDivider() }
                        Text(group.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, SettingsMetrics.dividerInset)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        ForEach(Array(group.options.enumerated()), id: \.element) { rowIndex, metric in
                            if rowIndex > 0 { SettingsDivider() }
                            HStack(alignment: .center, spacing: 8) {
                                HardwareMetricSymbolView(symbol: metric.systemImage, box: 20, glyph: 14)
                                Text(localization.string(metric.titleKey))
                                    .font(.system(size: 13))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                IconDesignerColorWell(
                                    selection: colorBinding(for: metric),
                                    onEditingChanged: { _ in }
                                )
                                .frame(width: 40, height: 20)
                                .accessibilityLabel(localization.string(metric.titleKey))
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }

            SettingsDivider()
            HStack {
                Button(localization.string(.hardwareMonitorSettingsResetColors)) {
                    store.hardwareMonitorMetricColors = [:]
                }
                .disabled(store.hardwareMonitorMetricColors.isEmpty)
                Spacer()
            }
            .padding(.leading, SettingsMetrics.dividerInset)
            .padding(.trailing, SettingsMetrics.rowPaddingH)
            .padding(.vertical, SettingsMetrics.rowPaddingV)
        }
    }

    private var colorMetricGroups: [(title: String, options: [HardwareMonitorMetric])] {
        [
            ("CPU", [.cpuUsage, .cpuTemperature]),
            ("GPU", [.gpuUsage, .gpuTemperature]),
            (localization.string(.settingsHardwareRingGroupOther),
             [.memoryUsage, .batteryTemperature, .fan, .downloadSpeed, .uploadSpeed])
        ]
    }

    /// The shared metric colour, editable here and in the ring's colour rows.
    private func colorBinding(for metric: HardwareMonitorMetric) -> Binding<Color> {
        Binding(
            get: { IconAppearanceColorConversion.color(from: store.hardwareColor(for: metric)) },
            set: { store.setHardwareColor(IconAppearanceColorConversion.iconRGBA(from: $0), for: metric) }
        )
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
