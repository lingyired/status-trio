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
    private lazy var service = SMAppService.daemon(plistName: PowerHelperConstants.launchDaemonPlistName)

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
final class PrivilegedHelperManager: ObservableObject {
    static let shared = PrivilegedHelperManager()

    @Published private(set) var status: PrivilegedHelperStatus
    @Published private(set) var didFailLastOperation = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isHelperResponsive = false

    private let service: PrivilegedHelperServicing

    /// Whether the user wants Low Power Mode control. Seeded from the system
    /// state so a registration that an earlier session left waiting for approval
    /// is still shown as on.
    @Published private(set) var isEnabled: Bool

    /// Base delay for the bounded approval and registration retry window.
    private let pollInterval: Duration
    private var needsBackgroundRecovery = false
    private var remainingBackgroundProbes = 0
    private static let maximumBackgroundProbes = 5
    private let recoveryProbe = PassthroughSubject<Void, Never>()
    var recoveryProbePublisher: AnyPublisher<Void, Never> { recoveryProbe.eraseToAnyPublisher() }
    private var lastApprovalStatusRead: ContinuousClock.Instant?
    private var awaitsApprovalReturn = false
    private var healthCheckTask: Task<Void, Never>?
    /// How often a pending-but-reachable helper is re-probed. Every probe
    /// starts the root daemon, which then idle-exits about five seconds later,
    /// so this interval is a direct process-churn cost on a machine whose
    /// native status stays pending. Activation still probes immediately, and a
    /// revoked grant surfaces as an error on the next real operation, so the
    /// timer only needs to keep the status line from going stale for long.
    private let healthCheckInterval: Duration
    /// Probe cadence for an enabled helper with unfinished background work.
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
    /// At most one activation-driven status read per interval.
    private let activationStatusRefreshInterval: Duration
    private var pendingProbeAttempts = 0
    private var verificationTask: Task<Void, Never>?
    private var registrationRetryTask: Task<Void, Never>?
    private var registrationRetryMayRegister = false
    private var registrationRetryGeneration: UInt64 = 0
    private var registrationNeedsApproval = false
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
    /// Debounce for an activation-driven status re-read. Approval can only
    /// change while the app is in the background, so one read per interval is
    /// enough; rapid app switching shares the same read instead of re-querying.
    static let defaultActivationStatusRefreshInterval: Duration = .seconds(60)

    init(
        service: PrivilegedHelperServicing = SystemPrivilegedHelperService(),
        pollInterval: Duration = .seconds(2),
        healthCheckInterval: Duration = PrivilegedHelperManager.defaultPendingHealthCheckInterval,
        enabledHealthCheckInterval: Duration = PrivilegedHelperManager.defaultEnabledHealthCheckInterval,
        pendingProbeBackoff: [Duration] = PrivilegedHelperManager.defaultPendingProbeBackoff,
        activationStatusRefreshInterval: Duration = PrivilegedHelperManager.defaultActivationStatusRefreshInterval
    ) {
        self.service = service
        self.isAvailable = service.isSupported
        let initialStatus: PrivilegedHelperStatus = isAvailable ? service.status : .notRegistered
        self.status = initialStatus
        self.isEnabled = initialStatus != .notRegistered
        self.pollInterval = pollInterval
        self.healthCheckInterval = healthCheckInterval
        self.enabledHealthCheckInterval = enabledHealthCheckInterval
        self.pendingProbeBackoff = pendingProbeBackoff
        self.activationStatusRefreshInterval = activationStatusRefreshInterval
        // A previous session may have quit while the registration was still
        // waiting for approval, so start watching for the system to accept it.
        if initialStatus == .requiresApproval { startRegistrationRetryWindow(allowRegistration: false) }
        checkHelperIfNeeded(confirmStartupApproval: initialStatus == .requiresApproval)
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

    /// The running bundle and signing identity determine support once.
    let isAvailable: Bool

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

        if enabled { publishSystemState() }
        scheduleHealthCheck()
        // The switch the user just flipped, so a failed read may use the short
        // retry window.
        checkHelperIfNeeded(userInitiated: enabled)
        startRegistrationRetryWindow()
    }

    /// Restores intent; pending registration gets the same delayed retries.
    func restoreUserIntent(_ enabled: Bool) {
        if isEnabled != enabled { invalidateVerification() }
        isEnabled = enabled
        checkHelperIfNeeded()
        if enabled { startRegistrationRetryWindow() } else { cancelRegistrationRetry() }
        scheduleHealthCheck()
    }

    /// Lid-sleep cleanup can outlive the panel. Give each pending cleanup a
    /// bounded XPC retry window and stop it as soon as the cleanup resolves.
    func setBackgroundRecoveryNeeded(_ needed: Bool) {
        guard needsBackgroundRecovery != needed else { return }
        needsBackgroundRecovery = needed
        remainingBackgroundProbes = needed ? Self.maximumBackgroundProbes : 0
        if needed {
            let firstDeadline = ContinuousClock.now.advanced(by: healthCheckInterval)
            nextEnabledHealthCheck = min(nextEnabledHealthCheck ?? firstDeadline, firstDeadline)
            if !isReady { refreshForUse() }
        }
        scheduleHealthCheck()
    }

    func refresh() {
        guard isAvailable else { return }
        publishSystemState()
        checkHelperIfNeeded(forceRead: pendingProbeIsDue() || enabledProbeIsDue())
        scheduleHealthCheck()
    }

    func refreshForUse() {
        guard isAvailable, isEnabled, recoveringGeneration != generation else { return }
        if status == .notRegistered { publishSystemState() }
        checkHelperIfNeeded(forceRead: true)
    }

    func verifyForUse() async -> Bool {
        guard !Task.isCancelled else { return false }
        refreshForUse()
        await verificationTask?.value
        return !Task.isCancelled && isReady
    }

    func refreshForApprovalSettings() {
        guard isAvailable, isEnabled, recoveringGeneration != generation else { return }
        let now = ContinuousClock.now
        // The approval pane and return from Login Items may arrive together.
        if let lastApprovalStatusRead,
           now - lastApprovalStatusRead < .milliseconds(250) { return }
        lastApprovalStatusRead = now
        publishSystemState()
        checkHelperIfNeeded(forceRead: !isReady, userInitiated: !isReady)
    }

    /// Returning from approval can precede the system's permission update.
    /// Ordinary activations re-read once but share that read within
    /// `activationStatusRefreshInterval`, so switching apps cannot turn into a
    /// tight query loop.
    func refreshAfterActivation() {
        guard isAvailable, isEnabled, recoveringGeneration != generation else { return }
        let now = ContinuousClock.now
        if awaitsApprovalReturn {
            awaitsApprovalReturn = false
            lastApprovalStatusRead = now
            publishSystemState()
            checkHelperIfNeeded(forceRead: true, userInitiated: true)
            startRegistrationRetryWindow()
            return
        }
        if let lastApprovalStatusRead,
           now - lastApprovalStatusRead < activationStatusRefreshInterval { return }
        lastApprovalStatusRead = now
        publishSystemState()
        checkHelperIfNeeded(forceRead: !isReady, userInitiated: !isReady)
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
        publishSystemState(service.status)
    }

    private func publishSystemState(_ observed: PrivilegedHelperStatus) {
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

    private func recordRegistrationError(_ error: any Error, observed: PrivilegedHelperStatus? = nil) {
        let observed = observed ?? service.status
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
        registrationRetryMayRegister = false
    }

    /// Recheck approval at 2, 6, 14, 30 and 60 seconds by default. Startup
    /// observes only; explicit opt-in and recovery may also retry registration.
    private func startRegistrationRetryWindow(allowRegistration: Bool = true) {
        guard isAvailable, isEnabled, status != .enabled, !isReady else { return }
        registrationRetryMayRegister = registrationRetryMayRegister || allowRegistration
        guard registrationRetryTask == nil else { return }
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
                if self.registrationRetryMayRegister {
                    self.registerIfNeeded()
                    self.refresh()
                }
                if self.status == .enabled || self.isReady { break }
            }
            guard let self, self.registrationRetryGeneration == retryGeneration else { return }
            self.registrationRetryTask = nil
            self.registrationRetryMayRegister = false
            self.scheduleHealthCheck()
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
        healthCheckTask?.cancel()
        healthCheckTask = nil
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
    private func checkHelperIfNeeded(
        forceRead: Bool = false,
        userInitiated: Bool = false,
        confirmStartupApproval: Bool = false
    ) {
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
            var finalStatus = self.status
            defer {
                if self.recoveringGeneration == requestGeneration {
                    self.recoveringGeneration = nil
                }
                if self.generation == requestGeneration {
                    self.verificationTask = nil
                    self.scheduleHealthCheck()
                }
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
                if observed != self.status {
                    self.publishSystemState(observed)
                    self.scheduleHealthCheck()
                    return
                }
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
                    let interval = self.recoveryAttempts < Self.maximumRecoveryAttempts
                        ? self.pollInterval : self.enabledHealthCheckInterval
                    self.nextEnabledHealthCheck = ContinuousClock.now.advanced(by: interval)
                }
                guard observed == .enabled else { return }
                guard self.recoveryAttempts < Self.maximumRecoveryAttempts else {
                    self.recordRegistrationError(error, observed: observed)
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
                    finalStatus = self.service.status
                    guard finalStatus == .enabled else {
                        self.publishSystemState(finalStatus)
                        self.startRegistrationRetryWindow()
                        return
                    }
                    try await self.service.verifyConnection()
                } catch {
                    guard !Task.isCancelled, self.generation == requestGeneration else { return }
                    self.recoveringGeneration = nil
                    let observed = self.service.status
                    self.recordRegistrationError(error, observed: observed)
                    self.publishSystemState(observed)
                    self.startRegistrationRetryWindow()
                    return
                }
            }
            guard !Task.isCancelled, self.generation == requestGeneration, self.isEnabled else { return }
            // An older session may have left approval in progress. Check once
            // after the startup probe before retiring the observation window.
            if confirmStartupApproval {
                let observed = self.service.status
                if observed != finalStatus {
                    self.publishSystemState(observed)
                    self.scheduleHealthCheck()
                    return
                }
            }
            let wasResponsive = self.isHelperResponsive
            self.isHelperResponsive = true
            self.pendingProbeAttempts = 0
            // A completed round trip is proof the recovery budget can start
            // over; otherwise two unrelated transient failures would disable
            // recovery for the rest of the session.
            self.recoveryAttempts = 0
            if finalStatus == .requiresApproval {
                self.nextPendingHealthCheck = ContinuousClock.now.advanced(by: self.healthCheckInterval)
            } else {
                self.nextPendingHealthCheck = nil
            }
            if finalStatus == .enabled {
                let interval = self.needsBackgroundRecovery
                    ? min(self.healthCheckInterval, self.enabledHealthCheckInterval)
                    : self.enabledHealthCheckInterval
                self.nextEnabledHealthCheck = ContinuousClock.now.advanced(by: interval)
            } else {
                self.nextEnabledHealthCheck = nil
            }
            self.cancelRegistrationRetry()
            powerHelperLogger.debug("helper verified by XPC")
            if self.didFailLastOperation {
                self.didFailLastOperation = false
                self.lastErrorMessage = nil
            }
            // A cleanup write can fail even when the helper keeps answering
            // health checks. Give it another chance without flipping readiness.
            if self.needsBackgroundRecovery, wasResponsive { self.recoveryProbe.send() }
        }
    }

    /// Schedules only XPC work with outstanding demand. A successful probe
    /// does not query ServiceManagement or restart the approval window.
    private func scheduleHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
        guard isAvailable, isEnabled, verificationTask == nil else { return }
        let now = ContinuousClock.now
        let canRetryCleanup = needsBackgroundRecovery && remainingBackgroundProbes > 0
        let due: ContinuousClock.Instant?
        switch status {
        case .enabled:
            let recovering = !isHelperResponsive && recoveryAttempts < Self.maximumRecoveryAttempts
            due = (canRetryCleanup || recovering)
                ? nextEnabledHealthCheck ?? now : nil
        case .requiresApproval:
            let observing = registrationRetryTask != nil || pendingProbeAttempts > 0
            due = (canRetryCleanup || observing)
                ? nextPendingHealthCheck ?? now : nil
        case .notRegistered:
            due = nil
        }
        guard let due else { return }
        let delay = max(.zero, now.duration(to: due))
        healthCheckTask = Task { [weak self] in
            do { try await Task.sleep(for: delay, tolerance: delay / 5) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            self.healthCheckTask = nil
            if canRetryCleanup { self.remainingBackgroundProbes -= 1 }
            self.checkHelperIfNeeded(forceRead: true)
        }
    }

    func openLoginItemsSettings() {
        awaitsApprovalReturn = isAvailable && isEnabled
        service.openLoginItemsSettings()
        cancelRegistrationRetry()
        startRegistrationRetryWindow()
    }
}
