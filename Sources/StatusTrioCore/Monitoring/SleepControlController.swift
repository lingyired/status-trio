import Combine
import Foundation
import IOKit.pwr_mgt
import PowerHelperProtocol

/// The timer choices offered next to each keep-awake toggle (#295).
enum SleepTimerDuration: String, CaseIterable, Identifiable, Sendable {
    case thirtyMinutes
    case oneHour
    case twoHours
    case unlimited

    var id: Self { self }

    /// `nil` means "no limit".
    var timeInterval: TimeInterval? {
        switch self {
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .twoHours: 2 * 60 * 60
        case .unlimited: nil
        }
    }

    var localizationKey: LocalizationKey {
        switch self {
        case .thirtyMinutes: .quickActionsTimerThirtyMinutes
        case .oneHour: .quickActionsTimerOneHour
        case .twoHours: .quickActionsTimerTwoHours
        case .unlimited: .quickActionsTimerUnlimited
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

    @Published private(set) var isPreventingDisplaySleep = false
    @Published private(set) var displayTimer: SleepTimerDuration = .unlimited
    @Published private(set) var displayExpiry: Date?
    @Published private(set) var isPreventingLidSleep = false
    @Published private(set) var lidTimer: SleepTimerDuration = .unlimited
    @Published private(set) var lidExpiry: Date?
    @Published private(set) var isApplyingLidSleep = false
    @Published private(set) var helperNeedsUpdate = false
    @Published private(set) var isHelperReady = false
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
    private var lidGeneration: UInt64 = 0

    init(
        assertion: any DisplaySleepAsserting = IOPMDisplaySleepAssertion(),
        client: any DisableSleepClienting = XPCPrivilegedHighPowerClient(),
        helperReadiness: any HelperReadinessProviding = SharedHelperReadiness(),
        ownership: any SleepOwnershipStoring = UserDefaultsSleepOwnershipStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.assertion = assertion
        self.client = client
        self.helperReadiness = helperReadiness
        self.ownership = ownership
        self.now = now
        self.isHelperReady = helperReadiness.isReady
    }

    /// Why the lid toggle is unavailable, or `nil` when it can be turned on.
    var lidUnavailableReason: LidSleepUnavailableReason? {
        if isPreventingLidSleep { return nil }
        if helperNeedsUpdate { return .helperNeedsUpdate }
        if !isHelperReady { return .helperUnavailable }
        if !isOnExternalPower { return .requiresPower }
        return nil
    }

    var canEnableLidSleep: Bool { lidUnavailableReason == nil }

    /// Whether quitting must first restore `disablesleep 0`.
    var needsTerminationCleanup: Bool {
        isPreventingLidSleep || ownership.ownsDisableSleep
    }

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
                        self.helperNeedsUpdate = false
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
        if !isStopped {
            stop()
        }
        guard ownership.ownsDisableSleep || isPreventingLidSleep else { return }
        guard helperReadiness.isReady, !helperNeedsUpdate else { return }
        guard let observed = try? await client.setDisableSleep(false) else { return }
        if !observed {
            ownership.ownsDisableSleep = false
            isPreventingLidSleep = false
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

    // MARK: - Lid sleep (helper-backed)

    func setLidSleep(_ enabled: Bool) {
        guard !isStopped, !isApplyingLidSleep, enabled != isPreventingLidSleep else { return }
        if enabled && !canEnableLidSleep {
            return
        }
        applyLidSleep(enabled)
    }

    func setLidTimer(_ duration: SleepTimerDuration) {
        lidTimer = duration
        guard isPreventingLidSleep else { return }
        scheduleLidAutoOff()
    }

    private func applyLidSleep(_ enabled: Bool) {
        isApplyingLidSleep = true
        lastError = nil
        lidGeneration &+= 1
        let generation = lidGeneration
        Task { [weak self] in
            guard let self else { return }
            do {
                let observed = try await self.client.setDisableSleep(enabled)
                guard generation == self.lidGeneration else { return }
                if observed == enabled {
                    self.isPreventingLidSleep = enabled
                    self.ownership.ownsDisableSleep = enabled
                    if enabled {
                        self.scheduleLidAutoOff()
                    } else {
                        self.cancelLidTimer()
                    }
                } else {
                    self.lastError = enabled
                        ? "The helper did not apply lid sleep prevention."
                        : "The helper did not clear lid sleep prevention."
                }
            } catch {
                guard generation == self.lidGeneration else { return }
                self.lastError = error.localizedDescription
            }
            if generation == self.lidGeneration {
                self.isApplyingLidSleep = false
            }
        }
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
        setLidSleep(false)
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
        guard isPreventingLidSleep else { return }
        guard !onExternalPower else { return }
        let isLow = battery.isPresent && battery.percentage <= Self.lowBatteryThreshold
        setLidSleep(false)
        showNotice(isLow ? .turnedOffLowBattery : .turnedOffUnplugged)
    }

    // MARK: - Helper probing / residual recovery

    private func probeHelperAndRecover() {
        guard !isStopped, isHelperReady else { return }
        Task { [weak self] in
            guard let self else { return }
            if let version = try? await self.client.protocolVersion() {
                self.helperNeedsUpdate = version < PowerHelperProtocolVersion.disableSleep
            }
            await self.recoverResidualIfOwned()
        }
    }

    /// Only clears `disablesleep` when *we* set it and it is still on. A value
    /// the user set through another tool is left untouched.
    private func recoverResidualIfOwned() async {
        guard ownership.ownsDisableSleep,
              helperReadiness.isReady,
              !helperNeedsUpdate else { return }
        guard let current = try? await client.readDisableSleep() else { return }
        if !current {
            ownership.ownsDisableSleep = false
            return
        }
        guard let observed = try? await client.setDisableSleep(false) else { return }
        if !observed {
            ownership.ownsDisableSleep = false
            isPreventingLidSleep = false
        }
    }

    // MARK: - Notices

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
