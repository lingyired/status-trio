import SwiftUI

/// Edits the selected menu-bar instance.
///
/// The editor is a normal Settings page column: the item's basics, its two
/// rows, the selected element, and the line-level styling and interaction
/// settings. The live preview stays pinned above the page. Nothing here
/// depends on a separate palette column or an implicit "selected row"; every
/// control says which instance and which row it edits.
struct MenuBarInstanceEditorView: View {
    @ObservedObject var model: MenuBarInstanceEditorModel
    let localization: Localization

    @State private var selectedSlot: MenuBarLineSlot = .top
    @State private var selectedElementID: UUID?

    private func L(_ key: LocalizationKey) -> String { localization.string(key) }

    var body: some View {
        Group {
            basicsGroup
            contentGroup
            paletteGroup
            rowStyleGroup
            spacingAndInteractionGroup
        }
    }

    // MARK: - Basics

    private var basicsGroup: some View {
        SettingsGroup {
            SettingsRow("tag", title: L(.menuBarEditorName)) {
                TextField(L(.menuBarEditorUntitled), text: Binding(
                    get: { model.instance.name },
                    set: { model.setName($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, maxWidth: 200)
                .accessibilityLabel(L(.menuBarEditorName))
            }

            SettingsDivider()

            SettingsRow("rectangle.split.2x1", title: L(.menuBarEditorLayout)) {
                Picker("", selection: Binding(
                    get: { model.instance.layoutMode },
                    set: { mode in
                        model.setLayoutMode(mode)
                        if mode == .singleLine {
                            selectedSlot = .top
                            selectedElementID = nil
                        }
                    }
                )) {
                    Text(L(.menuBarEditorSingleLine)).tag(MenuBarLayoutMode.singleLine)
                    Text(L(.menuBarEditorDoubleLine)).tag(MenuBarLayoutMode.doubleLine)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160, alignment: .trailing)
            }
        }
    }

    // MARK: - Content

    private var contentGroup: some View {
        SettingsGroup(
            L(.menuBarEditorStrip),
            footnote: selectedElement == nil ? L(.menuBarEditorSelectHint) : nil
        ) {
            MenuBarRowCanvasView(
                model: model,
                slot: .top,
                title: L(.menuBarEditorTopRow),
                localization: localization,
                selectedSlot: $selectedSlot,
                selectedElementID: $selectedElementID
            )

            if selectedSlot == .top, let element = selectedElement(in: .top) {
                SettingsDivider()
                elementInspector(element)
            }

            if model.instance.layoutMode == .doubleLine {
                SettingsDivider()
                MenuBarRowCanvasView(
                    model: model,
                    slot: .bottom,
                    title: L(.menuBarEditorBottomRow),
                    localization: localization,
                    selectedSlot: $selectedSlot,
                    selectedElementID: $selectedElementID
                )

                if selectedSlot == .bottom, let element = selectedElement(in: .bottom) {
                    SettingsDivider()
                    elementInspector(element)
                }
            }
        }
    }

    private var selectedElement: MenuBarElement? {
        selectedElement(in: selectedSlot)
    }

    private func selectedElement(in slot: MenuBarLineSlot) -> MenuBarElement? {
        model.elements(slot: slot).first { $0.id == selectedElementID }
    }

    private var paletteGroup: some View {
        MenuBarElementPalette(
            model: model,
            localization: localization,
            selectedSlot: $selectedSlot,
            selectedElementID: $selectedElementID
        )
    }

    private func elementInspector(_ element: MenuBarElement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L(.menuBarEditorSelectedElement))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button {
                    selectedElementID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L(.commonCloseDetail))
                .help(L(.commonCloseDetail))
            }

            switch element.content {
            case .text:
                TextField(L(.menuBarEditorText), text: Binding(
                    get: {
                        if case .text(let value) = element.content { return value }
                        return ""
                    },
                    set: { model.updateText($0, elementID: element.id, slot: selectedSlot) }
                ))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(L(.menuBarEditorText))

            case .metric(let metric):
                Text(localization.format(
                    .menuBarEditorDataSourceFormat,
                    L(MenuBarMetricRegistry.titleKey(for: metric))
                ))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            case .icon(let icon):
                iconEditor(icon: icon, elementID: element.id)
            }

            elementActions(element)
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, 10)
    }

    private func elementActions(_ element: MenuBarElement) -> some View {
        let elements = model.elements(slot: selectedSlot)
        let index = elements.firstIndex { $0.id == element.id } ?? 0
        let selected = selectedElementID == element.id

        return HStack(spacing: 8) {
            Button(L(.menuBarEditorMoveLeft)) {
                model.moveElement(id: element.id, to: index - 1, slot: selectedSlot)
            }
            .disabled(index == 0)

            Button(L(.menuBarEditorMoveRight)) {
                model.moveElement(id: element.id, to: index + 1, slot: selectedSlot)
            }
            .disabled(index >= elements.count - 1)

            Spacer(minLength: 8)

            Button(L(.menuBarEditorDelete), role: .destructive) {
                model.removeElement(id: element.id, slot: selectedSlot)
                if selected { selectedElementID = nil }
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private func iconEditor(icon: MenuBarIconSpec, elementID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: Binding(
                get: { iconKind(icon) },
                set: { kind in
                    model.updateIcon(
                        iconWithKind(kind, text: iconText(icon), tint: icon.tint),
                        elementID: elementID,
                        slot: selectedSlot
                    )
                }
            )) {
                Text("SF Symbol").tag(0)
                Text(L(.menuBarEditorIconEmoji)).tag(1)
                Text(L(.menuBarEditorIconAsset)).tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(L(.menuBarEditorIconType))

            TextField(iconPlaceholder(icon), text: Binding(
                get: { iconText(icon) },
                set: { text in
                    model.updateIcon(
                        iconWithKind(iconKind(icon), text: text, tint: icon.tint),
                        elementID: elementID,
                        slot: selectedSlot
                    )
                }
            ))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(L(.menuBarEditorIconType))
        }
    }

    private func iconKind(_ icon: MenuBarIconSpec) -> Int {
        switch icon.source {
        case .sfSymbol: return 0
        case .emoji: return 1
        case .asset: return 2
        }
    }

    private func iconText(_ icon: MenuBarIconSpec) -> String {
        switch icon.source {
        case .sfSymbol(let name): return name
        case .emoji(let value): return value
        case .asset(let name): return name
        }
    }

    private func iconPlaceholder(_ icon: MenuBarIconSpec) -> String {
        switch icon.source {
        case .sfSymbol: return L(.menuBarEditorIconSymbol)
        case .emoji: return L(.menuBarEditorIconEmoji)
        case .asset: return L(.menuBarEditorIconAsset)
        }
    }

    private func iconWithKind(_ kind: Int, text: String, tint: Bool) -> MenuBarIconSpec {
        switch kind {
        case 0: return MenuBarIconSpec(source: .sfSymbol(text), tint: tint)
        case 1: return MenuBarIconSpec(source: .emoji(text), tint: false)
        default: return MenuBarIconSpec(source: .asset(text), tint: tint)
        }
    }

    // MARK: - Row style

    private var rowStyleGroup: some View {
        SettingsGroup(L(.menuBarEditorRowStyle)) {
            if model.instance.layoutMode == .doubleLine {
                SettingsRow("rectangle.split.2x1", title: L(.menuBarEditorApplyTo)) {
                    Picker("", selection: Binding(
                        get: { selectedSlot },
                        set: { slot in
                            selectedSlot = slot
                            selectedElementID = nil
                        }
                    )) {
                        Text(L(.menuBarEditorTopRow)).tag(MenuBarLineSlot.top)
                        Text(L(.menuBarEditorBottomRow)).tag(MenuBarLineSlot.bottom)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160, alignment: .trailing)
                    .accessibilityLabel(L(.menuBarEditorApplyTo))
                }

                SettingsDivider()
            }

            SettingsToggleRow(symbol: "bold", title: L(.menuBarEditorBold), isOn: Binding(
                get: { currentLine?.isBold ?? false },
                set: { model.setBold($0, slot: selectedSlot) }
            ))

            SettingsDivider()

            SettingsToggleRow(symbol: "textformat.123", title: L(.menuBarEditorMonospaced), isOn: Binding(
                get: { currentLine?.usesMonospacedDigits ?? true },
                set: { model.setMonospacedDigits($0, slot: selectedSlot) }
            ))

            SettingsDivider()

            SettingsRow("text.alignleft", title: L(.menuBarEditorAlignment)) {
                Picker("", selection: Binding(
                    get: { currentLine?.alignment ?? .leading },
                    set: { model.setAlignment($0, slot: selectedSlot) }
                )) {
                    Text(L(.menuBarEditorLeading)).tag(LineAlignment.leading)
                    Text(L(.menuBarEditorCenter)).tag(LineAlignment.center)
                    Text(L(.menuBarEditorTrailing)).tag(LineAlignment.trailing)
                }
                .labelsHidden()
                .frame(width: 120, alignment: .trailing)
                .accessibilityLabel(L(.menuBarEditorAlignment))
            }

            SettingsDivider()

            SettingsRow("paintpalette", title: L(.menuBarEditorColor)) {
                Menu {
                    Button(L(.menuBarEditorInherit)) { model.setColor(.inheritSource, slot: selectedSlot) }
                    Button(L(.menuBarEditorFixedBlue)) {
                        model.setColor(.fixed(ColorValue(red: 0.2, green: 0.45, blue: 1)), slot: selectedSlot)
                    }
                    Button(L(.menuBarEditorFixedGreen)) {
                        model.setColor(.fixed(ColorValue(red: 0.2, green: 0.75, blue: 0.35)), slot: selectedSlot)
                    }
                    Button(L(.menuBarEditorFixedRed)) {
                        model.setColor(.fixed(ColorValue(red: 0.95, green: 0.25, blue: 0.2)), slot: selectedSlot)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(lineColorSwatch)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                        Text(lineColorName)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel(L(.menuBarEditorColor))
            }
        }
    }

    private var currentLine: MenuBarLine? {
        switch selectedSlot {
        case .top: return model.instance.top
        case .bottom: return model.instance.bottom
        }
    }

    private var lineColorName: String {
        switch currentLine?.color ?? .inheritSource {
        case .inheritSource:
            return L(.menuBarEditorInherit)
        case .fixed(let value):
            if matches(value, red: 0.2, green: 0.45, blue: 1) { return L(.menuBarEditorFixedBlue) }
            if matches(value, red: 0.2, green: 0.75, blue: 0.35) { return L(.menuBarEditorFixedGreen) }
            if matches(value, red: 0.95, green: 0.25, blue: 0.2) { return L(.menuBarEditorFixedRed) }
            return String(
                format: "#%02X%02X%02X",
                Int((value.red * 255).rounded()),
                Int((value.green * 255).rounded()),
                Int((value.blue * 255).rounded())
            )
        }
    }

    private var lineColorSwatch: Color {
        switch currentLine?.color ?? .inheritSource {
        case .inheritSource:
            return Color.secondary.opacity(0.35)
        case .fixed(let value):
            return Color(red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
        }
    }

    private func matches(_ value: ColorValue, red: Double, green: Double, blue: Double) -> Bool {
        abs(value.red - red) < 0.01 && abs(value.green - green) < 0.01 && abs(value.blue - blue) < 0.01
    }

    // MARK: - Spacing and interaction

    private var spacingAndInteractionGroup: some View {
        SettingsGroup(L(.menuBarEditorSpacing)) {
            spacingSliderRow(
                symbol: "rectangle.inset.filled",
                title: L(.menuBarEditorInnerPadding),
                value: Binding(
                    get: { model.instance.innerPadding },
                    set: { model.setPadding(inner: $0.rounded(), outer: model.instance.outerMargin) }
                ),
                range: 0...24,
                display: "\(Int(model.instance.innerPadding))"
            )

            SettingsDivider()

            spacingSliderRow(
                symbol: "rectangle.expand.vertical",
                title: L(.menuBarEditorOuterMargin),
                value: Binding(
                    get: { model.instance.outerMargin },
                    set: { model.setPadding(inner: model.instance.innerPadding, outer: $0.rounded()) }
                ),
                range: 0...24,
                display: "\(Int(model.instance.outerMargin))"
            )

            SettingsDivider()

            spacingSliderRow(
                symbol: "arrow.left.and.right",
                title: L(.menuBarEditorMinimumWidth),
                value: Binding(
                    get: { model.instance.minimumWidth ?? 0 },
                    set: { model.setMinimumWidth(($0 / 10).rounded() * 10) }
                ),
                range: 0...400,
                display: "\(Int(model.instance.minimumWidth ?? 0))"
            )

            SettingsDivider()

            SettingsRow("cursorarrow.click", title: L(.menuBarEditorClick)) {
                activationMenu(current: model.instance.clickAction, allowExternal: true) {
                    model.setActivation(
                        click: $0,
                        hover: model.instance.hoverAction,
                        rightClick: model.instance.rightClick
                    )
                }
            }

            SettingsDivider()

            SettingsRow("cursorarrow.motionlines", title: L(.menuBarEditorHover)) {
                activationMenu(current: model.instance.hoverAction, allowExternal: false) {
                    model.setActivation(
                        click: model.instance.clickAction,
                        hover: $0,
                        rightClick: model.instance.rightClick
                    )
                }
            }
        }
    }

    private func spacingSliderRow(
        symbol: String,
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: String
    ) -> some View {
        SettingsRow(symbol, title: title) {
            HStack(spacing: 8) {
                // No `step:` here: the default macOS slider draws a dotted
                // tick track when it has discrete steps. Round in the setter
                // instead, so the three rows share one clean 150 + 32 layout.
                Slider(value: value, in: range)
                    .frame(width: 150)
                    .accessibilityLabel(title)

                Text(display)
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
            }
        }
    }

    private func activationMenu(
        current: InstanceActivation,
        allowExternal: Bool,
        onSelect: @escaping (InstanceActivation) -> Void
    ) -> some View {
        Menu(activationLabel(current)) {
            Button(L(.menuBarEditorNone)) { onSelect(.none) }
            Button(L(.menuBarEditorSummaryPanel)) { onSelect(.panel("summary")) }
            Button(L(.hardwareMonitorCPU)) { onSelect(.panel("cpu")) }
            Button(L(.hardwareMonitorGPU)) { onSelect(.panel("gpu")) }
            Button(L(.hardwareMonitorMemory)) { onSelect(.panel("memory")) }
            Button(L(.hardwareMonitorBattery)) { onSelect(.panel("battery")) }
            if allowExternal {
                Divider()
                Button(L(.menuBarEditorAppSettings)) { onSelect(.openAppSettings) }
                Button(L(.menuBarEditorActivityMonitor)) { onSelect(.openActivityMonitor) }
                Button(L(.menuBarEditorWifiSettings)) { onSelect(.openSystemSettings(.wifi)) }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func activationLabel(_ activation: InstanceActivation) -> String {
        switch activation {
        case .none: return L(.menuBarEditorNone)
        case .sameAsMainIcon: return L(.menuBarEditorSameAsMain)
        case .panel(let raw):
            let name: String
            switch raw {
            case "summary": name = L(.menuBarEditorSummaryPanel)
            case "cpu": name = L(.hardwareMonitorCPU)
            case "gpu": name = L(.hardwareMonitorGPU)
            case "memory": name = L(.hardwareMonitorMemory)
            case "battery": name = L(.hardwareMonitorBattery)
            default: name = raw
            }
            return localization.format(.menuBarEditorPanelFormat, name)
        case .openAppSettings: return L(.menuBarEditorAppSettings)
        case .openActivityMonitor: return L(.menuBarEditorActivityMonitor)
        case .openSystemSettings(let pane):
            return localization.format(.menuBarEditorSystemSettingsFormat, pane.rawValue)
        }
    }
}
