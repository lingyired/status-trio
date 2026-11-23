import Foundation

/// The Bluetooth panel title glyph follows the same convention as the Wi-Fi
/// summary row (#352): system ink while the radio is on, secondary ink when it
/// is off or its state is unknown. The menu bar's middle glyph keeps its own
/// configurable colour (#275) and is unaffected.
enum BluetoothTitleTintResolver {
    static func tint(for power: BluetoothRadioPower) -> PanelTint {
        power == .on ? .primary : .secondary
    }
}
