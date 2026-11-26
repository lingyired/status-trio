import SwiftUI

struct MenuBarInstancesSectionView: View {
    @ObservedObject var store: SettingsStore
    @State private var editingID: UUID?

    private var model: MenuBarInstancesListModel { MenuBarInstancesListModel(store: store) }

    var body: some View {
        List {
            Section {
                if model.instances.isEmpty {
                    Text("No menu-bar instances yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.instances) { instance in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { instance.isEnabled },
                            set: { model.setEnabled($0, id: instance.id) }
                        ))
                        .labelsHidden()
                        Text(instance.name.isEmpty ? "Menu bar instance" : instance.name)
                        Spacer()
                        Button("Edit") { editingID = instance.id }
                        Button(role: .destructive) {
                            model.delete(id: instance.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onMove { offsets, destination in
                    model.move(from: offsets.first ?? 0, to: destination)
                }
            } header: {
                Text("Menu Bar Instances")
            } footer: {
                Text("Each instance is its own menu-bar item. Disabling keeps its slot; delete to remove it.")
                    .font(.caption)
            }

            Section("Add preset") {
                ForEach(MenuBarPreset.allCases) { preset in
                    Button(preset.titleKey.rawValue) { model.addPreset(preset) }
                        .disabled(!model.canAdd)
                }
            }
        }
        .listStyle(.inset)
        .sheet(isPresented: Binding(
            get: { editingID != nil },
            set: { if !$0 { editingID = nil } }
        )) {
            if let id = editingID {
                MenuBarInstanceEditorView(store: store, instanceID: id)
            }
        }
    }
}
