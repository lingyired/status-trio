import AppKit
import SwiftUI

/// The high-usage application card shared by CPU, GPU, memory and network.
/// It observes only the leaf top-apps observable, never the panel snapshot.
struct TopAppsListView: View {
    let metric: TopAppMetric
    @ObservedObject var observable: TopAppsObservable

    @EnvironmentObject private var localization: Localization

    /// The clicked row, frozen in place so the refreshing list cannot change or
    /// move this one row while the user aims at the ×. Other rows keep
    /// updating, mirroring Stats' single-row lock.
    @State private var armed: ArmedRow?
    @State private var pendingQuit: ForceQuitTarget?
    @State private var failedQuitName: String?

    private struct ArmedRow {
        let rowID: TopAppIdentity
        let row: TopAppRow
        /// The position the frozen row keeps until it is released.
        let index: Int
        let target: ForceQuitTarget

        init(_ row: TopAppRow, _ index: Int, _ target: ForceQuitTarget) {
            self.rowID = row.id
            self.row = row
            self.index = index
            self.target = target
        }
    }

    var body: some View {
        HardwareDetailCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(localization.string(titleKey))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    refreshCountdown
                }

                content

                if let failedQuitName {
                    Text(localization.format(.appForceQuitFailed, failedQuitName))
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // Force quit only, like Stats' popup kill. Confirm first because it
        // drops unsaved work, and default to Cancel.
        .alert(
            pendingQuit.map { localization.format(.appForceQuitConfirmTitle, $0.displayName) } ?? "",
            isPresented: Binding(
                get: { pendingQuit != nil },
                set: { if !$0 { pendingQuit = nil } }
            ),
            presenting: pendingQuit
        ) { target in
            Button(localization.string(.appForceQuitConfirmAction), role: .destructive) {
                performQuit(target)
            }
            Button(localization.string(.commonCancel), role: .cancel) { pendingQuit = nil }
        } message: { _ in
            Text(localization.string(.appForceQuitConfirmMessage))
        }
    }

    /// Seconds until the next sample, so the user knows when the list will next
    /// change. Shown as a compact number with a timer glyph on the card title.
    @ViewBuilder
    private var refreshCountdown: some View {
        if let nextRefreshAt = observable.nextRefreshAt {
            CountdownRing(nextRefreshAt: nextRefreshAt) { seconds in
                localization.format(.hardwareDetailTopAppsRefreshCountdown, seconds)
            }
        }
    }

    private var titleKey: LocalizationKey {
        metric == .memory ? .hardwareDetailTopAppsMemoryTitle : .hardwareDetailTopAppsTitle
    }

    /// The latest ranked rows for this metric (empty unless measured).
    private var liveRows: [TopAppRow] {
        if case let .measured(stateMetric, rows) = observable.state, stateMetric == metric {
            return rows
        }
        return []
    }

    @ViewBuilder
    private var content: some View {
        switch observable.state {
        case .measured(let stateMetric, let rows) where stateMetric == metric:
            let displayRows = displayRows(from: rows)
            if displayRows.isEmpty {
                message(.hardwareDetailTopAppsEmpty)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if metric == .network {
                        networkHeader
                    }
                    ForEach(displayRows) { row in
                        rowView(row)
                    }
                }
                // Rows have stable identities; a light animation keeps a
                // re-rank from looking like a jump instead of freezing order.
                .animation(.easeInOut(duration: 0.2), value: displayRows)
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

    /// Live rows, with the armed row's frozen snapshot pinned at its original
    /// index. The rest of the list keeps updating in place; only that one row is
    /// held still.
    private func displayRows(from live: [TopAppRow]) -> [TopAppRow] {
        guard let armed else { return live }
        var result = live.filter { $0.id != armed.rowID }
        let index = min(max(armed.index, 0), result.count)
        result.insert(armed.row, at: index)
        return result
    }

    private func rowView(_ row: TopAppRow) -> some View {
        let isArmed = armed?.rowID == row.id
        return HStack(alignment: .center, spacing: 8) {
            leadingSlot(for: row, isArmed: isArmed)
            Button {
                toggleArm(row)
            } label: {
                HStack(alignment: .center, spacing: 6) {
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
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background {
            if isArmed {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.1))
            }
        }
    }

    /// The 16pt leading slot: the app icon normally, the force-quit × once the
    /// row is clicked. Rows that cannot be quit (self, already-gone apps) never
    /// show the ×.
    @ViewBuilder
    private func leadingSlot(for row: TopAppRow, isArmed: Bool) -> some View {
        if isArmed, let target = armed?.target {
            Button {
                pendingQuit = target
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localization.format(.appForceQuitAction, target.displayName))
            .accessibilityLabel(localization.format(.appForceQuitAction, target.displayName))
        } else {
            icon(for: row)
        }
    }

    private func toggleArm(_ row: TopAppRow) {
        if armed?.rowID == row.id {
            armed = nil
            return
        }
        // Only arm rows that can actually be quit, so a click on a system or
        // self row does nothing visible.
        guard let target = AppQuitter.target(for: row, running: AppQuitter.currentRunningApps()) else {
            armed = nil
            return
        }
        let index = liveRows.firstIndex { $0.id == row.id } ?? 0
        armed = ArmedRow(row, index, target)
        failedQuitName = nil
    }

    private func performQuit(_ target: ForceQuitTarget) {
        let rowID = armed?.rowID
        pendingQuit = nil
        let succeeded = AppQuitter.forceQuit(target)
        if succeeded, let rowID {
            // Drop it from the list now rather than waiting for it to age out
            // at zero, so a closed app does not keep showing in the ranking.
            observable.requestRowRemoval(rowID)
        }
        failedQuitName = succeeded ? nil : target.displayName
        armed = nil
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
                .accessibilityHidden(true)
        } else {
            Image(systemName: "gearshape.fill")
                .frame(width: 16, height: 16)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
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

/// A circular countdown for the top-apps card header: the ring fills once per
/// second and the number inside drops by one when it completes a turn, so the
/// list-update cadence is predictable.
private struct CountdownRing: View {
    let nextRefreshAt: Date
    let labelFor: (Int) -> String
    var diameter: CGFloat = 18
    var lineWidth: CGFloat = 2.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let remaining = max(0, nextRefreshAt.timeIntervalSince(context.date))
            let whole = max(0, Int(remaining.rounded(.up)))
            // 0 → 1 across each one-second slice; resets as `whole` drops.
            let progress = min(1, max(0, Double(whole) - remaining))
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.15), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor.opacity(0.85),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(whole)")
                    .font(.system(size: diameter * 0.5, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: diameter, height: diameter)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(labelFor(whole))
        }
    }
}
