import SwiftUI

/// One draggable row canvas. Chips are plain views (not buttons) so the drag
/// session is not stolen by a tap gesture. Every chip also exposes a context
/// menu (move / delete) as the single-pointer and keyboard alternative to drag.
struct MenuBarRowCanvasView: View {
    @ObservedObject var model: MenuBarInstanceEditorModel
    let slot: MenuBarLineSlot
    let title: String
    let localization: Localization
    @Binding var selectedSlot: MenuBarLineSlot
    @Binding var selectedElementID: UUID?
    @State private var isTargeted = false

    private var elements: [MenuBarElement] { model.elements(slot: slot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                Spacer()
                Text("\(elements.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                if elements.isEmpty {
                    Label(localization.string(.menuBarEditorEmptyRow), systemImage: "arrow.down.to.line")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(elements.enumerated()), id: \.element.id) { index, element in
                    chip(element, index: index)
                        .dropDestination(for: MenuBarElementDragPayload.self) { payloads, _ in
                            guard let payload = payloads.first else { return false }
                            return drop(payload, index: index)
                        }
                }
                Spacer(minLength: 4)
            }
            .padding(8)
            .frame(minHeight: 38, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                                    lineWidth: isTargeted ? 1.5 : 1)
                    )
            )
            .dropDestination(for: MenuBarElementDragPayload.self) { payloads, _ in
                guard let payload = payloads.first else { return false }
                return drop(payload, index: elements.count)
            } isTargeted: { isTargeted = $0 }
        }
    }

    private func chip(_ element: MenuBarElement, index: Int) -> some View {
        let selected = selectedElementID == element.id && selectedSlot == slot
        return HStack(spacing: 4) {
            Image(systemName: chipSymbol(element))
                .font(.caption2)
            Text(label(for: element))
                .font(.callout)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(selected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1))
        .draggable(MenuBarElementDragPayload(source: .placed(instanceID: model.instance.id, slot: slot, elementID: element.id)))
        .onTapGesture {
            selectedSlot = slot
            selectedElementID = element.id
        }
        .contextMenu {
            Button(localization.string(.menuBarEditorMoveLeft)) { model.moveElement(id: element.id, to: index - 1, slot: slot) }
            Button(localization.string(.menuBarEditorMoveRight)) { model.moveElement(id: element.id, to: index + 1, slot: slot) }
            Divider()
            Button(localization.string(.menuBarEditorDelete), role: .destructive) { model.removeElement(id: element.id, slot: slot) }
        }
        .accessibilityLabel(label(for: element))
    }

    private func chipSymbol(_ element: MenuBarElement) -> String {
        switch element.content {
        case .text: return "textformat"
        case .metric: return "chart.bar"
        case .icon: return "photo"
        }
    }

    private func label(for element: MenuBarElement) -> String {
        switch element.content {
        case .text(let text): return text.isEmpty ? localization.string(.menuBarEditorTextPlaceholder) : text
        case .metric(let metric): return localization.string(MenuBarMetricRegistry.titleKey(for: metric))
        case .icon(let icon):
            switch icon.source {
            case .sfSymbol(let name): return name
            case .emoji(let value): return value
            case .asset(let name): return name
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
