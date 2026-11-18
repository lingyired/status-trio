import AppKit

/// Resolves the middle Bluetooth glyph's colour selection into a drawable
/// colour. Blue keeps the existing light/dark Bluetooth blue; primary uses the
/// menu bar's label ink; a custom colour is applied as-is unless the shared
/// visibility floor lifts it.
enum BluetoothIconColorResolver {
    static func resolve(
        _ selection: BluetoothIconColorSelection,
        foreground: CGColor,
        darkAppearance: Bool
    ) -> CGColor {
        let baseline = StatusIconRenderer.bluetoothColor(foreground: foreground)
        switch selection {
        case .systemBlue:
            return baseline
        case .primary:
            return foreground
        case .custom(let components):
            return BatteryStatusColorResolver.resolve(
                selection: .custom(components),
                systemBaseline: baseline,
                darkAppearance: darkAppearance
            ).color
        }
    }

    /// The status panel's Bluetooth title icon uses the configured colour only
    /// while the radio is on (#352). Every other power state returns `nil` so the
    /// caller draws secondary ink, matching the menu bar's on/off semantics.
    static func summarySelection(
        for power: BluetoothRadioPower,
        configured: BluetoothIconColorSelection
    ) -> BluetoothIconColorSelection? {
        power == .on ? configured : nil
    }
}
