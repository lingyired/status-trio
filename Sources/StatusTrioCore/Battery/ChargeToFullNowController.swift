import Combine
import Foundation

struct ChargeToFullNowDemand: Equatable, Sendable {
    let popoverVisible: Bool
    let batterySectionVisible: Bool
    let battery: BatteryStatus

    /// Capability, panel visibility and live battery state decide whether the
    /// action may run. The Settings toggle does not participate: it only
    /// controls whether the summary card shows the row, while the battery
    /// details page always shows it when the action is applicable.
    var showsSurface: Bool {
        popoverVisible
            && batterySectionVisible
            && battery.isPresent
    }

    var canStartChargeToFull: Bool {
        showsSurface
            && battery.isConnectedToPower
            && !battery.isCharged
            && battery.percentage < 100
    }
}

enum ChargeToFullNowPresentation: Equatable, Sendable {
    case hidden
    case available
    case applying
    case chargingToFull
    case failed
    case unavailable
    case cancelConfirmationRequired(limit: Int)
    case cancelPending
    case cancelling
    case cancelFailed(reason: ChargeToFullNowFailure)
    /// An intermediate charge limit that differs from the configured target
    /// was read while cancelling. The user confirms before it is replaced.
    case cancelLimitChangedConfirmation(current: Int, target: Int)
    /// The configured limit is back. The action stays hidden while the battery
    /// finishes charging toward a sub-100 limit.
    case limitRestored(limit: Int)

    var showsButton: Bool {
        switch self {
        case .hidden, .unavailable, .limitRestored:
            false
        case .available,
             .applying,
             .chargingToFull,
             .failed,
             .cancelConfirmationRequired,
             .cancelPending,
             .cancelling,
             .cancelFailed,
             .cancelLimitChangedConfirmation:
            true
        }
    }

    var isRestoredLimit: Bool {
        if case .limitRestored = self {
            return true
        }
        return false
    }

    var isApplying: Bool {
        self == .applying
    }

    var isChargingToFull: Bool {
        self == .chargingToFull
    }

    var isCancelling: Bool {
        self == .cancelling
    }
}

@MainActor
final class ChargeToFullNowController: ObservableObject {
    @Published private(set) var presentation: ChargeToFullNowPresentation = .hidden

    var capability: ChargeToFullNowCapability {
        backend.capability
    }

    var isSettingAvailable: Bool {
        capability.isAvailable
    }

    private let backend: any BatteryChargeControlling
    private let sessionStore: any ChargeToFullNowSessionStoring
    /// The limit the user configured in Settings → Battery; 100 means "no
    /// limit". Cancel always restores this value instead of guessing a limit
    /// macOS may have removed from the persisted plist.
    private let restoreLimit: () -> Int
    /// When a managed charge limit is active, that limit (not the slider above)
    /// is the cancel target, so a temporary full charge resumes the managed
    /// policy instead of the legacy fixed restore value. Two sessions persist
    /// independently (`chargeToFullNow.session.v1` here, `managedChargeLimit.session.v1`
    /// in the managed controller); this closure is the single read of the
    /// managed policy and takes precedence whenever it returns non-nil.
    private let managedRestoreLimit: () -> Int?
    private let now: () -> Date
    private var currentDemand: ChargeToFullNowDemand?
    private var session: ChargeToFullNowSession?
    private var restoredLimit: RestoredLimitState?
    private var sessionNeedsConfirmation = false
    private var isApplying = false
    private var isCancelling = false
    private var hasObservedTemporaryOverride = false
    private var pendingLimitChange: PendingLimitChange?

    private struct PendingLimitChange {
        let currentLimit: Int
        let targetLimit: Int
    }

    private struct RestoredLimitState {
        let limit: Int
        let restoredAt: Date
        var hasObservedCharging: Bool
    }

    init(
        backend: any BatteryChargeControlling,
        sessionStore: any ChargeToFullNowSessionStoring =
            VolatileChargeToFullNowSessionStore(),
        restoreLimit: @escaping () -> Int = { 80 },
        managedRestoreLimit: @escaping () -> Int? = { nil },
        now: @escaping () -> Date = Date.init
    ) {
        self.backend = backend
        self.sessionStore = sessionStore
        self.restoreLimit = restoreLimit
        self.managedRestoreLimit = managedRestoreLimit
        self.now = now
        session = sessionStore.load()
        sessionNeedsConfirmation = session != nil
    }

    func update(_ demand: ChargeToFullNowDemand) {
        currentDemand = demand
        guard !isApplying, !isCancelling else { return }
        guard demand.showsSurface, capability.isAvailable else {
            publish(.hidden)
            return
        }

        let state = backend.readState()
        if var restored = restoredLimit {
            if demand.battery.isCharging {
                restored.hasObservedCharging = true
                restoredLimit = restored
            }
            if shouldHoldRestoredLimit(restored, demand: demand, state: state) {
                publish(.limitRestored(limit: restored.limit))
                return
            }
            restoredLimit = nil
        }

        // A confirmation is an explicit user step. Keep it across live battery
        // ticks; the next tap re-reads the state before any write anyway.
        switch presentation {
        case .cancelConfirmationRequired, .cancelLimitChangedConfirmation:
            return
        default:
            break
        }

        if state.errorMessage != nil {
            if session != nil {
                sessionNeedsConfirmation = true
                publish(.cancelFailed(reason: .unavailable))
            } else {
                publish(.unavailable)
            }
            return
        }

        if session != nil, state.hasActiveChargeLimit {
            if mayBeStaleActiveLimit(state) {
                publish(.chargingToFull)
                return
            }
            // A later valid active limit means the override was ended or
            // replaced, including by the user or another app. Never overwrite it.
            clearSession()
        }

        if session != nil {
            hasObservedTemporaryOverride =
                hasObservedTemporaryOverride || state.indicatesTemporaryOverride
            publish(.chargingToFull)
            return
        }

        // macOS can start the same temporary override from its own battery
        // menu. There is no session, but the configured restore limit makes the
        // same cancellation available. Once the battery is full, unplugged, or
        // already charged there is nothing left to charge to, so the row
        // disappears like it does for the native action.
        if demand.canStartChargeToFull, state.indicatesTemporaryOverride {
            publish(.chargingToFull)
            return
        }

        guard demand.canStartChargeToFull else {
            publish(.hidden)
            return
        }
        publish(state.hasActiveChargeLimit ? .available : .hidden)
    }

    func clearDemand() {
        currentDemand = nil
        pendingLimitChange = nil
        // Closing the panel ends the restored-limit notice; reopening shows
        // the live state instead of a stale "restored" row.
        restoredLimit = nil
        if !isApplying, !isCancelling {
            publish(.hidden)
        }
    }

    func performPrimaryAction() {
        switch presentation {
        case .chargingToFull, .cancelConfirmationRequired, .cancelPending,
             .cancelFailed, .cancelLimitChangedConfirmation:
            requestCancelChargeToFullNow()
        case .available, .failed:
            requestChargeToFullNow()
        case .hidden, .applying, .cancelling, .unavailable, .limitRestored:
            break
        }
    }

    /// Menu-bar quick action: perform the same start/cancel toggle as the panel
    /// button, but without requiring the panel to be open.
    ///
    /// It synthesizes a demand as if the battery section were visible, then
    /// reuses `update` + `performPrimaryAction` so all the capability, live-state
    /// and restore-limit logic stays in one place. Returns whether an action was
    /// actually available; callers fall back to the context menu when it is not,
    /// so an impossible quick action never becomes a silent no-op.
    @discardableResult
    func performQuickToggle(battery: BatteryStatus) -> Bool {
        guard capability.isAvailable else { return false }

        update(
            ChargeToFullNowDemand(
                popoverVisible: true,
                batterySectionVisible: true,
                battery: battery
            )
        )

        switch presentation {
        case .available, .failed, .chargingToFull:
            performPrimaryAction()
            return true
        case .hidden, .applying, .cancelling, .unavailable, .limitRestored,
             .cancelConfirmationRequired, .cancelPending, .cancelFailed,
             .cancelLimitChangedConfirmation:
            return false
        }
    }

    func requestChargeToFullNow() {
        guard !isApplying,
              !isCancelling,
              session == nil,
              let requestedDemand = currentDemand,
              requestedDemand.canStartChargeToFull,
              capability.isAvailable else {
            return
        }

        let state = backend.readState()
        if state.errorMessage != nil {
            publish(.unavailable)
            return
        }
        guard state.hasActiveChargeLimit else {
            publish(.hidden)
            return
        }

        let originalLimit = state.reportedChargeLimit
        isApplying = true
        publish(.applying)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await backend.chargeToFullNow()
            isApplying = false
            if result.succeeded {
                let accepted = ChargeToFullNowSession(
                    originalLimit: originalLimit,
                    acceptedAt: now()
                )
                session = accepted
                sessionNeedsConfirmation = false
                hasObservedTemporaryOverride = false
                sessionStore.save(accepted)
            }

            guard let currentDemand,
                  currentDemand.showsSurface else {
                publish(.hidden)
                return
            }
            publish(result.succeeded ? .chargingToFull : .failed)
        }
    }

    func requestCancelChargeToFullNow() {
        guard !isApplying,
              !isCancelling,
              let requestedDemand = currentDemand,
              requestedDemand.showsSurface,
              capability.isAvailable else {
            return
        }

        let state = backend.readState()
        let limit = clampedRestoreLimit()

        if let pending = pendingLimitChange {
            pendingLimitChange = nil
            beginRestore(
                limit: pending.targetLimit,
                expectedLimit: pending.currentLimit
            )
            return
        }

        if session != nil {
            if state.hasActiveChargeLimit {
                if mayBeStaleActiveLimit(state) {
                    publish(.cancelPending)
                    return
                }
                clearSession()
                publish(
                    requestedDemand.canStartChargeToFull
                        ? .available
                        : .hidden
                )
                return
            }

            let needsConfirmation = sessionNeedsConfirmation
                || state.errorMessage != nil
                || (state.errorMessage == nil
                    && !state.indicatesTemporaryOverride)

            if needsConfirmation,
               presentation != .cancelConfirmationRequired(limit: limit) {
                publish(.cancelConfirmationRequired(limit: limit))
                return
            }

            beginRestore(limit: limit, expectedLimit: session?.originalLimit)
            return
        }

        // No session: the temporary override was started by macOS itself, for
        // example from the system battery menu. The configured limit is the
        // restore target, so no guessed-value confirmation is needed.
        guard state.errorMessage == nil,
              state.indicatesTemporaryOverride else {
            publish(
                requestedDemand.canStartChargeToFull
                    && state.hasActiveChargeLimit
                    ? .available
                    : .hidden
            )
            return
        }
        beginRestore(limit: limit, expectedLimit: nil)
    }

    private func beginRestore(limit: Int, expectedLimit: Int?) {
        isCancelling = true
        publish(.cancelling)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await backend.restoreChargeLimit(
                to: limit,
                expectedLimit: expectedLimit
            )
            isCancelling = false
            let verification = backend.readState()
            let verified = result.succeeded
                && Self.restoreIsVerified(limit: limit, state: verification)

            if verified {
                clearSession()
                pendingLimitChange = nil
                restoredLimit = RestoredLimitState(
                    limit: limit,
                    restoredAt: now(),
                    hasObservedCharging: false
                )
            }

            guard let currentDemand,
                  currentDemand.showsSurface else {
                publish(.hidden)
                return
            }

            if verified {
                publish(.limitRestored(limit: limit))
                return
            }

            // With no recorded original limit, a different sub-100 limit was
            // read after the enable step. Ask once before replacing it with the
            // configured target instead of dead-ending on a value that rarely
            // matches.
            if expectedLimit == nil,
               result.failure == .limitChanged,
               let currentLimit = verification.reportedChargeLimit {
                pendingLimitChange = PendingLimitChange(
                    currentLimit: currentLimit,
                    targetLimit: limit
                )
                publish(
                    .cancelLimitChangedConfirmation(
                        current: currentLimit,
                        target: limit
                    )
                )
                return
            }

            let reason = result.failure
                ?? (result.succeeded ? .verificationFailed : .rejected)
            publish(.cancelFailed(reason: reason))
        }
    }

    /// The restored target must be stored as a sub-100 limit again. MCL can
    /// still be disengaged or primed for a moment right after the write, so
    /// every non-override shape counts; requiring `raw == 1` failed healthy
    /// restores.
    static func restoreIsVerified(
        limit: Int,
        state: ChargeToFullNowDeviceState
    ) -> Bool {
        guard state.errorMessage == nil else { return false }
        return state.mclEnabledRawValue != 3
            && state.reportedChargeLimit == limit
    }

    /// The restored limit stays visible while the system keeps charging toward
    /// it. The action comes back once the battery reaches the limit or the
    /// system stops charging before it.
    private func shouldHoldRestoredLimit(
        _ restored: RestoredLimitState,
        demand: ChargeToFullNowDemand,
        state: ChargeToFullNowDeviceState
    ) -> Bool {
        guard state.errorMessage == nil,
              state.mclEnabledRawValue != 3,
              state.reportedChargeLimit == restored.limit,
              demand.canStartChargeToFull,
              demand.battery.percentage < restored.limit else {
            return false
        }
        if restored.hasObservedCharging {
            return demand.battery.isCharging
        }
        // The system needs a moment to resume charging after the restore. Give
        // it a bounded grace period instead of keeping an inert row forever.
        return now().timeIntervalSince(restored.restoredAt) < 30
    }

    private func clampedRestoreLimit() -> Int {
        // Managed targets come from PowerUI's advertised choices, which need not
        // share the legacy restore slider's fixed five-percent steps.
        if let managed = managedRestoreLimit() { return min(100, max(80, managed)) }
        let requested = restoreLimit()
        let clamped = min(
            Int(SettingsStore.chargeToFullRestoreLimitRange.upperBound),
            max(Int(SettingsStore.chargeToFullRestoreLimitRange.lowerBound), requested)
        )
        return (clamped / 5) * 5
    }

    private func clearSession() {
        session = nil
        sessionNeedsConfirmation = false
        hasObservedTemporaryOverride = false
        sessionStore.clear()
    }

    private func mayBeStaleActiveLimit(
        _ state: ChargeToFullNowDeviceState
    ) -> Bool {
        guard let session,
              !hasObservedTemporaryOverride,
              state.reportedChargeLimit == session.originalLimit else {
            return false
        }
        // The measured override took up to 10 seconds to appear in PowerUI.
        // A bounded grace period is evaluated only on demand, with no timer.
        let elapsed = now().timeIntervalSince(session.acceptedAt)
        return (0..<15).contains(elapsed)
    }

    private func publish(_ next: ChargeToFullNowPresentation) {
        guard presentation != next else { return }
        presentation = next
    }
}
