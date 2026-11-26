import SwiftUI

struct MenuBarInstanceEditorView: View {
    @ObservedObject var store: SettingsStore
    let instanceID: UUID
    @StateObject private var model: MenuBarInstanceEditorModel

    init(store: SettingsStore, instanceID: UUID) {
        self.store = store
        self.instanceID = instanceID
        let instance = store.menuBarInstances.instances.first(where: { $0.id == instanceID })
            ?? MenuBarInstance.default()
        _model = StateObject(wrappedValue: MenuBarInstanceEditorModel(instance: instance, store: store))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Preview") {
                    HStack {
                        if let image = model.previewImage() {
                            Image(nsImage: image)
                                .padding(4)
                        } else {
                            Text("No content").foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                TextField("Name", text: Binding(
                    get: { model.instance.name },
                    set: { model.setName($0) }
                ))

                MenuBarLineChipEditorView(model: model, slot: .top, title: "Top line")
                MenuBarLineChipEditorView(model: model, slot: .bottom, title: "Bottom line")

                GroupBox("Spacing") {
                    VStack(alignment: .leading) {
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
                    }
                }

                GroupBox("Interaction") {
                    VStack(alignment: .leading, spacing: 8) {
                        activationMenu(title: "Click", current: model.instance.clickAction, allowExternal: true) { newValue in
                            model.setActivation(click: newValue, hover: model.instance.hoverAction, rightClick: model.instance.rightClick)
                        }
                        activationMenu(title: "Hover", current: model.instance.hoverAction, allowExternal: false) { newValue in
                            model.setActivation(click: model.instance.clickAction, hover: newValue, rightClick: model.instance.rightClick)
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 520, minHeight: 640)
    }

    private func activationMenu(
        title: String,
        current: InstanceActivation,
        allowExternal: Bool,
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
                Button("Network") { onSelect(.panel("network")) }
                Button("Disk") { onSelect(.panel("disk")) }
                Button("Fan") { onSelect(.panel("fan")) }
                Button("Battery") { onSelect(.panel("battery")) }
                if allowExternal {
                    Divider()
                    Button("Open App Settings") { onSelect(.openAppSettings) }
                    Button("Open Activity Monitor") { onSelect(.openActivityMonitor) }
                    Button("Open Wi-Fi Settings") { onSelect(.openSystemSettings(.wifi)) }
                    Button("Open Bluetooth Settings") { onSelect(.openSystemSettings(.bluetooth)) }
                    Button("Open Battery Settings") { onSelect(.openSystemSettings(.battery)) }
                }
            }
        }
    }

    private func activationLabel(_ activation: InstanceActivation) -> String {
        switch activation {
        case .none: return "None"
        case .sameAsMainIcon: return "Same as main icon"
        case .panel(let raw): return "Panel: \(raw)"
        case .openAppSettings: return "Open App Settings"
        case .openActivityMonitor: return "Open Activity Monitor"
        case .openSystemSettings(let pane): return "System Settings: \(pane.rawValue)"
        }
    }
}
