import Combine
import Foundation
import OSLog
import PowerHelperProtocol
import ServiceManagement
import SwiftUI

/// Every power-helper decision worth explaining after the fact. The app runs as
/// a menu bar app, so `NSLog` only reaches a terminal that launched it; the
/// unified log is the only channel a user-facing report can be checked against.
private let powerHelperLogger = Logger(
    subsystem: "com.lingsmbp.StatusTrio",
    category: "powerHelper"
)

/// The privileged power helper's registration as reported by the system.
enum PrivilegedHelperStatus: Equatable, Sendable {
    /// Not registered, so launchd will not start the daemon.
    ///
    /// macOS reports an app that has never registered as `notRegistered` on
    /// some versions and `notFound` on others, so both collapse into this case.
    case notRegistered
    /// Registered, but an administrator must approve it in Login Items before
    /// launchd will bootstrap the daemon.
    case requiresApproval
    /// Approved; the daemon starts on demand when the app connects.
    case enabled
}

/// Abstracts `SMAppService.daemon` so the manager can be exercised with a fake.
@MainActor
protocol PrivilegedHelperServicing: AnyObject {
    /// False when the helper cannot run here: not an app bundle, the build
    /// excluded the helper, or the daemon binary is missing.
    var isSupported: Bool { get }
    var status: PrivilegedHelperStatus { get }
    func register() throws
    func unregisterForRecovery() async throws
    func verifyConnection() async throws
    func openLoginItemsSettings()
}

@MainActor
final class SystemPrivilegedHelperService: PrivilegedHelperServicing {
    private var service: SMAppService {
        SMAppService.daemon(plistName: PowerHelperConstants.launchDaemonPlistName)
    }

    /// The daemon must be present in the bundle for registration to mean
    /// anything, and this process must carry the identity that daemon accepts:
    /// an Ad-hoc build has no team, and a worktree build with a rewritten
    /// `BUNDLE_ID` fails the requirement's `identifier` clause. Both would
    /// register a helper whose every connection is rejected, so neither may
    /// offer the toggle.
    var isSupported: Bool {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return false }
        guard AppMetadata.includesPrivilegedHelper else { return false }
        guard FileManager.default.isExecutableFile(atPath: Self.daemonURL.path) else { return false }
        guard let identity = AppSigningIdentity.current() else { return false }
        return identity.bundleIdentifier == PowerHelperConstants.clientBundleIdentifier
            && identity.teamIdentifier == PowerHelperConstants.clientTeamIdentifier
    }

    private static var daemonURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/StatusTrioPowerHelper", isDirectory: false)
    }

    var status: PrivilegedHelperStatus {
        Self.status(for: service.status)
    }

    /// `SMAppService` answers `notFound` for a daemon that has never been
    /// registered, which is the same situation as `notRegistered` for our UI.
    /// Registering still works from that state, so it must not disable the toggle.
    static func status(for status: SMAppService.Status) -> PrivilegedHelperStatus {
        switch status {
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notRegistered, .notFound:
            .notRegistered
        @unknown default:
            .notRegistered
        }
    }

    func register() throws {
        try service.register()
    }

    func unregisterForRecovery() async throws {
        try await service.unregister()
    }

    func verifyConnection() async throws {
        _ = try await XPCPrivilegedHelperClient().readLowPowerMode()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Separates the feature opt-in from the helper's registration and approval.
///
/// Registering a LaunchDaemon does not start it: launchd only bootstraps the
/// daemon once an administrator approves it and the app first connects. So the
/// first opt-in requests registration. Opting out stops requests and leaves the
/// registration intact, so the daemon idle-exits without invalidating approval.
/// System Settings owns background authorization independently of this switch.
@MainActor
final class PrivilegedHelperManager: ObservableObject, PrivilegedHelperServicingFacade {
    static let shared = PrivilegedHelperManager()

    @Published private(set) var status: PrivilegedHelperStatus
    @Published private(set) var didFailLastOperation = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isHelperResponsive = false
    @Published private(set) var registrationNeedsApproval = false

    private let service: PrivilegedHelperServicing

    /// Whether the user wants Low Power Mode control. Seeded from the system
    /// state so a registration that an earlier session left waiting for approval
    /// is still shown as on.
    @Published private(set) var isEnabled: Bool

    /// How often the system state is re-read while a registration is pending.
    private let pollInterval: Duration
    /// How often a pending-but-reachable helper is re-probed. Every probe
    /// starts the root daemon, which then idle-exits about five seconds later,
    /// so this interval is a direct process-churn cost on a machine whose
    /// native status stays pending. Activation still probes immediately, and a
    /// revoked grant surfaces as an error on the next real operation, so the
    /// timer only needs to keep the status line from going stale for long.
    private let healthCheckInterval: Duration
    /// How often a helper the system reports as enabled is re-probed. Long
    /// enough that the daemon's idle-exit cycle is not restarted for a healthy
    /// helper, short enough that a crashed one surfaces within a session.
    private let enabledHealthCheckInterval: Duration
    private var nextPendingHealthCheck: ContinuousClock.Instant?
    /// Due time for the low-frequency re-probe of a helper the system already
    /// reports as enabled.
    ///
    /// Without one, a single successful verification was the last thing the app
    /// ever learned: a helper that crashed afterwards stayed "ready" until the
    /// user touched the switch, and its `recoveryAttempts` budget was never
    /// exercised again.
    private var nextEnabledHealthCheck: ContinuousClock.Instant?
    /// Offsets used to re-probe after a user-initiated read fails. See
    /// `defaultPendingProbeBackoff`.
    private let pendingProbeBackoff: [Duration]
    private var pendingProbeAttempts = 0
    private var pollTask: Task<Void, Never>?
    private var verificationTask: Task<Void, Never>?
    private var registrationRetryTask: Task<Void, Never>?
    private var registrationRetryGeneration: UInt64 = 0
    private var provisionalRegistrationError: String?
    private var generation: UInt64 = 0
    private var recoveryAttempts = 0
    private var recoveringGeneration: UInt64?
    private static let maximumRecoveryAttempts = 2
    /// Kept well above the daemon's idle-exit window: every pending health
    /// check starts the root daemon again, so a machine whose native status
    /// stays pending would spawn it continuously at a tighter cadence.
    static let defaultPendingHealthCheckInterval: Duration = .seconds(60)
    /// Re-probe cadence for a helper the system reports as enabled.
    static let defaultEnabledHealthCheckInterval: Duration = .seconds(300)
    /// Extra probes after a user-initiated read fails while the native status
    /// is still pending.
    ///
    /// Switching the helper off and on in System Settings leaves the native
    /// status pending the whole time, so the app cannot see the switch move.
    /// The forced probe that runs when the user comes back can land inside that
    /// transition and fail; waiting out the full health-check interval then
    /// makes the same gesture look like it randomly works. These offsets let
    /// the status line settle within seconds of the user returning, and the
    /// list is bounded so a machine that never grants approval still falls
    /// back onto the steady one-per-minute cadence after three extra daemon
    /// starts instead of churning.
    static let defaultPendingProbeBackoff: [Duration] = [
        .seconds(3), .seconds(10), .seconds(25),
    ]

    init(
        service: PrivilegedHelperServicing = SystemPrivilegedHelperService(),
        pollInterval: Duration = .seconds(2),
        healthCheckInterval: Duration = PrivilegedHelperManager.defaultPendingHealthCheckInterval,
        enabledHealthCheckInterval: Duration = PrivilegedHelperManager.defaultEnabledHealthCheckInterval,
        pendingProbeBackoff: [Duration] = PrivilegedHelperManager.defaultPendingProbeBackoff
    ) {
        self.service = service
        let initialStatus = service.status
        self.status = initialStatus
        self.isEnabled = initialStatus != .notRegistered
        self.pollInterval = pollInterval
        self.healthCheckInterval = healthCheckInterval
        self.enabledHealthCheckInterval = enabledHealthCheckInterval
        self.pendingProbeBackoff = pendingProbeBackoff
        // A previous session may have quit while the registration was still
        // waiting for approval, so start watching for the system to accept it.
        updateStatusPolling()
        checkHelperIfNeeded()
    }

    /// True while the system is waiting for the user to approve the helper.
    var requiresApproval: Bool {
        isEnabled && (status == .requiresApproval || registrationNeedsApproval)
    }

    /// Actual usability, independent of the native approval report. On some
    /// systems the report remains pending even after launchd permits XPC.
    /// A successful read is evidence of availability, not a rewritten approval.
    var isReady: Bool {
        isEnabled && status != .notRegistered && isHelperResponsive
    }

    /// False when this build or process cannot offer the helper at all.
    var isAvailable: Bool {
        service.isSupported
    }

    var presentation: PrivilegedHelperPresentation {
        Self.presentation(
            isAvailable: isAvailable,
            status: status,
            isEnabled: isEnabled,
            registrationNeedsApproval: registrationNeedsApproval,
            isHelperResponsive: isHelperResponsive,
            didFailLastOperation: didFailLastOperation,
            lastErrorMessage: lastErrorMessage
        )
    }

    var presentationPublisher: AnyPublisher<PrivilegedHelperPresentation, Never> {
        let isAvailable = isAvailable
        return $status.combineLatest(
            $isEnabled,
            $registrationNeedsApproval,
            $isHelperResponsive
        )
        .combineLatest($didFailLastOperation, $lastErrorMessage)
        .map {
            readiness,
            didFailLastOperation,
            lastErrorMessage in
            let (
                status,
                isEnabled,
                registrationNeedsApproval,
                isHelperResponsive
            ) = readiness
            return Self.presentation(
                isAvailable: isAvailable,
                status: status,
                isEnabled: isEnabled,
                registrationNeedsApproval: registrationNeedsApproval,
                isHelperResponsive: isHelperResponsive,
                didFailLastOperation: didFailLastOperation,
                lastErrorMessage: lastErrorMessage
            )
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }

    /// Builds a presentation entirely from the values delivered by the
    /// publisher. Reading `@Published` properties inside the sink would observe
    /// their pre-assignment value because publication happens in `willSet`.
    private static func presentation(
        isAvailable: Bool,
        status: PrivilegedHelperStatus,
        isEnabled: Bool,
        registrationNeedsApproval: Bool,
        isHelperResponsive: Bool,
        didFailLastOperation: Bool,
        lastErrorMessage: String?
    ) -> PrivilegedHelperPresentation {
        PrivilegedHelperPresentation(
            availability: isAvailable
                ? .available
                : .unsupported(reason: "The privileged power helper is unavailable in this build."),
            isEnabled: isEnabled,
            requiresApproval: isEnabled
                && (status == .requiresApproval || registrationNeedsApproval),
            isReady: isEnabled
                && status != .notRegistered
                && isHelperResponsive,
            didFailLastOperation: didFailLastOperation,
            lastErrorMessage: lastErrorMessage
        )
    }

    var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.isEnabled },
            set: { self.setEnabled($0) }
        )
    }

    func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        invalidateVerification()
        cancelRegistrationRetry()
        recoveryAttempts = 0
        registrationNeedsApproval = false
        provisionalRegistrationError = nil
        publishSystemState()
        didFailLastOperation = false
        lastErrorMessage = nil
        isEnabled = enabled

        if enabled {
            registerIfNeeded()
        }

        publishSystemState()
        updateStatusPolling()
        // The switch the user just flipped, so a failed read may use the short
        // retry window.
        checkHelperIfNeeded(userInitiated: enabled)
        startRegistrationRetryWindow()
    }

    /// Restores intent; pending registration gets the same delayed retries.
    func restoreUserIntent(_ enabled: Bool) {
        if isEnabled != enabled { invalidateVerification() }
        isEnabled = enabled
        updateStatusPolling()
        checkHelperIfNeeded()
        if enabled { startRegistrationRetryWindow() } else { cancelRegistrationRetry() }
    }

    /// Activation and polling observe approval without changing registration.
    func refresh() {
        publishSystemState()
        updateStatusPolling()
        checkHelperIfNeeded(forceRead: pendingProbeIsDue() || enabledProbeIsDue())
    }

    /// Returning from approval can precede the system's permission update.
    /// Give it a bounded retry window without removing the pending service.
    func refreshAfterActivation() {
        refresh()
        // Returning from System Settings is a user action, so an extra probe
        // is worth one more daemon start even when the timer is not due.
        checkHelperIfNeeded(forceRead: true, userInitiated: true)
        startRegistrationRetryWindow()
    }

    /// Every probe of a pending helper starts the root daemon, which then
    /// idle-exits. Throttle them to one per health-check interval so a native
    /// status that never leaves `requiresApproval` cannot turn the two-second
    /// approval poll into a daemon restart loop.
    private func pendingProbeIsDue(
        now: ContinuousClock.Instant = ContinuousClock.now
    ) -> Bool {
        guard status == .requiresApproval else { return false }
        guard let due = nextPendingHealthCheck else { return true }
        return now >= due
    }

    private func enabledProbeIsDue(
        now: ContinuousClock.Instant = ContinuousClock.now
    ) -> Bool {
        guard status == .enabled else { return false }
        guard let due = nextEnabledHealthCheck else { return true }
        return now >= due
    }

    /// Pending approval or a usable helper retires a registration failure.
    /// An owned recovery's intermediate removal is ignored.
    private func publishSystemState() {
        guard recoveringGeneration != generation else { return }
        let observed = service.status
        if observed == .enabled {
            registrationNeedsApproval = false
            provisionalRegistrationError = nil
        }
        if observed != status {
            invalidateVerification()
            status = observed
            if observed == .enabled { checkHelperIfNeeded(forceRead: true) }
        }

        if didFailLastOperation,
           status == .requiresApproval || isReady {
            didFailLastOperation = false
            lastErrorMessage = nil
        }
    }

    /// A pending approval is an expected intermediate state, including when
    /// macOS reports EPERM from register(). Leave its registration intact.
    private func registerIfNeeded() {
        guard isEnabled, isAvailable, status != .enabled, !isReady else { return }
        do {
            try service.register()
        } catch {
            recordRegistrationError(error)
        }
    }

    private func recordRegistrationError(_ error: any Error) {
        let observed = service.status
        // EPERM may precede requiresApproval. Keep the native status intact,
        // but don't present the same approval denial as two different errors.
        let nsError = error as NSError
        // The exported domain constant requires macOS 15; its string also
        // identifies errors on the older macOS releases we support.
        let approvalDenied = nsError.domain == "SMAppServiceErrorDomain" && nsError.code == 1
        if observed == .requiresApproval || (observed == .notRegistered && approvalDenied) {
            registrationNeedsApproval = true
            provisionalRegistrationError = observed == .notRegistered ? error.localizedDescription : nil
            didFailLastOperation = false
            lastErrorMessage = nil
            return
        }
        registrationNeedsApproval = false
        provisionalRegistrationError = nil
        didFailLastOperation = true
        lastErrorMessage = error.localizedDescription
    }

    private func cancelRegistrationRetry() {
        registrationRetryGeneration &+= 1
        registrationRetryTask?.cancel()
        registrationRetryTask = nil
    }

    /// Retry only register(), at 2, 6, 14, 30 and 60 seconds by default.
    /// Polling stays read-only; a new user interaction may start another window.
    private func startRegistrationRetryWindow() {
        guard isAvailable, isEnabled, status != .enabled, !isReady,
              registrationRetryTask == nil else { return }
        let retryGeneration = registrationRetryGeneration
        registrationRetryTask = Task { [weak self, pollInterval] in
            for multiplier in [1, 2, 4, 8, 15] {
                do { try await Task.sleep(for: pollInterval * multiplier) }
                catch { return }
                guard !Task.isCancelled, let self,
                      self.registrationRetryGeneration == retryGeneration else { return }
                self.refresh()
                guard self.isEnabled, self.isAvailable else { break }
                if self.status == .enabled || self.isReady { break }
                self.registerIfNeeded()
                self.refresh()
                if self.status == .enabled || self.isReady { break }
            }
            guard let self, self.registrationRetryGeneration == retryGeneration else { return }
            self.registrationRetryTask = nil
            // EPERM alone is not proof of pending consent. If the service
            // never registered, retire the provisional hint and expose why.
            if self.isEnabled, self.status == .notRegistered,
               let error = self.provisionalRegistrationError {
                self.registrationNeedsApproval = false
                self.provisionalRegistrationError = nil
                self.didFailLastOperation = true
                self.lastErrorMessage = error
            }
        }
    }

    private func invalidateVerification() {
        generation &+= 1
        verificationTask?.cancel()
        verificationTask = nil
        isHelperResponsive = false
        nextPendingHealthCheck = nil
        nextEnabledHealthCheck = nil
        pendingProbeAttempts = 0
    }

    /// Delay before the next pending probe after a failed read.
    ///
    /// A user-initiated failure burns one offset, so the status line can catch
    /// up with the switch the user just flipped instead of waiting out the
    /// whole health-check interval. The reads that follow an offset are
    /// ordinary scheduled probes and use the steady interval once the window is
    /// spent, which is what keeps a permanently pending helper from churning.
    private func pendingProbeDelayAfterFailure(userInitiated: Bool) -> Duration {
        guard userInitiated, pendingProbeAttempts < pendingProbeBackoff.count else {
            pendingProbeAttempts = 0
            return healthCheckInterval
        }
        defer { pendingProbeAttempts += 1 }
        return pendingProbeBackoff[pendingProbeAttempts]
    }

    /// Probe registered helpers even while native approval lags. Only a failed
    /// read with native approval enabled can trigger registration recovery;
    /// pending failures are expected and never unregister the service.
    ///
    /// A pending probe is throttled rather than tied to "not responsive yet":
    /// on a machine that never grants background approval the read keeps
    /// failing, and an unthrottled retry would start the root daemon on every
    /// two-second approval poll. A read the user's own action asked for is the
    /// exception: if it fails, one bounded short window re-probes, because the
    /// System Settings off-and-on flip is invisible in the native status and
    /// would otherwise look like it randomly failed. Each new user action
    /// opens its own window; the scheduled probes in between never do.
    private func checkHelperIfNeeded(forceRead: Bool = false, userInitiated: Bool = false) {
        guard isEnabled, isAvailable, status != .notRegistered,
              verificationTask == nil else { return }
        switch status {
        case .enabled:
            guard forceRead || !isHelperResponsive,
                  forceRead || recoveryAttempts < Self.maximumRecoveryAttempts else { return }
        case .requiresApproval:
            guard forceRead || (!isHelperResponsive && pendingProbeIsDue()) else { return }
        case .notRegistered:
            return
        }
        let requestGeneration = generation
        if userInitiated { pendingProbeAttempts = 0 }
        verificationTask = Task { [weak self] in
            guard let self, !Task.isCancelled, self.isEnabled,
                  self.generation == requestGeneration else { return }
            defer {
                if self.recoveringGeneration == requestGeneration {
                    self.recoveringGeneration = nil
                }
                if self.generation == requestGeneration { self.verificationTask = nil }
            }
            do {
                try await self.service.verifyConnection()
            } catch {
                guard !Task.isCancelled, self.generation == requestGeneration,
                      self.isEnabled else { return }
                let wasResponsive = self.isHelperResponsive
                self.isHelperResponsive = false
                // A pending helper that cannot be read is expected on a machine
                // that never grants background approval. Schedule the next
                // probe rather than clearing the due time, which would make the
                // two-second approval poll retry immediately and forever.
                let observed = self.service.status
                if observed == .requiresApproval {
                    let delay = self.pendingProbeDelayAfterFailure(userInitiated: userInitiated)
                    self.nextPendingHealthCheck = ContinuousClock.now.advanced(by: delay)
                    // Log the transitions a user could have caused: a read
                    // that used to work, or one the user just triggered.
                    // Logging every failure would repeat once a minute forever
                    // on a machine that simply never grants approval.
                    if userInitiated || wasResponsive {
                        powerHelperLogger.notice(
                            "pending probe failed (\(userInitiated ? "user-initiated" : "scheduled", privacy: .public), retry in \(String(describing: delay), privacy: .public)): \(error.localizedDescription, privacy: .public)"
                        )
                    }
                } else {
                    self.nextPendingHealthCheck = nil
                    self.pendingProbeAttempts = 0
                    // Throttle the retry of an enabled helper to the same
                    // cadence: the recovery above is capped, and after the cap
                    // every poll would otherwise read-fail and re-register.
                    self.nextEnabledHealthCheck = ContinuousClock.now
                        .advanced(by: self.enabledHealthCheckInterval)
                }
                guard observed == .enabled else { return }
                guard self.recoveryAttempts < Self.maximumRecoveryAttempts else {
                    self.recordRegistrationError(error)
                    return
                }
                self.recoveryAttempts += 1
                powerHelperLogger.error(
                    "recovery \(self.recoveryAttempts)/\(Self.maximumRecoveryAttempts) after failed XPC read: \(error.localizedDescription, privacy: .public)"
                )
                do {
                    // Await completion before registering again. A synchronous
                    // unregister may still be removing the job when it returns.
                    self.recoveringGeneration = requestGeneration
                    try await self.service.unregisterForRecovery()
                    guard !Task.isCancelled, self.generation == requestGeneration,
                          self.isEnabled else { return }
                    try self.service.register()
                    self.recoveringGeneration = nil
                    guard self.service.status == .enabled else {
                        self.publishSystemState()
                        self.startRegistrationRetryWindow()
                        return
                    }
                    try await self.service.verifyConnection()
                } catch {
                    guard !Task.isCancelled, self.generation == requestGeneration else { return }
                    self.recoveringGeneration = nil
                    self.recordRegistrationError(error)
                    self.publishSystemState()
                    self.startRegistrationRetryWindow()
                    return
                }
            }
            guard !Task.isCancelled, self.generation == requestGeneration,
                  self.isEnabled, self.service.status != .notRegistered else { return }
            self.isHelperResponsive = true
            self.pendingProbeAttempts = 0
            // A completed round trip is proof the recovery budget can start
            // over; otherwise two unrelated transient failures would disable
            // recovery for the rest of the session.
            self.recoveryAttempts = 0
            if self.service.status == .requiresApproval {
                self.nextPendingHealthCheck = ContinuousClock.now.advanced(by: self.healthCheckInterval)
            } else {
                self.nextPendingHealthCheck = nil
            }
            if self.service.status == .enabled {
                self.nextEnabledHealthCheck = ContinuousClock.now
                    .advanced(by: self.enabledHealthCheckInterval)
            } else {
                self.nextEnabledHealthCheck = nil
            }
            self.cancelRegistrationRetry()
            powerHelperLogger.debug("helper verified by XPC")
            self.publishSystemState()
        }
    }

    /// Watches the system state while a registration is pending.
    ///
    /// The state the app waits for can only be reached from System Settings, and
    /// macOS posts no notification when it changes, so re-reading on a timer is
    /// the only way the settings pane catches up without the user having to
    /// touch the app's switch again. The poll is read-only on purpose.
    private func updateStatusPolling() {
        guard isAvailable, isEnabled else {
            pollTask?.cancel()
            pollTask = nil
            return
        }
        guard pollTask == nil else { return }

        pollTask = Task { [weak self, pollInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pollInterval)
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }

    func openLoginItemsSettings() {
        service.openLoginItemsSettings()
        cancelRegistrationRetry()
        startRegistrationRetryWindow()
    }
}
