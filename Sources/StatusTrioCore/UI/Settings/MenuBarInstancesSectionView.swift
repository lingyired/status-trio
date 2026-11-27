import SwiftUI

/// Three-column editor: instance list | layout canvas | element palette.
struct MenuBarInstancesSectionView: View {
    @ObservedObject var store: SettingsStore
    let localization: Localization
    @State private var selectedID: UUID?
    @State private var model: MenuBarInstanceEditorModel?
    @State private var search = ""

    private var listModel: MenuBarInstancesListModel { MenuBarInstancesListModel(store: store) }
    private func L(_ key: LocalizationKey) -> String { localization.string(key) }

    private var filteredMetrics: [MenuBarMetricID] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return MenuBarMetricID.allCases }
        return MenuBarMetricID.allCases.filter {
            L(MenuBarMetricRegistry.titleKey(for: $0)).localizedCaseInsensitiveContains(query)
                || $0.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

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

    // MARK: - Left

    private var instanceColumn: some View {
        List {
            Section(L(.menuBarEditorInstances)) {
                ForEach(store.menuBarInstances.instances) { instance in
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { instance.isEnabled },
                            set: { listModel.setEnabled($0, id: instance.id) }
                        ))
                        .labelsHidden()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(instance.name.isEmpty ? L(.menuBarEditorUntitled) : instance.name)
                                .lineLimit(1)
                            Text("\(instance.layoutMode == .doubleLine ? L(.menuBarEditorDoubleLine) : L(.menuBarEditorSingleLine)) · \(instance.allMetrics.count) \(L(.menuBarEditorItems))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedID = instance.id }
                        .contextMenu {
                            Button(L(.menuBarEditorDuplicate)) { listModel.duplicate(id: instance.id) }
                            Button(L(.menuBarEditorDelete), role: .destructive) { listModel.delete(id: instance.id) }
                        }
                    }
                    .listRowBackground(selectedID == instance.id ? Color.accentColor.opacity(0.12) : Color.clear)
                }
                .onMove { listModel.move(from: $0.first ?? 0, to: $1) }
            }
            Section(L(.menuBarEditorNew)) {
                Button {
                    let blank = MenuBarInstance(name: L(.menuBarEditorUntitled), top: MenuBarLine())
                    store.updateMenuBarInstance(blank)
                    selectedID = blank.id
                } label: {
                    Label(L(.menuBarEditorBlankInstance), systemImage: "plus.rectangle")
                }
                .disabled(!listModel.canAdd)
                ForEach(MenuBarPreset.allCases) { preset in
                    Button {
                        listModel.addPreset(preset)
                        selectedID = store.menuBarInstances.instances.last?.id
                    } label: {
                        Label(L(preset.titleKey), systemImage: "square.grid.2x2")
                    }
                    .disabled(!listModel.canAdd)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Middle

    private var canvasColumn: some View {
        Group {
            if let model {
                MenuBarInstanceEditorView(model: model, localization: localization)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "menubar.rectangle").font(.largeTitle).foregroundStyle(.secondary)
                    Text(L(.menuBarEditorAddOrSelect)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Right

    private var paletteColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L(.menuBarEditorElements)).font(.headline)
            TextField(L(.menuBarEditorSearchPlaceholder), text: $search)
                .textFieldStyle(.roundedBorder)
            Text(L(.menuBarEditorPaletteHint)).font(.caption).foregroundStyle(.secondary)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L(.menuBarEditorMetrics)).font(.caption).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(filteredMetrics) { metric in
                            paletteChip(label: L(MenuBarMetricRegistry.titleKey(for: metric)),
                                        systemImage: symbol(for: metric),
                                        content: .metric(metric))
                        }
                    }
                    Text(L(.menuBarEditorTextIcons)).font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 6)], alignment: .leading, spacing: 6) {
                        paletteChip(label: L(.menuBarEditorText), systemImage: "textformat", content: .text("Text"))
                        paletteChip(label: "Emoji", systemImage: "face.smiling", content: .icon(MenuBarIconSpec(source: .emoji("🔥"))))
                        ForEach(["cpu", "memorychip", "gauge", "thermometer", "fan"], id: \.self) { symbol in
                            paletteChip(label: symbol, systemImage: symbol, content: .icon(MenuBarIconSpec(source: .sfSymbol(symbol))))
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    private func paletteChip(label: String, systemImage: String, content: MenuBarElementContent) -> some View {
        MenuBarEditorChipLabel(title: label, systemImage: systemImage)
            .draggable(MenuBarElementDragPayload(source: .palette(content)))
            .onTapGesture { addToTop(content) }
            .help(label)
            .accessibilityLabel(label)
    }

    private func symbol(for metric: MenuBarMetricID) -> String {
        switch metric {
        case .cpuUsage: return "cpu"
        case .cpuTemperature: return "thermometer.medium"
        case .gpuUsage: return "cpu.fill"
        case .gpuTemperature: return "thermometer.high"
        case .memoryUsage: return "memorychip"
        case .diskReadSpeed, .diskWriteSpeed: return "internaldrive"
        case .networkDownload: return "arrow.down.circle"
        case .networkUpload: return "arrow.up.circle"
        case .fanRPM: return "fan"
        case .batteryLevel: return "battery.100"
        case .wifiConnectionStatus: return "wifi"
        case .outputVolume: return "speaker.wave.2"
        case .screenBrightness: return "sun.max"
        }
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

    // MARK: - Selection

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
