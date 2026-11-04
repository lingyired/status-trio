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

    static let collapsedDisplayLimit = 3

    var hasHiddenRows: Bool {
        OutputDeviceListPresentation.canToggleExpansion(
            for: rows, limit: Self.collapsedDisplayLimit
        )
    }

    func visibleRows(expanded: Bool) -> [BrightnessRowState] {
        OutputDeviceListPresentation.visibleDevices(
            from: rows, limit: Self.collapsedDisplayLimit, isExpanded: expanded
        )
    }

    func displayName(for row: BrightnessRowState, builtInName: String) -> String {
        let name = row.isBuiltin ? builtInName : row.name
        let matching = rows.filter { $0.name == row.name && $0.isBuiltin == row.isBuiltin }
        guard matching.count > 1, let index = matching.firstIndex(where: { $0.id == row.id }) else {
            return name
        }
        return "\(name) · \(index + 1)"
    }

    static let placeholder = BrightnessPanelState(rows: [])
}
