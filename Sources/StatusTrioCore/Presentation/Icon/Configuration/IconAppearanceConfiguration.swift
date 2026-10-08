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
    var color: SlotColorStyle

    static let classic = Self(symbolScale: BluetoothAudioIconOptions.defaultSymbolScale, color: .automatic)

    func normalized() -> Self {
        Self(
            symbolScale: symbolScale.isFinite ? min(3, max(1, symbolScale)) : Self.classic.symbolScale,
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
            strokeScale: strokeScale.isFinite ? min(2.5, max(0.5, strokeScale)) : Self.classic.strokeScale,
            color: color.normalized()
        )
    }
}

struct IconAppearanceConfiguration: Codable, Equatable, Sendable {
    var outerRing: RingAppearance
    var center: CenterAppearance
    var footer: FooterAppearance

    static let classic = Self(
        outerRing: .classic,
        center: .classic,
        footer: .classic
    )

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
