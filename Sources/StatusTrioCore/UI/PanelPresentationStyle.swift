import AppKit
import SwiftUI

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
        case let .symbol(name, variableValue, _):
            Image(systemName: name, variableValue: variableValue)
                .font(.system(size: size, weight: weight))
        case let .image(url, fallbackSymbol):
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: size, height: size)
            } else {
                Image(systemName: fallbackSymbol).font(.system(size: size, weight: weight))
            }
        case let .primitive(primitive):
            Image(systemName: symbolName(for: primitive)).font(.system(size: size, weight: weight))
        }
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
