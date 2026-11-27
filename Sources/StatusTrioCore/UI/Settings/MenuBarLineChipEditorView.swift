import SwiftUI

struct MenuBarLineChipEditorView: View {
    @ObservedObject var model: MenuBarInstanceEditorModel
    let slot: MenuBarLineSlot
    let title: String

    private var elements: [MenuBarElement] { model.elements(slot: slot) }

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                if elements.isEmpty {
                    Text("Empty").foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    ForEach(Array(elements.enumerated()), id: \.element.id) { index, element in
                        chip(element, index: index)
                    }
                }
                HStack {
                    Menu("Add data source") {
                        ForEach(MenuBarMetricID.allCases) { metric in
                            Button(metric.rawValue) { model.addMetricElement(metric, slot: slot) }
                        }
                    }
                    Button("Add text") { model.addTextElement("Text", slot: slot) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func chip(_ element: MenuBarElement, index: Int) -> some View {
        let label: String = {
            switch element.content {
            case .text(let text): return text.isEmpty ? "(text)" : text
            case .metric(let metric): return "{\(metric.rawValue)}"
            case .icon(let icon):
                switch icon.source {
                case .sfSymbol(let name): return "icon:\(name)"
                case .emoji(let value): return value
                case .asset(let name): return "asset:\(name)"
                }
            }
        }()
        Text(label)
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .contextMenu {
                Button("Move left") { model.moveElement(id: element.id, to: index - 1, slot: slot) }
                Button("Move right") { model.moveElement(id: element.id, to: index + 1, slot: slot) }
                Divider()
                Button("Delete", role: .destructive) { model.removeElement(id: element.id, slot: slot) }
            }
    }
}
