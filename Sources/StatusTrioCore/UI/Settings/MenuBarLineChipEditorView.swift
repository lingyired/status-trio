import SwiftUI

/// One draggable row canvas. Chips are plain views (not buttons) so the drag
/// session is not stolen by a tap gesture. Dropping uses the pure mutation engine.
struct MenuBarRowCanvasView: View {
    @ObservedObject var model: MenuBarInstanceEditorModel
    let slot: MenuBarLineSlot
    let title: String
    @Binding var selectedSlot: MenuBarLineSlot
    @Binding var selectedElementID: UUID?
    @State private var isTargeted = false

    private var elements: [MenuBarElement] { model.elements(slot: slot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if elements.isEmpty {
                    Text("Empty — drag an element here")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(elements.enumerated()), id: \.element.id) { index, element in
                    chip(element)
                        .dropDestination(for: MenuBarElementDragPayload.self) { payloads, _ in
                            guard let payload = payloads.first else { return false }
                            return drop(payload, index: index)
                        }
                }
                Spacer(minLength: 4)
            }
            .padding(8)
            .background(
                (isTargeted ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08)),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .dropDestination(for: MenuBarElementDragPayload.self) { payloads, _ in
                guard let payload = payloads.first else { return false }
                return drop(payload, index: elements.count)
            } isTargeted: { isTargeted = $0 }
        }
    }

    private func chip(_ element: MenuBarElement) -> some View {
        Text(label(for: element))
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                selectedElementID == element.id && selectedSlot == slot
                    ? Color.accentColor.opacity(0.25)
                    : Color.secondary.opacity(0.15),
                in: Capsule()
            )
            .draggable(MenuBarElementDragPayload(source: .placed(instanceID: model.instance.id, slot: slot, elementID: element.id)))
            .onTapGesture {
                selectedSlot = slot
                selectedElementID = element.id
            }
    }

    private func label(for element: MenuBarElement) -> String {
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
    }

    private func drop(_ payload: MenuBarElementDragPayload, index: Int) -> Bool {
        var instance = model.instance
        let changed = MenuBarElementMutations.apply(
            payload: payload,
            to: &instance,
            target: .line(instanceID: instance.id, slot: slot, index: index)
        )
        if changed {
            model.instance = instance
            model.persist()
            selectedSlot = slot
        }
        return changed
    }
}
