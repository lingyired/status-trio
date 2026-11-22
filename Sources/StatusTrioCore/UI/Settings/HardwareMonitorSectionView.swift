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
            networkCapGroup
            temperatureMonitoringGroup
            ringGroup
            if store.showsHardwareRings { ringValueGroup }
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
            SettingsDivider()
            SettingsRow(
                "chart.line.uptrend.xyaxis",
                tint: .teal,
                title: localization.string(.hardwareMonitorSettingsHistoryWindow),
                subtitle: localization.string(.hardwareMonitorSettingsHistoryWindowDescription)
            ) {
                Picker(localization.string(.hardwareMonitorSettingsHistoryWindow),
                       selection: Binding(
                        get: { store.hardwareHistoryWindowMinutes },
                        set: { store.hardwareHistoryWindowMinutes = $0 })) {
                    ForEach(SettingsStore.hardwareHistoryWindowOptions, id: \.self) { minutes in
                        Text(localization.format(.hardwareMonitorHistoryWindowMinutes, minutes))
                            .tag(minutes)
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

    /// Mirrors the icon advanced settings so the network trend and the icon
    /// ring share one editable speed cap.
    private var networkCapGroup: some View {
        SettingsGroup(localization.string(.hardwareMonitorSettingsSpeedCapsTitle),
                      footnote: localization.string(.hardwareMonitorSettingsSpeedCapsDescription)) {
            SettingsRow(
                "arrow.down",
                tint: .blue,
                title: localization.string(.hardwareDetailDownload),
                subtitle: localization.string(.hardwareMonitorSpeedCapDescription)
            ) {
                HardwareCapField(
                    value: Binding(
                        get: { store.hardwareDownloadCapMbps },
                        set: { store.hardwareDownloadCapMbps = ($0).rounded() }),
                    range: SettingsStore.hardwareSpeedCapRange)
            }
            SettingsDivider()
            SettingsRow(
                "arrow.up",
                tint: .green,
                title: localization.string(.hardwareDetailUpload),
                subtitle: localization.string(.hardwareMonitorSpeedCapDescription)
            ) {
                HardwareCapField(
                    value: Binding(
                        get: { store.hardwareUploadCapMbps },
                        set: { store.hardwareUploadCapMbps = ($0).rounded() }),
                    range: SettingsStore.hardwareSpeedCapRange)
            }
            SettingsDivider()
            SettingsToggleRow(
                symbol: "ruler",
                tint: .purple,
                title: localization.string(.hardwareMonitorSettingsNetworkScale),
                subtitle: localization.string(.hardwareMonitorSettingsNetworkScaleDescription),
                isOn: Binding(
                    get: { store.hardwareNetworkChartFixedScale },
                    set: { store.hardwareNetworkChartFixedScale = $0 }
                )
            )
        }
    }

    private var colorGroup: some View {
        SettingsGroup(localization.string(.hardwareMonitorSettingsColorTitle)) {
            SettingsCustomRow {
                VStack(spacing: 0) {
                    ForEach(Array(colorGroups.enumerated()), id: \.offset) { groupIndex, group in
                        if groupIndex > 0 { SettingsDivider() }
                        Text(group.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        ForEach(Array(group.options.enumerated()), id: \.element) { rowIndex, row in
                            if rowIndex > 0 { SettingsDivider() }
                            HStack(alignment: .center, spacing: 8) {
                                HardwareMetricSymbolView(symbol: row.symbol, box: 20, glyph: 14)
                                Text(localization.string(row.titleKey))
                                    .font(.system(size: 13))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                IconDesignerColorWell(
                                    selection: colorBinding(for: row),
                                    onEditingChanged: { _ in }
                                )
                                .frame(width: 40, height: 20)
                                .accessibilityLabel(localization.string(row.titleKey))
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
                    store.hardwareDiskRingColor = HardwareRingColorConfiguration.solidStateDriveColor
                }
                .disabled(store.hardwareMonitorMetricColors.isEmpty
                          && store.hardwareDiskRingColor == HardwareRingColorConfiguration.solidStateDriveColor)
                Spacer()
            }
            .padding(.leading, SettingsMetrics.dividerInset)
            .padding(.trailing, SettingsMetrics.rowPaddingH)
            .padding(.vertical, SettingsMetrics.rowPaddingV)
        }
    }

    /// One colour row in the monitor colour group. SSD (disk capacity) is not a
    /// sampled `HardwareMonitorMetric`, so it is a distinct case alongside the
    /// metric-backed rows.
    private enum ColorRow: Hashable {
        case metric(HardwareMonitorMetric)
        case disk

        var symbol: String {
            switch self {
            case .metric(let metric): metric.systemImage
            case .disk: "internaldrive"
            }
        }

        var titleKey: LocalizationKey {
            switch self {
            case .metric(let metric): metric.titleKey
            case .disk: .hardwareMonitorSettingsItemDiskCapacity
            }
        }
    }

    private var colorGroups: [(title: String, options: [ColorRow])] {
        [
            ("CPU", [.metric(.cpuUsage), .metric(.cpuTemperature)]),
            ("GPU", [.metric(.gpuUsage), .metric(.gpuTemperature)]),
            (localization.string(.settingsHardwareRingGroupOther),
             HardwareMonitorMetric.colorEditableArcMetrics.map { ColorRow.metric($0) } + [.disk])
        ]
    }

    /// The shared metric colour, editable here and in the ring's colour rows.
    private func colorBinding(for row: ColorRow) -> Binding<Color> {
        switch row {
        case .metric(let metric):
            return Binding(
                get: { IconAppearanceColorConversion.color(from: store.hardwareColor(for: metric)) },
                set: { store.setHardwareColor(IconAppearanceColorConversion.iconRGBA(from: $0), for: metric) }
            )
        case .disk:
            return Binding(
                get: { IconAppearanceColorConversion.color(from: store.hardwareDiskRingColor) },
                set: { store.hardwareDiskRingColor = IconAppearanceColorConversion.iconRGBA(from: $0).normalized() }
            )
        }
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

    /// RAM and SSD ring value semantics, independent because a user may want
    /// remaining memory but consumed disk (or the reverse).
    private var ringValueGroup: some View {
        SettingsGroup(
            localization.string(.hardwareMonitorRingValueGroup),
            footnote: localization.string(.hardwareMonitorRingValueGroupDescription)
        ) {
            ringCenterRow(title: localization.string(.hardwareMonitorRingCenterCPU),
                          symbol: "cpu", tint: .blue,
                          selection: Binding(
                            get: {
                                store.hardwareTemperatureMonitoringEnabled
                                    ? store.cpuRingCenterContent : .frequency
                            },
                            set: { store.cpuRingCenterContent = $0 }),
                          options: store.hardwareTemperatureMonitoringEnabled
                              ? HardwareRingCenterContent.allCases : [.frequency])
            SettingsDivider()
            ringCenterRow(title: localization.string(.hardwareMonitorRingCenterGPU),
                          symbol: "cpu", tint: .purple,
                          selection: Binding(get: { store.gpuRingCenterContent },
                                             set: { store.gpuRingCenterContent = $0 }),
                          options: [.temperature])
            SettingsDivider()
            ringValueRow(title: localization.string(.hardwareMonitorMemory),
                         symbol: "memorychip", tint: .purple,
                         selection: Binding(get: { store.memoryRingDisplayMode },
                                            set: { store.memoryRingDisplayMode = $0 }))
            SettingsDivider()
            ringValueRow(title: localization.string(.hardwareMonitorRingValueSSD),
                         symbol: "internaldrive", tint: .teal,
                         selection: Binding(get: { store.ssdRingDisplayMode },
                                            set: { store.ssdRingDisplayMode = $0 }))
        }
    }

    private var temperatureMonitoringGroup: some View {
        SettingsGroup(
            footnote: localization.string(.hardwareMonitorSettingsTemperatureMonitoringDescription)
        ) {
            SettingsToggleRow(
                symbol: "thermometer.medium",
                tint: .orange,
                title: localization.string(.hardwareMonitorSettingsTemperatureMonitoring),
                subtitle: nil,
                isOn: Binding(
                    get: { store.hardwareTemperatureMonitoringEnabled },
                    set: { store.hardwareTemperatureMonitoringEnabled = $0 }
                )
            )
        }
    }

    private func ringCenterRow(title: String, symbol: String, tint: Color,
                               selection: Binding<HardwareRingCenterContent>,
                               options: [HardwareRingCenterContent]) -> some View {
        SettingsRow(symbol, tint: tint, title: title, subtitle: nil) {
            Picker(title, selection: selection) {
                ForEach(options) { content in
                    Text(localization.string(content.titleKey)).tag(content)
                }
            }
            .labelsHidden()
            .settingsMenuPickerWidth()
        }
    }

    private func ringValueRow(title: String, symbol: String, tint: Color,
                              selection: Binding<RingValueDisplayMode>) -> some View {
        SettingsRow(symbol, tint: tint, title: title, subtitle: nil) {
            Picker(title, selection: selection) {
                ForEach(RingValueDisplayMode.allCases) { mode in
                    Text(localization.string(mode.titleKey)).tag(mode)
                }
            }
            .labelsHidden()
            .settingsMenuPickerWidth()
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
