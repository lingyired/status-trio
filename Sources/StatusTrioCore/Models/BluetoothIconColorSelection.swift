import Foundation

/// How the middle Bluetooth glyph is coloured (#275).
///
/// `.systemBlue` keeps the historical Bluetooth blue. `.primary` follows the
/// menu bar's adaptive label colour (black on light bars, white on dark ones).
/// `.custom` stores the colour the picker reported. The stored raw value is kept
/// hand-parseable so a corrupted preference falls back to the blue default.
enum BluetoothIconColorSelection: Equatable, Hashable, Sendable {
    case systemBlue
    case primary
    case custom(BatteryStatusColorComponents)

    static let `default` = BluetoothIconColorSelection.systemBlue

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    /// The custom colour the picker should start from.
    var customComponents: BatteryStatusColorComponents? {
        if case let .custom(components) = self { return components }
        return nil
    }
}

extension BluetoothIconColorSelection {
    var storageValue: String {
        switch self {
        case .systemBlue:
            "blue"
        case .primary:
            "primary"
        case .custom(let components):
            "custom:\(components.hue),\(components.saturation),\(components.brightness)"
        }
    }

    init(storageValue: String) {
        if storageValue == "primary" {
            self = .primary
            return
        }
        if storageValue == "blue" {
            self = .systemBlue
            return
        }
        if storageValue.hasPrefix("custom:") {
            let parts = storageValue.dropFirst("custom:".count).split(separator: ",")
            if parts.count == 3,
               let hue = Double(parts[0]),
               let saturation = Double(parts[1]),
               let brightness = Double(parts[2]),
               hue.isFinite, saturation.isFinite, brightness.isFinite {
                self = .custom(BatteryStatusColorComponents(
                    hue: hue,
                    saturation: saturation,
                    brightness: brightness
                ))
                return
            }
        }
        self = .default
    }
}
