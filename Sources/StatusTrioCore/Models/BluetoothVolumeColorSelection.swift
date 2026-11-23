import Foundation

/// The colour of the Bluetooth audio volume indicator.
///
/// Replaces the old boolean "use blue" switch. `.automatic` follows the normal
/// primary colour (the pre-existing behaviour when the switch was off); a custom
/// colour is picked from the shared preset palette or the system picker. The
/// stored textual value keeps the preference hand-parseable and falls back to
/// `.automatic` on corruption so an upgrade never changes the icon.
enum BluetoothVolumeColorSelection: Equatable, Hashable, Sendable {
    case automatic
    case custom(IconRGBA)

    static let `default`: BluetoothVolumeColorSelection = .automatic

    /// The blue the old "use blue" switch drew, used to migrate installs that had
    /// it enabled onto the blue preset (sky, dark appearance).
    static let legacyBlue = IconRGBA(red: 0.255, green: 0.6715, blue: 0.85, alpha: 1)

    var isAutomatic: Bool {
        if case .automatic = self { return true }
        return false
    }

    var customColor: IconRGBA? {
        if case let .custom(color) = self { return color }
        return nil
    }
}

extension BluetoothVolumeColorSelection {
    var storageValue: String {
        switch self {
        case .automatic: "automatic"
        case let .custom(color):
            "custom:\(color.red),\(color.green),\(color.blue),\(color.alpha)"
        }
    }

    init(storageValue: String) {
        if storageValue == "automatic" {
            self = .automatic
            return
        }
        if storageValue.hasPrefix("custom:") {
            let parts = storageValue.dropFirst("custom:".count).split(separator: ",")
            if parts.count == 4,
               let red = Double(parts[0]), let green = Double(parts[1]),
               let blue = Double(parts[2]), let alpha = Double(parts[3]),
               [red, green, blue, alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) }) {
                self = .custom(IconRGBA(red: red, green: green, blue: blue, alpha: alpha))
                return
            }
        }
        self = .default
    }
}
