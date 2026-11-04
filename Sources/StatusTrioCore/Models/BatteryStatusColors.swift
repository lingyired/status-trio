import Foundation

/// One drawable state role that can carry a user-chosen colour.
///
/// This stays separate from `IconColorRole` because `IconColorRole` is the
/// renderer's resolution vocabulary (it also carries `.primary`, `.inactive`
/// and `.bluetooth`, which are not customisable), while this type is the
/// settings-facing identity of a customisable battery state.
enum BatteryStatusColorRole: String, CaseIterable, Hashable, Sendable {
    case charging
    case lowPower
    case critical
}

/// The colour a user picked for one role.
///
/// `.system` means "use the system semantic colour" and is the default, so an
/// upgrade never changes an existing icon. `.preset` names one of the built-in
/// palettes, which adapts to the menu bar's light/dark appearance by itself.
/// `.custom` stores the colour the picker reported and applies it unchanged to
/// both appearances, apart from the visibility floor.
enum BatteryStatusColorSelection: Equatable, Hashable, Sendable {
    case system
    case preset(BatteryStatusColorPreset)
    case custom(BatteryStatusColorComponents)

    var isSystem: Bool {
        if case .system = self { return true }
        return false
    }
}

/// Built-in alternatives to the system colour.
///
/// The concrete values live in `BatteryStatusColorResolver` so this model layer
/// stays free of AppKit; the raw values are persisted, so they must not change.
enum BatteryStatusColorPreset: String, CaseIterable, Hashable, Sendable {
    case mint
    case sky
    case lavender
    case amber
    case rose
    case slate
}

/// An HSB triple.
///
/// Stored as three components rather than RGB or a hex string so the picker and
/// the persisted value stay in the colour model the user edited. Presets are
/// fixed HSB pairs; a custom colour is mixed in RGB only when the visibility
/// floor needs it.
struct BatteryStatusColorComponents: Equatable, Hashable, Sendable {
    let hue: Double
    let saturation: Double
    let brightness: Double

    init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = Self.clamp(hue)
        self.saturation = Self.clamp(saturation)
        self.brightness = Self.clamp(brightness)
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

/// The per-role custom colour configuration, carried by `BatteryIconOptions`
/// and from there into the scene and the render environment, so the menu bar,
/// the Dock, the popover and every settings preview resolve one shared answer.
struct BatteryStatusColors: Equatable, Hashable, Sendable {
    var charging: BatteryStatusColorSelection
    var lowPower: BatteryStatusColorSelection
    var critical: BatteryStatusColorSelection

    init(
        charging: BatteryStatusColorSelection = .system,
        lowPower: BatteryStatusColorSelection = .system,
        critical: BatteryStatusColorSelection = .system
    ) {
        self.charging = charging
        self.lowPower = lowPower
        self.critical = critical
    }

    static let standard = BatteryStatusColors()

    /// Whether any role overrides the system colour. Used by the settings page
    /// to decide if the "follow system" reset is worth offering.
    var hasOverrides: Bool {
        !charging.isSystem || !lowPower.isSystem || !critical.isSystem
    }

    func selection(for role: BatteryStatusColorRole) -> BatteryStatusColorSelection {
        switch role {
        case .charging: charging
        case .lowPower: lowPower
        case .critical: critical
        }
    }

    mutating func setSelection(_ selection: BatteryStatusColorSelection, for role: BatteryStatusColorRole) {
        switch role {
        case .charging: charging = selection
        case .lowPower: lowPower = selection
        case .critical: critical = selection
        }
    }
}

// MARK: - Persistence

extension BatteryStatusColorSelection {
    /// A compact defaults value. Kept deliberately parseable-by-hand so a
    /// corrupted preference falls back to `.system` instead of trapping.
    var storageValue: String {
        switch self {
        case .system:
            "system"
        case .preset(let preset):
            "preset:\(preset.rawValue)"
        case .custom(let components):
            "custom:\(components.hue),\(components.saturation),\(components.brightness)"
        }
    }

    init(storageValue: String) {
        if storageValue == "system" {
            self = .system
            return
        }
        if storageValue.hasPrefix("preset:"),
           let preset = BatteryStatusColorPreset(rawValue: String(storageValue.dropFirst("preset:".count))) {
            self = .preset(preset)
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
        self = .system
    }
}
