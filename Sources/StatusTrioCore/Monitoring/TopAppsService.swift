import AppKit
import Combine
import Foundation

/// Leaf observer for the detail page. Top-app rows never enter the broad panel
/// or icon snapshots.
@MainActor
final class TopAppsObservable: ObservableObject {
    @Published private(set) var state: TopAppsState = .idle

    func update(_ state: TopAppsState) {
        guard self.state != state else { return }
        self.state = state
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
    /// Keeps the list height stable: a row that drops to zero stays until a new
    /// application replaces it.
    private var retainedRows: [TopAppRow] = []
    private var retainedMetric: TopAppMetric?

    /// Per-metric default cadence for the top-app list.
    nonisolated static func defaultInterval(for metric: TopAppMetric) -> Double {
        switch metric {
        case .cpu, .gpu, .network: return 2
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
        if metric != retainedMetric {
            retainedRows = []
            retainedMetric = metric
        }
        sessionGeneration &+= 1
        loopTask?.cancel()
        loopTask = nil
        if let metric {
            observable.update(.collecting(metric))
        } else {
            observable.update(.idle)
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
        requestTrackerReset()
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
        retainedMetric = nil
        sessionGeneration &+= 1
        loopTask?.cancel()
        loopTask = nil
        observable.update(.idle)
        requestTrackerReset()
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
                let remaining = interval - Double(elapsed) / 1_000_000_000
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
        let session = sessionGeneration
        let applicationSnapshot = applications()
        let result = await sampler.read(metric, applications: applicationSnapshot)
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
            observable.update(.collecting(metric))
        case .measured(let rows):
            retainedRows = Self.mergedRows(previous: retainedRows, incoming: rows,
                                           limit: Self.maximumRows)
            observable.update(.measured(metric, retainedRows))
        case .unsupported:
            observable.update(.unsupported(metric))
        case .failed:
            observable.update(.failed(metric))
        }
    }

    static let maximumRows = 8

    /// Stable merge: previous order first (updated values, or zeroed when the app
    /// stopped using the resource), then newly seen apps. A new app displaces a
    /// zero row instead of growing the list.
    static func mergedRows(previous: [TopAppRow], incoming: [TopAppRow],
                           limit: Int) -> [TopAppRow] {
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

    private func requestTrackerReset() {
        let sampler = self.sampler
        Task { await sampler.reset() }
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
