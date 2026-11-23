import Foundation

/// The three mutually exclusive states of the system Power Mode switch.
///
/// macOS exposes them as one switch: Automatic, Low Power Mode, High Power
/// Mode. The app used to show Low and High as two independent toggles, which
/// could not express "Automatic" and left the two switches able to disagree
/// while the daemon cleared one behind the other's back. This value is the
/// single selection the battery details page presents.
enum PowerModeSelection: CaseIterable, Hashable, Sendable {
    case automatic
    case low
    case high
}

/// The writes needed to move from the observed state to a selected state.
struct PowerModeTransition: Equatable, Sendable {
    var turnOffLow = false
    var turnOnLow = false
    var turnOffHigh = false
    var turnOnHigh = false

    static let none = PowerModeTransition()

    var isNoOp: Bool {
        self == .none
    }
}

/// Pure mapping between the observed controllers and the picker, kept out of
/// the view so the mutual exclusion can be tested without SwiftUI.
enum PowerModeSelectionLogic {
    /// What the picker shows. High wins over Low only because the two are
    /// mutually exclusive; if both read as on, the last observed write was
    /// High and the daemon is still settling.
    static func selection(isLow: Bool, isHigh: Bool) -> PowerModeSelection {
        if isHigh { return .high }
        if isLow { return .low }
        return .automatic
    }

    /// The writes needed to reach `target`.
    ///
    /// The daemon clears the other mode itself, so a transition never issues
    /// that second write: one request per user choice keeps the last-write
    /// wins ordering intact.
    static func transition(
        to target: PowerModeSelection,
        isLow: Bool,
        isHigh: Bool
    ) -> PowerModeTransition {
        var transition = PowerModeTransition()
        switch target {
        case .automatic:
            transition.turnOffLow = isLow
            transition.turnOffHigh = isHigh
        case .low:
            transition.turnOnLow = !isLow
        case .high:
            transition.turnOnHigh = !isHigh
        }
        return transition
    }
}
