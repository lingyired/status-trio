import AppKit
import Combine
import Foundation

/// Leaf observer for the detail page. Top-app rows never enter the broad panel
/// or icon snapshots.
@MainActor
final class TopAppsObservable: ObservableObject {
    @Published private(set) var state: TopAppsState = .idle
    /// When the next sample is expected, so the card can show a countdown. Nil
    /// while idle/asleep or between a sample finishing and the next schedule.
    @Published private(set) var nextRefreshAt: Date?

    func update(_ state: TopAppsState) {
        guard self.state != state else { return }
        self.state = state
    }

    func updateNextRefresh(_ date: Date?) {
        guard nextRefreshAt != date else { return }
        nextRefreshAt = date
    }

    /// A force-quit just removed a row; ask the service to drop it from the
    /// ranking immediately instead of waiting for it to age out at zero.
    private let rowRemovalSubject = PassthroughSubject<TopAppIdentity, Never>()
    var rowRemovalRequests: AnyPublisher<TopAppIdentity, Never> { rowRemovalSubject.eraseToAnyPublisher() }

    func requestRowRemoval(_ id: TopAppIdentity) {
        rowRemovalSubject.send(id)
    }
}

/// Owns the on-demand top-app sampling session. `top` is expensive, so the
/// default cadence is 2 s for CPU/GPU/network and 6 s for memory.
@MainActor
final class TopAppsService {
    let observable = TopAppsObservable()

    private let sampler: any TopAppsSampling
    private let applications: @MainActor () -> [ProcessApplication]
    private let automaticScheduling: Bool
    private let sleepFor: @Sendable (Duration) async throws -> Void
    private let clock: @Sendable () -> UInt64
    /// `top` costs far more than the syscall readers, so memory polls less often.
    private let intervalSeconds: @Sendable (TopAppMetric) -> Double

    private(set) var demand: TopAppMetric?
    private(set) var isAsleep = false
    private(set) var isStopped = false
    private(set) var sessionGeneration: UInt64 = 0
    private var loopTask: Task<Void, Never>?
    private var inFlight = false
    /// Set when a session ends while a cumulative read may still be running.
    /// The reset is deferred until that read returns and runs before any new
    /// read, so a late sample cannot overwrite the fresh baseline.
    private var needsTrackerReset = false
    /// Current ranked rows: a row that drops to zero still stays at the bottom
    /// until a live application replaces it. Always re-sorted by value.
    private var retainedRows: [TopAppRow] = []
    /// Last published rows per metric, kept across detail-page sessions so
    /// reopening a page can replay the previous ranking instead of a blank card.
    private var lastRowsByMetric: [TopAppMetric: [TopAppRow]] = [:]
    /// True when the last read only established a cumulative baseline; the next
    /// turn retries quickly instead of waiting a full interval.
    private var lastSampleWasCollecting = false

    /// Rows the user force-quit: dropped from the ranking at once and kept out
    /// until a fresh sample no longer reports them (so a stale in-flight read
    /// cannot resurrect the row).
    private var suppressedIDs: Set<TopAppIdentity> = []
    private var rowRemovalCancellable: AnyCancellable?

    /// After a cumulative metric only establishes its baseline, retry once
    /// quickly so the first frame appears in about half a second instead of a
    /// full refresh interval.
    static let collectingRetryInterval: Double = 0.5

    /// Per-metric default cadence for the top-app list. GPU is cheap to read
    /// through IOKit and drives the high-usage ranking, so it refreshes at 1 s;
    /// the syscall and top readers stay slower to keep the page low-power.
    nonisolated static func defaultInterval(for metric: TopAppMetric) -> Double {
        switch metric {
        case .gpu: return 1
        case .cpu, .network: return 2
        case .memory: return 6
        }
    }

    init(sampler: any TopAppsSampling = TopAppsSampler(),
         applications: @escaping @MainActor () -> [ProcessApplication] = TopAppsService.runningApplications,
         automaticScheduling: Bool = true,
         sleepFor: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         clock: @escaping @Sendable () -> UInt64 = { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) },
         intervalSeconds: @escaping @Sendable (TopAppMetric) -> Double = TopAppsService.defaultInterval(for:)) {
        self.sampler = sampler
        self.applications = applications
        self.automaticScheduling = automaticScheduling
        self.sleepFor = sleepFor
        self.clock = clock
        self.intervalSeconds = intervalSeconds
        rowRemovalCancellable = observable.rowRemovalRequests.sink { [weak self] id in
            self?.forgetRow(id)
        }
    }

    deinit { loopTask?.cancel() }

    var isReadInFlightForTesting: Bool { inFlight }

    static func runningApplications() -> [ProcessApplication] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard !app.isTerminated,
                  app.activationPolicy != .prohibited,
                  let url = app.bundleURL,
                  let name = app.localizedName else { return nil }
            return ProcessApplication(pid: app.processIdentifier,
                                      path: url.standardizedFileURL.path,
                                      bundleID: app.bundleIdentifier,
                                      name: name)
        }
    }

    /// Only the currently visible hardware detail page owns a list.
    func setDemand(_ metric: TopAppMetric?) {
        guard !isStopped else { return }
        guard metric != demand else { return }

        demand = metric
        // Seed from the last ranking for this metric so reopening the page
        // replays it immediately; a cold first open still shows the collecting
        // placeholder until the first frame arrives.
        retainedRows = metric.flatMap { lastRowsByMetric[$0] } ?? []
        sessionGeneration &+= 1
        loopTask?.cancel()
        loopTask = nil
        needsTrackerReset = true
        if let metric {
            if retainedRows.isEmpty {
                observable.update(.collecting(metric))
            } else {
                observable.update(.measured(metric, retainedRows))
            }
        } else {
            observable.update(.idle)
            observable.updateNextRefresh(nil)
            resetTrackersWhenIdle()
        }
        startLoopIfNeeded()
    }

    func sleep() {
        guard !isStopped, !isAsleep else { return }
        isAsleep = true
        sessionGeneration &+= 1
        loopTask?.cancel()
        loopTask = nil
        if let demand {
            observable.update(.collecting(demand))
        } else {
            observable.update(.idle)
        }
        observable.updateNextRefresh(nil)
        needsTrackerReset = true
        resetTrackersWhenIdle()
    }

    func wake() {
        guard !isStopped, isAsleep else { return }
        isAsleep = false
        if let demand {
            observable.update(.collecting(demand))
            startLoopIfNeeded()
        }
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        demand = nil
        retainedRows = []
        lastRowsByMetric.removeAll()
        suppressedIDs.removeAll()
        lastSampleWasCollecting = false
        sessionGeneration &+= 1
        loopTask?.cancel()
        loopTask = nil
        observable.update(.idle)
        observable.updateNextRefresh(nil)
        needsTrackerReset = true
        resetTrackersWhenIdle()
    }

    /// Drives one turn without waiting for the timer; tests use this to
    /// reproduce a slow read and a late result deterministically.
    func sampleNowForTesting() async {
        await sampleOnce()
    }

    private func startLoopIfNeeded() {
        guard automaticScheduling,
              loopTask == nil,
              !inFlight,
              !isAsleep,
              !isStopped,
              demand != nil else { return }

        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let started = self.clock()
                let metric = self.demand ?? .cpu
                await self.sampleOnce()
                guard !Task.isCancelled else { return }
                let now = self.clock()
                let elapsed = now >= started ? now - started : 0
                let interval = max(0.1, self.intervalSeconds(metric))
                // A baseline-only frame retries quickly so the ranking appears
                // in about half a second; steady-state keeps the metric cadence.
                let target = self.lastSampleWasCollecting
                    ? min(Self.collectingRetryInterval, interval)
                    : interval
                let remaining = target - Double(elapsed) / 1_000_000_000
                self.observable.updateNextRefresh(Date().addingTimeInterval(max(0, remaining)))
                if remaining > 0 {
                    try? await self.sleepFor(.seconds(remaining))
                } else {
                    await Task.yield()
                }
            }
        }
    }

    private func sampleOnce() async {
        guard let metric = demand, !inFlight, !isAsleep, !isStopped else { return }
        inFlight = true
        lastSampleWasCollecting = false
        let session = sessionGeneration

        await resetTrackerIfNeeded()

        guard session == sessionGeneration,
              demand == metric,
              !isAsleep,
              !isStopped else {
            inFlight = false
            startLoopIfNeeded()
            return
        }

        let applicationSnapshot = applications()
        let result = await sampler.read(metric, applications: applicationSnapshot)

        // The physical read has returned. If the session ended while it was
        // running, reset the trackers before another read can start.
        await resetTrackerIfNeeded()
        inFlight = false

        guard session == sessionGeneration,
              demand == metric,
              !isAsleep,
              !isStopped else {
            // A demand change while this read was running needs its loop now
            // that the physical read has finished and the baseline is safe.
            startLoopIfNeeded()
            return
        }

        switch result {
        case .collecting:
            lastSampleWasCollecting = true
            if retainedRows.isEmpty {
                observable.update(.collecting(metric))
            } else {
                // Keep the previous ranking visible while the new frame is
                // collected, so reopening the page never flashes an empty card.
                observable.update(.measured(metric, retainedRows))
            }
        case .measured(let rows):
            // Keep a just-quit row out until a fresh sample no longer lists it,
            // so a close does not leave it lingering at zero in the list.
            suppressedIDs = suppressedIDs.filter { id in rows.contains { $0.id == id } }
            let incoming = rows.filter { !suppressedIDs.contains($0.id) }
            retainedRows = Self.mergedRows(previous: retainedRows.filter { !suppressedIDs.contains($0.id) },
                                           incoming: incoming,
                                           metric: metric, limit: Self.maximumRows)
            lastRowsByMetric[metric] = retainedRows
            observable.update(.measured(metric, retainedRows))
        case .unsupported:
            observable.update(.unsupported(metric))
        case .failed:
            observable.update(.failed(metric))
        }
    }

    static let maximumRows = 8

    /// Removes a just-quit row from the published ranking right away.
    private func forgetRow(_ id: TopAppIdentity) {
        suppressedIDs.insert(id)
        retainedRows.removeAll { $0.id == id }
        guard let metric = demand else { return }
        lastRowsByMetric[metric] = retainedRows
        if case let .measured(stateMetric, _) = observable.state, stateMetric == metric {
            observable.update(.measured(metric, retainedRows))
        }
    }

    /// Merge then rank. Previous apps keep a slot with refreshed values (or zero
    /// when the app stopped using the resource) and newly seen apps are added;
    /// the result is always re-sorted by the current value so a busy app moves up
    /// and a new high-usage app lands in the right place. A zero row naturally
    /// settles at the bottom and is the first to be dropped past the limit.
    static func mergedRows(previous: [TopAppRow], incoming: [TopAppRow],
                           metric: TopAppMetric, limit: Int) -> [TopAppRow] {
        guard limit > 0 else { return [] }
        var byID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
        var result: [TopAppRow] = []
        for old in previous {
            if let updated = byID.removeValue(forKey: old.id) {
                result.append(updated)
            } else {
                result.append(TopAppRow(id: old.id, name: old.name,
                                        applicationPath: old.applicationPath,
                                        value: 0, upload: old.upload == nil ? nil : 0))
            }
        }
        for row in incoming where byID[row.id] != nil {
            result.append(row)
            byID.removeValue(forKey: row.id)
        }
        result = TopAppRanking.sorted(result, metric: metric)
        while result.count > limit {
            if let zeroIndex = result.lastIndex(where: {
                $0.value == 0 && ($0.upload ?? 0) == 0
            }) {
                result.remove(at: zeroIndex)
            } else {
                result.removeLast()
            }
        }
        return result
    }

    /// Runs only from `sampleOnce`, while `inFlight` still excludes another
    /// read. A reset requested during this await is covered by this reset:
    /// trackers are empty and no read can sample them until it finishes.
    /// When there is no active read to clear the baseline on its way out, take
    /// the same in-flight slot so a reopening page waits for this reset.
    private func resetTrackersWhenIdle() {
        guard !inFlight else { return }
        inFlight = true
        Task { [weak self] in
            guard let self else { return }
            await self.resetTrackerIfNeeded()
            self.inFlight = false
            self.startLoopIfNeeded()
        }
    }

    private func resetTrackerIfNeeded() async {
        guard needsTrackerReset else { return }
        needsTrackerReset = false
        await sampler.reset()
        needsTrackerReset = false
    }
}

extension HardwareDetailKind {
    /// The detail page's matching ranked metric; disk has no ranked list.
    var topAppMetric: TopAppMetric? {
        switch self {
        case .cpu: return .cpu
        case .gpu: return .gpu
        case .memory: return .memory
        case .network: return .network
        case .disk, .fan: return nil
        }
    }
}
