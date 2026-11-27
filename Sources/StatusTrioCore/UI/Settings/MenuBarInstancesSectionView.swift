import SwiftUI

/// Three-column editor: instance list | layout canvas | element palette.
struct MenuBarInstancesSectionView: View {
    @ObservedObject var store: SettingsStore
    let localization: Localization
    @State private var selectedID: UUID?
    @State private var model: MenuBarInstanceEditorModel?

    private var listModel: MenuBarInstancesListModel { MenuBarInstancesListModel(store: store) }
    private func L(_ key: LocalizationKey) -> String { localization.string(key) }

    var body: some View {
        HSplitView {
            instanceColumn.frame(minWidth: 170, idealWidth: 200, maxWidth: 260)
            canvasColumn.frame(minWidth: 320)
            paletteColumn.frame(minWidth: 190, idealWidth: 210, maxWidth: 260)
        }
        .onAppear { ensureSelection() }
        .onChange(of: store.menuBarInstances) { _ in ensureSelection() }
        .onChange(of: selectedID) { _ in rebuildModel() }
    }

    private var instanceColumn: some View {
        List {
            Section(L(.menuBarEditorInstances)) {
                ForEach(store.menuBarInstances.instances) { instance in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { instance.isEnabled },
                            set: { listModel.setEnabled($0, id: instance.id) }
                        ))
                        .labelsHidden()
                        Button {
                            selectedID = instance.id
                        } label: {
                            Text(instance.name.isEmpty ? L(.menuBarEditorUntitled) : instance.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selectedID == instance.id ? Color.accentColor : .primary)
                    }
                    .contextMenu {
                        Button(L(.menuBarEditorDuplicate)) { listModel.duplicate(id: instance.id) }
                        Button(L(.menuBarEditorDelete), role: .destructive) { listModel.delete(id: instance.id) }
                    }
                }
                .onMove { listModel.move(from: $0.first ?? 0, to: $1) }
            }
            Section(L(.menuBarEditorNew)) {
                Button(L(.menuBarEditorBlankInstance)) {
                    let blank = MenuBarInstance(name: L(.menuBarEditorUntitled), top: MenuBarLine())
                    store.updateMenuBarInstance(blank)
                    selectedID = blank.id
                }
                .disabled(!listModel.canAdd)
                ForEach(MenuBarPreset.allCases) { preset in
                    Button(L(preset.titleKey)) {
                        listModel.addPreset(preset)
                        selectedID = store.menuBarInstances.instances.last?.id
                    }
                    .disabled(!listModel.canAdd)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var canvasColumn: some View {
        Group {
            if let model {
                MenuBarInstanceEditorView(model: model, localization: localization)
            } else {
                ContentUnavailableViewCompat(text: L(.menuBarEditorAddOrSelect))
            }
        }
    }

    private var paletteColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L(.menuBarEditorElements)).font(.headline)
                Text(L(.menuBarEditorPaletteHint)).font(.caption).foregroundStyle(.secondary)
                Text(L(.menuBarEditorMetrics)).font(.subheadline).foregroundStyle(.secondary)
                ForEach(MenuBarMetricID.allCases) { metric in
                    paletteRow(label: L(MenuBarMetricRegistry.titleKey(for: metric)), content: .metric(metric))
                }
                Text(L(.menuBarEditorTextIcons)).font(.subheadline).foregroundStyle(.secondary)
                paletteRow(label: L(.menuBarEditorText), content: .text("Text"))
                paletteRow(label: "🔥", content: .icon(MenuBarIconSpec(source: .emoji("🔥"))))
                ForEach(["cpu", "memorychip", "gauge", "thermometer", "fan"], id: \.self) { symbol in
                    paletteRow(label: "SF: \(symbol)", content: .icon(MenuBarIconSpec(source: .sfSymbol(symbol))))
                }
            }
            .padding(12)
        }
    }

    private func paletteRow(label: String, content: MenuBarElementContent) -> some View {
        Text(label)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .draggable(MenuBarElementDragPayload(source: .palette(content)))
            .onTapGesture { addToTop(content) }
    }

    private func addToTop(_ content: MenuBarElementContent) {
        guard let model else { return }
        var instance = model.instance
        let index = instance.top?.elements.count ?? 0
        if MenuBarElementMutations.apply(
            payload: MenuBarElementDragPayload(source: .palette(content)),
            to: &instance,
            target: .line(instanceID: instance.id, slot: .top, index: index)
        ) {
            model.instance = instance
            model.persist()
        }
    }

    private func ensureSelection() {
        if let selectedID, store.menuBarInstances.instances.contains(where: { $0.id == selectedID }) { return }
        selectedID = store.menuBarInstances.instances.first?.id
        rebuildModel()
    }

    private func rebuildModel() {
        guard let id = selectedID, let instance = store.menuBarInstances.instances.first(where: { $0.id == id }) else {
            model = nil; return
        }
        model = MenuBarInstanceEditorModel(instance: instance, store: store)
    }
}

private struct ContentUnavailableViewCompat: View {
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "menubar.rectangle")
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
