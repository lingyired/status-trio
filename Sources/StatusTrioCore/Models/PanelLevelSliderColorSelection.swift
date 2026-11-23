import Foundation

/// How the status panel's level sliders (volume, brightness, microphone) are
/// filled (#359).
///
/// `.automatic` follows the label colour: white on a dark panel, black on a
/// light one. `.custom` stores the colour the user picked. The stored raw value
/// stays hand-parseable, and a corrupted preference falls back to `.automatic`
/// so an upgrade never changes the panel.
enum PanelLevelSliderColorSelection: Equatable, Hashable, Sendable {
    case automatic
    case custom(IconRGBA)

    static let `default` = PanelLevelSliderColorSelection.automatic

    var isAutomatic: Bool {
        if case .automatic = self { return true }
        return false
    }

    /// The custom colour, when the user picked one.
    var customColor: IconRGBA? {
        if case let .custom(color) = self { return color }
        return nil
    }
}

extension PanelLevelSliderColorSelection {
    var storageValue: String {
        switch self {
        case .automatic:
            "automatic"
        case .custom(let color):
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
