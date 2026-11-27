import SwiftUI

struct MenuBarInstanceEditorView: View {
    @ObservedObject var model: MenuBarInstanceEditorModel
    let localization: Localization
    @Binding var selectedSlot: MenuBarLineSlot
    @State private var selectedElementID: UUID?

    private func L(_ key: LocalizationKey) -> String { localization.string(key) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsGroup(L(.menuBarEditorName)) {
                    TextField(L(.menuBarEditorUntitled), text: Binding(
                        get: { model.instance.name },
                        set: { model.setName($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, SettingsMetrics.rowPaddingH)
                    .padding(.vertical, 8)
                }

                HStack {
                    Text(L(.menuBarEditorLayout)).font(.headline)
                    Picker("", selection: Binding(
                        get: { model.instance.layoutMode },
                        set: { model.setLayoutMode($0) }
                    )) {
                        Text(L(.menuBarEditorSingleLine)).tag(MenuBarLayoutMode.singleLine)
                        Text(L(.menuBarEditorDoubleLine)).tag(MenuBarLayoutMode.doubleLine)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 240)
                    Spacer()
                }

                SettingsGroup(L(.menuBarEditorPreview)) {
                    HStack {
                        HStack {
                            if let image = model.previewImage() {
                                Image(nsImage: image).padding(.horizontal, 10).padding(.vertical, 6)
                            } else {
                                Text(L(.menuBarEditorNoContent)).foregroundStyle(.secondary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.82)))
                        Spacer()
                    }
                    .padding(.horizontal, SettingsMetrics.rowPaddingH)
                    .padding(.vertical, 8)
                }

                MenuBarRowCanvasView(
                    model: model, slot: .top, title: L(.menuBarEditorTopRow), localization: localization,
                    selectedSlot: $selectedSlot, selectedElementID: $selectedElementID
                )
                if model.instance.layoutMode == .doubleLine {
                    MenuBarRowCanvasView(
                        model: model, slot: .bottom, title: L(.menuBarEditorBottomRow), localization: localization,
                        selectedSlot: $selectedSlot, selectedElementID: $selectedElementID
                    )
                }

                removeDropTarget
                elementInspector
                rowStyleControls
                spacingAndInteraction
            }
            .padding(16)
        }
    }

    private var removeDropTarget: some View {
        let hasSelection = selectedElementID != nil
        return HStack(spacing: 6) {
            Image(systemName: "trash")
            Text(hasSelection ? L(.menuBarEditorRemoveSelected) : L(.menuBarEditorDragRemove))
        }
        .font(.caption)
        .foregroundStyle(hasSelection ? Color.primary : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.secondary.opacity(hasSelection ? 0.12 : 0.06)))
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture {
            if let id = selectedElementID {
                model.removeElement(id: id, slot: selectedSlot)
                selectedElementID = nil
            }
        }
        .dropDestination(for: MenuBarElementDragPayload.self) { payloads, _ in
            guard let payload = payloads.first, case let .placed(_, slot, id) = payload.source else { return false }
            model.removeElement(id: id, slot: slot)
            selectedElementID = nil
            return true
        }
    }

    private var selectedElement: MenuBarElement? {
        model.elements(slot: selectedSlot).first { $0.id == selectedElementID }
    }

    @ViewBuilder
    private var elementInspector: some View {
        SettingsGroup(L(.menuBarEditorSelectedElement)) {
            if let element = selectedElement {
                switch element.content {
                case .text:
                    TextField(L(.menuBarEditorText), text: Binding(
                        get: { if case .text(let value) = element.content { return value } else { return "" } },
                        set: { model.updateText($0, elementID: element.id, slot: selectedSlot) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, SettingsMetrics.rowPaddingH)
                    .padding(.vertical, 8)
                case .metric(let metric):
                    SettingsRow("chart.bar", title: localization.format(.menuBarEditorDataSourceFormat, L(MenuBarMetricRegistry.titleKey(for: metric)))) { EmptyView() }
                case .icon:
                    SettingsHintRow(text: L(.menuBarEditorIconHint))
                }
            } else {
                SettingsHintRow(text: L(.menuBarEditorSelectHint))
            }
        }
    }

    @ViewBuilder
    private var rowStyleControls: some View {
        SettingsGroup(localization.format(.menuBarEditorRowStyleFormat, selectedSlot == .top ? L(.menuBarEditorTopRow) : L(.menuBarEditorBottomRow))) {
            SettingsToggleRow(symbol: "bold", title: L(.menuBarEditorBold), isOn: Binding(
                get: { (selectedSlot == .top ? model.instance.top : model.instance.bottom)?.isBold ?? false },
                set: { model.setBold($0, slot: selectedSlot) }
            ))
            SettingsDivider()
            SettingsToggleRow(symbol: "textformat.123", title: L(.menuBarEditorMonospaced), isOn: Binding(
                get: { (selectedSlot == .top ? model.instance.top : model.instance.bottom)?.usesMonospacedDigits ?? true },
                set: { model.setMonospacedDigits($0, slot: selectedSlot) }
            ))
            SettingsDivider()
            SettingsRow("text.alignleft", title: L(.menuBarEditorAlignment)) {
                Picker("", selection: Binding(
                    get: { (selectedSlot == .top ? model.instance.top : model.instance.bottom)?.alignment ?? .leading },
                    set: { model.setAlignment($0, slot: selectedSlot) }
                )) {
                    Text(L(.menuBarEditorLeading)).tag(LineAlignment.leading)
                    Text(L(.menuBarEditorCenter)).tag(LineAlignment.center)
                    Text(L(.menuBarEditorTrailing)).tag(LineAlignment.trailing)
                }
                .labelsHidden()
                .frame(width: 120)
            }
            SettingsDivider()
            SettingsRow("paintpalette", title: L(.menuBarEditorColor)) {
                Menu(L(.menuBarEditorColor)) {
                    Button(L(.menuBarEditorInherit)) { model.setColor(.inheritSource, slot: selectedSlot) }
                    Button(L(.menuBarEditorFixedBlue)) { model.setColor(.fixed(ColorValue(red: 0.2, green: 0.45, blue: 1)), slot: selectedSlot) }
                    Button(L(.menuBarEditorFixedGreen)) { model.setColor(.fixed(ColorValue(red: 0.2, green: 0.75, blue: 0.35)), slot: selectedSlot) }
                    Button(L(.menuBarEditorFixedRed)) { model.setColor(.fixed(ColorValue(red: 0.95, green: 0.25, blue: 0.2)), slot: selectedSlot) }
                }
                .menuStyle(.borderlessButton)
            }
        }
    }

    @ViewBuilder
    private var spacingAndInteraction: some View {
        SettingsGroup(L(.menuBarEditorSpacing)) {
            SettingsRow("rectangle.inset.filled", title: L(.menuBarEditorInnerPadding)) {
                HStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { model.instance.innerPadding },
                        set: { model.setPadding(inner: $0, outer: model.instance.outerMargin) }
                    ), in: 0...24, step: 1).frame(width: 150)
                    Text("\(Int(model.instance.innerPadding))").monospacedDigit().frame(width: 24, alignment: .trailing)
                }
            }
            SettingsDivider()
            SettingsRow("rectangle.expand.vertical", title: L(.menuBarEditorOuterMargin)) {
                HStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { model.instance.outerMargin },
                        set: { model.setPadding(inner: model.instance.innerPadding, outer: $0) }
                    ), in: 0...24, step: 1).frame(width: 150)
                    Text("\(Int(model.instance.outerMargin))").monospacedDigit().frame(width: 24, alignment: .trailing)
                }
            }
            SettingsDivider()
            SettingsRow("cursorarrow.click", title: L(.menuBarEditorClick)) {
                activationMenu(current: model.instance.clickAction, allowExternal: true) {
                    model.setActivation(click: $0, hover: model.instance.hoverAction, rightClick: model.instance.rightClick)
                }
            }
            SettingsDivider()
            SettingsRow("cursorarrow.motionlines", title: L(.menuBarEditorHover)) {
                activationMenu(current: model.instance.hoverAction, allowExternal: false) {
                    model.setActivation(click: model.instance.clickAction, hover: $0, rightClick: model.instance.rightClick)
                }
            }
        }
    }

    private func activationMenu(
        current: InstanceActivation, allowExternal: Bool,
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
        .frame(maxWidth: 150)
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
        case .openSystemSettings(let pane): return localization.format(.menuBarEditorSystemSettingsFormat, pane.rawValue)
        }
    }
}
