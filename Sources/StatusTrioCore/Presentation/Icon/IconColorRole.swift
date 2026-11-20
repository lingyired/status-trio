import Foundation

enum IconColorRole: Equatable, Hashable, Sendable {
    static let inactiveTrackOpacity = 0.22

    case primary
    /// Plain battery discharge, not connected to power (#357). Resolves to the
    /// user-chosen discharging colour; `.system` keeps the label colour.
    case discharging
    case inactive
    case critical
    case lowPower
    /// High Power Mode ring colour (#235).
    case highPower
    case powered
    /// The volume footer's Bluetooth tint.
    case bluetooth
    case custom(IconRGBA)
    /// The middle Bluetooth glyph, which may carry a user-chosen colour (#275).
    case bluetoothIcon
}
