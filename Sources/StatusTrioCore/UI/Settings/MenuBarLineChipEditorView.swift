import SwiftUI

/// Draggable chip used by both the row canvas and the palette. Deliberately a
/// plain view (not a Button): a button's gesture recognizer would claim the
/// mouse-down and prevent the drag session from starting.
struct MenuBarEditorChipLabel: View {
    let title: String
    let systemImage: String
    var isSelected = false
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.caption2)
            Text(title).font(compact ? .caption : .callout).lineLimit(1)
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// One draggable row canvas. Chips expose a context menu (move / delete) as the
/// single-pointer and keyboard alternative to dragging.
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
                Text("\(elements.count)").font(.caption2).foregroundStyle(.tertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
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
                    appendTarget
                }
                .padding(8)
            }
            .frame(minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.background.opacity(0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                                    lineWidth: isTargeted ? 1.5 : 1)
                    )
            )
            .dropDestination(for: MenuBarElementDragPayload.self) { payloads, _ in
                guard let payload = payloads.first else { return false }
                return drop(payload, index: elements.count)
            } isTargeted: { isTargeted = $0 }
            .onDeleteCommand {
                if let id = selectedElementID, selectedSlot == slot {
                    model.removeElement(id: id, slot: slot)
                    selectedElementID = nil
                }
            }
        }
    }

    private var appendTarget: some View {
        Image(systemName: "plus")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.35))
            )
            .dropDestination(for: MenuBarElementDragPayload.self) { payloads, _ in
                guard let payload = payloads.first else { return false }
                return drop(payload, index: elements.count)
            }
            .accessibilityLabel(localization.string(.menuBarEditorEmptyRow))
    }

    private func chip(_ element: MenuBarElement, index: Int) -> some View {
        let selected = selectedElementID == element.id && selectedSlot == slot
        return MenuBarEditorChipLabel(title: label(for: element), systemImage: chipSymbol(element), isSelected: selected)
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
            .accessibilityAddTraits(selected ? .isSelected : [])
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
