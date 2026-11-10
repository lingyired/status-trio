import Foundation

struct IconRGBA: Codable, Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let white = Self(red: 1, green: 1, blue: 1, alpha: 1)

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

    enum CodingKeys: String, CodingKey {
        case outerRing, center, footer, bluetoothIconColor, inputSourceMarkerStyle, bluetoothSymbolScale
    }

    static let classic = Self(
        outerRing: .classic,
        center: .classic,
        footer: .classic,
        bluetoothIconColor: .classic,
        inputSourceMarkerStyle: .systemIcon,
        bluetoothSymbolScale: BluetoothAudioIconOptions.defaultSymbolScale
    )

    init(
        outerRing: RingAppearance,
        center: CenterAppearance,
        footer: FooterAppearance,
        bluetoothIconColor: BluetoothIconColorConfiguration = .classic,
        inputSourceMarkerStyle: InputSourceMarkerStyle = .systemIcon,
        bluetoothSymbolScale: Double = BluetoothAudioIconOptions.defaultSymbolScale
    ) {
        self.outerRing = outerRing
        self.center = center
        self.footer = footer
        self.bluetoothIconColor = bluetoothIconColor
        self.inputSourceMarkerStyle = inputSourceMarkerStyle
        self.bluetoothSymbolScale = bluetoothSymbolScale
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
