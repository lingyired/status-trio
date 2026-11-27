import SwiftUI

/// A chip in the menu-bar strip or the element library.
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

/// One strip row. Elements are reordered by dragging or by the context menu;
/// new elements come from the library card below the strip.
struct MenuBarRowCanvasView: View {
    @ObservedObject var model: MenuBarInstanceEditorModel
    let slot: MenuBarLineSlot
    let title: String
    let localization: Localization
    @Binding var selectedSlot: MenuBarLineSlot
    @Binding var selectedElementID: UUID?

    @State private var isDropTargeted = false
    @State private var showingLeadingIconPicker = false

    private var elements: [MenuBarElement] { model.elements(slot: slot) }
    private var line: MenuBarLine? {
        slot == .top ? model.instance.top : model.instance.bottom
    }

    private func L(_ key: LocalizationKey) -> String { localization.string(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    showingLeadingIconPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: leadingIconSymbol)
                            .font(.system(size: 10, weight: .medium))
                        Text(L(.menuBarEditorLeadingIcon))
                            .font(.system(size: 10.5))
                    }
                    .foregroundStyle(line?.leadingIcon == nil ? Color.secondary : Color.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help(L(.menuBarEditorLeadingIcon))
                .accessibilityLabel(L(.menuBarEditorLeadingIcon))
                .popover(isPresented: $showingLeadingIconPicker, arrowEdge: .bottom) {
                    MenuBarLeadingIconPicker(
                        spec: line?.leadingIcon,
                        localization: localization
                    ) { icon in
                        model.setLeadingIcon(icon, slot: slot)
                    }
                }

                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("\(elements.count)")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 8)
            }

            canvas
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, 10)
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

    private var leadingIconSymbol: String {
        guard let icon = line?.leadingIcon else { return "plus.circle" }
        switch icon.source {
        case .sfSymbol(let name): return name
        case .emoji: return "face.smiling"
        case .asset: return "photo"
        }
    }

    private func drop(_ payload: MenuBarElementDragPayload?, at index: Int) -> Bool {
        guard let payload else { return false }

        switch payload.source {
        case .placed(let instanceID, let fromSlot, let elementID):
            guard instanceID == model.instance.id else { return false }
            if fromSlot == slot {
                model.moveElement(id: elementID, to: index, slot: slot)
            } else {
                model.moveElement(id: elementID, from: fromSlot, to: slot, index: index)
            }
            selectedSlot = slot
            selectedElementID = elementID
            return true

        case .palette(let content):
            guard let id = model.insertElement(content, at: index, slot: slot) else { return false }
            selectedSlot = slot
            selectedElementID = id
            return true
        }
    }

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

/// Small popover for picking (or clearing) a row's leading icon.
struct MenuBarLeadingIconPicker: View {
    let spec: MenuBarIconSpec?
    let localization: Localization
    let onChange: (MenuBarIconSpec?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: Int
    @State private var value: String

    private func L(_ key: LocalizationKey) -> String { localization.string(key) }

    init(spec: MenuBarIconSpec?, localization: Localization, onChange: @escaping (MenuBarIconSpec?) -> Void) {
        self.spec = spec
        self.localization = localization
        self.onChange = onChange
        let initialKind: Int
        let initialValue: String
        switch spec?.source {
        case .sfSymbol(let name):
            initialKind = 0
            initialValue = name
        case .emoji(let emoji):
            initialKind = 1
            initialValue = emoji
        case .asset(let name):
            initialKind = 2
            initialValue = name
        case nil:
            initialKind = 0
            initialValue = ""
        }
        _kind = State(initialValue: initialKind)
        _value = State(initialValue: initialValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L(.menuBarEditorLeadingIcon))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("", selection: $kind) {
                Text("SF Symbol").tag(0)
                Text(L(.menuBarEditorIconEmoji)).tag(1)
                Text(L(.menuBarEditorIconAsset)).tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField(placeholder, text: $value)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button(L(.menuBarEditorNone)) {
                    onChange(nil)
                    dismiss()
                }

                Spacer(minLength: 0)

                Button(L(.menuBarEditorAdd)) {
                    apply()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    private var placeholder: String {
        switch kind {
        case 1: return L(.menuBarEditorIconEmoji)
        case 2: return L(.menuBarEditorIconAsset)
        default: return L(.menuBarEditorIconSymbol)
        }
    }

    private func apply() {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onChange(nil)
            dismiss()
            return
        }
        let source: MenuBarIconSource
        switch kind {
        case 1: source = .emoji(trimmed)
        case 2: source = .asset(trimmed)
        default: source = .sfSymbol(trimmed)
        }
        onChange(MenuBarIconSpec(source: source, tint: kind != 1))
        dismiss()
    }
}

/// Element library shown under the menu-bar strip.
///
/// Clicking a chip adds it to the chosen row; chips can also be dragged into
/// either row. The explicit "add to" picker keeps the target visible instead of
/// relying on whichever row happened to be selected last.
struct MenuBarElementPalette: View {
    @ObservedObject var model: MenuBarInstanceEditorModel
    let localization: Localization
    @Binding var selectedSlot: MenuBarLineSlot
    @Binding var selectedElementID: UUID?

    private func L(_ key: LocalizationKey) -> String { localization.string(key) }

    private var isDoubleLine: Bool { model.instance.layoutMode == .doubleLine }
    private var targetSlot: MenuBarLineSlot { isDoubleLine ? selectedSlot : .top }

    var body: some View {
        SettingsGroup(L(.menuBarEditorLibrary)) {
            VStack(alignment: .leading, spacing: 12) {
                if isDoubleLine {
                    HStack(spacing: 8) {
                        Text(L(.menuBarEditorAddTo))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 8)

                        Picker("", selection: $selectedSlot) {
                            Text(L(.menuBarEditorTopRow)).tag(MenuBarLineSlot.top)
                            Text(L(.menuBarEditorBottomRow)).tag(MenuBarLineSlot.bottom)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 140, alignment: .trailing)
                        .accessibilityLabel(L(.menuBarEditorAddTo))
                    }
                }

                section(title: L(.menuBarEditorMetrics)) {
                    ForEach(MenuBarMetricID.allCases) { metric in
                        paletteChip(
                            .metric(metric),
                            title: L(MenuBarMetricRegistry.titleKey(for: metric)),
                            symbol: metric.editorSymbol
                        )
                    }
                }

                section(title: L(.menuBarEditorTextIcons)) {
                    paletteChip(.text(" "), title: L(.menuBarEditorSpace), symbol: "rectangle.dashed")
                    paletteChip(.text(""), title: L(.menuBarEditorText), symbol: "textformat")
                    paletteChip(
                        .icon(MenuBarIconSpec(source: .emoji("🔥"))),
                        title: "Emoji",
                        symbol: "face.smiling"
                    )
                    ForEach(["cpu", "memorychip", "gauge", "thermometer", "fan"], id: \.self) { name in
                        paletteChip(
                            .icon(MenuBarIconSpec(source: .sfSymbol(name))),
                            title: name,
                            symbol: name
                        )
                    }
                }
            }
            .padding(.horizontal, SettingsMetrics.rowPaddingH)
            .padding(.vertical, 10)
        }
    }

    private func section<Chips: View>(
        title: String,
        @ViewBuilder chips: () -> Chips
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            WrappingHStack(spacing: 6, rowSpacing: 6) {
                chips()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func paletteChip(
        _ content: MenuBarElementContent,
        title: String,
        symbol: String
    ) -> some View {
        MenuBarEditorChipLabel(title: title, systemImage: symbol, compact: true)
            .draggable(MenuBarElementDragPayload(source: .palette(content)))
            .onTapGesture { add(content) }
            .help(title)
            .accessibilityLabel(title)
            .accessibilityAction { add(content) }
    }

    private func add(_ content: MenuBarElementContent) {
        let slot = targetSlot
        let id: UUID?
        switch content {
        case .metric(let metric):
            id = model.addMetricElement(metric, slot: slot)
        case .text(let text):
            id = model.addTextElement(text, slot: slot)
        case .icon(let icon):
            id = model.addIconElement(icon, slot: slot)
        }
        if let id {
            selectedSlot = slot
            selectedElementID = id
        }
    }
}

extension MenuBarMetricID {
    /// SF Symbol used by the editor and the element library.
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
