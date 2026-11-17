import SwiftUI

/// The status-panel hardware summary: four independent glass cards for the
/// CPU/GPU/RAM/SSD rings, and one compact single-line info bar underneath for
/// download / upload / average fan / disk I/O. Colours stay on the rings; the
/// cards are neutral silver glass like the battery power cards.
struct HardwareMonitorSummaryView: View {
    @ObservedObject var model: HardwareMonitorObservable
    var metricColors: [HardwareMonitorMetric: IconRGBA] = [:]
    var showsRings: Bool = true
    var showsSummaryRow: Bool = true
    /// Routes a ring card or info-bar cell to its detail page. Nil disables taps
    /// (previews, design grid) without changing any drawing.
    var onOpenHardwareDetail: ((HardwareDetailKind) -> Void)? = nil

    @EnvironmentObject private var localization: Localization

    var body: some View {
        if showsRings || showsSummaryRow {
            content
        }
    }

    private var content: some View {
        let items = HardwareMonitorSummaryPresentation.items(
            snapshot: model.summarySnapshot, localization: localization)
        return VStack(spacing: 6) {
            if showsRings {
                HardwareRingStrip(hardware: model, colors: metricColors, carded: true,
                                  onSelectSlot: onOpenHardwareDetail)
            }
            if showsSummaryRow {
                CompactSummaryInfoBar(items: items) { metric in
                    switch metric {
                    case .download, .upload: onOpenHardwareDetail?(.network)
                    case .disk: onOpenHardwareDetail?(.disk)
                    case .fan: break
                    }
                }
            }
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localization.string(.hardwareMonitorTitle))
    }
}

/// One low-weight glass bar holding the four auxiliary metrics on one line.
struct CompactSummaryInfoBar: View {
    let items: [HardwareSummaryMetricPresentation]
    var onSelect: ((HardwareSummaryMetric) -> Void)? = nil

    @State private var hoveredMetric: HardwareSummaryMetric?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.metric) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 1, height: 14)
                }
                cell(item)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: HardwareSummaryMetricCell.barHeight)
        .panelCardSurface(.silver(.disconnected), tint: .clear, cornerRadius: 10)
    }

    @ViewBuilder
    private func cell(_ item: HardwareSummaryMetricPresentation) -> some View {
        if let onSelect, item.metric != .fan {
            Button { onSelect(item.metric) } label: {
                HardwareSummaryMetricCell(item: item)
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(hoveredMetric == item.metric ? 0.08 : 0))
                    .allowsHitTesting(false)
            }
            .onHover { inside in
                if inside { hoveredMetric = item.metric }
                else if hoveredMetric == item.metric { hoveredMetric = nil }
            }
        } else {
            HardwareSummaryMetricCell(item: item)
        }
    }
}

/// One info-bar group with fixed slots: [icon][value right-aligned][unit].
/// Every slot has a constant width so a value or unit change can never shift the
/// icon or the neighbouring metrics, and an empty unit keeps its reserved space.
struct HardwareSummaryMetricCell: View {
    let item: HardwareSummaryMetricPresentation

    static let barHeight: CGFloat = 28
    static let contentHeight: CGFloat = 26

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: item.symbol)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(item.valueText)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .opacity(item.isStale ? 0.45 : 1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !item.unitText.isEmpty {
                Text(item.unitText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.contentHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityValue(item.accessibilityValue)
        .help(item.help)
    }
}
