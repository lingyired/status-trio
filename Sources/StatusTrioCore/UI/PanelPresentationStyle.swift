import AppKit
import SwiftUI

enum PanelSummaryActionMetrics {
    static let hitTarget: CGFloat = 24
}

/// One optical and hit-target container for every trailing status-panel action.
/// Keeping the image centered inside a square target prevents SF Symbols with
/// different intrinsic bounds from drifting vertically between rows.
struct PanelActionGlyph: View {
    let systemName: String
    var font: Font = .body
    var size: CGFloat = PanelSummaryActionMetrics.hitTarget
    /// A row may pin the symbol to its measured centre when a taller neighbouring
    /// text block makes the default optical correction unnecessary.
    var verticalOpticalOffset: CGFloat? = nil

    var body: some View {
        Image(systemName: systemName)
            .font(font)
            .frame(
                width: size,
                height: size,
                alignment: .center
            )
            .offset(y: verticalOpticalOffset ?? defaultOpticalOffsetY)
    }

    /// SF Symbols keep their own ink bounds inside an equal frame. The gear's
    /// lower optical center differs from chevrons and switches by half a point.
    /// A quarter-point correction lands between the two raster centres without
    /// introducing a compensating drift in the opposite direction.
    private var defaultOpticalOffsetY: CGFloat {
        systemName == "gearshape" ? -0.25 : 0
    }
}

extension PanelTint {
    func color(caution: Color = .orange) -> Color {
        switch self {
        case .primary: .primary
        case .secondary: .secondary
        case .positive: .green
        case .caution: caution
        case .critical: .red
        }
    }
}

struct PanelSymbolView: View {
    let source: IconSymbolSource
    var size: CGFloat = 15
    var weight: Font.Weight = .medium

    var body: some View {
        switch source {
        case let .symbol(name, variableValue, fallback):
            Image(systemName: resolvedSymbolName(name, fallback: fallback), variableValue: variableValue)
                .font(.system(size: size, weight: weight))
        case let .image(url, fallbackSymbol):
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: size, height: size)
            } else {
                Image(systemName: resolvedSymbolName(fallbackSymbol, fallback: nil))
                    .font(.system(size: size, weight: weight))
            }
        case let .primitive(primitive):
            Image(systemName: symbolName(for: primitive)).font(.system(size: size, weight: weight))
        }
    }

    private func resolvedSymbolName(_ name: String, fallback: String?) -> String {
        SymbolFallback.name(name, [fallback ?? "questionmark.circle", "questionmark.circle"])
    }

    private func symbolName(for primitive: IconPrimitive) -> String {
        switch primitive {
        case .wiredPort: "cable.connector"
        case .screenWedge: "display"
        case .arrowWedge: "arrow.left.and.right"
        case .bolt: "bolt.fill"
        case .plug: "powerplug.fill"
        }
    }
}

struct PanelDetailRowsView: View {
    @EnvironmentObject private var localization: Localization
    let detailRows: [PanelDetailRow]
    var leadingInset: CGFloat = 0
    var onCopyValue: (String) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 5) {
            ForEach(detailRows, id: \.id) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if row.isCopyable {
                        Button(row.value) { onCopyValue(row.value) }
                            .buttonStyle(.plain)
                            .textSelection(.enabled)
                            .accessibilityLabel("\(row.label): \(row.accessibilityValue)")
                    } else {
                        Text(row.value)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }
                .foregroundStyle(row.tint.color())
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.leading, leadingInset)
    }
}
