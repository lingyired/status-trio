import Foundation

/// One display row in the brightness section.
struct BrightnessRowState: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let isBuiltin: Bool
    /// 0...1, or nil when the value is unknown or unreadable.
    let scalar: Double?
    let canAdjust: Bool
    let backend: BrightnessBackend
    let source: BrightnessControlSource
    let percentageText: String
    let accessibilityLabel: String
    /// A short explanation shown instead of the percentage when unavailable.
    let unavailableText: String?

    /// A sun icon rather than a per-device icon, so every row reads as
    /// "brightness" instead of "this display".
    var symbolName: String {
        SymbolFallback.name("sun.max.fill", "sun.max")
    }
}

/// The brightness panel section's fully resolved state.
struct BrightnessPanelState: Equatable, Sendable {
    let rows: [BrightnessRowState]
    let transitionGeneration: UInt64

    init(rows: [BrightnessRowState], transitionGeneration: UInt64 = 0) {
        self.rows = rows
        self.transitionGeneration = transitionGeneration
    }

    var isEmpty: Bool { rows.isEmpty }

    static let placeholder = BrightnessPanelState(rows: [])
}
