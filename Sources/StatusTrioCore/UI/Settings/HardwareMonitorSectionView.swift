import SwiftUI

/// Settings → 监控: whether the module appears, its refresh cadence, and two
/// display groups — the rings and the bottom bar — each with a master switch and
/// per-item toggles. Hiding an item collapses it so the remaining items share the
/// width evenly.
struct HardwareMonitorSectionView: View {
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage {
            placementGroup
            refreshGroup
            ringGroup
            bottomBarGroup
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

            SettingsToggleRow(
                symbol: "clock.arrow.circlepath",
                tint: .green,
                title: localization.string(.hardwareMonitorSettingsBackground),
                subtitle: localization.string(.hardwareMonitorSettingsBackgroundDescription),
                isOn: Binding(
                    get: { store.hardwareBackgroundHistoryEnabled },
                    set: { store.hardwareBackgroundHistoryEnabled = $0 }
                )
            )

            SettingsToggleRow(
                symbol: "list.number",
                tint: .orange,
                title: localization.string(.hardwareMonitorSettingsTopApps),
                subtitle: localization.string(.hardwareMonitorSettingsTopAppsDescription),
                isOn: Binding(
                    get: { store.showsHardwareTopApps },
                    set: { store.showsHardwareTopApps = $0 }
                )
            )
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

    private var ringGroup: some View {
        SettingsGroup(localization.string(.hardwareMonitorSettingsGroupRings)) {
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
            if store.showsHardwareRings {
                itemToggleRows {
                    ForEach(Array(HardwareRingSlot.allCases.enumerated()), id: \.element) { index, slot in
                        if index > 0 { SettingsDivider() }
                        perItemToggleRow(
                            title: localization.string(slot.titleKey),
                            isOn: store.enabledHardwareRingSlots.contains(slot),
                            canTurnOff: store.enabledHardwareRingSlots.count > 1,
                            set: { store.setHardwareRingSlot(slot, enabled: $0) }
                        )
                    }
                }
            }
        }
    }

    private var bottomBarGroup: some View {
        SettingsGroup(localization.string(.hardwareMonitorSettingsGroupBottomBar)) {
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
            if store.showsHardwareSummaryRow {
                itemToggleRows {
                    ForEach(Array(HardwareSummaryMetric.allCases.enumerated()), id: \.element) { index, metric in
                        if index > 0 { SettingsDivider() }
                        perItemToggleRow(
                            title: localization.string(metric.titleKey),
                            isOn: store.enabledHardwareSummaryMetrics.contains(metric),
                            canTurnOff: store.enabledHardwareSummaryMetrics.count > 1,
                            set: { store.setHardwareSummaryMetric(metric, enabled: $0) }
                        )
                    }
                }
            }
        }
    }

    /// The indented list of per-item toggles under an enabled block.
    private func itemToggleRows<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
    }

    /// A compact indented toggle for one item inside an enabled block. Texts sit
    /// in the same column as the parent rows' titles; the switch sits at the
    /// trailing edge. The last remaining item of a block cannot be turned off.
    private func perItemToggleRow(title: String, isOn: Bool, canTurnOff: Bool,
                                  set: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: Binding(get: { isOn }, set: { set($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(isOn && !canTurnOff)
        }
        .padding(.leading, SettingsMetrics.dividerInset)
        .padding(.trailing, SettingsMetrics.rowPaddingH)
        .padding(.vertical, 7)
    }
}
