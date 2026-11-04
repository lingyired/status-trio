import Foundation

/// Pure, hardware-free decision engine shared by the Intel (`BCLM`) and Apple
/// Silicon (inhibit) backends.
///
/// It answers one question on every event — "should charging be allowed right
/// now?" — from injected battery level, AC state and the user's ceiling. All
/// I/O (SMC reads/writes, sleep/wake notifications, timers) is external; this
/// type only decides. That keeps the hysteresis, plug/unplug and sleep/wake
/// edge cases fully unit-testable (plan §9 `ChargeLimitEngineTests`).
struct LegacyChargeLimitEngine: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        /// Nothing to do; current gate already matches the desired state.
        case none
        /// Allow the battery to charge.
        case allowCharging
        /// Stop the battery from charging.
        case inhibitCharging
    }

    /// The user's requested ceiling (80–100).
    let limit: Int
    /// Hysteresis band in percentage points (plan suggests 2%).
    let hysteresis: Int

    init(limit: Int, hysteresis: Int = LegacyChargeLimitValidator.hysteresis) {
        self.limit = limit
        self.hysteresis = hysteresis
    }

    /// Decides what to do for a fresh battery reading.
    ///
    /// Semantics (matching the plan):
    /// - At/above the ceiling: inhibit.
    /// - Below the ceiling by more than the hysteresis band: allow.
    /// - Inside the hysteresis band: keep whatever the current gate is, so we
    ///   do not flap on a 1–2% wobble.
    ///
    /// `currentlyAllowing` is the last gate state we actually wrote (or nil if
    /// unknown, in which case a definite decision is required).
    func decide(
        batteryLevel: Int,
        isOnAC: Bool,
        currentlyAllowing: Bool?
    ) -> Action {
        // Without power there is nothing to gate; do not pretend to inhibit.
        guard isOnAC else {
            return currentlyAllowing == false ? .allowCharging : .none
        }

        // At or above the ceiling: always inhibit.
        if batteryLevel >= limit {
            return currentlyAllowing == false ? .none : .inhibitCharging
        }

        // Well below the ceiling: allow charging.
        if batteryLevel <= limit - hysteresis {
            return currentlyAllowing == true ? .none : .allowCharging
        }

        // Inside the hysteresis band: hold the current gate, unless unknown.
        if let currentlyAllowing {
            return .none
        }
        return .allowCharging
    }

    /// Whether a one-time "charge to full" should keep charging.
    ///
    /// A temporary override ignores the ceiling until the battery is full;
    /// the caller cancels explicitly or on reaching 100%.
    static func temporaryFullShouldContinue(batteryLevel: Int) -> Bool {
        batteryLevel < 100
    }
}

/// A tiny event-driven reducer around the engine that also tracks the last gate
/// it wrote, so the same logic can be replayed on wake / replug / sleep events.
struct LegacyChargeLimitReducer: Equatable, Sendable {
    private(set) var lastAllowed: Bool?

    mutating func apply(
        _ engine: LegacyChargeLimitEngine,
        batteryLevel: Int,
        isOnAC: Bool
    ) -> LegacyChargeLimitEngine.Action {
        let action = engine.decide(
            batteryLevel: batteryLevel,
            isOnAC: isOnAC,
            currentlyAllowing: lastAllowed
        )
        switch action {
        case .allowCharging: lastAllowed = true
        case .inhibitCharging: lastAllowed = false
        case .none: break
        }
        return action
    }

    /// After sleep/wake we no longer trust the previous gate and must re-evaluate.
    mutating func resetForWake() {
        lastAllowed = nil
    }

    /// Re-applies the desired state after a replug event.
    mutating func replug() {
        lastAllowed = nil
    }
}