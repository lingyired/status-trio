import SwiftUI

struct MenuBarInstanceEditorView: View {
    @ObservedObject var model: MenuBarInstanceEditorModel
    @State private var selectedSlot: MenuBarLineSlot = .top
    @State private var selectedElementID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Layout").font(.headline)
                    Picker("Layout", selection: Binding(
                        get: { model.instance.layoutMode },
                        set: { model.setLayoutMode($0) }
                    )) {
                        Text("Single line").tag(MenuBarLayoutMode.singleLine)
                        Text("Double line").tag(MenuBarLayoutMode.doubleLine)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 260)
                    Spacer()
                }

                GroupBox("Preview") {
                    HStack {
                        if let image = model.previewImage() {
                            Image(nsImage: image).padding(4)
                        } else {
                            Text("No content").foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                MenuBarRowCanvasView(
                    model: model, slot: .top, title: "Top row",
                    selectedSlot: $selectedSlot, selectedElementID: $selectedElementID
                )
                if model.instance.layoutMode == .doubleLine {
                    MenuBarRowCanvasView(
                        model: model, slot: .bottom, title: "Bottom row",
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
        GroupBox("Selected element") {
            if let element = selectedElement {
                switch element.content {
                case .text:
                    TextField("Text", text: Binding(
                        get: { if case .text(let value) = element.content { return value } else { return "" } },
                        set: { model.updateText($0, elementID: element.id, slot: selectedSlot) }
                    ))
                case .metric(let metric):
                    Text("Data source: \(metric.rawValue)")
                        .foregroundStyle(.secondary)
                case .icon:
                    Text("Icon element (edit in the palette)")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Click an element in a row to edit it.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var rowStyleControls: some View {
        GroupBox("Row style (\(selectedSlot == .top ? "top" : "bottom"))") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle("Bold", isOn: Binding(
                        get: { (selectedSlot == .top ? model.instance.top : model.instance.bottom)?.isBold ?? false },
                        set: { model.setBold($0, slot: selectedSlot) }
                    ))
                    Toggle("Monospaced digits", isOn: Binding(
                        get: { (selectedSlot == .top ? model.instance.top : model.instance.bottom)?.usesMonospacedDigits ?? true },
                        set: { model.setMonospacedDigits($0, slot: selectedSlot) }
                    ))
                }
                Picker("Alignment", selection: Binding(
                    get: { (selectedSlot == .top ? model.instance.top : model.instance.bottom)?.alignment ?? .leading },
                    set: { model.setAlignment($0, slot: selectedSlot) }
                )) {
                    Text("Leading").tag(LineAlignment.leading)
                    Text("Center").tag(LineAlignment.center)
                    Text("Trailing").tag(LineAlignment.trailing)
                }
                HStack {
                    Text("Color")
                    Menu("Color") {
                        Button("Inherit data source") { model.setColor(.inheritSource, slot: selectedSlot) }
                        Button("Fixed blue") { model.setColor(.fixed(ColorValue(red: 0.2, green: 0.45, blue: 1)), slot: selectedSlot) }
                        Button("Fixed green") { model.setColor(.fixed(ColorValue(red: 0.2, green: 0.75, blue: 0.35)), slot: selectedSlot) }
                        Button("Fixed red") { model.setColor(.fixed(ColorValue(red: 0.95, green: 0.25, blue: 0.2)), slot: selectedSlot) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var spacingAndInteraction: some View {
        GroupBox("Spacing & interaction") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Inner padding")
                    Slider(value: Binding(
                        get: { model.instance.innerPadding },
                        set: { model.setPadding(inner: $0, outer: model.instance.outerMargin) }
                    ), in: 0...24, step: 1)
                    Text("\(Int(model.instance.innerPadding))")
                }
                HStack {
                    Text("Outer margin")
                    Slider(value: Binding(
                        get: { model.instance.outerMargin },
                        set: { model.setPadding(inner: model.instance.innerPadding, outer: $0) }
                    ), in: 0...24, step: 1)
                    Text("\(Int(model.instance.outerMargin))")
                }
                activationMenu(title: "Click", current: model.instance.clickAction, allowExternal: true) {
                    model.setActivation(click: $0, hover: model.instance.hoverAction, rightClick: model.instance.rightClick)
                }
                activationMenu(title: "Hover", current: model.instance.hoverAction, allowExternal: false) {
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
                Button("None") { onSelect(.none) }
                Button("Summary panel") { onSelect(.panel("summary")) }
                Button("CPU") { onSelect(.panel("cpu")) }
                Button("GPU") { onSelect(.panel("gpu")) }
                Button("Memory") { onSelect(.panel("memory")) }
                Button("Battery") { onSelect(.panel("battery")) }
                if allowExternal {
                    Divider()
                    Button("App Settings") { onSelect(.openAppSettings) }
                    Button("Activity Monitor") { onSelect(.openActivityMonitor) }
                    Button("Wi-Fi Settings") { onSelect(.openSystemSettings(.wifi)) }
                }
            }
        }
    }

    private func activationLabel(_ activation: InstanceActivation) -> String {
        switch activation {
        case .none: return "None"
        case .sameAsMainIcon: return "Same as main icon"
        case .panel(let raw): return "Panel: \(raw)"
        case .openAppSettings: return "App Settings"
        case .openActivityMonitor: return "Activity Monitor"
        case .openSystemSettings(let pane): return "System Settings: \(pane.rawValue)"
        }
    }
}
