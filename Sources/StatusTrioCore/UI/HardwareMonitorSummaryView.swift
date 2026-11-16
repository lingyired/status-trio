import SwiftUI

/// The status-panel hardware summary: the existing four rings on top and a
/// single compact row of four aligned data groups underneath (download, upload,
/// average fan, disk read/write). The row uses the same four equal columns and
/// 10 pt spacing as the rings, so every group sits centred under its ring.
struct HardwareMonitorSummaryView: View {
    @ObservedObject var model: HardwareMonitorObservable
    var metricColors: [HardwareMonitorMetric: IconRGBA] = [:]
    /// Show the CPU/GPU/RAM/SSD rings.
    var showsRings: Bool = true
    /// Show the bottom download/upload/fan/disk data row.
    var showsSummaryRow: Bool = true

    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if showsRings || showsSummaryRow {
            content
        }
    }

    private var content: some View {
        let items = HardwareMonitorSummaryPresentation.items(
            snapshot: model.summarySnapshot, localization: localization)
        return VStack(spacing: 8) {
            if showsRings {
                HardwareRingStrip(hardware: model, colors: metricColors)
            }
            if showsSummaryRow {
                if showsRings {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)
                }
                HStack(alignment: .top, spacing: 10) {
                    ForEach(items, id: \.metric) { item in
                        HardwareSummaryMetricCell(item: item)
                            .frame(maxWidth: .infinity)
                    }
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
struct HardwareSummaryMetricCell: View {
    let item: HardwareSummaryMetricPresentation

    var body: some View {
        VStack(spacing: 3) {
            Text(item.valueText)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .opacity(item.isStale ? 0.45 : 1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: 16)
            HStack(spacing: 3) {
                Image(systemName: item.symbol)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                if !item.unitText.isEmpty {
                    Text(item.unitText)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(height: 12)
        }
        // Fixed cell height: identical whether a value is short or shrunk to fit,
        // so the icon/unit row cannot shift between columns or resize the panel.
        .frame(maxWidth: .infinity)
        .frame(height: 31, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityValue(item.accessibilityValue)
        .help(item.help)
    }
}
