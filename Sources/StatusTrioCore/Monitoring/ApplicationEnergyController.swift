import AppKit
import Combine
import Foundation

@MainActor
final class ApplicationEnergyController: ObservableObject {
    typealias Reader = @Sendable ([EnergyApplication]) -> ApplicationEnergySnapshot
    @Published private(set) var ranking = ApplicationEnergyRanking()
    private let reader: Reader
    private let applications: @MainActor () -> [EnergyApplication]
    private static let queue = DispatchQueue(label: "com.lingsmbp.StatusTrio.application-energy", qos: .utility)
    private var previous: ApplicationEnergySnapshot?
    private var monitorsInBackground = false
    private(set) var backgroundInterval: Duration
    private var isSuspended = false
    private var isSampling = false
    private var active = false
    private var generation = 0
    private var inFlight = false
    private var needsRefresh = false
    private var refreshTask: Task<Void, Never>?

    init(reader: @escaping Reader = { ApplicationEnergyReader().read(applications: $0) },
         applications: @escaping @MainActor () -> [EnergyApplication] = {
             NSWorkspace.shared.runningApplications.compactMap { app in
                 guard !app.isTerminated, app.activationPolicy != .prohibited,
                       let url = app.bundleURL, let name = app.localizedName else { return nil }
                 return EnergyApplication(id: url.path, name: name)
             }
         },
         backgroundInterval: Duration = .seconds(10)) {
        self.reader = reader
        self.applications = applications
        self.backgroundInterval = backgroundInterval
    }

    deinit { refreshTask?.cancel() }

    func activate() {
        guard !active else { return }
        active = true
        reconcileSampling(refreshImmediately: true)
    }

    func deactivate() {
        guard active else { return }
        active = false
        reconcileSampling()
    }

    /// Owned by the running app and the persisted opt-in, independently of the
    /// detail page. Opening a page consumes the already-warm recent ranking.
    func setBackgroundMonitoringEnabled(_ enabled: Bool) {
        guard monitorsInBackground != enabled else { return }
        monitorsInBackground = enabled
        if !enabled {
            active = false
            stopSampling(clearCache: true)
        } else {
            reconcileSampling(refreshImmediately: true)
        }
    }

    func setBackgroundInterval(_ interval: Duration) {
        guard backgroundInterval != interval else { return }
        backgroundInterval = interval
        // The detail page owns a fixed live cadence. Background changes only
        // need to reschedule when that page is not currently visible.
        if !active { reconcileSampling() }
    }

    func setSuspended(_ suspended: Bool) {
        guard isSuspended != suspended else { return }
        isSuspended = suspended
        if suspended { stopSampling(clearCache: true) } else { reconcileSampling(refreshImmediately: true) }
    }

    func stop() {
        monitorsInBackground = false
        active = false
        stopSampling(clearCache: true)
    }

    private func reconcileSampling(refreshImmediately: Bool = false) {
        guard !isSuspended, active || monitorsInBackground else {
            stopSampling(clearCache: false)
            return
        }
        let starting = !isSampling
        if starting {
            generation += 1
            isSampling = true
        }
        if starting || refreshImmediately { refresh() }
        refreshTask?.cancel()
        let interval: Duration = active ? .seconds(5) : backgroundInterval
        // A cold start needs two counters. Warm once after 1 second; subsequent
        // work is low-frequency and never tied to opening the menu.
        let firstDelay: Duration = ranking.phase == .sampling ? .seconds(1) : interval
        refreshTask = Task { @MainActor [weak self] in
            var delay = firstDelay
            while !Task.isCancelled {
                do { try await Task.sleep(for: delay, tolerance: .milliseconds(250)) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.refresh()
                delay = interval
            }
        }
    }

    private func stopSampling(clearCache: Bool) {
        isSampling = false
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        needsRefresh = false
        if clearCache {
            previous = nil
            ranking = ApplicationEnergyRanking()
        }
    }

    func refresh(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard isSampling else { return }
        if let previous, now - previous.readAt > 15 {
            self.previous = nil
            ranking = ApplicationEnergyRanking()
        }
        // Visibility changes must not replace a valid ranking with a zero-length
        // interval or schedule redundant IPC immediately after a background read.
        if let previous, (0..<0.5).contains(now - previous.readAt) { return }
        guard !inFlight else { needsRefresh = true; return }
        inFlight = true
        needsRefresh = false
        let generation = generation
        let applications = applications()
        let reader = reader
        Self.queue.async { [weak self] in
            guard self != nil else { return }
            let snapshot = reader(applications)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = false
                if self.isSampling && self.generation == generation {
                    // A blocked read must not publish a stale ranking.
                    if (0...15).contains(ProcessInfo.processInfo.systemUptime - snapshot.readAt) {
                        self.ranking = ApplicationEnergyRanking.rank(previous: self.previous, current: snapshot)
                        self.previous = snapshot
                    } else {
                        self.previous = nil
                        self.ranking = ApplicationEnergyRanking()
                    }
                }
                if self.needsRefresh { self.refresh() }
            }
        }
    }
}
