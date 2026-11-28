import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Two-column editor for the app's own menu-bar items.
///
/// The left column is the instance list; the right column is the selected
/// instance's editor. The element library lives inside the editor, under the
/// menu-bar strip, so the whole page fits the Settings window without a third
/// column.
struct MenuBarInstancesSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    let localization: Localization
    @Binding var previewIsDark: Bool
    var consumePendingMenuBarInstance: () -> UUID? = { nil }

    @State private var selectedID: UUID?
    @State private var model: MenuBarInstanceEditorModel?
    @State private var instancePendingDeletion: MenuBarInstance?

    private var listModel: MenuBarInstancesListModel { MenuBarInstancesListModel(store: store) }

    private func L(_ key: LocalizationKey) -> String { localization.string(key) }

    var body: some View {
        HSplitView {
            instanceColumn
                .frame(minWidth: 214, idealWidth: 236, maxWidth: 280)

            editorColumn
                .frame(minWidth: 300)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if let id = consumePendingMenuBarInstance(),
               store.menuBarInstances.instances.contains(where: { $0.id == id }) {
                selectedID = id
            }
            synchronizeSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsSelectSection)) { _ in
            if let id = consumePendingMenuBarInstance(),
               store.menuBarInstances.instances.contains(where: { $0.id == id }) {
                selectedID = id
            }
        }
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
        List {
            Section(L(.menuBarEditorInstances)) {
                ForEach(listModel.instances) { instance in
                    instanceRow(instance)
                        .tag(instance.id)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedID = instance.id }
                        .listRowBackground(
                            selectedID == instance.id
                                ? Color.accentColor.opacity(0.14)
                                : Color.clear
                        )
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

                Divider()
                Button {
                    importInstance()
                } label: {
                    Label(L(.menuBarEditorImportInstance), systemImage: "square.and.arrow.down")
                }
                .disabled(!listModel.canAdd)
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

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: instance))
                    .font(.system(size: 12.5, weight: .medium))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .help(displayName(for: instance))

                Text(summary(for: instance))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            instanceActions(instance)
        }
        .padding(.vertical, 3)
    }

    private func displayName(for instance: MenuBarInstance) -> String {
        instance.name.isEmpty ? L(.menuBarEditorUntitled) : instance.name
    }

    private func summary(for instance: MenuBarInstance) -> String {
        switch instance.layoutMode {
        case .singleLine: return L(.menuBarEditorSingleLine)
        case .doubleLine: return L(.menuBarEditorDoubleLine)
        case .doubleLineLargeTop: return L(.menuBarEditorDoubleLineLargeTop)
        case .doubleLineLargeBottom: return L(.menuBarEditorDoubleLineLargeBottom)
        }
    }

    private func instanceActions(_ instance: MenuBarInstance) -> some View {
        let index = listModel.instances.firstIndex { $0.id == instance.id } ?? 0
        let lastIndex = listModel.instances.count - 1

        return Menu {
            Button(L(.menuBarEditorDuplicate)) {
                duplicateInstance(instance)
            }
            Button(L(.menuBarEditorExportInstance)) {
                exportInstance(instance)
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
            VStack(spacing: 0) {
                MenuBarInstancePreviewCard(
                    model: model,
                    store: store,
                    statusStore: statusStore,
                    hardwareObservable: statusStore.hardwareMetrics.observable,
                    powerSampling: statusStore.powerSampling,
                    isDarkBackground: $previewIsDark,
                    localization: localization
                )
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 6)

                ScrollView {
                    MenuBarInstanceEditorView(model: model, localization: localization)
                        .id(model.instance.id)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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

    // MARK: - Mutations

    private func exportInstance(_ instance: MenuBarInstance) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        let base = displayName(for: instance)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(base).statustrio-instance.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try MenuBarInstanceTransfer.encode(instance)
            try data.write(to: url, options: .atomic)
        } catch {
            presentTransferError(title: L(.menuBarEditorExportFailed), error: error)
        }
    }

    private func importInstance() {
        guard listModel.canAdd else {
            let alert = NSAlert()
            alert.messageText = L(.menuBarEditorImportFailed)
            alert.informativeText = L(.menuBarEditorInstanceLimit)
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            var instance = try MenuBarInstanceTransfer.decode(data)
            if store.menuBarInstances.instances.contains(where: { $0.name == instance.name && !instance.name.isEmpty }) {
                instance.name += " " + L(.menuBarEditorImported)
            }
            guard let imported = listModel.importInstance(instance) else { return }
            selectedID = imported.id
        } catch {
            presentTransferError(title: L(.menuBarEditorImportFailed), error: error)
        }
    }

    private func presentTransferError(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

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
        let provider = MenuBarMetricValueProvider(
            localize: { localization.string($0) },
            externalVolumePaths: { store.hardwareSSDExternalVolumePaths },
            systemPower: { statusStore.powerSampling.systemPower },
            inputPower: { statusStore.powerSampling.inputPower },
            batteryPower: { statusStore.powerSampling.batteryPower }
        )
        model = MenuBarInstanceEditorModel(
            instance: instance,
            store: store,
            readingsProvider: { metrics in
                provider.readings(
                    for: metrics,
                    hardware: statusStore.hardwareMetrics.observable.snapshot,
                    status: statusStore.snapshot
                )
            }
        )
    }
}
