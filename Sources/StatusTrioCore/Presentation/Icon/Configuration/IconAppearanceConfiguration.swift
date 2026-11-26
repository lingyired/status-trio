import Foundation

struct IconRGBA: Codable, Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let white = Self(red: 1, green: 1, blue: 1, alpha: 1)

    /// Converts the picker's HSB components into a drawable RGB colour. Used by
    /// the icon ring, which paints a concrete colour rather than carrying the
    /// appearance-dependent visibility floor the menu-bar glyph applies.
    static func hsb(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1) -> Self {
        func clamp(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
        let h = (clamp(hue) * 6).truncatingRemainder(dividingBy: 6)
        let s = clamp(saturation)
        let v = clamp(brightness)
        let sector = Int(floor(h))
        let f = h - floor(h)
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))
        let rgb: (Double, Double, Double) = switch sector % 6 {
        case 0: (v, t, p)
        case 1: (q, v, p)
        case 2: (p, v, t)
        case 3: (p, q, v)
        case 4: (t, p, v)
        default: (v, p, q)
        }
        return Self(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: clamp(alpha))
    }

    func normalized() -> Self {
        func component(_ value: Double, fallback: Double) -> Double {
            value.isFinite ? min(1, max(0, value)) : fallback
        }
        return Self(
            red: component(red, fallback: 1),
            green: component(green, fallback: 1),
            blue: component(blue, fallback: 1),
            alpha: component(alpha, fallback: 1)
        )
    }
}

enum IconSemanticColorRole: String, Codable, CaseIterable, Hashable, Sendable {
    case primary
    case inactive
    case critical
    case lowPower
    case powered
    /// Connected to power without charging (#389). Separate from `powered` so a
    /// slot using semantic overrides can colour the two states differently,
    /// matching the battery-status palette.
    case connected
    case bluetooth
}

enum SlotColorStyle: Codable, Equatable, Sendable {
    case automatic
    case fixed(IconRGBA)
    case semanticOverrides([IconSemanticColorRole: IconRGBA])

    func normalized() -> Self {
        switch self {
        case .automatic:
            return .automatic
        case let .fixed(color):
            return .fixed(color.normalized())
        case let .semanticOverrides(colors):
            return .semanticOverrides(colors.mapValues { $0.normalized() })
        }
    }
}

struct RingAppearance: Codable, Equatable, Sendable {
    var strokeScale: Double
    var color: SlotColorStyle

    static let classic = Self(strokeScale: RingStrokeStyle.regular.scale, color: .automatic)

    func normalized() -> Self {
        Self(strokeScale: Self.bounded(strokeScale, fallback: Self.classic.strokeScale), color: color.normalized())
    }

    private static func bounded(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? min(2.5, max(0.5, value)) : fallback
    }
}

struct CenterAppearance: Codable, Equatable, Sendable {
    var symbolScale: Double
    var effectiveSymbolScale: Double? = nil
    var normalizedPercentageScale: Double? = nil
    /// Explicit, source-independent visible-size percentage. Nil preserves legacy rendering.
    var normalizedSizePercentage: Double? = nil
    var color: SlotColorStyle

    static let classic = Self(symbolScale: BluetoothAudioIconOptions.defaultSymbolScale, color: .automatic)

    func normalized() -> Self {
        let normalizedEffectiveScale = effectiveSymbolScale.map { value in
            value.isFinite ? min(6, max(0.5, value)) : BluetoothAudioIconOptions.defaultSymbolScale
        }
        let normalizedPercentageScale = normalizedPercentageScale.map { value in
            value.isFinite
                ? min(IconCenterSizingPolicy.legacyPersistedPercentageRange.upperBound,
                      max(IconCenterSizingPolicy.legacyPersistedPercentageRange.lowerBound, value))
                : 1
        }
        let normalizedSizePercentage = normalizedSizePercentage.map { IconCenterSizingPolicy.normalizedPercentage($0) }
        return Self(
            symbolScale: symbolScale.isFinite ? min(3, max(1, symbolScale)) : Self.classic.symbolScale,
            effectiveSymbolScale: normalizedEffectiveScale,
            normalizedPercentageScale: normalizedPercentageScale,
            normalizedSizePercentage: normalizedSizePercentage,
            color: color.normalized()
        )
    }
}

struct FooterAppearance: Codable, Equatable, Sendable {
    var strokeScale: Double
    var color: SlotColorStyle

    static let classic = Self(strokeScale: RingStrokeStyle.regular.scale, color: .automatic)

    func normalized() -> Self {
        Self(
            strokeScale: strokeScale.isFinite ? min(IconStrokeSizingPolicy.persistedScaleRange.upperBound, max(IconStrokeSizingPolicy.persistedScaleRange.lowerBound, strokeScale)) : Self.classic.strokeScale,
            color: color.normalized()
        )
    }
}

struct IconAppearanceConfiguration: Codable, Equatable, Sendable {
    var outerRing: RingAppearance
    var center: CenterAppearance
    var footer: FooterAppearance
    /// The middle Bluetooth glyph colour (#275).
    var bluetoothIconColor: BluetoothIconColorConfiguration
    /// The marker style for the input-source centre (#297).
    var inputSourceMarkerStyle: InputSourceMarkerStyle
    /// The Bluetooth glyph scale, carried separately from the generic centre
    /// scale so a pinned glyph keeps its own size.
    var bluetoothSymbolScale: Double
    /// User colour overrides for battery status roles (#235 palette).
    var batteryStatusColors: BatteryStatusColorsConfiguration
    /// AirPods ring arc colours: left ear, right ear, and the single-arc view.
    /// Defaults keep the historical look (left blue, right/single primary).
    var airPodsLeftArcColor: BluetoothIconColorConfiguration
    var airPodsRightArcColor: BluetoothIconColorConfiguration
    var airPodsSingleArcColor: BluetoothIconColorConfiguration

    enum CodingKeys: String, CodingKey {
        case outerRing, center, footer, bluetoothIconColor, inputSourceMarkerStyle, bluetoothSymbolScale
        case batteryStatusColors
        case airPodsLeftArcColor, airPodsRightArcColor, airPodsSingleArcColor
    }

    static let classic = Self(
        outerRing: .classic,
        center: .classic,
        footer: .classic,
        bluetoothIconColor: .classic,
        inputSourceMarkerStyle: .systemIcon,
        bluetoothSymbolScale: BluetoothAudioIconOptions.defaultSymbolScale,
        batteryStatusColors: .classic,
        airPodsLeftArcColor: .init(storageValue: "blue"),
        airPodsRightArcColor: .init(storageValue: "primary"),
        airPodsSingleArcColor: .init(storageValue: "primary")
    )

    init(
        outerRing: RingAppearance,
        center: CenterAppearance,
        footer: FooterAppearance,
        bluetoothIconColor: BluetoothIconColorConfiguration = .classic,
        inputSourceMarkerStyle: InputSourceMarkerStyle = .systemIcon,
        bluetoothSymbolScale: Double = BluetoothAudioIconOptions.defaultSymbolScale,
        batteryStatusColors: BatteryStatusColorsConfiguration = .classic,
        airPodsLeftArcColor: BluetoothIconColorConfiguration = .init(storageValue: "blue"),
        airPodsRightArcColor: BluetoothIconColorConfiguration = .init(storageValue: "primary"),
        airPodsSingleArcColor: BluetoothIconColorConfiguration = .init(storageValue: "primary")
    ) {
        self.outerRing = outerRing
        self.center = center
        self.footer = footer
        self.bluetoothIconColor = bluetoothIconColor
        self.inputSourceMarkerStyle = inputSourceMarkerStyle
        self.bluetoothSymbolScale = bluetoothSymbolScale
        self.batteryStatusColors = batteryStatusColors
        self.airPodsLeftArcColor = airPodsLeftArcColor
        self.airPodsRightArcColor = airPodsRightArcColor
        self.airPodsSingleArcColor = airPodsSingleArcColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outerRing = try container.decode(RingAppearance.self, forKey: .outerRing)
        center = try container.decode(CenterAppearance.self, forKey: .center)
        footer = try container.decode(FooterAppearance.self, forKey: .footer)
        bluetoothIconColor = try container.decodeIfPresent(
            BluetoothIconColorConfiguration.self, forKey: .bluetoothIconColor
        ) ?? .classic
        inputSourceMarkerStyle = try container.decodeIfPresent(
            InputSourceMarkerStyle.self, forKey: .inputSourceMarkerStyle
        ) ?? .systemIcon
        bluetoothSymbolScale = try container.decodeIfPresent(
            Double.self, forKey: .bluetoothSymbolScale
        ) ?? BluetoothAudioIconOptions.defaultSymbolScale
        batteryStatusColors = try container.decodeIfPresent(
            BatteryStatusColorsConfiguration.self, forKey: .batteryStatusColors
        ) ?? .classic
        airPodsLeftArcColor = try container.decodeIfPresent(
            BluetoothIconColorConfiguration.self, forKey: .airPodsLeftArcColor
        ) ?? .init(storageValue: "blue")
        airPodsRightArcColor = try container.decodeIfPresent(
            BluetoothIconColorConfiguration.self, forKey: .airPodsRightArcColor
        ) ?? .init(storageValue: "primary")
        airPodsSingleArcColor = try container.decodeIfPresent(
            BluetoothIconColorConfiguration.self, forKey: .airPodsSingleArcColor
        ) ?? .init(storageValue: "primary")
    }

    func resetting(_ slot: IconSlot) -> Self {
        var copy = self
        switch slot {
        case .outerRing: copy.outerRing = .classic
        case .center: copy.center = .classic
        case .footer: copy.footer = .classic
        }
        return copy
    }
}


/// Codable storage for `BluetoothIconColorSelection` (#275). Stores the same
/// hand-parseable raw value the settings model persists.
struct BluetoothIconColorConfiguration: Codable, Equatable, Sendable {
    var storageValue: String

    static let classic = Self(storageValue: "blue")

    init(storageValue: String = "blue") {
        self.storageValue = storageValue
    }

    init(_ selection: BluetoothIconColorSelection) {
        self.storageValue = selection.storageValue
    }

    var selection: BluetoothIconColorSelection {
        BluetoothIconColorSelection(storageValue: storageValue)
    }
}

extension InputSourceMarkerStyle: Codable {}


/// Codable storage for `BatteryStatusColors`. Each role stores the same
/// hand-parseable value the settings model persists (`system`, `preset:<name>`
/// or `custom:<hue>,<saturation>,<brightness>`).
struct BatteryStatusColorsConfiguration: Codable, Equatable, Sendable {
    var discharging: String
    var charging: String
    var connected: String
    var lowPower: String
    var highPower: String
    var critical: String

    enum CodingKeys: String, CodingKey {
        case discharging, charging, connected, lowPower, highPower, critical
    }

    static let classic = Self(
        discharging: "system",
        charging: "system",
        connected: "system",
        lowPower: "system",
        highPower: "system",
        critical: "system"
    )

    init(discharging: String = "system", charging: String = "system", connected: String = "system",
         lowPower: String = "system",
         highPower: String = "system", critical: String = "system") {
        self.discharging = discharging
        self.charging = charging
        self.connected = connected
        self.lowPower = lowPower
        self.highPower = highPower
        self.critical = critical
    }

    // Configurations saved before the discharging role existed lack its key, so
    // decode it with a system default instead of failing the whole document.
    // Configurations saved before the connected role existed (#389) inherit the
    // old merged charging colour, so an upgrade never changes the connected look.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        discharging = try container.decodeIfPresent(String.self, forKey: .discharging) ?? "system"
        let storedCharging = try container.decodeIfPresent(String.self, forKey: .charging) ?? "system"
        charging = storedCharging
        connected = try container.decodeIfPresent(String.self, forKey: .connected) ?? storedCharging
        lowPower = try container.decodeIfPresent(String.self, forKey: .lowPower) ?? "system"
        highPower = try container.decodeIfPresent(String.self, forKey: .highPower) ?? "system"
        critical = try container.decodeIfPresent(String.self, forKey: .critical) ?? "system"
    }

    init(_ colors: BatteryStatusColors) {
        self.init(
            discharging: colors.discharging.storageValue,
            charging: colors.charging.storageValue,
            connected: colors.connected.storageValue,
            lowPower: colors.lowPower.storageValue,
            highPower: colors.highPower.storageValue,
            critical: colors.critical.storageValue
        )
    }

    var colors: BatteryStatusColors {
        BatteryStatusColors(
            discharging: BatteryStatusColorSelection(storageValue: discharging),
            charging: BatteryStatusColorSelection(storageValue: charging),
            connected: BatteryStatusColorSelection(storageValue: connected),
            lowPower: BatteryStatusColorSelection(storageValue: lowPower),
            highPower: BatteryStatusColorSelection(storageValue: highPower),
            critical: BatteryStatusColorSelection(storageValue: critical)
        )
    }
}
