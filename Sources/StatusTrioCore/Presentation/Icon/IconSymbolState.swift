import Foundation

enum IconPrimitive: Equatable, Hashable, Sendable {
    case wiredPort
    case screenWedge
    case arrowWedge
    case bolt
    case plug
}

enum IconSymbolSource: Equatable, Hashable, Sendable {
    case symbol(name: String, variableValue: Double?, fallback: String?)
    case image(url: URL, fallbackSymbol: String)
    case primitive(IconPrimitive)
}

struct IconSymbolState: Equatable, Hashable, Sendable {
    let source: IconSymbolSource
    let color: IconColorRole
    let scale: Double

    /// Keeps supplied, context-validated scales intact and replaces unusable
    /// values with the context-neutral symbol scale used by current defaults.
    init(source: IconSymbolSource, color: IconColorRole, scale: Double) {
        self.source = Self.normalized(source)
        self.color = color
        self.scale = Self.normalizedScale(scale)
    }

    static func normalizedScale(_ scale: Double) -> Double {
        guard scale.isFinite, scale > 0 else { return 1 }
        return scale
    }

    private static func normalized(_ source: IconSymbolSource) -> IconSymbolSource {
        guard case let .symbol(name, variableValue, fallback) = source,
              let variableValue else {
            return source
        }

        guard variableValue.isFinite else {
            return .symbol(name: name, variableValue: nil, fallback: fallback)
        }

        return .symbol(
            name: name,
            variableValue: min(1, max(0, variableValue)),
            fallback: fallback
        )
    }
}

struct IconTextState: Equatable, Hashable, Sendable {
    let text: String
    let color: IconColorRole
    let scale: Double

    /// Mapper supplies the relevant option value; invalid values fall back to
    /// the context-neutral text scale of 1.0.
    init(text: String, color: IconColorRole, scale: Double) {
        self.text = text
        self.color = color
        self.scale = IconSymbolState.normalizedScale(scale)
    }
}
