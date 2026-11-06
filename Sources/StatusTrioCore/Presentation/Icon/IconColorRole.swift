enum IconColorRole: Equatable, Hashable, Sendable {
    case primary
    case inactive
    case critical
    case lowPower
    /// High Power Mode ring colour (#235).
    case highPower
    case powered
    /// The volume footer's Bluetooth tint.
    case bluetooth
    /// The middle Bluetooth glyph, which may carry a user-chosen colour (#275).
    case bluetoothIcon
}
