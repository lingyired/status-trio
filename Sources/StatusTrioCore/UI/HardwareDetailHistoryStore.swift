import Combine
import Foundation

/// One sample on a detail chart. `values` carries one entry per series (CPU/GPU/
/// RAM = 1, network/disk = 2); a nil entry is a gap, never a zero.
struct HardwareDetailHistoryPoint: Equatable, Identifiable {
    let id: Int
    let date: Date
    let values: [Double?]
}

/// Bounded 60 s history shared by all five detail pages. Subscribes to the leaf
/// hardware observable only while the page is visible: no timer of its own, and
/// nothing is retained after the page closes.
@MainActor
final class HardwareDetailHistoryStore: ObservableObject {
    nonisolated static let window: TimeInterval = 60
    nonisolated static let maximumGap: TimeInterval = 8
    static let maxPoints = 400

    let seriesCount: Int
    @Published private(set) var points: [HardwareDetailHistoryPoint] = []

    private var cancellable: AnyCancellable?
    private var lastDate: Date?
    private var sequence = 0
    private var timestampProvider: ((HardwareMetricsSnapshot) -> Date?)?
    private var valuesProvider: ((HardwareMetricsSnapshot) -> [Double?])?

    init(seriesCount: Int = 1, seeded: [HardwareDetailHistoryPoint]? = nil) {
        self.seriesCount = max(1, seriesCount)
        if let seeded {
            points = seeded
            lastDate = seeded.last?.date
            sequence = (seeded.last?.id ?? -1) + 1
        }
    }

    func start(observable: HardwareMonitorObservable,
               timestamp: @escaping (HardwareMetricsSnapshot) -> Date?,
               values: @escaping (HardwareMetricsSnapshot) -> [Double?],
               seedRows: [HardwareHistoryRow] = [],
               seedMetricIDs: [HardwareMetricID] = []) {
        stop()
        timestampProvider = timestamp
        valuesProvider = values
        if !seedRows.isEmpty, !seedMetricIDs.isEmpty {
            seedFromHistory(seedRows, metricIDs: seedMetricIDs)
        }
        cancellable = observable.snapshotPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in self?.ingest(snapshot) }
        ingest(observable.snapshot)
    }

    /// Prefills the buffer from the panel-session history the summary already
    /// collected, so opening a detail page shows the last ~60 s immediately.
    func seedFromHistory(_ rows: [HardwareHistoryRow], metricIDs: [HardwareMetricID]) {
        var seeded: [HardwareDetailHistoryPoint] = []
        for row in rows {
            let values = metricIDs.map { row.values[$0] }
            guard values.contains(where: { $0 != nil }) else { continue }
            seeded.append(HardwareDetailHistoryPoint(id: seeded.count, date: row.date, values: values))
        }
        guard !seeded.isEmpty else { return }
        points = seeded
        lastDate = seeded.last?.date
        sequence = seeded.count
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
        timestampProvider = nil
        valuesProvider = nil
        points = []
        lastDate = nil
        sequence = 0
    }

    /// Appends only genuinely new samples: a repeated timestamp (stale refresh or
    /// a redraw) never appends a duplicate.
    func ingest(_ snapshot: HardwareMetricsSnapshot) {
        guard let date = timestampProvider?(snapshot),
              let values = valuesProvider?(snapshot) else { return }
        if let lastDate, date <= lastDate { return }
        lastDate = date
        points.append(HardwareDetailHistoryPoint(id: sequence, date: date, values: values))
        sequence += 1
        prune(now: date)
    }

    /// Seeds a static buffer for an offscreen render. Not used by the live app.
    func seed(_ seeded: [HardwareDetailHistoryPoint]) {
        points = seeded
        lastDate = seeded.last?.date
        sequence = (seeded.last?.id ?? -1) + 1
    }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.window)
        points.removeAll { $0.date < cutoff }
        if points.count > Self.maxPoints {
            points.removeFirst(points.count - Self.maxPoints)
        }
    }
}
