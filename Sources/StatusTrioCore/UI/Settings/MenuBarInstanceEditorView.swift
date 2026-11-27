import SwiftUI

struct MenuBarInstanceEditorView: View {
    @ObservedObject var model: MenuBarInstanceEditorModel
    let localization: Localization
    @State private var selectedSlot: MenuBarLineSlot = .top
    @State private var selectedElementID: UUID?

    private func L(_ key: LocalizationKey) -> String { localization.string(key) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
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

                GroupBox(L(.menuBarEditorPreview)) {
                    HStack {
                        if let image = model.previewImage() {
                            Image(nsImage: image).padding(4)
                        } else {
                            Text(L(.menuBarEditorNoContent)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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

                elementInspector
                rowStyleControls
                spacingAndInteraction
            }
            .padding(16)
        }
    }

    private var selectedElement: MenuBarElement? {
        model.elements(slot: selectedSlot).first { $0.id == selectedElementID }
    }

    @ViewBuilder
    private var elementInspector: some View {
        GroupBox(L(.menuBarEditorSelectedElement)) {
            if let element = selectedElement {
                switch element.content {
                case .text:
                    TextField(L(.menuBarEditorText), text: Binding(
                        get: { if case .text(let value) = element.content { return value } else { return "" } },
                        set: { model.updateText($0, elementID: element.id, slot: selectedSlot) }
                    ))
                case .metric(let metric):
                    Text(localization.format(.menuBarEditorDataSourceFormat, L(MenuBarMetricRegistry.titleKey(for: metric))))
                        .foregroundStyle(.secondary)
                case .icon:
                    Text(L(.menuBarEditorIconHint)).foregroundStyle(.secondary)
                }
            } else {
                Text(L(.menuBarEditorSelectHint)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var rowStyleControls: some View {
        GroupBox(localization.format(.menuBarEditorRowStyleFormat, selectedSlot == .top ? L(.menuBarEditorTopRow) : L(.menuBarEditorBottomRow))) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle(L(.menuBarEditorBold), isOn: Binding(
                        get: { (selectedSlot == .top ? model.instance.top : model.instance.bottom)?.isBold ?? false },
                        set: { model.setBold($0, slot: selectedSlot) }
                    ))
                    Toggle(L(.menuBarEditorMonospaced), isOn: Binding(
                        get: { (selectedSlot == .top ? model.instance.top : model.instance.bottom)?.usesMonospacedDigits ?? true },
                        set: { model.setMonospacedDigits($0, slot: selectedSlot) }
                    ))
                }
                Picker(L(.menuBarEditorAlignment), selection: Binding(
                    get: { (selectedSlot == .top ? model.instance.top : model.instance.bottom)?.alignment ?? .leading },
                    set: { model.setAlignment($0, slot: selectedSlot) }
                )) {
                    Text(L(.menuBarEditorLeading)).tag(LineAlignment.leading)
                    Text(L(.menuBarEditorCenter)).tag(LineAlignment.center)
                    Text(L(.menuBarEditorTrailing)).tag(LineAlignment.trailing)
                }
                HStack {
                    Text(L(.menuBarEditorColor))
                    Menu(L(.menuBarEditorColor)) {
                        Button(L(.menuBarEditorInherit)) { model.setColor(.inheritSource, slot: selectedSlot) }
                        Button(L(.menuBarEditorFixedBlue)) { model.setColor(.fixed(ColorValue(red: 0.2, green: 0.45, blue: 1)), slot: selectedSlot) }
                        Button(L(.menuBarEditorFixedGreen)) { model.setColor(.fixed(ColorValue(red: 0.2, green: 0.75, blue: 0.35)), slot: selectedSlot) }
                        Button(L(.menuBarEditorFixedRed)) { model.setColor(.fixed(ColorValue(red: 0.95, green: 0.25, blue: 0.2)), slot: selectedSlot) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var spacingAndInteraction: some View {
        GroupBox(L(.menuBarEditorSpacing)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L(.menuBarEditorInnerPadding))
                    Slider(value: Binding(
                        get: { model.instance.innerPadding },
                        set: { model.setPadding(inner: $0, outer: model.instance.outerMargin) }
                    ), in: 0...24, step: 1)
                    Text("\(Int(model.instance.innerPadding))")
                }
                HStack {
                    Text(L(.menuBarEditorOuterMargin))
                    Slider(value: Binding(
                        get: { model.instance.outerMargin },
                        set: { model.setPadding(inner: model.instance.innerPadding, outer: $0) }
                    ), in: 0...24, step: 1)
                    Text("\(Int(model.instance.outerMargin))")
                }
                activationMenu(title: L(.menuBarEditorClick), current: model.instance.clickAction, allowExternal: true) {
                    model.setActivation(click: $0, hover: model.instance.hoverAction, rightClick: model.instance.rightClick)
                }
                activationMenu(title: L(.menuBarEditorHover), current: model.instance.hoverAction, allowExternal: false) {
                    model.setActivation(click: model.instance.clickAction, hover: $0, rightClick: model.instance.rightClick)
                }
            }
        }
    }

    private func activationMenu(
        title: String, current: InstanceActivation, allowExternal: Bool,
        onSelect: @escaping (InstanceActivation) -> Void
    ) -> some View {
        HStack {
            Text(title)
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
        }
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
