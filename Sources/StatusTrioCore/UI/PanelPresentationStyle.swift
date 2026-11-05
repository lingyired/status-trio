import AppKit
import SwiftUI

enum PanelSummaryActionMetrics {
    static let hitTarget: CGFloat = 24
    /// Fixed horizontal slot for the leading (mute/input/brightness) glyph so
    /// the volume, mic, and brightness sliders all start on the same x.
    ///
    /// The three panel rows use different SF Symbols (speaker / mic / sun) whose
    /// natural ink widths differ; without a shared slot width the sliders'
    /// leading edge drifts between rows. Equal slots keep every slider's
    /// leading edge aligned.
    static let leadingGlyphSlot: CGFloat = 24
    /// Gap between the trailing action icons of one summary row.
    ///
    /// The hit target already supplies most of the visual air, so a wide stack
    /// spacing made rows with several icons (battery: high/low/chevron/gear)
    /// look loose and uneven. One shared value keeps every row identical.
    static let actionSpacing: CGFloat = 2
    /// The standard gap between trailing action glyphs. Every panel row uses it
    /// together with `iconInset`, so a row with two icons and a row with four
    /// (battery: high/low/chevron/gear) share one edge-to-edge rhythm.
    /// Edge-to-edge gap between two trailing icons whose slots are sized to the
    /// glyph itself. Equal insets plus one gap make every pair of icons in a row
    /// read as evenly spaced, including a narrow chevron next to a wide gear.
    static let iconGap: CGFloat = 8
    /// Horizontal padding added around a trailing glyph so its click target is
    /// comfortable without widening the visual gap between glyphs.
    static let iconInset: CGFloat = 6
}

/// One optical and hit-target container for every trailing status-panel action.
/// Keeping the image centered inside a square target prevents SF Symbols with
/// different intrinsic bounds from drifting vertically between rows.
struct PanelActionGlyph: View {
    let systemName: String
    var font: Font = .body
    /// An explicit square slot for callers that align on a fixed size (the back
    /// chevron). `nil` uses the panel's natural-glyph sizing.
    var size: CGFloat? = nil
    /// A row may pin the symbol to its measured centre when a taller neighbouring
    /// text block makes the default optical correction unnecessary.
    var verticalOpticalOffset: CGFloat? = nil

    var body: some View {
        Group {
            if let size {
                Image(systemName: systemName)
                    .font(font)
                    .frame(width: size, height: size, alignment: .center)
            } else {
                // Natural glyph width with one shared inset: a narrow chevron
                // and a wide gear then read the same distance apart.
                Image(systemName: systemName)
                    .font(font)
                    .padding(.horizontal, PanelSummaryActionMetrics.iconInset)
                    .frame(height: PanelSummaryActionMetrics.hitTarget)
            }
        }
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
