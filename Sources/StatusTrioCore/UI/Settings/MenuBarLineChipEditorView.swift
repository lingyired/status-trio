import SwiftUI

struct MenuBarLineChipEditorView: View {
    @ObservedObject var model: MenuBarInstanceEditorModel
    let slot: MenuBarLineSlot
    let title: String

    private var segments: [MenuBarLineSegment] {
        switch slot {
        case .top: return model.instance.top?.segments ?? []
        case .bottom: return model.instance.bottom?.segments ?? []
        }
    }

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                if segments.isEmpty {
                    Text("Empty").foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        chip(segment, index: index)
                    }
                }
                HStack {
                    Menu("Add data source") {
                        ForEach(MenuBarMetricID.allCases) { metric in
                            Button(metric.rawValue) { model.addMetricSegment(metric, slot: slot) }
                        }
                    }
                    Button("Add text") { model.addTextSegment("Text", slot: slot) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func chip(_ segment: MenuBarLineSegment, index: Int) -> some View {
        let label: String = {
            switch segment {
            case .text(let text): return text.isEmpty ? "(text)" : text
            case .metric(let metric): return "{\(MenuBarMetricRegistry.titleKey(for: metric).rawValue)}"
            }
        }()
        Text(label)
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .contextMenu {
                Button("Move left") { model.moveSegment(from: index, to: index - 1, slot: slot) }
                Button("Move right") { model.moveSegment(from: index, to: index + 1, slot: slot) }
                Divider()
                Button("Delete", role: .destructive) { model.removeSegment(at: index, slot: slot) }
            }
    }
}
