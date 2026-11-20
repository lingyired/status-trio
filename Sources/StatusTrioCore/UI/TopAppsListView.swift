import AppKit
import SwiftUI

/// The high-usage application card shared by CPU, GPU, memory and network.
/// It observes only the leaf top-apps observable, never the panel snapshot.
struct TopAppsListView: View {
    let metric: TopAppMetric
    @ObservedObject var observable: TopAppsObservable

    @EnvironmentObject private var localization: Localization

    var body: some View {
        HardwareDetailCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(localization.string(titleKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                content
            }
        }
    }

    private var titleKey: LocalizationKey {
        metric == .memory ? .hardwareDetailTopAppsMemoryTitle : .hardwareDetailTopAppsTitle
    }

    @ViewBuilder
    private var content: some View {
        switch observable.state {
        case .measured(let stateMetric, let rows) where stateMetric == metric:
            if rows.isEmpty {
                message(.hardwareDetailTopAppsEmpty)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if metric == .network {
                        networkHeader
                    }
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
            }
        case .collecting(let stateMetric) where stateMetric == metric:
            message(.hardwareDetailTopAppsCollecting)
        case .unsupported(let stateMetric) where stateMetric == metric:
            message(.hardwareDetailTopAppsUnsupported)
        case .failed(let stateMetric) where stateMetric == metric:
            message(.hardwareDetailTopAppsFailed)
        default:
            message(.hardwareDetailTopAppsCollecting)
        }
    }

    private func rowView(_ row: TopAppRow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            icon(for: row)
            Text(row.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            if metric == .network {
                networkColumns(row)
            } else {
                Text(valueText(row.value))
                    .font(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var networkColumnWidth: CGFloat { 68 }

    /// Matches Stats' process list: download and upload are two side-by-side
    /// columns, not two stacked lines per application.
    private var networkHeader: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 16, height: 10)
            Spacer(minLength: 0)
            Image(systemName: "arrow.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: networkColumnWidth, alignment: .trailing)
                .accessibilityLabel(localization.string(.hardwareDetailDownload))
            Image(systemName: "arrow.up")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green)
                .frame(width: networkColumnWidth, alignment: .trailing)
                .accessibilityLabel(localization.string(.hardwareDetailUpload))
        }
    }

    private func networkColumns(_ row: TopAppRow) -> some View {
        HStack(spacing: 8) {
            Text(HardwareDetailFormat.rate(row.value))
                .frame(width: networkColumnWidth, alignment: .trailing)
                .accessibilityLabel("\(localization.string(.hardwareDetailDownload)) \(HardwareDetailFormat.rate(row.value))")
            Text(HardwareDetailFormat.rate(row.upload ?? 0))
                .frame(width: networkColumnWidth, alignment: .trailing)
                .accessibilityLabel("\(localization.string(.hardwareDetailUpload)) \(HardwareDetailFormat.rate(row.upload ?? 0))")
        }
        .font(.caption)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    @ViewBuilder
    private func icon(for row: TopAppRow) -> some View {
        if let path = row.applicationPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "gearshape.fill")
                .frame(width: 16, height: 16)
                .foregroundStyle(.secondary)
        }
    }

    private func valueText(_ value: Double) -> String {
        switch metric {
        case .cpu, .gpu:
            return HardwareDetailFormat.appPercent(value)
        case .memory:
            return HardwareDetailFormat.memoryBytes(value)
        case .network:
            return HardwareDetailFormat.rate(value)
        }
    }

    private func message(_ key: LocalizationKey) -> some View {
        Text(localization.string(key))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
