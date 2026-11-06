import Foundation

/// Every reason the "Charge to Full Now" control cannot start right now.
///
/// The list is produced by `ChargeToFullNowController.hiddenReasons(...)` for
/// the Settings pane, which shows each applicable reason as explanatory text
/// while the toggle is on. It is intentionally read-only: deriving the reasons
/// never writes a charge limit, starts an operation or polls the system.
enum ChargeToFullNowHiddenReason: Equatable, Sendable {
    case unsupportedSystem
    case unsupportedArchitecture
    case frameworkUnavailable
    case apiUnavailable
    case mclUnsupported
    case noBattery
    case batterySectionHidden
    case disconnectedFromPower
    case fullyCharged
    case stateReadFailed
    case noActiveChargeLimit
    case unrecognizedChargeLimitState
    case restoredLimit(Int)
}
