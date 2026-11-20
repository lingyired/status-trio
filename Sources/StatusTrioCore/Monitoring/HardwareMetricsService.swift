import Combine
import Foundation

/// One panel-session sample row used to prefill detail charts. Primary metrics
/// are sampled on the summary already, so recording them here adds no sampling
/// cost; rows are capped at the largest selectable detail window and dropped when
/// the panel closes.
struct HardwareHistoryRow: Equatable, Sendable {
    let date: Date
    let values: [HardwareMetricID: Double]
}

/// A leaf observer: metric updates never enter the broad panel/icon snapshots.
@MainActor
final class HardwareMonitorObservable: ObservableObject {
    /// Backing store. Deliberately NOT `@Published`: `@Published` fires its
    /// projected publisher in `willSet`, so a synchronous subscriber that reads
    /// `snapshot` gets the *previous* value — which made the icon lag one sample
    /// behind. We publish through `snapshotPublisher` *after* the stored value is
    /// updated, so subscribers always read the value they were just handed.
    private var stored: HardwareMetricsSnapshot
    /// Last measured (valued) sample per metric, retained across close/stale so
    /// the panel can show the previous reading instead of flashing an em dash.
    private var lastKnown: [HardwareMetricID: HardwareMetricSample] = [:]
    private let snapshotSubject = PassthroughSubject<HardwareMetricsSnapshot, Never>()
    /// Panel-session history of the primary hardware metrics, kept to the
    /// largest selectable detail window (5 minutes). The detail page trims its
    /// own buffer to the user's 1–5 minute setting when seeding.
    private var historyRows: [HardwareHistoryRow] = []
    static let historyWindow: TimeInterval = 300
    nonisolated static let historyMetricIDs: [HardwareMetricID] = [
        .cpuUsage, .gpuUsage, .memoryUsage,
        .networkDownload, .networkUpload, .diskRead, .diskWrite
    ]

    init(snapshot: HardwareMetricsSnapshot = .empty) { self.stored = snapshot }

    var snapshot: HardwareMetricsSnapshot { stored }

    /// Snapshot for the status-panel summary: fills any missing/valued-less
    /// summary metric from the retained last reading (marked stale/dimmed), so a
    /// reopened panel shows the previous values until a fresh sample lands.
    var summarySnapshot: HardwareMetricsSnapshot { summarySnapshot(at: Date()) }

    /// Fills missing summary values from the retained last reading, but only
    /// while that reading is within `cacheLifetime`; older caches are dropped so
    /// a long-closed panel does not show an ancient number as if current.
    func summarySnapshot(at now: Date) -> HardwareMetricsSnapshot {
        var copy = stored
        for id in HardwareMetricsService.hardwareSummaryMetricIDs {
            if copy.samples[id]?.value == nil, let known = lastKnown[id] {
                let age = now.timeIntervalSince(known.sampledAt)
                guard age >= -5, age <= HardwareMetricSample.cacheLifetime else { continue }
                var cached = known
                cached.availability = .stale
                copy.samples[id] = cached
            }
        }
        return copy
    }

    /// Emits the new snapshot after it has been stored.
    var snapshotPublisher: AnyPublisher<HardwareMetricsSnapshot, Never> {
        snapshotSubject.eraseToAnyPublisher()
    }

    func update(_ snapshot: HardwareMetricsSnapshot, now: Date = Date()) {
        let next = snapshot.expiring(at: now)
        for (id, sample) in next.samples where sample.availability == .measured {
            if let value = sample.value, value.isFinite { lastKnown[id] = sample }
        }
        guard next != stored else { return }
        objectWillChange.send()
        stored = next
        snapshotSubject.send(next)
        recordHistory(from: next)
    }

    /// Records measured primary samples once per timestamp. Shared by every
    /// detail page so opening one shows the trend already accumulating on the
    /// summary instead of starting from empty.
    private func recordHistory(from snapshot: HardwareMetricsSnapshot) {
        // Only metrics sampled in *this* tick form a row. A merged snapshot also
        // carries older samples; including those at the newest timestamp would
        // fabricate points for metrics the current page is not sampling.
        var newest: Date?
        for id in Self.historyMetricIDs {
            guard let sample = snapshot.samples[id], sample.availability == .measured,
                  let value = sample.value, value.isFinite else { continue }
            _ = value
            if newest == nil || sample.sampledAt > newest! { newest = sample.sampledAt }
        }
        guard let newest else { return }
        var values: [HardwareMetricID: Double] = [:]
        for id in Self.historyMetricIDs {
            guard let sample = snapshot.samples[id], sample.availability == .measured,
                  let value = sample.value, value.isFinite,
                  abs(sample.sampledAt.timeIntervalSince(newest)) < 0.001 else { continue }
            values[id] = value
        }
        guard !values.isEmpty else { return }
        if let last = historyRows.last, newest <= last.date { return }
        historyRows.append(HardwareHistoryRow(date: newest, values: values))
        let cutoff = newest.addingTimeInterval(-Self.historyWindow)
        historyRows.removeAll { $0.date < cutoff }
    }

    /// Copy of the panel-session history for seeding a detail chart.
    var historyRowsForDetail: [HardwareHistoryRow] { historyRows }

    func clearHistory() {
        historyRows.removeAll()
    }

    /// Keep the last frame as cached, non-fresh values instead of blanking it,
    /// so reopening the panel shows the previous readings (dimmed) until the
    /// first fresh sample lands.
    func markStale(now: Date = Date()) {
        let next = stored.expiring(at: now)
        guard next != stored else { return }
        objectWillChange.send()
        stored = next
        snapshotSubject.send(next)
    }

    func clear() {
        historyRows.removeAll()
        guard stored != .empty else { return }
        objectWillChange.send()
        stored = .empty
        snapshotSubject.send(stored)
    }

    /// Removes the live snapshot for metrics that just lost their last consumer,
    /// so a hidden card cannot keep displaying a value the data source no longer
    /// refreshes. The last good reading is retained in `lastKnown` but marked
    /// stale, so a later reopen dims it instead of presenting it as live.
    func pruneInactive(_ ids: Set<HardwareMetricID>, now: Date) {
        var changed = false
        for id in ids {
            if stored.samples.removeValue(forKey: id) != nil { changed = true }
        }
        for id in ids {
            guard var known = lastKnown[id] else { continue }
            known.availability = .stale
            lastKnown[id] = known
        }
        guard changed else { return }
        objectWillChange.send()
        snapshotSubject.send(stored)
    }

    /// Drops every detail payload that does not belong to the page now on screen,
    /// so switching pages cannot show another page's stale per-core/breakdown data.
    func clearDetailPayloads(except kind: HardwareDetailKind?) {
        var changed = false
        if kind != .cpu, stored.cpuDetail != nil { stored.cpuDetail = nil; changed = true }
        if kind != .gpu, stored.gpuDetail != nil { stored.gpuDetail = nil; changed = true }
        if kind != .memory, stored.memoryDetail != nil { stored.memoryDetail = nil; changed = true }
        if kind != .network, stored.networkDetail != nil { stored.networkDetail = nil; changed = true }
        if kind != .disk, stored.diskDetail != nil { stored.diskDetail = nil; changed = true }
        guard changed else { return }
        objectWillChange.send()
        snapshotSubject.send(stored)
    }
}

/// One demand-driven schedule shared by all hardware consumers. Only `.panel`
/// is used in this feature; other surfaces reserve an independent demand ID.
/// Physical reads run on HardwareSampler's utility serial queue, never here.
@MainActor
final class HardwareMetricsService: ObservableObject {
    enum Demand: Hashable, Sendable {
        case panel, menuBarArc, menuBarCenter, dock
        /// User-opted low-frequency sampling while the panel is closed.
        case background
    }

    /// Background cadence in seconds (0 = disabled). Only consulted when the
    /// background demand is the sole consumer, so an open panel still refreshes
    /// at the fast metric cadence. Set by the panel view model from settings.
    var backgroundIntervalSeconds: TimeInterval = 0
    /// Panel-open cadence in seconds (0 = metric default). Applied only when the
    /// panel is the sole non-background consumer, so icon/dock consumers keep
    /// their own fast needs.
    var panelIntervalSeconds: TimeInterval = 0

    static let defaultMetricIDs: Set<HardwareMetricID> = [
        .cpuUsage, .gpuUsage, .memoryUsage, .cpuTemperature, .batteryTemperature, .fanRPM(index: 0)
    ]
    /// The compact status-panel summary shows the four rings (CPU/GPU/RAM usage
    /// plus CPU/GPU temperature) and the four data groups (download, upload,
    /// average fan, disk read/write). These are fixed, so the panel samples the
    /// same set regardless of the user's card-metric selection.
    static let hardwareSummaryMetricIDs: Set<HardwareMetricID> = [
        .cpuUsage, .gpuUsage, .memoryUsage,
        .cpuTemperature, .gpuTemperature,
        .fanRPM(index: 0),
        .networkDownload, .networkUpload,
        .diskRead, .diskWrite
    ]

    /// The metrics each detail page needs. GPU/memory/network/disk request only
    /// what that page shows; CPU also enables the separately-throttled frequency.
    static func detailMetricIDs(for kind: HardwareDetailKind) -> Set<HardwareMetricID> {
        HardwareMetricDemandResolver.detailMetrics(for: kind)
    }
    typealias Reader = @Sendable (Set<HardwareMetricID>, Date) async -> HardwareMetricsSnapshot

    let observable = HardwareMonitorObservable()
    private(set) var demands: [Demand: Set<HardwareMetricID>] = [:]
    private(set) var isRunning = false
    private(set) var isAsleep = false
    var isAwaitingReadForTesting: Bool { inFlight }
    /// The loop only needs to wake as often as the fastest demanded metric.
    /// With only slow sensors visible this doubles the sleep and halves wakeups.
    var currentTickIntervalForTesting: TimeInterval { tickInterval }
    /// Effective cadence for one metric after mixing every active consumer.
    func intervalForTesting(_ id: HardwareMetricID) -> TimeInterval { interval(for: id) }
    /// The delay the scheduler would use next — used to prove a slow read parks
    /// the loop instead of spinning at the 50 ms floor.
    var currentWakeDelayForTesting: TimeInterval { nextWakeDelay() }

    private let reader: Reader?
    private let now: () -> Date
    private let automaticScheduling: Bool
    private let sampler = HardwareSampler()
    private var loopTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    /// Physical ownership survives stop/sleep. An outstanding IOKit read cannot
    /// be canceled; reopening must wait for it before starting another read.
    private var inFlight = false
    private var needReaderReset = true
    private var lastRead: [HardwareMetricID: Date] = [:]
    private var forcedIDs: Set<HardwareMetricID> = []
    /// Which detail page (if any) is open; drives the structured payloads and
    /// the per-page expensive work (CPU frequency, network session totals).
    private(set) var detailKind: HardwareDetailKind?

    init(automaticScheduling: Bool = true,
         now: @escaping () -> Date = Date.init,
         reader: Reader? = nil) {
        self.automaticScheduling = automaticScheduling
        self.now = now
        self.reader = reader
    }

    deinit { loopTask?.cancel() }

    private var requestedIDs: Set<HardwareMetricID> {
        demands.values.reduce(into: []) { $0.formUnion($1) }
    }

    /// Sets which detail payload the sampler should build. Clears the other
    /// payloads immediately and stops the expensive per-page work it owned.
    func setDetailDemand(_ kind: HardwareDetailKind?) {
        guard kind != detailKind else { return }
        let previous = detailKind
        detailKind = kind
        // A read already in flight captured the previous page. Invalidate its
        // token so it cannot merge that page's payload back after the clear.
        generation &+= 1
        if previous == .cpu, kind != .cpu { sampler.releaseFrequencyReader() }
        if previous == .network, kind != .network { sampler.resetNetworkSession() }
        observable.clearDetailPayloads(except: kind)
        if kind != nil, isRunning, !isAsleep {
            forcedIDs.formUnion(requestedIDs)
        }
    }

    /// Forces the next tick to read every currently demanded ID (used when a
    /// detail page opens, so its first payload is not delayed behind an interval).
    func forceRefresh() {
        guard isRunning, !isAsleep else { return }
        forcedIDs.formUnion(requestedIDs)
        refreshIfNeeded(forceFamilies: [])
    }

    func begin(_ demand: Demand, metrics: Set<HardwareMetricID> = defaultMetricIDs) {
        guard !metrics.isEmpty else { end(demand); return }
        guard demands[demand] != metrics else { return }
        let previous = requestedIDs
        demands[demand] = metrics
        generation &+= 1
        let removed = previous.subtracting(requestedIDs)
        if !removed.isEmpty {
            observable.pruneInactive(removed, now: now())
        }
        if !isRunning {
            isRunning = true
            // Keep the CPU tick baseline across a close/reopen so the first
            // frame can still produce a usage delta instead of "collecting".
            lastRead.removeAll()
        }
        // Age the retained frame against the current clock so a long-closed
        // panel's cached reading is presented as stale (dimmed), not as live.
        observable.markStale(now: now())
        // Compare IDs, not just families: adding GPU to a CPU-only consumer
        // needs an immediate GPU read even though both belong to `.usage`.
        forcedIDs.formUnion(requestedIDs.subtracting(previous))
        startLoopIfNeeded()
        refreshIfNeeded(forceFamilies: [])
    }

    func end(_ demand: Demand) {
        guard demands.removeValue(forKey: demand) != nil else { return }
        generation &+= 1
        if demands.isEmpty {
            stopLoop()
        } else {
            pruneSnapshot()
            forcedIDs.formIntersection(requestedIDs)
            refreshIfNeeded(forceFamilies: [])
        }
    }

    func stopAll() {
        demands.removeAll()
        generation &+= 1
        stopLoop()
    }

    func sleep() {
        guard !isAsleep else { return }
        isAsleep = true
        generation &+= 1
        loopTask?.cancel()
        loopTask = nil
        needReaderReset = true
        lastRead.removeAll()
        forcedIDs = requestedIDs
        observable.markStale(now: now())
        observable.clearDetailPayloads(except: nil)
        sampler.releaseFrequencyReader()
        sampler.resetNetworkSession()
    }

    func wake() {
        isAsleep = false
        generation &+= 1
        needReaderReset = true
        lastRead.removeAll()
        forcedIDs = requestedIDs
        guard isRunning else { return }
        startLoopIfNeeded()
        refreshIfNeeded(forceFamilies: [])
    }

    private func stopLoop() {
        isRunning = false
        loopTask?.cancel()
        loopTask = nil
        lastRead.removeAll()
        forcedIDs.removeAll()
        observable.markStale(now: now())
        observable.clearDetailPayloads(except: nil)
        // History is deliberately NOT cleared here: a background sample collected
        // while the panel was closed must survive the hand-off to the panel/detail
        // page. It stays bounded to the last 60 s and is pruned on the next sample.
        // `inFlight` deliberately stays true until the outstanding read exits.
    }

    private func startLoopIfNeeded() {
        guard automaticScheduling, isRunning, !isAsleep, loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                let delay = self?.nextWakeDelay() ?? 2
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.refreshIfNeeded(forceFamilies: [])
            }
        }
    }

    /// Wakes when the earliest-demanded metric next comes due instead of on a
    /// fixed heartbeat, so a 4 s sensor is not repeatedly pushed to 6 s by a 2 s
    /// tick. A pending read (inFlight) parks the loop until it finishes, which
    /// then re-enters through the completion path.
    private func nextWakeDelay() -> TimeInterval {
        // A pending read is bounded by its own timeout; waking every 50 ms while
        // its metric is overdue only spins the main actor. Completion restarts
        // the loop at the freshly computed cadence.
        if inFlight { return 30 }
        let ids = requestedIDs
        guard !ids.isEmpty else { return 2 }
        let current = now()
        let soonest = ids.map { id -> TimeInterval in
            let last = lastRead[id] ?? current
            return last.addingTimeInterval(interval(for: id)).timeIntervalSince(current)
        }.min() ?? 2
        return min(max(soonest, 0.05), 30)
    }

    func refreshIfNeeded(forceFamilies: Set<HardwareMetricFamily>) {
        guard isRunning, !isAsleep else { return }
        let ids = requestedIDs
        guard !ids.isEmpty else { return }
        let date = now()
        // Expire displayed values even while a slow IOKit request is outstanding.
        observable.update(observable.snapshot, now: date)
        for id in ids where !HardwareMetricFamily.requested(from: [id]).isDisjoint(with: forceFamilies) {
            forcedIDs.insert(id)
        }
        guard !inFlight else { return }
        let due = Set(ids.filter { id in
            forcedIDs.contains(id) || date.timeIntervalSince(lastRead[id] ?? .distantPast) >= interval(for: id)
        })
        guard !due.isEmpty else { return }
        forcedIDs.subtract(due)
        for id in due { lastRead[id] = date }
        inFlight = true
        let token = generation
        let reset = needReaderReset
        needReaderReset = false
        let sampler = self.sampler
        let includeDetail = detailKind
        let injected = reader
        Task { [weak self] in
            // A surface can close before this task reaches its first suspension.
            guard self?.canRead(token: token) == true else {
                self?.discardFinishedRead()
                return
            }
            if reset, injected == nil { await sampler.reset() }
            guard self?.canRead(token: token) == true else {
                self?.discardFinishedRead()
                return
            }
            let snapshot: HardwareMetricsSnapshot
            if let injected { snapshot = await injected(due, date) }
            else {
                snapshot = await sampler.read(ids: due, at: date,
                                              includeCPUFrequency: includeDetail == .cpu,
                                              details: includeDetail.map { [$0] } ?? [])
            }
            guard let self else { return }
            self.inFlight = false
            guard self.canRead(token: token) else {
                // A new epoch is waiting: discard the old result, then issue one
                // fresh read. Never overlap physical reads across epochs.
                if self.isRunning, !self.isAsleep {
                    self.forcedIDs.formUnion(self.requestedIDs)
                    self.refreshIfNeeded(forceFamilies: [])
                    self.restartLoopAfterRead()
                }
                return
            }
            var merged = self.observable.snapshot
            let includesFans = due.contains { if case .fanRPM = $0 { return true }; return false }
            var previousFanSamples: [HardwareMetricID: HardwareMetricSample] = [:]
            if includesFans {
                previousFanSamples = merged.samples.filter { if case .fanRPM = $0.key { return true }; return false }
                merged.samples = merged.samples.filter { if case .fanRPM = $0.key { return false }; return true }
                if let fanCount = snapshot.fanCount {
                    merged.fanCount = fanCount
                }
            }
            for (id, sample) in snapshot.samples where self.isRequested(id) {
                if sample.availability == .collecting, sample.value == nil,
                   let existing = merged.samples[id],
                   existing.availability == .measured
                    || (existing.availability == .stale && existing.value != nil) {
                    // The CPU baseline rebuilds after a long gap; keep the cached
                    // reading rather than flashing "—" for this first tick.
                    continue
                }
                merged.samples[id] = sample
            }
            if includesFans {
                // A transient SMC miss must not blank a fan that was reporting a
                // moment ago; keep the cached reading until a real value arrives.
                for (id, old) in previousFanSamples where merged.samples[id] == nil {
                    merged.samples[id] = old
                }
            }
            if includesFans, let count = snapshot.fanCount ?? merged.fanCount {
                merged.samples = merged.samples.filter { id, _ in
                    if case let .fanRPM(index) = id { return index < count }
                    return true
                }
            }
            if let detail = snapshot.cpuDetail { merged.cpuDetail = detail }
            if let detail = snapshot.gpuDetail { merged.gpuDetail = detail }
            if let detail = snapshot.memoryDetail { merged.memoryDetail = detail }
            if let detail = snapshot.networkDetail { merged.networkDetail = detail }
            if let detail = snapshot.diskDetail { merged.diskDetail = detail }
            self.observable.update(merged, now: self.now())
            self.refreshIfNeeded(forceFamilies: [])
            self.restartLoopAfterRead()
        }
    }

    private func canRead(token: UInt64) -> Bool {
        generation == token && isRunning && !isAsleep
    }

    private func discardFinishedRead() {
        inFlight = false
        if isRunning, !isAsleep {
            forcedIDs.formUnion(requestedIDs)
            refreshIfNeeded(forceFamilies: [])
            restartLoopAfterRead()
        }
    }

    /// Cancel the sleeping scheduler and let it recompute from the completion
    /// path. Without this a read that finished early would wait out the parked
    /// 30 s delay before the next sample.
    private func restartLoopAfterRead() {
        loopTask?.cancel()
        loopTask = nil
        startLoopIfNeeded()
    }

    private var tickInterval: TimeInterval {
        let ids = requestedIDs
        guard !ids.isEmpty else { return 2 }
        return ids.map(interval(for:)).min() ?? 2
    }

    /// A metric is read as often as its most demanding active consumer needs it.
    /// A slow panel therefore never drags an icon's fast metric slower, and a
    /// fast icon never speeds up a metric only the slow panel asked for.
    private func interval(for id: HardwareMetricID) -> TimeInterval {
        let base = defaultMetricInterval(for: id)
        var result: TimeInterval?
        for (demand, metrics) in demands {
            let owns = metrics.contains(id)
                || (Self.isFanMetric(id) && metrics.contains(where: Self.isFanMetric))
            guard owns else { continue }
            let cadence: TimeInterval
            switch demand {
            case .panel: cadence = panelIntervalSeconds
            case .background: cadence = backgroundIntervalSeconds
            default: cadence = 0
            }
            // A consumer's cadence can slow a metric down but never speed it
            // past its own floor: a 1 s panel must not drive a 4 s sensor at 1 s.
            let candidate = cadence > 0 ? max(base, cadence) : base
            result = min(result ?? candidate, candidate)
        }
        return max(0.2, result ?? base)
    }

    private static func isFanMetric(_ id: HardwareMetricID) -> Bool {
        if case .fanRPM = id { return true }
        return false
    }

    private func defaultMetricInterval(for id: HardwareMetricID) -> TimeInterval {
        switch id {
        case .cpuUsage, .gpuUsage, .memoryUsage: 2
        case .cpuTemperature, .gpuTemperature, .batteryTemperature, .fanRPM: 4
        case .networkDownload, .networkUpload: 1
        case .diskRead, .diskWrite: 1
        case .volume, .wifiSignal, .batteryLevel: 2
        }
    }

    private func isRequested(_ id: HardwareMetricID) -> Bool {
        if case .fanRPM = id {
            return requestedIDs.contains { if case .fanRPM = $0 { return true }; return false }
        }
        return requestedIDs.contains(id)
    }

    private func pruneSnapshot() {
        var next = observable.snapshot
        next.samples = next.samples.filter { isRequested($0.key) }
        if !requestedIDs.contains(where: { if case .fanRPM = $0 { return true }; return false }) {
            next.fanCount = nil
        }
        observable.update(next, now: now())
    }
}
