import Foundation

extension BatteryGapContent {
    /// The ring-top accessory that draws this gap content, shared by the system
    /// battery ring and the hardware ring's `chargingIndicator` top content
    /// (#315 / #361).
    ///
    /// Both surfaces derive their gap content from the same per-state
    /// `BatteryTopMarker` choices, so mapping the content here keeps their bolt,
    /// plug and percentage markers — and the `.empty` "hidden" choice — in sync.
    /// `.empty` returns `nil`, which closes the top gap instead of leaving a
    /// blank slot; a percentage also renders nothing on a battery-less Mac.
    func ringAccessory(battery: BatteryStatus, scale: Double) -> RingAccessoryState? {
        switch self {
        case .empty:
            return nil
        case .percentage:
            guard battery.isPresent else { return nil }
            return .text(IconTextState(text: "\(battery.percentage)", color: .primary, scale: scale))
        case .bolt:
            return .symbol(IconSymbolState(source: .primitive(.bolt), color: .primary, scale: scale))
        case .plug:
            return .symbol(IconSymbolState(source: .primitive(.plug), color: .primary, scale: scale))
        }
    }
}
