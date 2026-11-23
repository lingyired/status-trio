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
    /// One fixed square slot for every *trailing* action glyph in a summary row.
    ///
    /// Sizing each action to a fixed slot — instead of its SF Symbol's natural
    /// ink width — is what keeps one row's action columns on the same vertical
    /// lines as another row's. A caption-weight `chevron.right` and a
    /// body-weight `arrow.clockwise` have very different natural widths; without
    /// a shared slot the middle button shifts the whole cluster, so the gear
    /// lands in a different column on the Wi-Fi and Bluetooth rows.
    ///
    /// 30 equals the widest trailing glyph (the gear's ink) plus the two
    /// `iconInset` paddings the natural-width path used to add, so switching to
    /// fixed slots keeps every row's previous edge-to-edge rhythm and leaves the
    /// same width for its text and sliders. A tighter slot would widen those
    /// columns and re-wrap the battery runtime subtitle; a wider one would drift
    /// from the established spacing budget.
    static let actionSlot: CGFloat = 30
    /// The one gap between trailing action slots. Every summary row uses it, so
    /// a two-icon row and the four-icon battery row share a single rhythm.
    static let actionSpacing: CGFloat = 2
    /// Horizontal padding around a natural-width glyph. Only the non-summary
    /// glyph path uses it (disclosure rows, section headers); summary rows size
    /// their trailing actions with `actionSlot` instead.
    static let iconInset: CGFloat = 6
}

/// One optical and hit-target container for every trailing status-panel action.
/// Keeping the image centered inside a square target prevents SF Symbols with
/// different intrinsic bounds from drifting vertically between rows.
struct PanelActionGlyph: View {
    let systemName: String
    var font: Font = .body
    /// An explicit square slot for callers that align on a fixed size. Every
    /// summary-row trailing action passes `actionSlot` so its column matches the
    /// other rows; `nil` keeps the natural-glyph sizing used outside the summary
    /// rows (disclosure rows, section headers).
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
