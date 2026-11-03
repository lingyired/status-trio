import SwiftUI

/// An sRGB triple with no opacity baked in.
///
/// The neutral card surfaces cannot come from a semantic style: they are neither
/// the label colour nor a status colour, so they need explicit numbers. Keeping
/// the numbers in a plain value type lets a test state the intent (cool, not
/// neutral) instead of re-deriving it from a screenshot.
struct PowerCardRGB: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }
}

/// The surface painted behind one power metric card: a fill and a thin rim.
///
/// The green / orange / blue cards wash their own semantic tint over the panel
/// glass. The charger-input cards cannot do that: their foreground tint is
/// `.primary`, which in light mode is pure black, and black at 18% over light
/// Liquid Glass reads as a flat dirty grey rather than metal. Those cards get an
/// appearance-adaptive silver instead.
///
/// Foregrounds are deliberately not part of this type: the plug glyph and the
/// wattage keep `.primary` / `.secondary` so their contrast does not depend on
/// the surface. The summary power bar and the battery details flow diagram share
/// this type so the two "charger input" cards cannot drift apart.
enum PowerCardSurface: Equatable, Sendable {
    /// The card's own semantic tint at these opacities.
    case tint(fillOpacity: Double, strokeOpacity: Double)
    /// The neutral silver family, resolved for the current appearance.
    case silver(PowerCardSilver.Role)

    func fill(tint: Color, scheme: ColorScheme) -> Color {
        switch self {
        case let .tint(fillOpacity, _):
            return tint.opacity(fillOpacity)
        case let .silver(role):
            return PowerCardSilver.values(for: role, scheme: scheme).fill
        }
    }

    func stroke(tint: Color, scheme: ColorScheme) -> Color {
        switch self {
        case let .tint(_, strokeOpacity):
            return tint.opacity(strokeOpacity)
        case let .silver(role):
            return PowerCardSilver.values(for: role, scheme: scheme).stroke
        }
    }
}

/// The numeric silver recipe for the charger-input cards.
///
/// Light mode needs a cool, light fill plus a slightly deeper rim so the card
/// reads as a brushed metal surface instead of a grey wash. Dark mode keeps
/// roughly the brightness the previous white wash had (it already looked right
/// over dark glass) and only shifts it cooler.
struct PowerCardSilver: Equatable, Sendable {
    enum Role: Equatable, Sendable {
        /// The adapter is supplying power.
        case connected
        /// No adapter: the same neutral family, washed out so the card reads as
        /// inactive without turning a different colour.
        case disconnected
    }

    let fillRGB: PowerCardRGB
    let fillOpacity: Double
    let strokeRGB: PowerCardRGB
    let strokeOpacity: Double

    var fill: Color { fillRGB.color.opacity(fillOpacity) }
    var stroke: Color { strokeRGB.color.opacity(strokeOpacity) }

    static func values(for role: Role, scheme: ColorScheme) -> PowerCardSilver {
        let dark = scheme == .dark
        switch role {
        case .connected:
            return dark
                ? PowerCardSilver(
                    fillRGB: PowerCardRGB(red: 0.70, green: 0.78, blue: 0.92),
                    fillOpacity: 0.22,
                    strokeRGB: PowerCardRGB(red: 0.82, green: 0.89, blue: 1.00),
                    strokeOpacity: 0.34)
                : PowerCardSilver(
                    fillRGB: PowerCardRGB(red: 0.62, green: 0.69, blue: 0.79),
                    fillOpacity: 0.22,
                    strokeRGB: PowerCardRGB(red: 0.35, green: 0.43, blue: 0.56),
                    strokeOpacity: 0.30)
        case .disconnected:
            return dark
                ? PowerCardSilver(
                    fillRGB: PowerCardRGB(red: 0.70, green: 0.78, blue: 0.92),
                    fillOpacity: 0.12,
                    strokeRGB: PowerCardRGB(red: 0.82, green: 0.89, blue: 1.00),
                    strokeOpacity: 0.18)
                : PowerCardSilver(
                    fillRGB: PowerCardRGB(red: 0.62, green: 0.69, blue: 0.79),
                    fillOpacity: 0.12,
                    strokeRGB: PowerCardRGB(red: 0.35, green: 0.43, blue: 0.56),
                    strokeOpacity: 0.18)
        }
    }
}
