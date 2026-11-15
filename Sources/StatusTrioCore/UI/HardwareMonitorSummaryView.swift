import SwiftUI

/// The status-panel hardware summary: the existing four rings on top and a
/// single compact row of four aligned data groups underneath (download, upload,
/// average fan, disk read/write). The row uses the same four equal columns and
/// 10 pt spacing as the rings, so every group sits centred under its ring.
struct HardwareMonitorSummaryView: View {
    @ObservedObject var model: HardwareMonitorObservable
    var metricColors: [HardwareMonitorMetric: IconRGBA] = [:]

    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let items = HardwareMonitorSummaryPresentation.items(
            snapshot: model.snapshot, localization: localization)
        VStack(spacing: 8) {
            HardwareRingStrip(hardware: model, colors: metricColors)
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
            HStack(alignment: .top, spacing: 10) {
                ForEach(items, id: \.metric) { item in
                    HardwareSummaryMetricCell(item: item)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(
                    HardwareMonitorCardView.backgroundOpacity(reduceTransparency: reduceTransparency)))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localization.string(.hardwareMonitorTitle))
    }
}

/// One summary group: value on top, icon + unit below, both centred so the group
/// aligns to its ring column. Stale readings are dimmed, missing values show the
/// presentation's em dash rather than a fabricated zero.
private struct HardwareSummaryMetricCell: View {
    let item: HardwareSummaryMetricPresentation

    var body: some View {
        VStack(spacing: 3) {
            Text(item.valueText)
                .font(.system(size: 13, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .opacity(item.isStale ? 0.45 : 1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 3) {
                Image(systemName: item.symbol)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                if !item.unitText.isEmpty {
                    Text(item.unitText)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityValue(item.accessibilityValue)
        .help(item.help)
    }
}
