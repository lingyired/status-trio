import AppKit
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

/// Icon picker for a row's leading icon.
///
/// SF Symbols and emoji are shown as an even, searchable grid so choosing an
/// icon is visual rather than remembering its name; a compact custom-name
/// field remains for symbols outside the curated list.
struct MenuBarLeadingIconPicker: View {
    let spec: MenuBarIconSpec?
    let localization: Localization
    let onChange: (MenuBarIconSpec?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var search = ""
    @State private var customEmoji = ""
    @State private var customAsset = ""
    @State private var visibleCount = 240

    private static let pageSize = 240

    private func L(_ key: LocalizationKey) -> String { localization.string(key) }

    /// All symbols shipped by the running macOS. `CoreGlyphs` is the system
    /// bundle that also backs the SF Symbols app; reading its order list gives
    /// the complete catalog without hard-coding a subset.
    private static let systemSymbols: [String] = {
        let path = "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/symbol_order.plist"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let names = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String],
              !names.isEmpty else {
            return fallbackSymbols
        }
        // Drop localized variants and numeral-prefixed glyphs; they are valid
        // system symbols but make the default grid noise.
        let localizedSuffixes = [
            ".ar", ".hi", ".he", ".th", ".ja", ".ko", ".ru", ".zh", ".my",
            ".bn", ".gu", ".kn", ".ml", ".mr", ".or", ".pa", ".ta", ".te",
            ".ur", ".vi"
        ]
        return names.filter { name in
            guard let first = name.first, !first.isNumber else { return false }
            return !localizedSuffixes.contains { name.hasSuffix($0) }
        }
    }()

    /// Keep the familiar, task-relevant icons at the top of the grid, then
    /// expose the rest of the system catalog alphabetically.
    private static let orderedSymbols: [String] = {
        var seen = Set<String>()
        var result: [String] = []
        for name in fallbackSymbols + systemSymbols.sorted() where seen.insert(name).inserted {
            result.append(name)
        }
        return result
    }()

    /// Small safety net for systems where the CoreGlyphs bundle cannot be read.
    private static let fallbackSymbols: [String] = [
        // Arrows and navigation
        "arrow.up", "arrow.down", "arrow.left", "arrow.right",
        "arrow.up.circle", "arrow.down.circle", "arrow.left.arrow.right",
        "arrow.up.arrow.down", "arrow.up.to.line", "arrow.down.to.line",
        "chevron.up", "chevron.down", "chevron.left", "chevron.right",
        "arrow.up.right", "arrow.down.left", "arrow.clockwise", "arrow.triangle.2.circlepath",
        // Network
        "wifi", "wifi.exclamationmark", "wifi.slash", "network", "globe",
        "antenna.radiowaves.left.and.right", "dot.radiowaves.left.and.right",
        "cable.connector", "cloud", "cloud.fill",
        // System and power
        "power", "bolt.fill", "bolt.slash", "sleep", "moon.fill", "sun.max.fill",
        "battery.100", "battery.75", "battery.50", "battery.25", "battery.0",
        "display", "desktopcomputer", "laptopcomputer", "iphone", "ipad",
        "applewatch", "airpods", "headphones", "speaker.wave.2", "speaker.slash",
        // Hardware and metrics
        "cpu", "cpu.fill", "memorychip", "internaldrive", "externaldrive",
        "gauge", "gauge.with.dots.needle.50percent", "thermometer.low",
        "thermometer.medium", "thermometer.high", "fan", "fan.fill",
        "chart.bar.fill", "chart.line.uptrend.xyaxis", "chart.pie.fill",
        // Media and misc
        "play.fill", "pause.fill", "backward.fill", "forward.fill",
        "music.note", "microphone", "video", "camera",
        "gearshape", "gearshape.fill", "star.fill", "heart.fill", "bell.fill",
        "clock", "calendar", "checkmark.circle", "exclamationmark.triangle",
        "info.circle", "questionmark.circle", "plus", "minus", "xmark", "ellipsis"
    ]

    private static let emoji: [String] = [
        "⬆️", "⬇️", "⬅️", "➡️", "🔄", "⚡️", "🔥", "❤️",
        "✅", "⚠️", "📶", "🔋", "🖥", "💻", "📱", "🎧",
        "🔊", "🔇", "🌐", "☁️", "🌡", "💾", "📀", "⏱",
        "🕐", "📊", "📈", "⏰", "🚀", "⭐️", "✨", "🎯"
    ]

    private var filteredSymbols: [String] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Self.orderedSymbols }
        return Self.orderedSymbols.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var visibleSymbols: [String] {
        Array(filteredSymbols.prefix(visibleCount))
    }

    private var hasMoreSymbols: Bool {
        visibleCount < filteredSymbols.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Picker("", selection: $tab) {
                Text("SF Symbol").tag(0)
                Text(L(.menuBarEditorIconEmoji)).tag(1)
                Text(L(.menuBarEditorIconAsset)).tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case 0: symbolGrid
            case 1: emojiGrid
            default: assetEntry
            }

            Divider()

            Button {
                onChange(nil)
                dismiss()
            } label: {
                Label(L(.menuBarEditorNone), systemImage: "xmark.circle")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                currentIconPreview
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(L(.menuBarEditorLeadingIcon))
                    .font(.system(size: 12, weight: .semibold))
                Text(iconDescription)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var currentIconPreview: some View {
        switch spec?.source {
        case .sfSymbol(let name):
            if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
                Image(systemName: name)
                    .font(.system(size: 17))
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .font(.system(size: 17))
            }
        case .emoji(let value):
            Text(value).font(.system(size: 19))
        case .asset:
            Image(systemName: "photo")
                .font(.system(size: 17))
        case nil:
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    private var iconDescription: String {
        switch spec?.source {
        case .sfSymbol(let name): return name
        case .emoji(let value): return value
        case .asset(let name): return name
        case nil: return L(.menuBarEditorNone)
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(34), spacing: 6), count: 8)
    }

    private var symbolGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField

            ScrollView {
                if filteredSymbols.isEmpty {
                    Text(L(.menuBarEditorNoContent))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 18)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 6) {
                        ForEach(visibleSymbols, id: \.self) { name in
                            IconPickerTile(
                                symbol: name,
                                isSelected: isSelected(.sfSymbol(name))
                            ) {
                                apply(MenuBarIconSpec(source: .sfSymbol(name)))
                            }
                            .help(name)
                            .accessibilityLabel(name)
                        }
                    }
                    .padding(2)

                    if hasMoreSymbols {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .onAppear {
                                visibleCount += Self.pageSize
                            }
                    }
                }
            }
            .frame(height: 236)
            .onChange(of: search) { _ in
                visibleCount = Self.pageSize
            }

        }
    }

    private var emojiGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 6) {
                    ForEach(Self.emoji, id: \.self) { emoji in
                        IconPickerTile(
                            emoji: emoji,
                            isSelected: isSelected(.emoji(emoji))
                        ) {
                            apply(MenuBarIconSpec(source: .emoji(emoji), tint: false))
                        }
                    }
                }
                .padding(2)
            }
            .frame(height: 236)

            HStack(spacing: 8) {
                TextField(L(.menuBarEditorIconEmoji), text: $customEmoji)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addCustomEmoji() }
                Button(L(.menuBarEditorAdd)) { addCustomEmoji() }
                    .disabled(customEmoji.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var assetEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(L(.menuBarEditorIconAsset), text: $customAsset)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addCustomAsset() }
                Button(L(.menuBarEditorAdd)) { addCustomAsset() }
                    .disabled(customAsset.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer(minLength: 0)
                .frame(height: 236)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField(L(.menuBarEditorSearchIcons), text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private func isSelected(_ source: MenuBarIconSource) -> Bool {
        spec?.source == source
    }

    private func apply(_ icon: MenuBarIconSpec) {
        onChange(icon)
        dismiss()
    }

    private func addCustomEmoji() {
        let value = customEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        apply(MenuBarIconSpec(source: .emoji(value), tint: false))
    }

    private func addCustomAsset() {
        let name = customAsset.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        apply(MenuBarIconSpec(source: .asset(name)))
    }
}

private struct IconPickerTile: View {
    var symbol: String? = nil
    var emoji: String? = nil
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .regular))
                } else if let emoji {
                    Text(emoji)
                        .font(.system(size: 18))
                }
            }
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.22)
                            : Color.primary.opacity(isHovering ? 0.08 : 0)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// Element library shown under the menu-bar strip./// Element library shown under the menu-bar strip.
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
