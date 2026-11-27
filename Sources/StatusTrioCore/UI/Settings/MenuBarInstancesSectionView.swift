import SwiftUI

/// Settings page for the app's own menu-bar items.
///
/// The page follows the rest of Settings: one scrolling column of grouped
/// cards. The instance list is a native, selectable `List`; the selected item
/// is edited in the cards below instead of a bespoke three-column split that
/// could not fit the Settings window.
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
        SettingsPage(pinnedHeader: {
            MenuBarInstancePreviewCard(
                model: model,
                isEnabled: selectedInstanceIsEnabled,
                isDarkBackground: $previewIsDark,
                localization: localization
            )
        }) {
            instancesGroup
            if let model {
                MenuBarInstanceEditorView(model: model, localization: localization)
                    .id(model.instance.id)
            }
        }
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

    // MARK: - Instance selection

    private var currentInstance: MenuBarInstance? {
        guard let selectedID else { return nil }
        return listModel.instances.first { $0.id == selectedID }
    }

    private var selectedInstanceIsEnabled: Bool {
        store.menuBarInstances.instances.first { $0.id == selectedID }?.isEnabled ?? true
    }

    private var instancesGroup: some View {
        SettingsGroup {
            if let instance = currentInstance {
                SettingsRow("square.stack.3d.up", title: L(.menuBarEditorInstances)) {
                    HStack(spacing: 6) {
                        instancePicker
                        addInstanceMenu
                        instanceActions(instance)
                    }
                }

                SettingsDivider()

                SettingsToggleRow(
                    symbol: "eye",
                    title: L(.menuBarEditorShowInMenuBar),
                    subtitle: summary(for: instance),
                    isOn: Binding(
                        get: { instance.isEnabled },
                        set: { listModel.setEnabled($0, id: instance.id) }
                    )
                )
            } else {
                SettingsHintRow(text: L(.menuBarEditorAddOrSelect))
                SettingsDivider()
                addInstanceRow
            }
        }
    }

    private var instancePicker: some View {
        Picker("", selection: $selectedID) {
            ForEach(listModel.instances) { instance in
                Text(displayName(for: instance))
                    .tag(Optional(instance.id))
            }
        }
        .labelsHidden()
        .frame(width: 150, alignment: .trailing)
        .accessibilityLabel(L(.menuBarEditorInstances))
    }

    private var addInstanceMenu: some View {
        Menu {
            Button(L(.menuBarEditorBlankInstance)) { addBlankInstance() }
            Divider()
            ForEach(MenuBarPreset.allCases) { preset in
                Button(L(preset.titleKey)) { addPreset(preset) }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!listModel.canAdd)
        .accessibilityLabel(L(.menuBarEditorNew))
        .help(L(.menuBarEditorNew))
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
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(L(.menuMore))
        .help(L(.menuMore))
    }

    private var addInstanceRow: some View {
        HStack(spacing: 8) {
            Menu {
                Button(L(.menuBarEditorBlankInstance)) { addBlankInstance() }
                Divider()
                ForEach(MenuBarPreset.allCases) { preset in
                    Button(L(preset.titleKey)) { addPreset(preset) }
                }
            } label: {
                Label(L(.menuBarEditorNew), systemImage: "plus")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!listModel.canAdd)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, 8)
    }

    private func displayName(for instance: MenuBarInstance) -> String {
        instance.name.isEmpty ? L(.menuBarEditorUntitled) : instance.name
    }

    private func summary(for instance: MenuBarInstance) -> String {
        let layout = instance.layoutMode == .doubleLine
            ? L(.menuBarEditorDoubleLine)
            : L(.menuBarEditorSingleLine)
        let count = instance.renderedLines.flatMap { $0.line.elements }.count
        return "\(layout) · \(count) \(L(.menuBarEditorItems))"
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
