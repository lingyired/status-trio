import SwiftUI

/// Two-column editor for the app's own menu-bar items.
///
/// The left column is the instance list; the right column is the selected
/// instance's editor. The element library lives inside the editor, under the
/// menu-bar strip, so the whole page fits the Settings window without a third
/// column.
struct MenuBarInstancesSectionView: View {
    @ObservedObject var store: SettingsStore
    let localization: Localization
    @Binding var previewIsDark: Bool

    @State private var selectedID: UUID?
    @State private var model: MenuBarInstanceEditorModel?
    @State private var instancePendingDeletion: MenuBarInstance?

    private var listModel: MenuBarInstancesListModel { MenuBarInstancesListModel(store: store) }

    private func L(_ key: LocalizationKey) -> String { localization.string(key) }

    var body: some View {
        HSplitView {
            instanceColumn
                .frame(width: 190)

            editorColumn
                .frame(minWidth: 300)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { synchronizeSelection() }
        .onChange(of: store.menuBarInstances) { _ in synchronizeSelection() }
        .onChange(of: selectedID) { _ in rebuildModel() }
        .alert(
            L(.menuBarEditorDelete),
            isPresented: Binding(
                get: { instancePendingDeletion != nil },
                set: { if !$0 { instancePendingDeletion = nil } }
            ),
            presenting: instancePendingDeletion
        ) { instance in
            Button(L(.commonCancel), role: .cancel) {
                instancePendingDeletion = nil
            }
            Button(L(.menuBarEditorDelete), role: .destructive) {
                listModel.delete(id: instance.id)
                instancePendingDeletion = nil
            }
        } message: { instance in
            Text(instance.name.isEmpty ? L(.menuBarEditorUntitled) : instance.name)
        }
    }

    // MARK: - Left column

    private var instanceColumn: some View {
        List(selection: $selectedID) {
            Section(L(.menuBarEditorInstances)) {
                ForEach(listModel.instances) { instance in
                    instanceRow(instance)
                        .tag(instance.id)
                }
                .onMove { offsets, destination in
                    guard let source = offsets.first else { return }
                    listModel.move(from: source, to: destination)
                }
            }

            Section(L(.menuBarEditorNew)) {
                Button {
                    addBlankInstance()
                } label: {
                    Label(L(.menuBarEditorBlankInstance), systemImage: "plus.rectangle")
                }
                .disabled(!listModel.canAdd)

                ForEach(MenuBarPreset.allCases) { preset in
                    Button {
                        addPreset(preset)
                    } label: {
                        Label(L(preset.titleKey), systemImage: "square.grid.2x2")
                    }
                    .disabled(!listModel.canAdd)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 38)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func instanceRow(_ instance: MenuBarInstance) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { instance.isEnabled },
                set: { listModel.setEnabled($0, id: instance.id) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .accessibilityLabel(L(.menuBarEditorShowInMenuBar))

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName(for: instance))
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)

                Text(summary(for: instance))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            instanceActions(instance)
        }
        .padding(.vertical, 2)
    }

    private func displayName(for instance: MenuBarInstance) -> String {
        instance.name.isEmpty ? L(.menuBarEditorUntitled) : instance.name
    }

    private func summary(for instance: MenuBarInstance) -> String {
        instance.layoutMode == .doubleLine
            ? L(.menuBarEditorDoubleLine)
            : L(.menuBarEditorSingleLine)
    }

    private func instanceActions(_ instance: MenuBarInstance) -> some View {
        let index = listModel.instances.firstIndex { $0.id == instance.id } ?? 0
        let lastIndex = listModel.instances.count - 1

        return Menu {
            Button(L(.menuBarEditorDuplicate)) {
                duplicateInstance(instance)
            }
            Divider()
            Button(L(.menuBarEditorMoveUp)) {
                listModel.move(from: index, to: index - 1)
            }
            .disabled(index == 0)
            Button(L(.menuBarEditorMoveDown)) {
                listModel.move(from: index, to: index + 1)
            }
            .disabled(index >= lastIndex)
            Divider()
            Button(L(.menuBarEditorDelete), role: .destructive) {
                instancePendingDeletion = instance
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(L(.menuMore))
        .help(L(.menuMore))
    }

    // MARK: - Right column

    @ViewBuilder
    private var editorColumn: some View {
        if let model {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsMetrics.groupSpacing) {
                    MenuBarInstancePreviewCard(
                        model: model,
                        isEnabled: selectedInstanceIsEnabled,
                        isDarkBackground: $previewIsDark,
                        localization: localization
                    )

                    MenuBarInstanceEditorView(model: model, localization: localization)
                        .id(model.instance.id)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "menubar.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(L(.menuBarEditorAddOrSelect))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedInstanceIsEnabled: Bool {
        store.menuBarInstances.instances.first { $0.id == selectedID }?.isEnabled ?? true
    }

    // MARK: - Mutations

    private func addBlankInstance() {
        guard listModel.canAdd else { return }
        let blank = MenuBarInstance(
            name: "",
            layoutMode: .doubleLine,
            top: MenuBarLine()
        )
        store.updateMenuBarInstance(blank)
        selectedID = blank.id
    }

    private func addPreset(_ preset: MenuBarPreset) {
        guard listModel.canAdd else { return }
        listModel.addPreset(preset)
        guard var instance = store.menuBarInstances.instances.last else { return }
        // The preset's factory name is English; show the localized preset title
        // instead so a new item does not start with a half-translated name.
        instance.name = L(preset.titleKey)
        store.updateMenuBarInstance(instance)
        selectedID = instance.id
    }

    private func duplicateInstance(_ instance: MenuBarInstance) {
        guard listModel.canAdd else { return }
        listModel.duplicate(id: instance.id)
        guard let raw = store.menuBarInstances.instances.last, raw.id != instance.id else { return }

        // The store-level copy carries a developer-oriented " copy" suffix; give
        // it a name that reads in every shipped language instead.
        var copy = raw
        let base = instance.name.isEmpty ? L(.menuBarEditorUntitled) : instance.name
        copy.name = "\(base) (\(L(.menuBarEditorDuplicate)))"
        store.updateMenuBarInstance(copy)
        selectedID = copy.id
    }

    // MARK: - Selection

    private func synchronizeSelection() {
        if let selectedID, store.menuBarInstances.instances.contains(where: { $0.id == selectedID }) {
            if model == nil { rebuildModel() }
            return
        }
        selectedID = store.menuBarInstances.instances.first?.id
        rebuildModel()
    }

    private func rebuildModel() {
        guard let id = selectedID,
              let instance = store.menuBarInstances.instances.first(where: { $0.id == id })
        else {
            model = nil
            return
        }
        model = MenuBarInstanceEditorModel(instance: instance, store: store)
    }
}
