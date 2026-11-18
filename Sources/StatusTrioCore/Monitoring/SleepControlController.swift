import AppKit
import Combine
import Foundation
import IOKit.pwr_mgt
import PowerHelperProtocol

/// The timer choices offered next to each keep-awake toggle (#295).
enum SleepTimerDuration: String, CaseIterable, Identifiable, Sendable {
    case thirtyMinutes
    case oneHour
    case twoHours
    case fourHours
    case unlimited

    var id: Self { self }

    /// `nil` means "no limit".
    var timeInterval: TimeInterval? {
        switch self {
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .twoHours: 2 * 60 * 60
        case .fourHours: 4 * 60 * 60
        case .unlimited: nil
        }
    }

    var localizationKey: LocalizationKey {
        switch self {
        case .thirtyMinutes: .quickActionsTimerThirtyMinutes
        case .oneHour: .quickActionsTimerOneHour
        case .twoHours: .quickActionsTimerTwoHours
        case .fourHours: .quickActionsTimerFourHours
        case .unlimited: .quickActionsTimerUnlimited
        }
    }

    /// The compact label on the time button: `30m`, `1h`, `2h`, `4h`, `∞`.
    var shortLabel: String {
        switch self {
        case .thirtyMinutes: "30m"
        case .oneHour: "1h"
        case .twoHours: "2\u{2009}h"
        case .fourHours: "4\u{2009}h"
        case .unlimited: "∞"
        }
    }
}

/// Why the lid-close toggle cannot be turned on right now (#295).
enum LidSleepUnavailableReason: Equatable, Sendable {
    case helperUnavailable
    case helperNeedsUpdate
    case requiresPower

    var localizationKey: LocalizationKey {
        switch self {
        case .helperUnavailable: .quickActionsHelperUnavailable
        case .helperNeedsUpdate: .quickActionsHelperNeedsUpdate
        case .requiresPower: .quickActionsRequiresPower
        }
    }
}

/// A non-error explanation shown when the lid toggle can't safely act. Kept
/// separate from `lastError` so it renders as neutral guidance, not a red
/// failure — e.g. another tool already set `disablesleep`, or the state can't
/// be read.
enum LidSleepExternalState: Equatable, Sendable {
    case managedExternally
    case stateUnreadable

    var localizationKey: LocalizationKey {
        switch self {
        case .managedExternally: .quickActionsLidSleepExternal
        case .stateUnreadable: .quickActionsLidSleepUnreadable
        }
    }
}

/// Explicit Helper capability state (stage 2), so an old helper and a missing
/// helper are told apart instead of collapsing into one "needs update" flag.
/// Only a helper that has answered the version handshake at or above the
/// `disableSleep` protocol may receive `disableSleep` writes; the pre-probe
/// `.undetected`/`.detecting` states stay optimistic so startup does not dead-
/// click, and the probe refines them within the first runloop.
enum HelperCapability: Equatable, Sendable {
    case undetected
    case detecting
    case available
    case needsUpdate
    case unavailable

    /// Whether a `disableSleep` write may be attempted in this state.
    var supportsDisableSleep: Bool {
        switch self {
        case .available, .undetected, .detecting: return true
        case .needsUpdate, .unavailable: return false
        }
    }
}

/// A short, self-clearing notice shown in the card after an automatic change.
enum SleepControlNotice: Equatable, Sendable {
    case turnedOffUnplugged
    case turnedOffLowBattery
    case timerEnded

    var localizationKey: LocalizationKey {
        switch self {
        case .turnedOffUnplugged: .quickActionsTurnedOffUnplugged
        case .turnedOffLowBattery: .quickActionsTurnedOffLowBattery
        case .timerEnded: .quickActionsTurnedOffTimerEnded
        }
    }
}

/// The local "keep the display awake" assertion. Injected so the controller can
/// be exercised without touching IOKit.
protocol DisplaySleepAsserting: AnyObject {
    /// Acquires the assertion; `false` means the system refused it.
    func acquire() -> Bool
    func release()
}

/// The production assertion: `PreventUserIdleDisplaySleep` needs no privilege.
///
/// It is released when the app quits, so a crash cannot leave the display awake.
final class IOPMDisplaySleepAssertion: DisplaySleepAsserting {
    private var assertionID: IOPMAssertionID = 0
    private var isHeld = false

    func acquire() -> Bool {
        guard !isHeld else { return true }
        var id: IOPMAssertionID = 0
        let reason = "Status Trio is keeping the screen awake." as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &id
        )
        guard result == kIOReturnSuccess else { return false }
        assertionID = id
        isHeld = true
        return true
    }

    func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isHeld = false
    }
}

/// Records whether *this app* turned `disablesleep` on, so a later launch only
/// clears its own residue and never a value the user set by hand. `pmset`
/// `disablesleep` survives reboots, which makes the distinction matter.
protocol SleepOwnershipStoring: AnyObject {
    var ownsDisableSleep: Bool { get set }
}

final class UserDefaultsSleepOwnershipStore: SleepOwnershipStoring {
    static let key = "sleepControl.ownsDisableSleep"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var ownsDisableSleep: Bool {
        get { defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

/// Owns the two keep-awake toggles and their optional timers (#295).
///
/// The display toggle is a local `IOPMAssertion`. The lid toggle goes through
/// the privileged helper's `pmset -a disablesleep` support (protocol version 3)
/// and is only allowed on external power. Neither adds a background poll: each
/// timer is a single sleeping task that turns its toggle off, and power changes
/// arrive as battery snapshots the store already produces.
@MainActor
final class SleepControlController: ObservableObject {
    /// Turning the lid toggle off below this percentage keeps a battery-only Mac
    /// from being run flat with the lid shut. External-power-only gating already
    /// covers the common case; this is the explicit low-battery guard the issue
    /// asks for.
    static let lowBatteryThreshold = 20

    /// Behaviour options driven by Settings. Defaults keep the friendlier
    /// "allowed on battery" behaviour with low-battery auto-off still on.
    var allowsLidSleepOnBattery = true
    var autoDisablesLidSleepOnLowBattery = true

    @Published private(set) var isPreventingDisplaySleep = false
    @Published private(set) var displayTimer: SleepTimerDuration = .unlimited
    @Published private(set) var displayExpiry: Date?
    @Published private(set) var isPreventingLidSleep = false
    @Published private(set) var lidTimer: SleepTimerDuration = .unlimited
    @Published private(set) var lidExpiry: Date?
    @Published private(set) var isApplyingLidSleep = false
    @Published private(set) var helperCapability: HelperCapability = .undetected
    @Published private(set) var isHelperReady = false
    /// Non-error explanation for the lid toggle (external ownership / unreadable).
    @Published private(set) var lidSleepExternalState: LidSleepExternalState?
    /// Best-effort names of processes currently holding a sleep-preventing power
    /// assertion, shown as "possibly X" when an external disablesleep is found.
    @Published private(set) var lidExternalOwnerNames: [String] = []
    /// Injectable for tests; defaults to reading the system IOPM assertions.
    var lidAssertionOwnerProvider: () -> [String] = SleepControlController.systemLidSleepAssertionOwners

    /// Kept for the existing "needs update" copy; derived from the capability.
    var helperNeedsUpdate: Bool { helperCapability == .needsUpdate }
    @Published private(set) var notice: SleepControlNotice?
    @Published private(set) var lastError: String?
    @Published private(set) var isOnExternalPower = true
    @Published private(set) var batteryPercentage = 100

    private let assertion: any DisplaySleepAsserting
    private let client: any DisableSleepClienting
    private let helperReadiness: any HelperReadinessProviding
    private let ownership: any SleepOwnershipStoring
    private let now: () -> Date

    private var displayOffTask: Task<Void, Never>?
    private var lidOffTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var readinessCancellable: AnyCancellable?
    private var hasStarted = false
    private var isStopped = false

    // Serialized lid-sleep coordinator (stage 1). All `disableSleep` writes flow
    // through one worker so concurrent/rapid requests cannot complete out of
    // order; the desired state is the source of truth and the worker converges
    // the real system state toward it.
    private var lidWorkerTask: Task<Void, Never>?
    private var lidWorkerRunning = false
    private var lidInFlightWrite = false
    private var desiredLidSleep = false
    private var lidDisableAttempts = 0
    private var lidPendingRecovery = false
    private var lidForeignActive = false
    private let lidDisableRetryDelays: [TimeInterval]

    init(
        assertion: any DisplaySleepAsserting = IOPMDisplaySleepAssertion(),
        client: any DisableSleepClienting = XPCPrivilegedHighPowerClient(),
        helperReadiness: any HelperReadinessProviding = SharedHelperReadiness(),
        ownership: any SleepOwnershipStoring = UserDefaultsSleepOwnershipStore(),
        now: @escaping () -> Date = Date.init,
        lidDisableRetryDelays: [TimeInterval] = [1, 3, 9]
    ) {
        self.assertion = assertion
        self.client = client
        self.helperReadiness = helperReadiness
        self.ownership = ownership
        self.now = now
        self.lidDisableRetryDelays = lidDisableRetryDelays
        self.isHelperReady = helperReadiness.isReady
        // Optimistic before the first probe (keeps startup from dead-clicking);
        // a known-missing helper is unavailable immediately.
        self.helperCapability = helperReadiness.isReady ? .undetected : .unavailable
    }

    /// Why the lid toggle is unavailable, or `nil` when it can be turned on.
    var lidUnavailableReason: LidSleepUnavailableReason? {
        if isPreventingLidSleep { return nil }
        if !isHelperReady { return .helperUnavailable }
        switch helperCapability {
        case .needsUpdate: return .helperNeedsUpdate
        case .unavailable: return .helperUnavailable
        case .undetected, .detecting, .available: break
        }
        if !isOnExternalPower && !allowsLidSleepOnBattery { return .requiresPower }
        return nil
    }

    var canEnableLidSleep: Bool { lidUnavailableReason == nil }

    /// Whether quitting must first restore `disablesleep 0`.
    var needsTerminationCleanup: Bool {
        isPreventingLidSleep || ownership.ownsDisableSleep || lidWorkerRunning
            || lidInFlightWrite || lidPendingRecovery || desiredLidSleep
    }

    /// True while a failed lid-sleep clear is still awaiting recovery. The helper
    /// self-check must not drop to the slow cadence while this is set, or the
    /// residual `disablesleep=1` would go unnoticed.
    var hasPendingLidRecovery: Bool { lidPendingRecovery }

    // MARK: - Lifecycle

    func start() {
        guard !hasStarted, !isStopped else { return }
        hasStarted = true
        readinessCancellable = helperReadiness.readinessPublisher
            .sink { [weak self] ready in
                Task { @MainActor [weak self] in
                    guard let self, !self.isStopped else { return }
                    self.isHelperReady = ready
                    if ready {
                        self.probeHelperAndRecover()
                    } else {
                        self.helperCapability = .unavailable
                    }
                }
            }
        probeHelperAndRecover()
    }

    /// Cancels timers and releases the local assertion. Does not touch
    /// `disablesleep`; that needs the async `shutdown()`.
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        readinessCancellable?.cancel()
        readinessCancellable = nil
        displayOffTask?.cancel()
        lidOffTask?.cancel()
        lidWorkerTask?.cancel()
        noticeTask?.cancel()
        displayOffTask = nil
        lidOffTask = nil
        noticeTask = nil
        if isPreventingDisplaySleep {
            assertion.release()
            isPreventingDisplaySleep = false
        }
    }

    /// Restores the system default before the app quits. Best effort: a helper
    /// that cannot be reached keeps the ownership marker so the next launch
    /// retries the cleanup.
    func shutdown() async {
        // Refuse new enables and stop timers first, then let any in-flight write
        // settle before issuing the clear so a late enable cannot land after it.
        desiredLidSleep = false
        if !isStopped { stop() }
        if let task = lidWorkerTask { _ = await task.value }
        guard ownership.ownsDisableSleep || isPreventingLidSleep || lidInFlightWrite else {
            isPreventingLidSleep = false
            return
        }
        guard helperReadiness.isReady, helperCapability.supportsDisableSleep,
              helperCapability != .needsUpdate else { return }
        let observed = try? await client.setDisableSleep(false)
        if observed == false {
            ownership.ownsDisableSleep = false
            isPreventingLidSleep = false
            lidPendingRecovery = false
        }
    }

    // MARK: - Display sleep

    func setDisplaySleep(_ enabled: Bool) {
        guard !isStopped, enabled != isPreventingDisplaySleep else { return }
        if enabled {
            guard assertion.acquire() else {
                lastError = "The display-sleep assertion was refused."
                return
            }
            isPreventingDisplaySleep = true
            scheduleDisplayAutoOff()
        } else {
            assertion.release()
            isPreventingDisplaySleep = false
            cancelDisplayTimer()
        }
    }

    func setDisplayTimer(_ duration: SleepTimerDuration) {
        displayTimer = duration
        guard isPreventingDisplaySleep else { return }
        scheduleDisplayAutoOff()
    }

    private func scheduleDisplayAutoOff() {
        displayOffTask?.cancel()
        displayOffTask = nil
        guard let interval = displayTimer.timeInterval else {
            displayExpiry = nil
            return
        }
        displayExpiry = now().addingTimeInterval(interval)
        displayOffTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled, let self else { return }
            self.displayTimerFired()
        }
    }

    /// The end of a display timer. Internal so tests exercise it without waiting.
    func displayTimerFired() {
        guard isPreventingDisplaySleep else { return }
        setDisplaySleep(false)
        showNotice(.timerEnded)
    }

    private func cancelDisplayTimer() {
        displayOffTask?.cancel()
        displayOffTask = nil
        displayExpiry = nil
    }

    // MARK: - Lid sleep (helper-backed, serialized)

    /// Requests the desired lid-sleep state. Every actual `disableSleep` write is
    /// funnelled through one serial worker, so rapid toggles or an unplug during
    /// an in-flight enable cannot leave the system on battery with the lid awake.
    func setLidSleep(_ enabled: Bool) {
        guard !isStopped else { return }
        // Re-fetch the helper's state on every user click so it never acts on a
        // stale readiness/external value.
        helperReadiness.refreshStatus()
        if enabled {
            guard canEnableLidSleep else { return }
        }
        requestLidState(enabled)
    }

    func setLidTimer(_ duration: SleepTimerDuration) {
        lidTimer = duration
        guard isPreventingLidSleep else { return }
        scheduleLidAutoOff()
    }

    private func requestLidState(_ enabled: Bool) {
        guard !isStopped else { return }
        if enabled == desiredLidSleep, !lidWorkerRunning,
           isPreventingLidSleep == enabled, !lidPendingRecovery {
            return
        }
        desiredLidSleep = enabled
        startLidWorkerIfNeeded()
    }

    /// One bounded in-session retry for an unconfirmed enable. It runs after the
    /// current worker has returned; if the helper is still unreachable the
    /// durable marker waits for quit/relaunch instead of looping forever.
    private func scheduleLidRecoveryRetry() {
        guard !isStopped else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !self.isStopped, self.lidPendingRecovery,
                  !self.lidWorkerRunning else { return }
            self.startLidWorkerIfNeeded()
        }
    }

    private func startLidWorkerIfNeeded() {
        guard !lidWorkerRunning, !isStopped else { return }
        lidWorkerRunning = true
        isApplyingLidSleep = true
        lidWorkerTask = Task { [weak self] in
            await self?.runLidWorker()
        }
    }

    private enum LidWriteOutcome: Equatable {
        case applied
        case blockedByPolicy
        case retryableFailure
        case failed
    }

    private func runLidWorker() async {
        defer {
            lidWorkerRunning = false
            isApplyingLidSleep = false
            lidWorkerTask = nil
        }
        while !isStopped {
            let target = desiredLidSleep
            if target == isPreventingLidSleep && !lidPendingRecovery {
                return
            }
            if target {
                // Re-check after any previous await: an unplug during an in-flight
                // enable must flip the target off before we ever write `1`.
                if !canEnableLidSleep {
                    desiredLidSleep = false
                    if isPreventingLidSleep { continue }
                    return
                }
                switch await performEnableLidSleep() {
                case .applied:
                    continue
                case .blockedByPolicy:
                    desiredLidSleep = false
                    continue
                case .retryableFailure, .failed:
                    desiredLidSleep = false
                    return
                }
            } else {
                switch await performDisableLidSleep() {
                case .applied:
                    continue
                case .retryableFailure:
                    lidDisableAttempts += 1
                    if lidDisableAttempts <= lidDisableRetryDelays.count {
                        let delay = lidDisableRetryDelays[lidDisableAttempts - 1]
                        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                        continue
                    }
                    lidPendingRecovery = true
                    return
                case .blockedByPolicy, .failed:
                    return
                }
            }
        }
    }

    private static let foreignActiveMessage =
        "Lid sleep was already disabled by another tool; Status Trio will not change it."

    private func performEnableLidSleep() async -> LidWriteOutcome {
        guard canEnableLidSleep else { return .blockedByPolicy }
        // Never claim ownership of a value the user (or another tool) set first.
        let current: Bool?
        do { current = try await client.readDisableSleep() } catch { current = nil }
        guard let current else {
            lidSleepExternalState = .stateUnreadable
            return .failed
        }
        if current {
            if ownership.ownsDisableSleep {
                isPreventingLidSleep = true
                lidPendingRecovery = false
                scheduleLidAutoOff()
                return .applied
            }
            lidForeignActive = true
            lidExternalOwnerNames = lidAssertionOwnerProvider()
            lidSleepExternalState = .managedExternally
            return .failed
        }
        // The helper may have taken a while to answer the initial read. Re-check
        // the current intent and power policy before claiming ownership or
        // writing: an unplug or a toggle-off during that await must win.
        guard desiredLidSleep, !isStopped, canEnableLidSleep else {
            return .blockedByPolicy
        }
        // Persist the intent *before* the write so a crash mid-write is recovered
        // on the next launch (this is the durable pending-cleanup record).
        ownership.ownsDisableSleep = true
        lidInFlightWrite = true
        var observed: Bool?
        var writeAnswered = false
        do {
            observed = try await client.setDisableSleep(true)
            writeAnswered = true
        } catch {
            observed = nil
        }
        lidInFlightWrite = false

        var stateIsKnown = writeAnswered
        var onNow = (observed == true)
        if !onNow {
            if let read = try? await client.readDisableSleep() {
                onNow = read
                stateIsKnown = true
            }
        }
        if onNow {
            isPreventingLidSleep = true
            lidForeignActive = false
            lidSleepExternalState = nil
            lidExternalOwnerNames = []
            lidPendingRecovery = false
            scheduleLidAutoOff()
            return .applied
        }
        guard stateIsKnown else {
            // The write may have landed even though both the reply and the
            // read were lost. Keep the durable marker and hand the cleanup to
            // the bounded recovery path; clearing it here could leave the
            // system permanently unable to sleep after a restart.
            lidPendingRecovery = true
            lidSleepExternalState = .stateUnreadable
            lastError = "The helper did not confirm lid sleep prevention; cleanup will be retried."
            scheduleLidRecoveryRetry()
            return .retryableFailure
        }
        ownership.ownsDisableSleep = false
        lastError = "The helper did not apply lid sleep prevention."
        return .failed
    }

    private func performDisableLidSleep() async -> LidWriteOutcome {
        guard ownership.ownsDisableSleep || isPreventingLidSleep || lidInFlightWrite else {
            isPreventingLidSleep = false
            lidPendingRecovery = false
            cancelLidTimer()
            return .applied
        }
        lidInFlightWrite = true
        let observed: Bool?
        do { observed = try await client.setDisableSleep(false) } catch { observed = nil }
        lidInFlightWrite = false
        var offNow = (observed == false)
        if !offNow { offNow = ((try? await client.readDisableSleep()) == false) }
        if offNow {
            isPreventingLidSleep = false
            ownership.ownsDisableSleep = false
            lidSleepExternalState = nil
            lidExternalOwnerNames = []
            lidPendingRecovery = false
            lidDisableAttempts = 0
            cancelLidTimer()
            return .applied
        }
        lastError = "The helper did not clear lid sleep prevention."
        return .retryableFailure
    }

    private func scheduleLidAutoOff() {
        lidOffTask?.cancel()
        lidOffTask = nil
        guard let interval = lidTimer.timeInterval else {
            lidExpiry = nil
            return
        }
        lidExpiry = now().addingTimeInterval(interval)
        lidOffTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled, let self else { return }
            self.lidTimerFired()
        }
    }

    /// The end of a lid timer. Internal so tests exercise it without waiting.
    func lidTimerFired() {
        guard isPreventingLidSleep else { return }
        requestLidState(false)
        showNotice(.timerEnded)
    }

    private func cancelLidTimer() {
        lidOffTask?.cancel()
        lidOffTask = nil
        lidExpiry = nil
    }

    // MARK: - Power policy

    /// Feeds the current battery reading. Turning the lid toggle off when the
    /// Mac leaves external power (or the battery gets low) is the safety rule
    /// the issue asks for.
    func updatePowerState(battery: BatteryStatus) {
        let onExternalPower = battery.isPresent ? battery.isConnectedToPower : true
        isOnExternalPower = onExternalPower
        batteryPercentage = battery.percentage
        applyLidPowerPolicy()
    }

    /// Re-applies the battery policy after a power/battery or settings change.
    /// Only acts while on battery:
    ///  - low battery + auto-off → turn off (low-battery notice);
    ///  - battery disallowed → turn off (unplugged notice);
    ///  - otherwise keep running (allowed on battery).
    func applyLidPowerPolicy() {
        guard !isOnExternalPower else { return }
        let wasActive = isPreventingLidSleep || lidWorkerRunning
            || desiredLidSleep || lidInFlightWrite
        guard wasActive else { return }
        let isLow = batteryPercentage <= Self.lowBatteryThreshold
        if autoDisablesLidSleepOnLowBattery && isLow {
            requestLidState(false)
            showNotice(.turnedOffLowBattery)
        } else if !allowsLidSleepOnBattery {
            requestLidState(false)
            showNotice(.turnedOffUnplugged)
        }
    }

    // MARK: - Helper probing / residual recovery

    private func probeHelperAndRecover() {
        guard !isStopped, isHelperReady else {
            if !isHelperReady { helperCapability = .unavailable }
            return
        }
        helperCapability = .detecting
        Task { [weak self] in
            guard let self else { return }
            do {
                let version = try await self.client.protocolVersion()
                guard !self.isStopped else { return }
                self.helperCapability =
                    version < PowerHelperProtocolVersion.disableSleep ? .needsUpdate : .available
            } catch {
                guard !self.isStopped else { return }
                // A helper that answers readiness but cannot name a version is a
                // pre-handshake (old) helper: treat it as needing an update.
                self.helperCapability = self.isHelperReady ? .needsUpdate : .unavailable
            }
            await self.recoverResidualIfOwned()
            if self.lidPendingRecovery {
                self.startLidWorkerIfNeeded()
            }
        }
    }

    /// Only clears `disablesleep` when *we* set it and it is still on. A value
    /// the user set through another tool is left untouched.
    private func recoverResidualIfOwned() async {
        // Residual cleanup is for a leftover value, never for a toggle the user
        // is intentionally holding on. Without this guard a readiness blip
        // during an active session would silently turn lid sleep back off.
        guard !isPreventingLidSleep, !desiredLidSleep,
              !lidWorkerRunning, !lidInFlightWrite else { return }
        guard ownership.ownsDisableSleep,
              helperReadiness.isReady,
              helperCapability.supportsDisableSleep,
              helperCapability != .needsUpdate else { return }
        guard let current = try? await client.readDisableSleep() else { return }
        if !current {
            ownership.ownsDisableSleep = false
            lidPendingRecovery = false
            return
        }
        guard let observed = try? await client.setDisableSleep(false) else { return }
        if observed == false {
            ownership.ownsDisableSleep = false
            isPreventingLidSleep = false
            lidPendingRecovery = false
        }
    }

    // MARK: - Notices

    /// Best-effort list of app names holding a sleep-preventing power assertion.
    /// macOS does not record who set `disablesleep`, so this is only a hint.
    nonisolated static func systemLidSleepAssertionOwners() -> [String] {
        var assertionRef: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&assertionRef) == kIOReturnSuccess,
              let cf = assertionRef?.takeRetainedValue() else { return [] }
        let dict = cf as NSDictionary
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var names: [String] = []
        for case let key as NSNumber in dict.allKeys {
            let pid = pid_t(key.intValue)
            if pid == ownPID { continue }
            guard let assertions = dict[key] as? [[String: Any]] else { continue }
            let prevents = assertions.contains { item in
                (item[kIOPMAssertionTypeKey as String] as? String)?.contains("Prevent") == true
            }
            guard prevents else { continue }
            if let name = NSRunningApplication(processIdentifier: pid)?.localizedName,
               !name.isEmpty {
                names.append(name)
            }
        }
        var seen = Set<String>()
        var unique: [String] = []
        for name in names where !seen.contains(name) {
            seen.insert(name)
            unique.append(name)
        }
        return Array(unique.prefix(3))
    }

    private func showNotice(_ value: SleepControlNotice) {
        notice = value
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}
