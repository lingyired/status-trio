import Combine
import Foundation

@MainActor
final class MobileBatteryController: ObservableObject {
    private static let refreshInterval: Duration = .seconds(60)
    private static let cacheLifetime: TimeInterval = 1_200
    private static let initialWatchRetryInterval: Duration = .seconds(60)
    private static let maximumInitialWatchRetries = 3

    @Published private(set) var snapshots: [MobileBatterySnapshot] = []
    @Published private(set) var failures: [MobileBatteryReadFailure] = []
    @Published private(set) var isRefreshing = false

    private let reader: any MobileBatteryReading
    private let clock: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private var claims: Set<String> = []
    private var authorizedDeviceIDs: Set<AppleDeviceID> = []
    private var backgroundAuthorizedDeviceIDs: Set<AppleDeviceID> = []
    private var initialWatchRetryAttempts: [AppleDeviceID: Int] = [:]
    private var isSurfaceVisible = false
    private var isReadingEnabled = true
    private var isBackgroundRefreshEnabled = false
    private var backgroundRefreshInterval: Duration = .seconds(60)
    private var isStopped = false
    private var generation: UInt64 = 0
    private var readTask: Task<Void, Never>?
    private var activeReadDemandIDs: Set<AppleDeviceID> = []
    private var refreshTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var nextFullRefreshDate: Date?

    init(
        reader: any MobileBatteryReading = MobileBatteryHelperReader(),
        clock: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.reader = reader
        self.clock = clock
        self.sleep = sleep
    }

    deinit {
        readTask?.cancel()
        refreshTask?.cancel()
        expiryTask?.cancel()
    }

    func request(_ token: String) {
        guard !isStopped, !token.isEmpty else { return }
        let wasEnabled = isEnabled
        claims.insert(token)
        if !wasEnabled { updateLifecycle() }
    }

    func release(_ token: String, keepingResults: Bool = false) {
        guard !isStopped, claims.remove(token) != nil else { return }
        if claims.isEmpty {
            updateLifecycle()
            if !keepingResults && !isBackgroundRefreshEnabled {
                snapshots = []
                failures = []
            }
        }
    }

    func setSurfaceVisible(_ visible: Bool) {
        guard !isStopped, isSurfaceVisible != visible else { return }
        isSurfaceVisible = visible
        updateLifecycle()
    }

    func setAuthorizedDeviceIDs(_ ids: Set<AppleDeviceID>) {
        guard !isStopped, authorizedDeviceIDs != ids else { return }
        let wasEnabled = isEnabled
        let previousAuthorization = authorizedDeviceIDs.union(backgroundAuthorizedDeviceIDs)
        authorizedDeviceIDs = ids
        reconcileInitialWatchRetryState(previousAuthorization: previousAuthorization)
        failures.removeAll { failure in
            guard let deviceID = failure.deviceID else { return true }
            return !ids.contains { id in id.matchesHelperIdentifier(deviceID) }
        }
        if wasEnabled || isEnabled { updateLifecycle() }
    }

    func setBackgroundAuthorizedDeviceIDs(_ ids: Set<AppleDeviceID>) {
        guard !isStopped, backgroundAuthorizedDeviceIDs != ids else { return }
        let previousAuthorization = authorizedDeviceIDs.union(backgroundAuthorizedDeviceIDs)
        backgroundAuthorizedDeviceIDs = ids
        reconcileInitialWatchRetryState(previousAuthorization: previousAuthorization)
        updateLifecycle()
    }

    func revokeDeviceIDs(_ ids: Set<AppleDeviceID>) {
        guard !isStopped, !ids.isEmpty else { return }
        let identities = Set(ids.map(\.readIdentity))
        snapshots.removeAll { identities.contains($0.identity) }
        failures.removeAll { failure in
            guard let deviceID = failure.deviceID else { return false }
            return ids.contains { $0.matchesHelperIdentifier(deviceID) }
        }
        authorizedDeviceIDs.subtract(ids)
        backgroundAuthorizedDeviceIDs.subtract(ids)
        for id in ids { initialWatchRetryAttempts.removeValue(forKey: id) }
        updateLifecycle()
    }

    /// Gates the controller from central settings so disabling the opt-in also
    /// clears cached results when the Bluetooth view is not mounted. Re-enabling
    /// only resumes work when a visible surface still owns a claim.
    func setReadingEnabled(_ enabled: Bool) {
        guard !isStopped, isReadingEnabled != enabled else { return }
        isReadingEnabled = enabled
        guard enabled else {
            cancelActiveWork()
            expiryTask?.cancel()
            expiryTask = nil
            snapshots = []
            failures = []
            return
        }
        updateLifecycle()
    }

    func setBackgroundRefresh(enabled: Bool, interval: Duration) {
        guard !isStopped else { return }
        let interval = interval < .seconds(60) ? .seconds(60) : interval
        guard isBackgroundRefreshEnabled != enabled || backgroundRefreshInterval != interval else { return }
        isBackgroundRefreshEnabled = enabled
        backgroundRefreshInterval = interval
        nextFullRefreshDate = clock().addingTimeInterval(Self.timeInterval(for: configuredRefreshInterval))
        updateLifecycle()
    }

    func refresh() {
        guard !isStopped, isEnabled else { return }
        beginRead(superseding: true)
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        claims.removeAll()
        authorizedDeviceIDs.removeAll()
        isSurfaceVisible = false
        cancelActiveWork()
        expiryTask?.cancel()
        expiryTask = nil
        snapshots = []
        failures = []
        isRefreshing = false
    }

    private var isEnabled: Bool { isReadingEnabled && isSurfaceVisible && !claims.isEmpty && !authorizedDeviceIDs.isEmpty }

    private var hasReadDemand: Bool {
        isReadingEnabled && !effectiveReadIDs.isEmpty
            && ((isSurfaceVisible && !claims.isEmpty) || isBackgroundRefreshEnabled)
    }

    private var effectiveReadIDs: Set<AppleDeviceID> {
        isBackgroundRefreshEnabled
            ? authorizedDeviceIDs.union(backgroundAuthorizedDeviceIDs)
            : authorizedDeviceIDs
    }

    var backgroundReadDeviceIDs: Set<AppleDeviceID> {
        backgroundAuthorizedDeviceIDs
    }

    private func updateLifecycle() {
        if hasReadDemand {
            if readTask != nil, activeReadDemandIDs == effectiveReadIDs { return }
            beginRead(superseding: true)
        } else {
            cancelActiveWork()
        }
    }

    private func cancelActiveWork() {
        generation &+= 1
        readTask?.cancel()
        readTask = nil
        activeReadDemandIDs = []
        isRefreshing = false
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func beginRead(superseding: Bool, selectedIDs requestedIDs: Set<AppleDeviceID>? = nil) {
        guard !isStopped, hasReadDemand else { return }
        if superseding {
            generation &+= 1
            readTask?.cancel()
            readTask = nil
            refreshTask?.cancel()
            refreshTask = nil
        } else if readTask != nil {
            return
        }

        let readGeneration = generation
        let reader = self.reader
        let selectedIDs = requestedIDs ?? effectiveReadIDs
        guard !selectedIDs.isEmpty else { return }
        activeReadDemandIDs = effectiveReadIDs
        isRefreshing = true
        readTask = Task { [weak self, reader] in
            do {
                let result = try await reader.read(selectedIDs: selectedIDs)
                guard !Task.isCancelled else { return }
                self?.finishRead(result, requestedIDs: selectedIDs, generation: readGeneration)
            } catch {
                guard !Task.isCancelled else { return }
                self?.finishRead(
                    MobileBatteryReadResult(failures: [MobileBatteryReadFailure(category: "read-failed", deviceID: nil)]),
                    requestedIDs: selectedIDs,
                    generation: readGeneration
                )
            }
        }
    }

    private func finishRead(
        _ result: MobileBatteryReadResult,
        requestedIDs: Set<AppleDeviceID>,
        generation readGeneration: UInt64
    ) {
        guard !isStopped, readGeneration == generation, hasReadDemand else { return }
        let acceptedReadIDs = requestedIDs.intersection(effectiveReadIDs)
        let requestedIdentities = Set(acceptedReadIDs.map(\.readIdentity))
        let snapshots = result.snapshots.filter { requestedIdentities.contains($0.identity) }
        readTask = nil
        activeReadDemandIDs = []
        isRefreshing = false
        failures = result.failures.filter { failure in
            guard let deviceID = failure.deviceID else { return false }
            return acceptedReadIDs.contains { $0.matchesHelperIdentifier(deviceID) }
        }

        if !snapshots.isEmpty {
            var byIdentity = Dictionary(uniqueKeysWithValues: self.snapshots.map { ($0.identity, $0) })
            for snapshot in snapshots {
                byIdentity[snapshot.identity] = snapshot
            }
            self.snapshots = byIdentity.values.sorted { $0.identity < $1.identity }
        }
        for snapshot in snapshots {
            guard let parentID = snapshot.parentID else { continue }
            let id = AppleDeviceID.trustedWatch(parentID: parentID, id: snapshot.id)
            initialWatchRetryAttempts.removeValue(forKey: id)
        }
        pruneExpiredSnapshots()
        scheduleExpiry()
        if requestedIDs == effectiveReadIDs {
            nextFullRefreshDate = clock().addingTimeInterval(Self.timeInterval(for: configuredRefreshInterval))
        }
        scheduleNextRefresh(generation: readGeneration)
    }

    private func scheduleNextRefresh(generation readGeneration: UInt64) {
        guard !isStopped, readGeneration == generation, hasReadDemand else { return }
        let sleep = self.sleep
        pruneExpiredSnapshots()
        let missingWatches = missingAuthorizedWatchesNeedingRetry
        let configuredInterval = configuredRefreshInterval
        let fullRefreshDate = nextFullRefreshDate ?? clock().addingTimeInterval(Self.timeInterval(for: configuredInterval))
        let remainingFullRefresh = max(0, fullRefreshDate.timeIntervalSince(clock()))
        let retryInterval = Self.timeInterval(for: Self.initialWatchRetryInterval)
        let fullRefreshIsNext = missingWatches.isEmpty || remainingFullRefresh <= retryInterval
        let interval = fullRefreshIsNext
            ? .milliseconds(Int64(ceil(remainingFullRefresh * 1_000)))
            : Self.initialWatchRetryInterval
        refreshTask = Task { [weak self, sleep, interval, fullRefreshIsNext] in
            do { try await sleep(interval) }
            catch { return }
            guard !Task.isCancelled else { return }
            guard let self, self.generation == readGeneration, self.hasReadDemand else { return }
            self.refreshTask = nil
            if !fullRefreshIsNext {
                let retryIDs = self.missingAuthorizedWatchesNeedingRetry
                guard !retryIDs.isEmpty else {
                    self.beginRead(superseding: false)
                    return
                }
                for id in retryIDs {
                    self.initialWatchRetryAttempts[id, default: 0] += 1
                }
                self.beginRead(superseding: false, selectedIDs: retryIDs)
            } else {
                self.beginRead(superseding: false)
            }
        }
    }

    private var configuredRefreshInterval: Duration {
        isBackgroundRefreshEnabled ? backgroundRefreshInterval : Self.refreshInterval
    }

    private static func timeInterval(for duration: Duration) -> TimeInterval {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private var missingAuthorizedWatchesNeedingRetry: Set<AppleDeviceID> {
        let cachedWatchIdentities = Set(snapshots.map(\.identity))
        return Set(effectiveReadIDs.filter { id in
            guard case .trustedWatch = id,
                  !cachedWatchIdentities.contains(id.readIdentity),
                  (initialWatchRetryAttempts[id] ?? 0) < Self.maximumInitialWatchRetries else { return false }
            return true
        })
    }

    private func reconcileInitialWatchRetryState(previousAuthorization: Set<AppleDeviceID>) {
        let currentAuthorization = authorizedDeviceIDs.union(backgroundAuthorizedDeviceIDs)
        initialWatchRetryAttempts = initialWatchRetryAttempts.filter { currentAuthorization.contains($0.key) }
        for id in currentAuthorization.subtracting(previousAuthorization) {
            guard case .trustedWatch = id else { continue }
            initialWatchRetryAttempts.removeValue(forKey: id)
        }
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        guard let nextExpiry = snapshots.map({ $0.observedAt.addingTimeInterval(Self.cacheLifetime) }).min() else { return }

        let delay = max(0, nextExpiry.timeIntervalSince(clock()))
        let sleep = self.sleep
        expiryTask = Task { [weak self, sleep] in
            do { try await sleep(.seconds(delay)) }
            catch { return }
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.expiryTask = nil
            self.pruneExpiredSnapshots()
            self.scheduleExpiry()
        }
    }

    private func pruneExpiredSnapshots() {
        let now = clock()
        let fresh = snapshots.filter { now < $0.observedAt.addingTimeInterval(Self.cacheLifetime) }
        if fresh.count != snapshots.count { snapshots = fresh }
    }

}

private extension AppleDeviceID {
    var readIdentity: String {
        switch self {
        case let .trustedDevice(id): "phone:\(id)"
        case let .trustedWatch(parentID, id): "watch:\(parentID):\(id)"
        case .ble: ""
        }
    }

    func matchesHelperIdentifier(_ identifier: String) -> Bool {
        switch self {
        case let .trustedDevice(id): id == identifier
        case let .trustedWatch(_, id): id == identifier
        case .ble: false
        }
    }
}
