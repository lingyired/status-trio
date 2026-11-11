import SwiftUI

/// Settings → 监控: choose whether the card appears in the status panel, which
/// metrics it shows, and their order.
struct HardwareMonitorSectionView: View {
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage {
            placementGroup
            metricsGroup
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

    private var metricsGroup: some View {
        SettingsGroup(
            localization.string(.hardwareMonitorSettingsMetrics),
            footnote: localization.string(.hardwareMonitorSettingsMetricsDescription)
        ) {
            SettingsCustomRow {
                List {
                    ForEach(store.hardwareMonitorMetricOrder) { metric in
                        HStack(alignment: .center, spacing: 8) {
                            Toggle("", isOn: binding(for: metric))
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .disabled(isOnlyEnabled(metric))
                                .accessibilityLabel(localization.string(metric.titleKey))

                            Image(systemName: metric.systemImage)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18, alignment: .center)

                            Text(localization.string(metric.titleKey))
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            PanelActionGlyph(systemName: "line.3.horizontal", font: .caption, size: 18)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 3)
                    }
                    .onMove { source, destination in
                        store.moveHardwareMonitorMetrics(fromOffsets: source, toOffset: destination)
                    }
                }
                .listStyle(.inset)
                .frame(height: listHeight)
            }
        }
    }

    private func binding(for metric: HardwareMonitorMetric) -> Binding<Bool> {
        Binding(
            get: { store.enabledHardwareMonitorMetrics.contains(metric) },
            set: { store.setHardwareMonitorMetric(metric, enabled: $0) }
        )
    }

    private func isOnlyEnabled(_ metric: HardwareMonitorMetric) -> Bool {
        store.enabledHardwareMonitorMetrics == [metric]
    }

    private var listHeight: CGFloat {
        min(max(CGFloat(store.hardwareMonitorMetricOrder.count) * 32 + 12, 48), 320)
    }
}