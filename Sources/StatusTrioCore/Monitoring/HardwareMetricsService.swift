import Combine
import Foundation

/// A leaf observer: metric updates never enter the broad panel/icon snapshots.
@MainActor
final class HardwareMonitorObservable: ObservableObject {
    @Published private(set) var snapshot: HardwareMetricsSnapshot

    init(snapshot: HardwareMetricsSnapshot = .empty) { self.snapshot = snapshot }

    func update(_ snapshot: HardwareMetricsSnapshot, now: Date = Date()) {
        let next = snapshot.expiring(at: now)
        if self.snapshot != next { self.snapshot = next }
    }

    /// Keep the last frame as cached, non-fresh values instead of blanking it,
    /// so reopening the panel shows the previous readings (dimmed) until the
    /// first fresh sample lands.
    func markStale(now: Date = Date()) {
        let next = snapshot.expiring(at: now)
        if snapshot != next { snapshot = next }
    }

    func clear() {
        if snapshot != .empty { snapshot = .empty }
    }
}

/// One demand-driven schedule shared by all hardware consumers. Only `.panel`
/// is used in this feature; other surfaces reserve an independent demand ID.
/// Physical reads run on HardwareSampler's utility serial queue, never here.
@MainActor
final class HardwareMetricsService: ObservableObject {
    enum Demand: Hashable, Sendable {
        case panel, menuBarArc, menuBarCenter, dock
    }

    static let defaultMetricIDs: Set<HardwareMetricID> = [
        .cpuUsage, .gpuUsage, .cpuTemperature, .fanRPM(index: 0)
    ]
    typealias Reader = @Sendable (Set<HardwareMetricID>, Date) async -> HardwareMetricsSnapshot

    let observable = HardwareMonitorObservable()
    private(set) var demands: [Demand: Set<HardwareMetricID>] = [:]
    private(set) var isRunning = false
    private(set) var isAsleep = false
    var isAwaitingReadForTesting: Bool { inFlight }

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

    func begin(_ demand: Demand, metrics: Set<HardwareMetricID> = defaultMetricIDs) {
        guard !metrics.isEmpty else { end(demand); return }
        guard demands[demand] != metrics else { return }
        let previous = requestedIDs
        demands[demand] = metrics
        generation &+= 1
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
        // `inFlight` deliberately stays true until the outstanding read exits.
    }

    private func startLoopIfNeeded() {
        guard automaticScheduling, isRunning, !isAsleep, loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.refreshIfNeeded(forceFamilies: [])
            }
        }
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
            else { snapshot = await sampler.read(ids: due, at: date) }
            guard let self else { return }
            self.inFlight = false
            guard self.canRead(token: token) else {
                // A new epoch is waiting: discard the old result, then issue one
                // fresh read. Never overlap physical reads across epochs.
                if self.isRunning, !self.isAsleep {
                    self.forcedIDs.formUnion(self.requestedIDs)
                    self.refreshIfNeeded(forceFamilies: [])
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
            self.observable.update(merged, now: self.now())
            self.refreshIfNeeded(forceFamilies: [])
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
        }
    }

    private func interval(for id: HardwareMetricID) -> TimeInterval {
        switch id {
        case .cpuUsage, .gpuUsage: 2
        case .cpuTemperature, .gpuTemperature, .fanRPM: 4
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
