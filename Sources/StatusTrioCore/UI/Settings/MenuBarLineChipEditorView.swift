import SwiftUI

/// A chip in the row canvas or in the element picker.
///
/// Deliberately a plain view rather than a Button: a button's gesture
/// recognizer would claim the mouse-down and prevent the drag session from
/// starting. It still exposes a button trait and selection state so VoiceOver
/// treats it as the interactive element it is.
struct MenuBarEditorChipLabel: View {
    let title: String
    let systemImage: String
    var isSelected = false
    var compact = false

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 10 : 10.5, weight: .medium))
            Text(title)
                .font(.system(size: compact ? 11 : 11.5))
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, compact ? 7 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.18)
                        : Color.primary.opacity(isHovering ? 0.09 : 0.05)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(isHovering ? 0.2 : 0.1),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One editable row of the selected instance.
///
/// The row owns its own "add" button, so adding an element never depends on
/// which row happened to be selected last. Chips can be dragged within the
/// row, across rows, or moved from the context menu as the pointer-free
/// alternative.
struct MenuBarRowCanvasView: View {
    @ObservedObject var model: MenuBarInstanceEditorModel
    let slot: MenuBarLineSlot
    let title: String
    let localization: Localization
    @Binding var selectedSlot: MenuBarLineSlot
    @Binding var selectedElementID: UUID?

    @State private var showingPicker = false
    @State private var isDropTargeted = false

    private var elements: [MenuBarElement] { model.elements(slot: slot) }

    private func L(_ key: LocalizationKey) -> String { localization.string(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("\(elements.count)")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 8)

                Button {
                    showingPicker = true
                } label: {
                    Label(L(.menuBarEditorAdd), systemImage: "plus")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(L(.menuBarEditorAdd))
            }

            canvas
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, 10)
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            MenuBarElementPicker(
                localization: localization,
                onAddText: { text in
                    add(model.addTextElement(text, slot: slot))
                },
                onAddMetric: { metric in
                    add(model.addMetricElement(metric, slot: slot))
                },
                onAddIcon: { icon in
                    add(model.addIconElement(icon, slot: slot))
                }
            )
        }
    }

    private var canvas: some View {
        Group {
            if elements.isEmpty {
                Text(L(.menuBarEditorEmptyRow))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                WrappingHStack(spacing: 6, rowSpacing: 6) {
                    ForEach(Array(elements.enumerated()), id: \.element.id) { index, element in
                        chip(element, at: index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: 30, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.primary.opacity(0.09),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .dropDestination(for: MenuBarElementDragPayload.self) { payloads, _ in
            drop(payloads.first, at: elements.count)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private func chip(_ element: MenuBarElement, at index: Int) -> some View {
        let selected = selectedElementID == element.id && selectedSlot == slot

        return MenuBarEditorChipLabel(
            title: label(for: element),
            systemImage: symbol(for: element),
            isSelected: selected
        )
        .draggable(MenuBarElementDragPayload(source: .placed(
            instanceID: model.instance.id,
            slot: slot,
            elementID: element.id
        )))
        .onTapGesture {
            if selected {
                selectedElementID = nil
            } else {
                selectedSlot = slot
                selectedElementID = element.id
            }
        }
        .contextMenu {
            Button(L(.menuBarEditorMoveLeft)) {
                model.moveElement(id: element.id, to: index - 1, slot: slot)
            }
            .disabled(index == 0)

            Button(L(.menuBarEditorMoveRight)) {
                model.moveElement(id: element.id, to: index + 1, slot: slot)
            }
            .disabled(index >= elements.count - 1)

            Divider()

            Button(L(.menuBarEditorDelete), role: .destructive) {
                model.removeElement(id: element.id, slot: slot)
                if selected { selectedElementID = nil }
            }
        }
        .dropDestination(for: MenuBarElementDragPayload.self) { payloads, _ in
            drop(payloads.first, at: index)
        }
        .accessibilityLabel(label(for: element))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction {
            if selected {
                selectedElementID = nil
            } else {
                selectedSlot = slot
                selectedElementID = element.id
            }
        }
        .accessibilityAction(named: Text(L(.menuBarEditorMoveLeft))) {
            model.moveElement(id: element.id, to: index - 1, slot: slot)
        }
        .accessibilityAction(named: Text(L(.menuBarEditorMoveRight))) {
            model.moveElement(id: element.id, to: index + 1, slot: slot)
        }
        .accessibilityAction(named: Text(L(.menuBarEditorDelete))) {
            model.removeElement(id: element.id, slot: slot)
            if selected { selectedElementID = nil }
        }
    }

    // MARK: - Adding and moving

    private func add(_ id: UUID?) {
        guard let id else { return }
        selectedSlot = slot
        selectedElementID = id
    }

    private func drop(_ payload: MenuBarElementDragPayload?, at index: Int) -> Bool {
        guard let payload, case let .placed(instanceID, fromSlot, elementID) = payload.source,
              instanceID == model.instance.id
        else { return false }

        if fromSlot == slot {
            model.moveElement(id: elementID, to: index, slot: slot)
        } else {
            model.moveElement(id: elementID, from: fromSlot, to: slot, index: index)
        }
        selectedSlot = slot
        selectedElementID = elementID
        return true
    }

    // MARK: - Presentation

    private func label(for element: MenuBarElement) -> String {
        switch element.content {
        case .text(let text):
            return text.isEmpty ? L(.menuBarEditorTextPlaceholder) : text
        case .metric(let metric):
            return L(MenuBarMetricRegistry.titleKey(for: metric))
        case .icon(let icon):
            switch icon.source {
            case .sfSymbol(let name): return name
            case .emoji(let value): return value
            case .asset(let name): return name
            }
        }
    }

    private func symbol(for element: MenuBarElement) -> String {
        switch element.content {
        case .text:
            return "textformat"
        case .metric(let metric):
            return metric.editorSymbol
        case .icon(let icon):
            switch icon.source {
            case .sfSymbol(let name): return name
            case .emoji: return "face.smiling"
            case .asset: return "photo"
            }
        }
    }
}

// MARK: - Element picker

/// Searchable picker for the element types a row can hold.
///
/// A popover keeps the palette out of the page until it is needed, which is
/// what lets the editor fit the Settings window without a third column.
struct MenuBarElementPicker: View {
    let localization: Localization
    let onAddText: (String) -> Void
    let onAddMetric: (MenuBarMetricID) -> Void
    let onAddIcon: (MenuBarIconSpec) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var search = ""
    @State private var text = ""
    @State private var iconKind = 0
    @State private var iconValue = ""

    private func L(_ key: LocalizationKey) -> String { localization.string(key) }

    private var filteredMetrics: [MenuBarMetricID] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return MenuBarMetricID.allCases }
        return MenuBarMetricID.allCases.filter {
            L(MenuBarMetricRegistry.titleKey(for: $0)).localizedCaseInsensitiveContains(query)
                || $0.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $tab) {
                Text(L(.menuBarEditorMetrics)).tag(0)
                Text(L(.menuBarEditorTextIcons)).tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if tab == 0 {
                metricsPicker
            } else {
                textAndIconPicker
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    private var metricsPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L(.menuBarEditorSearchPlaceholder), text: $search)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredMetrics) { metric in
                        MenuBarMetricPickerRow(
                            title: L(MenuBarMetricRegistry.titleKey(for: metric)),
                            symbol: metric.editorSymbol
                        ) {
                            onAddMetric(metric)
                            dismiss()
                        }

                        if metric.id != filteredMetrics.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.trailing, 10)
            }
            .frame(height: 250)
        }
    }

    private var textAndIconPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L(.menuBarEditorText))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField(L(.menuBarEditorTextPlaceholder), text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addText() }

                Button(L(.menuBarEditorAdd)) { addText() }
                    .disabled(text.isEmpty)
            }

            Divider()

            Text(L(.menuBarEditorIconType))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("", selection: $iconKind) {
                Text("SF Symbol").tag(0)
                Text(L(.menuBarEditorIconEmoji)).tag(1)
                Text(L(.menuBarEditorIconAsset)).tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 8) {
                TextField(iconPlaceholder, text: $iconValue)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addIcon() }

                Button(L(.menuBarEditorAdd)) { addIcon() }
                    .disabled(iconValue.isEmpty)
            }
        }
    }

    private var iconPlaceholder: String {
        switch iconKind {
        case 1: return L(.menuBarEditorIconEmoji)
        case 2: return L(.menuBarEditorIconAsset)
        default: return L(.menuBarEditorIconSymbol)
        }
    }

    private func addText() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onAddText(value)
        dismiss()
    }

    private func addIcon() {
        let value = iconValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let source: MenuBarIconSource
        switch iconKind {
        case 1: source = .emoji(value)
        case 2: source = .asset(value)
        default: source = .sfSymbol(value)
        }
        onAddIcon(MenuBarIconSpec(source: source, tint: iconKind != 1))
        dismiss()
    }
}

private struct MenuBarMetricPickerRow: View {
    let title: String
    let symbol: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

extension MenuBarMetricID {
    /// SF Symbol used by the editor and the metric picker.
    var editorSymbol: String {
        switch self {
        case .cpuUsage: return "cpu"
        case .cpuTemperature: return "thermometer.medium"
        case .gpuUsage: return "cpu.fill"
        case .gpuTemperature: return "thermometer.high"
        case .memoryUsage: return "memorychip"
        case .diskReadSpeed, .diskWriteSpeed: return "internaldrive"
        case .networkDownload: return "arrow.down.circle"
        case .networkUpload: return "arrow.up.circle"
        case .fanRPM: return "fan"
        case .batteryLevel: return "battery.75"
        case .wifiConnectionStatus: return "wifi"
        case .outputVolume: return "speaker.wave.2"
        case .screenBrightness: return "sun.max"
        }
    }
}
