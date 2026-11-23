import Foundation

/// The summary row's power switch state. `nil` on `PanelSummaryState` means the
/// row is read-only (no configured system VPN, or proxy-only).
struct VPNPowerPresentation: Equatable, Sendable {
    let isOn: Bool
    let isChanging: Bool
    let canSetPower: Bool
    let failureMessage: String?
    let turnOnHelp: String
    let turnOffHelp: String
    let changingHelp: String
}
