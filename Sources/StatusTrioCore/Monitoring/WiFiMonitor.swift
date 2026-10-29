import CoreWLAN
import Foundation
import Network
import SystemConfiguration
import os

private let wifiMonitorLogger = Logger(
    subsystem: "com.lingsmbp.StatusTrio",
    category: "WiFiMonitor"
)

enum WiFiInterfaceMode: Equatable, Sendable {
    case none
    case station
    case ibss
    case hostAP
    case unknown

    init(coreWLANMode: CWInterfaceMode) {
        switch coreWLANMode {
        case .none:
            self = .none
        case .station:
            self = .station
        case .IBSS:
            self = .ibss
        case .hostAP:
            self = .hostAP
        @unknown default:
            self = .unknown
        }
    }
}

struct WiFiClassificationInput: Equatable, Sendable {
    var powerOn: Bool
    var serviceActive: Bool
    var mode: WiFiInterfaceMode
    var pathSatisfied: Bool?
    var pathUsesWiFi: Bool
    var pathExpensive: Bool
    var sharingActive: Bool
}

enum WiFiClassifier {
    static func classify(_ input: WiFiClassificationInput) -> WiFiState {
        if !input.powerOn { return .off }
        if !input.serviceActive { return .notAssociated }
        if input.sharingActive { return .shared }
        if input.mode == .ibss { return .temporary }

        if let pathSatisfied = input.pathSatisfied {
            if pathSatisfied && input.pathUsesWiFi && input.pathExpensive {
                return .hotspot
            }
            if !pathSatisfied {
                return .noInternet
            }
        }

        return .connected
    }
}

struct WiFiSystemReading: Equatable, Sendable {
    var powerOn: Bool
    var serviceActive: Bool
    var mode: WiFiInterfaceMode
    var rssi: Int?
    var ssid: String?
    var band: WiFiFrequencyBand? = nil
}

protocol WiFiSystemReadingProviding: AnyObject {
    func read() -> WiFiSystemReading?
    func read(includeSSID: Bool) -> WiFiSystemReading?
}

extension WiFiSystemReadingProviding {
    func read(includeSSID: Bool) -> WiFiSystemReading? {
        read()
    }
}

protocol InternetSharingDetecting: AnyObject, Sendable {
    func isActive() -> Bool?
}

protocol WiFiEventMonitoring: AnyObject {
    func start(delegate: any CWEventDelegate, events: [CWEventType])
    func restart(delegate: any CWEventDelegate, events: [CWEventType])
    func stop()
}

struct WiFiPathSnapshot: Equatable, Sendable {
    var satisfied = false
    var usesWiFi = false
    var expensive = false
}

struct WiFiPathUpdate: Equatable, Sendable {
    let sequence: UInt64
    let snapshot: WiFiPathSnapshot
}

protocol WiFiPathMonitoring: AnyObject {
    func start(
        queue: DispatchQueue,
        handler: @escaping (WiFiPathUpdate) -> Void
    )
    func cancel()
}

typealias WiFiClientFactory = () -> CWWiFiClient

final class CoreWLANWiFiSystemReader: WiFiSystemReadingProviding {
    private let client: CWWiFiClient

    init(client: CWWiFiClient = CWWiFiClient.shared()) {
        self.client = client
    }

    func read() -> WiFiSystemReading? {
        read(includeSSID: true)
    }

    func read(includeSSID: Bool) -> WiFiSystemReading? {
        guard let interface = client.interface() else { return nil }

        let powerOn = interface.powerOn()
        let serviceActive = interface.serviceActive()
        return WiFiSystemReading(
            powerOn: powerOn,
            serviceActive: serviceActive,
            mode: WiFiInterfaceMode(coreWLANMode: interface.interfaceMode()),
            rssi: interface.rssiValue(),
            ssid: includeSSID ? interface.ssid() : nil,
            // includeSSID is the existing visible-details gate. This reads the
            // associated interface only; it never requests a network scan.
            band: includeSSID && powerOn && serviceActive ? interface.wlanChannel().flatMap {
                WiFiFrequencyBand(coreWLANBand: $0.channelBand)
            } : nil
        )
    }
}

final class CoreWLANWiFiEventMonitor: WiFiEventMonitoring {
    private let clientFactory: WiFiClientFactory
    private var client: CWWiFiClient

    init(clientFactory: @escaping WiFiClientFactory = { CWWiFiClient() }) {
        self.clientFactory = clientFactory
        self.client = clientFactory()
    }

    func start(delegate: any CWEventDelegate, events: [CWEventType]) {
        configure(delegate: delegate, events: events)
    }

    func restart(delegate: any CWEventDelegate, events: [CWEventType]) {
        clear()
        client = clientFactory()
        configure(delegate: delegate, events: events)
    }

    func stop() {
        clear()
    }

    private func configure(delegate: any CWEventDelegate, events: [CWEventType]) {
        client.delegate = delegate
        for event in events {
            do {
                try client.startMonitoringEvent(with: event)
            } catch {
                wifiMonitorLogger.error(
                    "Failed to register CoreWLAN event \(event.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func clear() {
        client.delegate = nil
        do {
            try client.stopMonitoringAllEvents()
        } catch {
            wifiMonitorLogger.error(
                "Failed to clear CoreWLAN events: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

private final class PathSequenceGenerator: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    func next() -> UInt64 {
        lock.withLock {
            value &+= 1
            return value
        }
    }
}

final class NetworkWiFiPathMonitor: @unchecked Sendable, WiFiPathMonitoring {
    private let lock = NSLock()
    private let sequenceGenerator = PathSequenceGenerator()
    private var monitor: NWPathMonitor?
    private var handler: ((WiFiPathUpdate) -> Void)?

    func start(
        queue: DispatchQueue,
        handler: @escaping (WiFiPathUpdate) -> Void
    ) {
        let monitor = NWPathMonitor()
        lock.withLock {
            self.monitor = monitor
            self.handler = handler
        }
        monitor.pathUpdateHandler = { [weak self, weak monitor] path in
            guard
                let self,
                let monitor,
                self.lock.withLock({ self.monitor === monitor })
            else { return }
            let update = WiFiPathUpdate(
                sequence: self.sequenceGenerator.next(),
                snapshot: WiFiPathSnapshot(
                    satisfied: path.status == .satisfied,
                    usesWiFi: path.usesInterfaceType(.wifi),
                    expensive: path.isExpensive
                )
            )
            let handler = self.lock.withLock { self.handler }
            handler?(update)
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        let monitor = lock.withLock { () -> NWPathMonitor? in
            let monitor = self.monitor
            self.monitor = nil
            handler = nil
            return monitor
        }
        monitor?.cancel()
    }
}

@MainActor
final class WiFiMonitor: NSObject, WiFiMonitoring, CWEventDelegate {
    private enum Lifecycle {
        case idle
        case running
        case stopped
    }

    let updates: AsyncStream<WiFiStatus>

    private static let monitoredEvents: [CWEventType] = [
        .powerDidChange,
        .ssidDidChange,
        .bssidDidChange,
        .linkDidChange,
        .linkQualityDidChange,
        .modeDidChange
    ]

    private let continuation: AsyncStream<WiFiStatus>.Continuation
    private let statusReader: any WiFiStatusReadingProviding
    private let nameAuthorizer: any WiFiNameAuthorizing
    nonisolated(unsafe) private let eventMonitor: any WiFiEventMonitoring
    nonisolated(unsafe) private let pathMonitor: any WiFiPathMonitoring
    private let pathQueue = DispatchQueue(label: "StatusTrio.WiFiPath")
    private let staleInterval: TimeInterval
    /// How long a known-good RSSI stays usable while the interface is still
    /// associated but a fresh `rssiValue()` read comes back invalid (0/absent).
    private let rssiCacheInterval: TimeInterval
    private let now: () -> Date
    private let refreshDebounceInterval: Duration
    private let refreshDebounceSleep: @Sendable (Duration) async throws -> Void
    private var scheduledRefreshTask: Task<Void, Never>?
    private var detailsVisible = true
    private var readInFlight = false
    private var refreshPending = false
    private var readGeneration: UInt64 = 0
    private var readToken: UInt64 = 0
    private let readWatchdog: ReadWatchdog

    private var latestPath: WiFiPathSnapshot?
    private var latestPathSequence: UInt64?
    private var lastValidStatus: WiFiStatus?
    private var lastValidDate: Date?
    /// Last known-good signal strength for the current association. Reused (never
    /// extended) while a read is momentarily invalid, and dropped whenever the
    /// association changes so a previous network's strength is never shown.
    private var cachedRSSI: Int?
    private var cachedRSSIDate: Date?
    private var lastRecoveryAttempt: Date?
    private var isPersistentReadFailure = false
    /// Rebuilds performed while reads reported no interface at all, which is what
    /// a Mac without Wi-Fi hardware returns on every read. Rebuilding the CoreWLAN
    /// event stack for those is pure waste, so the rebuilds are bounded. Reads the
    /// stale-interval gate suppresses do not count; any read that reports an
    /// interface, and `recover()`, reset it.
    private(set) var interfaceAbsentStreak = 0
    private let noInterfaceRecoveryLimit: Int
    private var lifecycle = Lifecycle.idle

    init(
        statusReader: any WiFiStatusReadingProviding = CoreWLANStatusReader(
            sharingDetector: nil
        ),
        nameAuthorizer: any WiFiNameAuthorizing = CoreLocationWiFiNameAuthorizer(),
        eventMonitor: any WiFiEventMonitoring = CoreWLANWiFiEventMonitor(),
        pathMonitor: any WiFiPathMonitoring = NetworkWiFiPathMonitor(),
        staleInterval: TimeInterval = 30,
        rssiCacheInterval: TimeInterval = 30,
        initialPath: WiFiPathSnapshot? = nil,
        now: @escaping () -> Date = Date.init,
        refreshDebounceInterval: Duration = .milliseconds(150),
        refreshDebounceSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        noInterfaceRecoveryLimit: Int = 3,
        readTimeout: Duration = .seconds(5),
        readTimeoutSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.statusReader = statusReader
        self.nameAuthorizer = nameAuthorizer
        self.eventMonitor = eventMonitor
        self.pathMonitor = pathMonitor
        self.staleInterval = staleInterval
        self.rssiCacheInterval = rssiCacheInterval
        self.latestPath = initialPath
        self.now = now
        self.refreshDebounceInterval = refreshDebounceInterval
        self.refreshDebounceSleep = refreshDebounceSleep
        self.noInterfaceRecoveryLimit = noInterfaceRecoveryLimit
        readWatchdog = ReadWatchdog(
            baseTimeout: readTimeout,
            maxTimeout: .seconds(60),
            sleep: readTimeoutSleep
        )
        (updates, continuation) = MonitorStream.make(of: WiFiStatus.self)
        super.init()
        nameAuthorizer.onAccessChange = { [weak self] in
            self?.readGeneration &+= 1
            self?.refresh()
        }
    }

    deinit {
        scheduledRefreshTask?.cancel()
        if lifecycle != .stopped {
            eventMonitor.stop()
            pathMonitor.cancel()
            continuation.finish()
        }
    }

    func start() {
        guard lifecycle == .idle else { return }
        lifecycle = .running

        eventMonitor.start(delegate: self, events: Self.monitoredEvents)
        startPathMonitoring()
        refresh()
    }

    /// External triggers (a wake, an explicit `recover()`) start a fresh budget;
    /// the internal retry path is the one that is bounded.
    func recover() {
        guard lifecycle == .running else { return }
        interfaceAbsentStreak = 0
        restartMonitoring()
    }

    @discardableResult
    func requestNameAccess() -> WiFiNameAccessRequestResult {
        guard lifecycle == .running else { return .notNeeded }
        let result = nameAuthorizer.requestAccess()
        if result == .notNeeded {
            // The displayed permission state may lag behind a grant in Settings.
            readGeneration &+= 1
            refresh()
        }
        return result
    }

    func setDetailsVisible(_ visible: Bool) {
        guard lifecycle != .stopped else { return }
        let changed = detailsVisible != visible
        detailsVisible = visible
        if changed { readGeneration &+= 1 }
        if changed, !visible, lifecycle == .running {
            refresh()
        }
    }

    private func startPathMonitoring() {
        pathMonitor.start(queue: pathQueue) { [weak self] update in
            Task { @MainActor [weak self] in
                guard let self, self.lifecycle == .running else { return }
                if let latestPathSequence = self.latestPathSequence,
                   update.sequence <= latestPathSequence {
                    return
                }
                self.latestPathSequence = update.sequence
                self.latestPath = update.snapshot
                self.scheduleRefresh()
            }
        }
    }

    func stop() {
        guard lifecycle != .stopped else { return }
        lifecycle = .stopped
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = nil
        readWatchdog.cancel()
        teardown()
    }

    func refresh() {
        guard lifecycle != .stopped else { return }
        // Coalesce event bursts and polling while a slow system service replies.
        // At most one read and one follow-up are retained, regardless of latency.
        guard !readInFlight else {
            refreshPending = true
            return
        }
        readInFlight = true
        readToken &+= 1
        let token = readToken
        let generation = readGeneration
        readWatchdog.arm { [weak self] in
            self?.abandonTimedOutRead(token: token)
        }
        statusReader.read(includeSSID: detailsVisible) { [weak self] result in
            // A completion that arrives after the read was declared stuck must not
            // release the latch of the read that replaced it.
            guard let self, token == self.readToken else { return }
            self.readWatchdog.cancel()
            guard self.lifecycle != .stopped else { return }
            self.readWatchdog.recordSuccess()
            self.readInFlight = false
            let needsRefresh = self.refreshPending || generation != self.readGeneration
            self.refreshPending = false
            // Visibility, permission and wake/recovery changes invalidate old reads.
            if generation == self.readGeneration {
                self.receive(result)
            }
            // A debounced event already owns the follow-up. Starting it now would
            // let that timer enqueue another read while this follow-up is in flight.
            if needsRefresh, self.scheduledRefreshTask == nil { self.refresh() }
        }
    }

    /// A system read never returned. Ignore its late completion, release the
    /// single-read latch so the monitor is not stuck forever, and try again so a
    /// transient stall can recover. The reader moves the retry to a fresh queue.
    private func abandonTimedOutRead(token: UInt64) {
        guard token == readToken else { return }
        readToken &+= 1
        readInFlight = false
        readGeneration &+= 1
        refresh()
    }

    private func receive(_ result: WiFiStatusReading) {
        guard let reading = result.interface else {
            publish(.unavailable, rssi: nil, ssid: nil, nameAccess: nameAuthorizer.access)
            return
        }

        interfaceAbsentStreak = 0
        lastRecoveryAttempt = nil
        isPersistentReadFailure = false

        let input = WiFiClassificationInput(
            powerOn: reading.powerOn,
            serviceActive: reading.serviceActive,
            mode: reading.mode,
            pathSatisfied: latestPath?.satisfied,
            pathUsesWiFi: latestPath?.usesWiFi ?? false,
            pathExpensive: latestPath?.expensive ?? false,
            sharingActive: result.sharingActive
        )
        let nameAccess = nameAuthorizer.access
        let state = WiFiClassifier.classify(input)
        let currentDate = now()
        publish(
            state,
            rssi: resolveRSSI(normalizedRSSI(reading.rssi), state: state, at: currentDate),
            ssid: detailsVisible && nameAccess == .authorized ? normalizedSSID(reading.ssid) : nil,
            nameAccess: nameAccess,
            band: detailsVisible && (state == .connected || state == .hotspot) ? reading.band : nil
        )
    }

    nonisolated func clientConnectionInterrupted() {
        Task { @MainActor [weak self] in
            guard let self, self.lifecycle == .running else { return }
            self.scheduleRefresh()
        }
    }

    nonisolated func clientConnectionInvalidated() {
        Task { @MainActor [weak self] in
            guard let self, self.lifecycle == .running else { return }
            self.recover()
            self.scheduleRefresh()
        }
    }

    nonisolated func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.handleAssociationChange()
        }
    }

    nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.handleAssociationChange()
        }
    }

    nonisolated func bssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.handleAssociationChange()
        }
    }

    nonisolated func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.handleAssociationChange()
        }
    }

    nonisolated func linkQualityDidChangeForWiFiInterface(
        withName interfaceName: String,
        rssi: Int,
        transmitRate: Double
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.lifecycle == .running else { return }
            // The event carries the associated network's signal strength; keep it
            // as a fallback for a poll that comes back invalid before the refresh.
            self.noteEventRSSI(rssi)
            self.scheduleRefresh()
        }
    }

    nonisolated func modeDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.scheduleRefresh()
        }
    }

    /// An association identity change (roam, join, leave, radio toggle). The
    /// last network's signal must never be reused for the next one, so the
    /// cached RSSI is dropped before the fresh read is scheduled.
    private func handleAssociationChange() {
        clearCachedRSSI()
        scheduleRefresh()
    }

    /// Records a known-good signal strength delivered by a link-quality event so
    /// a poll that momentarily returns an invalid value can still show a number.
    private func noteEventRSSI(_ rssi: Int) {
        guard rssi < 0 else { return }
        cachedRSSI = rssi
        cachedRSSIDate = now()
    }

    private func scheduleRefresh() {
        guard lifecycle == .running, scheduledRefreshTask == nil else { return }

        let interval = refreshDebounceInterval
        let sleep = refreshDebounceSleep
        scheduledRefreshTask = Task { @MainActor [weak self] in
            do {
                try await sleep(interval)
            } catch {
                self?.scheduledRefreshTask = nil
                return
            }

            guard !Task.isCancelled, let self, self.lifecycle == .running else {
                self?.scheduledRefreshTask = nil
                return
            }

            self.scheduledRefreshTask = nil
            self.refresh()
        }
    }

    private func teardown() {
        eventMonitor.stop()
        pathMonitor.cancel()
        latestPath = nil
        latestPathSequence = nil
        lastValidStatus = nil
        lastValidDate = nil
        clearCachedRSSI()
        lastRecoveryAttempt = nil
        isPersistentReadFailure = false
        continuation.finish()
    }

    private func publish(
        _ state: WiFiState,
        rssi: Int?,
        ssid: String?,
        nameAccess: WiFiNameAccess,
        band: WiFiFrequencyBand? = nil
    ) {
        // A non-associated state is a disconnect or radio-off; the cached signal
        // belongs to a network that is no longer current.
        if !state.isNetworkAssociated {
            clearCachedRSSI()
        }

        let candidate = WiFiStatus(
            state: state,
            rssi: rssi,
            ssid: ssid,
            nameAccess: nameAccess,
            band: band
        )

        if state == .unavailable {
            let currentDate = now()
            if
                let lastValidStatus,
                let lastValidDate,
                currentDate.timeIntervalSince(lastValidDate) <= staleInterval
            {
                continuation.yield(WiFiStatus(
                    state: lastValidStatus.state,
                    rssi: lastValidStatus.rssi,
                    ssid: detailsVisible && nameAccess == .authorized ? lastValidStatus.ssid : nil,
                    nameAccess: nameAccess
                ))
                return
            }

            let shouldAttemptRecovery = lastValidStatus != nil || isPersistentReadFailure
            isPersistentReadFailure = true
            if shouldAttemptRecovery {
                recoverIfAllowed(at: currentDate)
            }

            lastValidStatus = nil
            lastValidDate = nil
            continuation.yield(candidate)
            return
        }

        isPersistentReadFailure = false
        lastValidStatus = candidate
        lastValidDate = now()
        continuation.yield(candidate)
    }

    private func recoverIfAllowed(at date: Date) {
        // Bound the rebuilds, not the reads: the streak is counted only for absent
        // reads that reach the far side of the stale-interval gate and actually
        // rebuild, so gated reads cost nothing and the budget stays
        // `noInterfaceRecoveryLimit` rebuilds whatever the read cadence. The gate
        // also absorbs the fix-up read a rebuild triggers, so a rebuild can never
        // re-trigger itself.
        guard interfaceAbsentStreak < noInterfaceRecoveryLimit else { return }
        if
            let lastRecoveryAttempt,
            date.timeIntervalSince(lastRecoveryAttempt) < staleInterval
        {
            return
        }

        interfaceAbsentStreak += 1
        restartMonitoring()
    }

    private func restartMonitoring() {
        readGeneration &+= 1
        lastRecoveryAttempt = now()
        eventMonitor.restart(delegate: self, events: Self.monitoredEvents)
        pathMonitor.cancel()
        startPathMonitoring()
    }

    /// Resolves the signal strength to publish for an associated interface.
    ///
    /// A fresh valid reading wins and refreshes the cache. When the read is
    /// invalid (`rssiValue()` returns 0/absent while still associated, which is
    /// what issue #110 sees intermittently) the last known-good value is reused
    /// unchanged for up to `rssiCacheInterval`. Reuse never extends that window,
    /// and the cache is dropped on any association change, so a stale value
    /// cannot survive into a different network.
    private func resolveRSSI(_ raw: Int?, state: WiFiState, at date: Date) -> Int? {
        guard state.isNetworkAssociated else { return raw }

        if let raw {
            cachedRSSI = raw
            cachedRSSIDate = date
            return raw
        }

        if
            let cachedRSSI,
            let cachedRSSIDate,
            date.timeIntervalSince(cachedRSSIDate) <= rssiCacheInterval
        {
            return cachedRSSI
        }

        return nil
    }

    private func clearCachedRSSI() {
        cachedRSSI = nil
        cachedRSSIDate = nil
    }

    private func normalizedRSSI(_ rssi: Int?) -> Int? {
        guard let rssi, rssi < 0 else { return nil }
        return rssi
    }

    private func normalizedSSID(_ ssid: String?) -> String? {
        guard let ssid else { return nil }
        let value = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
