import Foundation

/// Turns Low Power Mode on automatically when the battery drops below the
/// existing low-battery threshold while the Mac runs on battery (issue #246).
///
/// The threshold is the same "low battery threshold" the battery icon colours
/// already use (`SettingsStore.batteryCriticalThreshold`), so there is one
/// number for both behaviours rather than a second setting to keep in sync.
///
/// The automation fires at most once per low-battery cycle. A cycle starts when
/// the battery falls below the threshold while on battery and ends when the Mac
/// is back on power or the battery is at or above the threshold. Without that
/// bound, a user who turns Low Power Mode back off below the threshold would
/// immediately have it switched on again.
@MainActor
final class LowPowerAutoEnableController {
    private(set) var didAutoEnableThisCycle = false

    /// Evaluates one battery snapshot. Returns `true` when the caller should
    /// write Low Power Mode on; `false` means there is nothing to do.
    ///
    /// - Parameters:
    ///   - battery: The current battery snapshot.
    ///   - threshold: The low-battery percentage, 0...100.
    ///   - isEnabled: Whether the user turned the automation on, together with
    ///     the helper-backed control it needs.
    ///   - isHelperReady: Whether the privileged helper can actually serve the
    ///     write. Defaulted for the cycle-focused unit tests; the store always
    ///     passes the helper's real readiness.
    func evaluate(
        battery: BatteryStatus,
        threshold: Double,
        isEnabled: Bool,
        isHelperReady: Bool = true
    ) -> Bool {
        guard updateCycle(battery: battery, threshold: threshold, isEnabled: isEnabled) else { return false }
        // The helper readiness is a precondition for acting, not part of the
        // battery cycle: without it this snapshot cannot write, so the cycle
        // stays unconsumed and may still fire once when the helper is ready.
        guard isHelperReady else { return false }
        guard !didAutoEnableThisCycle else { return false }

        // Consume the cycle even when the mode is already on: the user's manual
        // change must not be overridden for the rest of this battery cycle.
        didAutoEnableThisCycle = true
        return !battery.isLowPowerMode
    }

    func updateCycle(battery: BatteryStatus, threshold: Double, isEnabled: Bool) -> Bool {
        guard isEnabled, !battery.isConnectedToPower else {
            reset()
            return false
        }
        // An unknown reading must neither enter nor end the current cycle.
        guard battery.isPresent, battery.rawPercentage != nil else { return false }
        guard Double(battery.percentage) < threshold else {
            reset()
            return false
        }
        return true
    }

    /// Re-arms the automation, used when the feature is turned off and the next
    /// enable should be treated as a fresh intent.
    func reset() {
        didAutoEnableThisCycle = false
    }
}
