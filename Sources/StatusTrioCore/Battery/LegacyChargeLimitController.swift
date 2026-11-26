import AppKit
import Combine
import Foundation

/// App-facing state for the legacy charge limiter (macOS 13–15).
///
/// It owns the user intent and the UI status; the *hardware* ownership record
/// lives in the helper's journal so a crash cannot lose the stock value. The
/// controller never writes SMC keys: every command is a typed request.
@MainActor
final class LegacyChargeLimitController: ObservableObject {
    static let limits = Array(stride(from: 80, through: 100, by: 5))

    /// UI-preview only. A *development* build may set the
    /// `STForceLegacyChargeUIPreview` user default (or the
    /// STATUS_TRIO_FORCE_LEGACY_CHARGE_UI=1 env var) to render the legacy group
    /// and card with a fabricated "holding 85%" state on any macOS version.
    /// It never touches the helper or SMC and is inert in a release bundle.
    nonisolated static let isDemoPreviewForced: Bool = {
        let env = ProcessInfo.processInfo.environment["STATUS_TRIO_FORCE_LEGACY_CHARGE_UI"] == "1"
        let prefersDemo = UserDefaults.standard.bool(forKey: "STForceLegacyChargeUIPreview")
        guard env || prefersDemo else { return false }
        let info = Bundle.main.infoDictionary ?? [:]
        let codename = info["STDevelopmentCodename"] as? String ?? ""
        let bundleID = info["CFBundleIdentifier"] as? String ?? ""
        return !codename.isEmpty || bundleID.contains(".dev.")
    }()

    static let demoPreviewLimit = 85

    @Published private(set) var availability: LegacyChargeLimitAvailability = .unavailable(.helperUnavailable)
    @Published private(set) var status: LegacyChargeLimitStatus = .notEnabled
    @Published private(set) var selectedLimit: Int?
    @Published private(set) var isApplying = false

    /// True while the user's temporary "charge to full" override is in effect.
    var isTemporarilyCharging: Bool {
        if case .temporarilyChargingToFull = status { return true }
        return false
    }

    private let client: any LegacyChargeLimitClienting
    private let sessionStore: any LegacyChargeLimitSessionStoring
    private let architecture: LegacyRuntimeArchitecture
    private let osBand: LegacyOSBand
    private let notificationCenter: NotificationCenter
    private var session: LegacyChargeLimitSession?
    private var started = false
    private var cancellables: Set<AnyCancellable> = []
    private var batteries: (any Publisher<BatteryStatus, Never>)?
    /// Last gate decision this controller asked for, so hysteresis does not
    /// flap on small level wobbles and we do not write on every battery tick.
    private var lastAppliedAllowsCharging: Bool?
    /// Reports whether a held cap needs the shared root helper registered and
    /// polled. The environment wires this to `PrivilegedHelperManager`, so an
    /// idle app with no cap never keeps the daemon alive.
    var onHelperDemandChanged: ((Bool) -> Void)?
    /// Fired after a charge command succeeds so the app can force a battery
    /// re-read. A legacy/firmware write can change the charging state without an
    /// IOPS power-source notification, which would leave the panel subtitle
    /// ("已连接电源" vs "预计…充满") stale until the fallback poll.
    var onCommandCompleted: (() -> Void)?
    /// Bumped by every user command. A launch reconcile captures this and
    /// discards its result if a command landed while it was awaiting the helper,
    /// so a slow startup verify can never overwrite the user's newer action.
    private var commandGeneration = 0
    /// Sleep behaviour while a ceiling is held; wired to SettingsStore.
    var sleepPolicyProvider: () -> LegacySleepPolicy = { .pauseCharging }
    private let sleepAssertion = LegacySleepAssertion()
    private var lastBatteryLevel: Int?
    private var lastWasOnAC: Bool?

    init(
        client: any LegacyChargeLimitClienting = XPCPrivilegedLegacyChargeClient(),
        sessionStore: any LegacyChargeLimitSessionStoring = UserDefaultsLegacyChargeLimitSessionStore(defaults: .standard),
        architecture: LegacyRuntimeArchitecture = LegacyRuntimeArchitecture.current,
        osBand: LegacyOSBand = LegacyOSBand.current,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.client = client
        self.sessionStore = sessionStore
        self.architecture = architecture
        self.osBand = osBand
        self.notificationCenter = notificationCenter
    }

    var isAvailable: Bool { availability.isAvailable }

    // MARK: - Lifecycle

    /// App launch must not start the root helper: the plan limits health probes
    /// to an active limit or a visible Settings pane. A saved session is the
    /// only reason to verify at launch (it owns the hardware).
    func start() {
        guard !started else { return }
        started = true
        guard sessionStore.load() != nil else {
            status = .notEnabled
            client.releaseConnection()
            return
        }
        taskRefresh()
    }

    /// Event-driven hysteresis. The app's existing battery snapshot is the
    /// trigger; no polling timer is introduced. Only a decision change writes.
    func start(batteries: AnyPublisher<BatteryStatus, Never>) {
        self.batteries = batteries
        // Reconcile the saved intent exactly as the launch path does. The
        // caller's publisher already omits its initial replay value, so this
        // subscription must NOT drop the first genuine event.
        start()
        guard cancellables.isEmpty else { return }
        // Sleep: close a software-driven gate before the machine suspends, and
        // re-evaluate from hardware on wake. This is not a polling timer.
        notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in await self.prepareForSleep() }
            }
            .store(in: &cancellables)
        notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in await self.handleWake() }
            }
            .store(in: &cancellables)
        batteries
            .removeDuplicates()
            .sink { [weak self] battery in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleBattery(level: battery.percentage,
                                             isOnAC: battery.isConnectedToPower)
                }
            }
            .store(in: &cancellables)
    }

    /// Inhibits charging before sleep when a cap is held. A temporary full
    /// charge is an explicit user choice and is left alone by the helper.
    func prepareForSleep() async {
        // "Keep awake until limit" never inhibits; it keeps the Mac awake so the
        // ceiling can be reached first. "Pause charging" stops before sleep.
        guard sleepPolicyProvider() == .pauseCharging else { return }
        guard isAvailable, session != nil, status != .temporarilyChargingToFull else { return }
        do {
            _ = try await client.prepareForSleep()
        } catch {
            // Sleep proceeds regardless; the helper still holds the journal and
            // the next wake re-evaluates the gate.
            status = .failed
        }
    }

    func handleBattery(level: Int, isOnAC: Bool) async {
        lastBatteryLevel = level
        // A temporary full charge ends when it expires (24h from the toggle) or,
        // for older records without a deadline, when the battery is full. The
        // held ceiling is then re-applied; ordinary events never interrupt it.
        if status == .temporarilyChargingToFull {
            let ended: Bool
            if let until = session?.temporaryFullUntil {
                ended = Date() >= until
            } else if let session {
                ended = !LegacyChargeLimitEngine.temporaryFullShouldContinue(batteryLevel: level)
            } else {
                ended = true
            }
            if ended { _ = await cancelChargeToFull() }
            updateSleepAssertion(level: level, isOnAC: isOnAC)
            return
        }
        guard isAvailable, let session else { return }
        guard session.requestedLimit > 0 else { return }
        // On AC plug-in (or the first event after launch), repair a value the
        // system may have reset. A foreign owner is reported, never overwritten.
        if isOnAC, lastWasOnAC != true {
            lastWasOnAC = true
            do {
                let outcome = try await client.reconcile(session.requestedLimit)
                applyReconcile(outcome, limit: session.requestedLimit)
            } catch {
                status = .failed
            }
            updateSleepAssertion(level: level, isOnAC: isOnAC)
            return
        }
        lastWasOnAC = isOnAC
        if !isOnAC {
            // No AC means nothing to gate; do not touch the hardware.
            lastAppliedAllowsCharging = nil
            return
        }
        // The firmware charge-limit backend enforces its own upper/lower band;
        // do not run the legacy allow/inhibit engine (or rewrite the keys) on
        // every battery tick. Plug-in, wake and launch already reconcile, and
        // those paths keep the limit self-healed.
        if availability == .available(.firmwareLimit) {
            updateSleepAssertion(level: level, isOnAC: isOnAC)
            return
        }
        let decision = LegacyChargeLimitEngine(limit: session.requestedLimit).decide(
            batteryLevel: level,
            isOnAC: isOnAC,
            currentlyAllowing: lastAppliedAllowsCharging
        )
        switch decision {
        case .none:
            return
        case .allowCharging:
            lastAppliedAllowsCharging = true
        case .inhibitCharging:
            lastAppliedAllowsCharging = false
        }
        await reapply(limit: session.requestedLimit)
        updateSleepAssertion(level: level, isOnAC: isOnAC)
    }

    /// Holds/releases the sleep assertion from the current state. Pure decision
    /// lives on `LegacySleepPolicy`; this only applies it to IOKit.
    private func updateSleepAssertion(level: Int, isOnAC: Bool) {
        let target = status == .temporarilyChargingToFull ? 100 : (session?.requestedLimit ?? 100)
        let keep = LegacySleepPolicy.shouldStayAwake(
            level: level,
            target: target,
            isOnAC: isOnAC,
            hasSession: session != nil && status != .notEnabled,
            policy: sleepPolicyProvider()
        )
        if keep {
            sleepAssertion.acquire(reason: "Status Trio is charging to the charge limit")
        } else {
            sleepAssertion.release()
        }
    }

    /// Called when the battery Settings pane becomes visible. This is the only
    /// place availability is probed, so an idle app never spawns the helper.
    func refreshAvailability() async {
        await refresh()
    }

    func stop() {
        started = false
        cancellables.removeAll()
        batteries = nil
        lastAppliedAllowsCharging = nil
        sleepAssertion.release()
        lastWasOnAC = nil
        client.releaseConnection()
    }

    // MARK: - Commands

    func refresh() async {
        if Self.isDemoPreviewForced {
            availability = .available(.siliconLegacyInhibit)
            selectedLimit = Self.demoPreviewLimit
            status = .holding(at: Self.demoPreviewLimit)
            return
        }
        guard osBand.allowsLegacyLimiter else {
            availability = .unavailable(.unsupportedOS)
            status = .notEnabled
            // No legacy backend exists here; do not keep the root helper alive.
            client.releaseConnection()
            return
        }
        let generation = commandGeneration
        let probe: LegacyChargeLimitProbeFacts
        do {
            probe = try await client.probe()
        } catch {
            availability = .unavailable(.helperUnavailable)
            status = .notEnabled
            return
        }
        availability = LegacyChargeLimitAvailability.resolve(
            probe: probe,
            architecture: architecture,
            osBand: osBand,
            helperAvailable: true
        )
        guard generation == commandGeneration else { return }
        guard let loaded = sessionStore.load() else {
            session = nil
            selectedLimit = nil
            status = .notEnabled
            // No active limit owns the hardware: let the helper idle-exit.
            client.releaseConnection()
            return
        }
        if loaded.isTemporarilyOverridden {
            // A still-running temporary full charge survives relaunch: it has a
            // durable 24h deadline rather than a live timer.
            if let until = loaded.temporaryFullUntil, Date() < until {
                session = loaded
                selectedLimit = loaded.requestedLimit
                status = .temporarilyChargingToFull
                return
            }
            var cleared = loaded
            cleared.isTemporarilyOverridden = false
            cleared.temporaryFullUntil = nil
            session = cleared
            saveSession(cleared)
        }
        session = loaded
        selectedLimit = loaded.requestedLimit
        status = .checkingHardware
        let outcome = try? await client.reconcile(loaded.requestedLimit)
        guard generation == commandGeneration else { return }
        applyReconcile(outcome, limit: loaded.requestedLimit)
    }

    @discardableResult
    func setLimit(_ limit: Int) async -> Bool {
        if Self.isDemoPreviewForced {
            guard Self.limits.contains(limit) else { return false }
            selectedLimit = limit
            status = .holding(at: limit)
            return true
        }
        guard isAvailable else {
            status = .unsupported
            return false
        }
        // A 100% ceiling is the same as no ceiling: turn limiting off instead of
        // writing an inhibit that can never bind.
        if limit >= 100 { return await disable() }
        guard Self.limits.contains(limit) else { return false }
        commandGeneration &+= 1
        isApplying = true
        defer { isApplying = false }
        do {
            let outcome = try await client.setLimit(limit, expectedLimit: session?.requestedLimit)
            guard outcome.succeeded else {
                status = outcome.error == .ownershipConflict ? .externalChange : .failed
                return false
            }
            let newSession = LegacyChargeLimitSession(
                requestedLimit: limit,
                originalLimit: session?.originalLimit
            )
            saveSession(newSession)
            selectedLimit = limit
            status = .holding(at: limit)
            onHelperDemandChanged?(true)
            updateSleepAssertion(level: lastBatteryLevel ?? limit, isOnAC: true)
            onCommandCompleted?()
            return true
        } catch LegacyChargeLimitClientError.helperUnavailable {
            availability = .unavailable(.helperUnavailable)
            status = .notEnabled
            return false
        } catch {
            status = .failed
            return false
        }
    }

    @discardableResult
    func disable() async -> Bool {
        if Self.isDemoPreviewForced {
            selectedLimit = nil
            status = .notEnabled
            return true
        }
        guard isAvailable else {
            status = .unsupported
            return false
        }
        isApplying = true
        defer { isApplying = false }
        do {
            commandGeneration &+= 1
            // The helper owns the stock value; the app only knows its intent, so
            // it must not fabricate an "expected hardware value" here. Ownership
            // is enforced by the helper's journal, not by a client guess.
            let outcome = try await client.disable(expectedLimit: nil)
            guard outcome.succeeded else {
                status = .restoreFailed
                return false
            }
            saveSession(nil)
            selectedLimit = nil
            status = .notEnabled
            sleepAssertion.release()
            client.releaseConnection()
            onHelperDemandChanged?(false)
            onCommandCompleted?()
            return true
        } catch {
            status = .restoreFailed
            return false
        }
    }

    @discardableResult
    func chargeToFullOnce() async -> Bool {
        if Self.isDemoPreviewForced {
            status = .temporarilyChargingToFull
            return true
        }
        guard isAvailable, session != nil else { return false }
        commandGeneration &+= 1
        isApplying = true
        defer { isApplying = false }
        do {
            let outcome = try await client.chargeToFullOnce()
            guard outcome.succeeded else {
                status = .failed
                return false
            }
            if var updated = session {
                updated.isTemporarilyOverridden = true
                updated.temporaryFullUntil = Date().addingTimeInterval(24 * 60 * 60)
                saveSession(updated)
            }
            status = .temporarilyChargingToFull
            updateSleepAssertion(level: lastBatteryLevel ?? 0, isOnAC: true)
            onCommandCompleted?()
            return true
        } catch {
            status = .failed
            return false
        }
    }

    @discardableResult
    func cancelChargeToFull() async -> Bool {
        if Self.isDemoPreviewForced {
            status = .holding(at: selectedLimit ?? Self.demoPreviewLimit)
            return true
        }
        guard isAvailable, let session else { return false }
        commandGeneration &+= 1
        isApplying = true
        defer { isApplying = false }
        do {
            let outcome = try await client.cancelChargeToFull()
            guard outcome.succeeded else {
                status = .restoreFailed
                return false
            }
            var updated = session
            updated.isTemporarilyOverridden = false
            updated.temporaryFullUntil = nil
            saveSession(updated)
            status = .holding(at: session.requestedLimit)
            updateSleepAssertion(level: lastBatteryLevel ?? session.requestedLimit, isOnAC: true)
            onCommandCompleted?()
            return true
        } catch {
            status = .restoreFailed
            return false
        }
    }

    /// Re-applies the held limit after wake or a power-source change.
    ///
    /// Only runs when a session exists and no temporary override is in flight:
    /// a full-charge override must not be interrupted by ordinary battery
    /// events. A failure here is surfaced, never silently retried.
    func handleWake() async {
        guard isAvailable, let session, status != .temporarilyChargingToFull else { return }
        // The previous gate is untrusted after sleep; re-evaluate from scratch.
        lastAppliedAllowsCharging = nil
        do {
            let outcome = try await client.reconcile(session.requestedLimit)
            applyReconcile(outcome, limit: session.requestedLimit)
        } catch {
            status = .failed
        }
    }

    /// Maps a reconcile result to the visible status. `nil` means the call threw.
    private func applyReconcile(_ outcome: LegacyChargeLimitWriteOutcome?, limit: Int) {
        guard let outcome else { status = .failed; return }
        if outcome.succeeded {
            status = .holding(at: limit)
        } else if outcome.error == .ownershipConflict {
            status = .externalChange
        } else {
            status = .failed
        }
    }

    // MARK: - Helpers

    private func reapply(limit: Int) async {
        do {
            let outcome = try await client.setLimit(limit, expectedLimit: limit)
            if outcome.succeeded {
                status = .holding(at: limit)
            } else if outcome.error == .ownershipConflict {
                status = .externalChange
            }
        } catch {
            status = .failed
        }
    }

    private func saveSession(_ session: LegacyChargeLimitSession?) {
        self.session = session
        if let session {
            sessionStore.save(session)
        } else {
            sessionStore.clear()
        }
    }
}

private extension LegacyChargeLimitController {
    nonisolated func taskRefresh() {
        Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }
}