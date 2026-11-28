import AppKit
import Combine
import Foundation

@MainActor
final class ApplicationEnergyController: ObservableObject {
    typealias Reader = @Sendable ([ProcessApplication]) -> ApplicationEnergySnapshot

    @Published private(set) var ranking = ApplicationEnergyRanking()
    private let reader: any ApplicationEnergyReading
    private let applications: @MainActor () -> [ProcessApplication]
    private static let queue = DispatchQueue(label: "com.lingsmbp.StatusTrio.application-energy",
                                             qos: .utility)
    private var window: ApplicationEnergyWindow
    private var intervalBuilder: ApplicationEnergyIntervalBuilder
    private var monitorsInBackground = false
    private(set) var backgroundInterval: Duration
    private var isSuspended = false
    private var isSampling = false
    private var active = false
    private var generation = 0
    private var inFlight = false
    private var needsRefresh = false
    private var refreshTask: Task<Void, Never>?

    convenience init() {
        self.init(reader: ApplicationEnergyReader())
    }

    convenience init(reader: @escaping Reader,
                     applications: @escaping @MainActor () -> [ProcessApplication] = ApplicationEnergyController.defaultApplications,
                     backgroundInterval: Duration = .seconds(10),
                     windowConfiguration: ApplicationEnergyWindow.Configuration = .init()) {
        self.init(reader: ClosureEnergyReader(readBody: reader),
                  applications: applications,
                  backgroundInterval: backgroundInterval,
                  windowConfiguration: windowConfiguration)
    }

    init(reader: any ApplicationEnergyReading,
         applications: @escaping @MainActor () -> [ProcessApplication] = ApplicationEnergyController.defaultApplications,
         backgroundInterval: Duration = .seconds(10),
         windowConfiguration: ApplicationEnergyWindow.Configuration = .init()) {
        self.reader = reader
        self.applications = applications
        self.backgroundInterval = backgroundInterval
        self.window = ApplicationEnergyWindow(configuration: windowConfiguration)
        self.intervalBuilder = ApplicationEnergyIntervalBuilder(
            configuration: .init(maximumGap: windowConfiguration.maximumGap)
        )
    }

    deinit { refreshTask?.cancel() }

    static func defaultApplications() -> [ProcessApplication] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard !app.isTerminated, app.activationPolicy != .prohibited,
                  let url = app.bundleURL, let name = app.localizedName else { return nil }
            return ProcessApplication(pid: app.processIdentifier,
                                      path: url.path,
                                      bundleID: app.bundleIdentifier,
                                      name: name)
        }
    }

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
        if suspended {
            stopSampling(clearCache: true)
        } else {
            reconcileSampling(refreshImmediately: true)
        }
    }

    func stop() {
        monitorsInBackground = false
        active = false
        stopSampling(clearCache: true)
    }

    private func reconcileSampling(refreshImmediately: Bool = false) {
        applySamplingTolerances()
        guard !isSuspended, active || monitorsInBackground else {
            // Closing the page without background monitoring releases the GPU
            // subscription, client cache and rolling window as required by the
            // sampling lifecycle.
            stopSampling(clearCache: true)
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
        let firstDelay: Duration = ranking.effectiveDuration == 0 ? .seconds(1) : interval
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

    private func applySamplingTolerances() {
        let interval = active ? Duration.seconds(5) : backgroundInterval
        let components = interval.components
        let seconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        let gap = max(15, seconds + 5)
        window.configuration.maximumGap = gap
        intervalBuilder.setMaximumGap(gap)
    }

    private func stopSampling(clearCache: Bool) {
        isSampling = false
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        needsRefresh = false
        if clearCache {
            window.reset()
            intervalBuilder.reset()
            ranking = ApplicationEnergyRanking()
            let reader = reader
            Self.queue.async { reader.reset() }
        }
    }

    func refresh(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard isSampling else { return }
        if let lastEnd = window.lastEnd, now - lastEnd > window.configuration.maximumGap {
            window.reset()
            intervalBuilder.reset()
            ranking = ApplicationEnergyRanking()
        }
        if let previous = intervalBuilder.previous,
           (0..<0.5).contains(now - previous.readAt) {
            return
        }
        guard !inFlight else { needsRefresh = true; return }
        inFlight = true
        needsRefresh = false
        let generation = generation
        let applications = applications()
        let reader = reader
        Self.queue.async { [weak self] in
            guard self != nil else { return }
            let snapshot = reader.read(applications: applications)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = false
                guard self.isSampling, self.generation == generation else {
                    if self.needsRefresh {
                        self.needsRefresh = false
                        self.refresh()
                    }
                    return
                }
                let freshness = ProcessInfo.processInfo.systemUptime - snapshot.readAt
                guard (0...15).contains(freshness) else {
                    self.window.reset()
                    self.intervalBuilder.reset()
                    self.ranking = ApplicationEnergyRanking()
                    if self.needsRefresh {
                        self.needsRefresh = false
                        self.refresh()
                    }
                    return
                }
                let intervals = self.intervalBuilder.build(current: snapshot)
                self.window.append(contentsOf: intervals)
                self.ranking = self.window.ranking()
                if self.needsRefresh {
                    self.needsRefresh = false
                    self.refresh()
                }
            }
        }
    }
}

/// Adapts a test/legacy closure to the reader protocol.
private final class ClosureEnergyReader: ApplicationEnergyReading, @unchecked Sendable {
    let readBody: @Sendable ([ProcessApplication]) -> ApplicationEnergySnapshot

    init(readBody: @escaping @Sendable ([ProcessApplication]) -> ApplicationEnergySnapshot) {
        self.readBody = readBody
    }

    func read(applications: [ProcessApplication]) -> ApplicationEnergySnapshot {
        readBody(applications)
    }

    func reset() {}
}
