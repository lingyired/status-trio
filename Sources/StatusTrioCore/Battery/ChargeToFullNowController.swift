import Combine
import Foundation

struct ChargeToFullNowDemand: Equatable, Sendable {
    let settingEnabled: Bool
    let popoverVisible: Bool
    let batterySectionVisible: Bool
    let battery: BatteryStatus

    var showsSurface: Bool {
        settingEnabled
            && popoverVisible
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
    case cancelConfirmationRequired(limit: Int, usedFallback: Bool)
    case cancelPending
    case cancelling
    case cancelFailed(message: String?)
    case cancelSucceeded(limit: Int, usedFallback: Bool)

    var showsButton: Bool {
        switch self {
        case .hidden, .unavailable:
            false
        case .available,
             .applying,
             .chargingToFull,
             .failed,
             .cancelConfirmationRequired,
             .cancelPending,
             .cancelling,
             .cancelFailed,
             .cancelSucceeded:
            true
        }
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
    private let now: () -> Date
    private var currentDemand: ChargeToFullNowDemand?
    private var session: ChargeToFullNowSession?
    private var sessionNeedsConfirmation = false
    private var isApplying = false
    private var isCancelling = false
    private var hasObservedTemporaryOverride = false

    init(
        backend: any BatteryChargeControlling,
        sessionStore: any ChargeToFullNowSessionStoring =
            VolatileChargeToFullNowSessionStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.backend = backend
        self.sessionStore = sessionStore
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
        if state.errorMessage != nil {
            if session != nil {
                sessionNeedsConfirmation = true
                publish(.cancelFailed(message: state.errorMessage))
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

        guard demand.canStartChargeToFull else {
            publish(.hidden)
            return
        }
        publish(state.hasActiveChargeLimit ? .available : .hidden)
    }

    func clearDemand() {
        currentDemand = nil
        if !isApplying, !isCancelling {
            publish(.hidden)
        }
    }

    func performPrimaryAction() {
        switch presentation {
        case .chargingToFull, .cancelConfirmationRequired, .cancelPending, .cancelFailed:
            requestCancelChargeToFullNow()
        case .available, .failed, .cancelSucceeded:
            requestChargeToFullNow()
        case .hidden, .applying, .cancelling, .unavailable:
            break
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
              let activeSession = session,
              let requestedDemand = currentDemand,
              requestedDemand.showsSurface,
              capability.isAvailable else {
            return
        }

        let state = backend.readState()
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

        let target = validatedLimit(
            state.reportedChargeLimit ?? activeSession.originalLimit,
            in: state
        )
        let limit = target ?? 80
        let usedFallback = target == nil
        let needsConfirmation = sessionNeedsConfirmation
            || state.errorMessage != nil
            || usedFallback
            || (state.errorMessage == nil
                && !state.indicatesTemporaryOverride)

        if needsConfirmation,
           presentation != .cancelConfirmationRequired(
               limit: limit,
               usedFallback: usedFallback
           ) {
            publish(
                .cancelConfirmationRequired(
                    limit: limit,
                    usedFallback: usedFallback
                )
            )
            return
        }

        isCancelling = true
        publish(.cancelling)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await backend.restoreChargeLimit(to: limit)
            isCancelling = false
            let verification = backend.readState()
            let verified = result.succeeded
                && verification.hasActiveChargeLimit
                && verification.reportedChargeLimit == limit

            if verified {
                clearSession()
            }

            guard let currentDemand,
                  currentDemand.showsSurface else {
                publish(.hidden)
                return
            }

            if verified {
                publish(
                    .cancelSucceeded(
                        limit: limit,
                        usedFallback: usedFallback
                    )
                )
            } else {
                publish(
                    .cancelFailed(
                        message: result.errorMessage
                            ?? verification.errorMessage
                            ?? "PowerUI did not confirm the restored charge limit."
                    )
                )
            }
        }
    }

    private func validatedLimit(
        _ candidate: Int?,
        in state: ChargeToFullNowDeviceState
    ) -> Int? {
        guard let candidate, (80..<100).contains(candidate) else {
            return nil
        }
        if !state.availableChargeLimits.isEmpty {
            return state.availableChargeLimits.contains(candidate) ? candidate : nil
        }
        return [80, 85, 90, 95].contains(candidate) ? candidate : nil
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
