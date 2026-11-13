import Combine
import Foundation
import OSLog

private let appleDeviceDiscoveryLogger = Logger(
    subsystem: "com.lingsmbp.StatusTrio",
    category: "apple-device-discovery"
)

/// One discovery cycle, reduced to counts. Routine diagnostics carry no device
/// identifiers, so a Watch that never appears is still diagnosable from a log.
struct AppleDeviceDiscoveryDiagnostics: Equatable, Sendable {
    let candidateCount: Int
    let watchCandidateCount: Int
    let verifiedCandidateCount: Int
    let rejectedWatchCount: Int
    let rejectedOtherCount: Int
    let failureCategory: String?
    let routeDiagnostics: MobileBatteryDiscoveryRouteDiagnostics?

    static func make(
        from values: [AppleDeviceCandidate],
        failureCategory: String? = nil,
        routeDiagnostics: MobileBatteryDiscoveryRouteDiagnostics? = nil
    ) -> Self {
        var watchCandidateCount = 0
        var verifiedCandidateCount = 0
        var rejectedWatchCount = 0
        var rejectedOtherCount = 0
        for candidate in values {
            let isWatch: Bool
            if case .trustedWatch = candidate.id { isWatch = true; watchCandidateCount += 1 }
            else { isWatch = false }
            if candidate.isVerifiedTrustedAppleDevice {
                verifiedCandidateCount += 1
            } else if isWatch {
                rejectedWatchCount += 1
            } else {
                rejectedOtherCount += 1
            }
        }
        return Self(
            candidateCount: values.count,
            watchCandidateCount: watchCandidateCount,
            verifiedCandidateCount: verifiedCandidateCount,
            rejectedWatchCount: rejectedWatchCount,
            rejectedOtherCount: rejectedOtherCount,
            failureCategory: failureCategory ?? routeDiagnostics.flatMap { routes in
                routes.failureCategories.isEmpty ? nil
                    : routes.failureCategories.map(\.rawValue).sorted().joined(separator: ",")
            },
            routeDiagnostics: routeDiagnostics
        )
    }
}

@MainActor
final class AppleDeviceDiscoveryController: ObservableObject {
    @Published private(set) var candidates: [AppleDeviceCandidate] = []
    @Published private(set) var isDiscovering = false
    @Published private(set) var discoveryGeneration: UInt64 = 0
    /// The last completed discovery cycle. Read-only; a future Settings row can
    /// use it to explain why an Apple Watch row is missing.
    @Published private(set) var discoveryDiagnostics: AppleDeviceDiscoveryDiagnostics?
    /// IDs returned by the last cycle that actually completed. `nil` until one
    /// has: a failed or still-running cycle must not make an empty list look like
    /// "these devices are gone".
    @Published private(set) var lastSuccessfulCandidateIDs: Set<AppleDeviceID>?

    private let reader: any MobileBatteryReading
    private var claims: Set<String> = []
    private var isEnabled = false
    private var refreshInterval: Duration = .seconds(60)
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var lastLoggedDiagnostics: AppleDeviceDiscoveryDiagnostics?

    init(reader: any MobileBatteryReading = MobileBatteryHelperReader()) {
        self.reader = reader
    }

    deinit {
        task?.cancel()
        refreshTask?.cancel()
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        if !enabled { stopDiscovery(clearCandidates: true) }
        else { updateLifecycle() }
    }

    func setRefreshInterval(_ interval: Duration) {
        guard refreshInterval != interval else { return }
        refreshInterval = interval
        if isActive { scheduleRefresh() }
    }

    func request(_ token: String) {
        guard !token.isEmpty else { return }
        let wasActive = isActive
        claims.insert(token)
        if !wasActive { updateLifecycle() }
    }

    func release(_ token: String) {
        guard claims.remove(token) != nil else { return }
        if claims.isEmpty { stopDiscovery(clearCandidates: false) }
    }

    func refresh() {
        guard isActive else { return }
        startDiscovery()
    }

    func stop() {
        claims.removeAll()
        isEnabled = false
        stopDiscovery(clearCandidates: true)
    }

    private var isActive: Bool { isEnabled && !claims.isEmpty }

    private func updateLifecycle() {
        if isActive { startDiscovery() }
        else { stopDiscovery(clearCandidates: false) }
    }

    private func startDiscovery() {
        guard isActive else { return }
        refreshTask?.cancel()
        refreshTask = nil
        generation &+= 1
        let currentGeneration = generation
        discoveryGeneration = currentGeneration
        candidates = []
        task?.cancel()
        isDiscovering = true
        let reader = self.reader
        task = Task { [weak self, reader] in
            do {
                let result = try await reader.discoverWithDiagnostics()
                guard !Task.isCancelled else { return }
                self?.finish(result.candidates, generation: currentGeneration, routeDiagnostics: result.routeDiagnostics)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError),
                      (error as? MobileBatteryHelperError) != .cancelled else { return }
                self?.finish(
                    [],
                    generation: currentGeneration,
                    failureCategory: Self.failureCategory(for: error)
                )
            }
        }
    }

    private func finish(
        _ values: [AppleDeviceCandidate],
        generation currentGeneration: UInt64,
        failureCategory: String? = nil,
        routeDiagnostics: MobileBatteryDiscoveryRouteDiagnostics? = nil
    ) {
        guard generation == currentGeneration, isActive else { return }
        let sorted = values.sorted { $0.id.rowID < $1.id.rowID }
        candidates = sorted
        isDiscovering = false
        task = nil
        // Only a cycle that finished without any failure is evidence about which
        // devices exist. A failed or partially failed cycle leaves the previous
        // answer in place: a device that lived only on the failed route must not
        // look absent.
        if failureCategory == nil, (routeDiagnostics?.failedRouteCount ?? 0) == 0 {
            lastSuccessfulCandidateIDs = Set(sorted.map(\.id))
        }
        let diagnostics = AppleDeviceDiscoveryDiagnostics.make(
            from: sorted,
            failureCategory: failureCategory,
            routeDiagnostics: routeDiagnostics
        )
        discoveryDiagnostics = diagnostics
        logIfChanged(diagnostics, candidates: sorted)
        if isActive {
            scheduleRefresh()
        }
    }

    /// A bounded, identifier-free category so a missing Watch row can be
    /// traced to a failed helper or a malformed payload.
    private static func failureCategory(for error: any Error) -> String {
        if error is DecodingError { return "invalid-envelope" }
        if let helperError = error as? MobileBatteryHelperError {
            return switch helperError {
            case .unavailable: "helper-unavailable"
            case .timedOut: "helper-timeout"
            case .cancelled: "cancelled"
            case .processFailed: "helper-failed"
            case .outputTooLarge: "helper-output-too-large"
            case .cycleTimedOut: "cycle-timeout"
            }
        }
        if let wireError = error as? MobileBatteryWireError {
            return switch wireError {
            case .invalidEnvelope: "invalid-envelope"
            case .unsupportedSchema: "unsupported-schema"
            }
        }
        return "discovery-failed"
    }

    /// Log one summary per changed cycle, plus one line per candidate shape.
    /// The owner is this controller's discovery lifecycle, so logging stops when
    /// discovery stops. Nothing here carries a device identifier.
    private func logIfChanged(
        _ diagnostics: AppleDeviceDiscoveryDiagnostics,
        candidates: [AppleDeviceCandidate]
    ) {
        guard lastLoggedDiagnostics != diagnostics else { return }
        lastLoggedDiagnostics = diagnostics
        let failure = diagnostics.failureCategory ?? "none"
        let routeSummary: String
        if let routes = diagnostics.routeDiagnostics {
            let outcome = routes.failedRouteCount > 0 && routes.failedRouteCount == routes.attemptedRouteCount
                ? "all-routes-failed"
                : routes.failedRouteCount > 0 ? "partial-failure"
                : diagnostics.candidateCount == 0 ? "empty" : "success"
            routeSummary = "attempted=\(routes.attemptedRouteCount) failed=\(routes.failedRouteCount) outcome=\(outcome)"
        } else {
            routeSummary = "routes=not-reported"
        }
        appleDeviceDiscoveryLogger.info(
            "discovery candidates=\(diagnostics.candidateCount, privacy: .public) watches=\(diagnostics.watchCandidateCount, privacy: .public) verified=\(diagnostics.verifiedCandidateCount, privacy: .public) rejectedWatches=\(diagnostics.rejectedWatchCount, privacy: .public) rejectedOthers=\(diagnostics.rejectedOtherCount, privacy: .public) failure=\(failure, privacy: .public) \(routeSummary, privacy: .public)"
        )
        for candidate in candidates {
            let transport = candidate.transports.map(\.rawValue).joined(separator: ",")
            let reason = candidate.trustRequired ? "trust-required"
                : !candidate.transports.contains(.usb) && !candidate.transports.contains(.network)
                    ? "no-trusted-transport"
                    : candidate.isVerifiedTrustedAppleDevice ? "verified" : "unsupported-evidence-or-model"
            appleDeviceDiscoveryLogger.debug(
                "candidate kind=\(Self.kind(of: candidate.id), privacy: .public) transport=\(transport, privacy: .public) evidence=\(candidate.evidence.rawValue, privacy: .public) eligibility=\(reason, privacy: .public)"
            )
        }
    }

    private static func kind(of id: AppleDeviceID) -> String {
        return switch id {
        case .ble: "ble"
        case .trustedDevice: "phone"
        case .trustedWatch: "watch"
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshTask = Task { [weak self] in
            do {
                guard let interval = self?.refreshInterval else { return }
                try await Task.sleep(for: interval)
            }
            catch { return }
            guard !Task.isCancelled else { return }
            guard let self, self.isActive else { return }
            self.refresh()
        }
    }

    private func stopDiscovery(clearCandidates: Bool) {
        generation &+= 1
        discoveryGeneration = generation
        task?.cancel()
        task = nil
        refreshTask?.cancel()
        refreshTask = nil
        isDiscovering = false
        if clearCandidates {
            candidates = []
            // No cycle has completed for this new active period yet. Keeping an
            // old answer would make the first frames treat "not discovered yet"
            // as "gone" and hide rows until the first cycle lands.
            lastSuccessfulCandidateIDs = nil
            discoveryDiagnostics = nil
            lastLoggedDiagnostics = nil
        }
    }
}
