import SwiftUI

struct IconDesignerView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    var inputSourceController: InputSourceController? = nil
    var onEditSamples: () -> Void = {}
    @ObservedObject var previewSession: IconDesignerPreviewSession
    @StateObject private var editorModel: IconDesignerEditorModel

    init(
        store: SettingsStore,
        statusStore: SystemStatusStore,
        inputSourceController: InputSourceController? = nil,
        onEditSamples: @escaping () -> Void = {},
        previewSession: IconDesignerPreviewSession
    ) {
        self.store = store
        self.statusStore = statusStore
        self.inputSourceController = inputSourceController
        self.onEditSamples = onEditSamples
        self.previewSession = previewSession
        self._editorModel = StateObject(wrappedValue: IconDesignerEditorModel(store: store))
    }

    var previewIsDarkBackground: Binding<Bool> {
        Binding(
            get: { previewSession.isDarkBackground },
            set: { previewSession.isDarkBackground = $0 }
        )
    }

    private var selectedSlot: Binding<IconSlot> {
        Binding(get: { previewSession.selectedSlot }, set: { previewSession.selectedSlot = $0 })
    }
    private var previewScenario: IconPreviewScenario { .live }
    private var customAirPodsSample: CustomAirPodsPreviewSample { previewSession.samples.airPods }

    @EnvironmentObject private var localization: Localization

    var body: some View {
        GeometryReader { geometry in
            let columns = IconDesignerLayout.columns(for: geometry.size.width)
            HStack(alignment: .top, spacing: 18) {
                previewPane(width: columns.preview)
                    .frame(width: columns.preview)
                VStack(alignment: .leading, spacing: 10) {
                    SettingsGroup(localization.format(.iconDesignerEditingElementFormat,
                        localization.string(IconDesignerInspectorModel.slotName(selectedSlot.wrappedValue)))) {
                        IconSlotPicker(selection: selectedSlot, configuration: store.iconConfiguration)
                            .padding(.horizontal, SettingsMetrics.rowPaddingH)
                            .padding(.vertical, 8)
                    }
                    .accessibilityIdentifier("iconDesigner.slotCard")
                    ScrollView {
                        inspector
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)
                    .accessibilityIdentifier("iconDesigner.inspectorScrollView")

                    inspectorActions
                }
                .frame(width: columns.inspector)
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, IconDesignerLayout.horizontalPadding)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .environmentObject(editorModel)
    }

    private func previewPane(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localization.string(previewSession.mode == .simulated ? .iconPreviewModeSimulated : .iconPreviewModeLive))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(localization.string(.iconPreviewEditData), action: onEditSamples)
                    .buttonStyle(.borderless)
            }
            previewCard(content: .menuBarOnly, iconPointSize: IconDesignerLayout.menuBarPreviewPointSize)
                .accessibilityIdentifier("iconDesigner.menuBarSizePreview")
            previewCard(content: .designerLarge, largePreviewWidth: width)
            previewCard(content: .dockDetails)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("iconDesigner.previewPane")
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionContent(for: .source)
            if hasEditableBehavior(.primary) { sectionContent(for: .behavior) }
            if IconDesignerInspectorModel.showsAppearance(slot: selectedSlot.wrappedValue,
                configuration: store.iconConfiguration, targetIsAudio: false) { sectionContent(for: .appearance) }
            if selectedSource(.primary)?.pluginBinding != nil {
                IconDesignerFallbackSection(isExpanded: fallbackExpanded, summary: fallbackSummary, setupNotice: fallbackSetupNotice) {
                    IconSourceEditor(store: store, slot: selectedSlot.wrappedValue, target: .fallback,
                        bluetoothDevices: statusStore.bluetoothDevices, statusStore: statusStore)
                    if let source = selectedSource(.fallback), hasEditableBehavior(.fallback) {
                        Text(localization.format(.iconDesignerEditingFallbackFormat, localization.string(source.localizationKey)))
                            .font(.callout.weight(.semibold))
                        behaviorEditor(target: .fallback)
                    }
                }
            }
            if selectedSlot.wrappedValue == .center { IconDesignerAlertSection(store: store) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fallbackExpanded: Binding<Bool> {
        let slot = selectedSlot.wrappedValue
        return Binding(get: { previewSession.expandedFallbackSlots.contains(slot) }, set: { expanded in
            if expanded { previewSession.expandedFallbackSlots.insert(slot) }
            else { previewSession.expandedFallbackSlots.remove(slot) }
        })
    }

    private var fallbackSummary: String {
        guard let source = selectedSource(.fallback), source.pluginBinding != nil else {
            return localization.string(.iconDesignerHideElement)
        }
        return localization.format(.iconDesignerFallbackSummaryFormat, localization.string(source.localizationKey))
    }

    private var fallbackSetupNotice: String? {
        IconDesignerInspectorModel.fallbackSetupReason(slot: selectedSlot.wrappedValue,
            configuration: store.iconConfiguration, bluetoothAuthorized: statusStore.bluetoothDevices.authorization == .allowed,
            devices: statusStore.bluetoothDevices.availability == .available ? statusStore.bluetoothDevices.devices : [],
            airPodsAddress: store.airPodsIconDeviceAddress, connectedDeviceAddress: store.connectedBluetoothIconDeviceAddress)
            .map { localization.string($0) }
    }

    private func selectedSource(_ target: IconDesignerBehaviorTarget) -> IconDesignerSource? {
        IconDesignerEditingModel.source(for: target, slot: selectedSlot.wrappedValue, in: store.iconConfiguration)
    }

    private func hasEditableBehavior(_ target: IconDesignerBehaviorTarget) -> Bool {
        let deviceTarget = store.connectedBluetoothIconDeviceAddress.map {
            IconDesignerBluetoothTarget.connectedDevice(address: $0)
        } ?? .currentAudioOutput
        return IconDesignerInspectorModel.hasEditableBehavior(slot: selectedSlot.wrappedValue, target: target,
            configuration: store.iconConfiguration, targetIsAudio: IconDesignerBluetoothTargetModel.isAudioTarget(deviceTarget,
                devices: statusStore.bluetoothDevices.availability == .available ? statusStore.bluetoothDevices.devices : []))
    }

    private func behaviorEditor(target: IconDesignerBehaviorTarget) -> some View {
        IconBehaviorEditor(store: store, slot: selectedSlot.wrappedValue,
            bluetoothDevices: statusStore.bluetoothDevices.devices,
            bluetoothAvailability: statusStore.bluetoothDevices.availability,
            bluetoothDeviceOrder: store.bluetoothDeviceOrder, behaviorTarget: target)
    }

    private var inspectorActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(localization.string(.iconDesignerUndo)) { editorModel.undo() }
                    .disabled(!editorModel.canUndo)
                    .keyboardShortcut("z", modifiers: .command)
                    .accessibilityIdentifier("iconDesigner.undo")
                if editorModel.hasExternalChangeNotice {
                    Text(localization.string(.iconDesignerExternalChangeNotice))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("iconDesigner.externalChangeNotice")
                }
                Spacer(minLength: 0)
            }
            IconPresetPicker(store: store, slot: selectedSlot.wrappedValue)
        }
        .padding(.top, 8)
        .background(alignment: .top) { Divider() }
        .accessibilityIdentifier("iconDesigner.inspectorActions")
    }

    private func previewCard(
        content: StatusIconPreviewCardContent,
        largePreviewWidth: CGFloat? = nil,
        iconPointSize: CGFloat? = nil
    ) -> some View {
        StatusIconPreviewCard(
            store: store,
            statusStore: statusStore,
            isDarkBackground: previewIsDarkBackground,
            inputSourceController: inputSourceController,
            scenario: previewScenario,
            customAirPodsSample: customAirPodsSample,
            previewSession: previewSession,
            largeIconPointSize: largePreviewWidth.map { IconDesignerLayout.largePreviewPointSize(for: $0) } ?? iconPointSize,
            showsResolutionExplanation: isLargePreview(content),
            selectedSlot: selectedSlot.wrappedValue,
            onSelectSlot: { previewSession.selectedSlot = $0 },
            content: content
        )
    }

    private func isLargePreview(_ content: StatusIconPreviewCardContent) -> Bool {
        if case .designerLarge = content { return true }
        return false
    }


    private var customAirPodsControls: some View {
        SettingsGroup(localization.string(.iconDesignerAirPodsTestTitle)) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsHintRow(text: localization.string(.iconDesignerAirPodsTestSimulatedData))
                Toggle(localization.string(.iconDesignerAirPodsTestLeftAvailable), isOn: Binding(
                    get: { previewSession.samples.airPods.leftAvailable },
                    set: { previewSession.setAirPodsAvailability(.left, isAvailable: $0) }
                ))
                .padding(.horizontal, SettingsMetrics.rowPaddingH)
                Toggle(localization.string(.iconDesignerAirPodsTestRightAvailable), isOn: Binding(
                    get: { previewSession.samples.airPods.rightAvailable },
                    set: { previewSession.setAirPodsAvailability(.right, isAvailable: $0) }
                ))
                .padding(.horizontal, SettingsMetrics.rowPaddingH)
                batterySlider(
                    title: .iconDesignerAirPodsTestLeftBattery,
                    value: customAirPodsSample.leftBattery,
                    setValue: { previewSession.setAirPodsBattery(.left, $0) }
                )
                batterySlider(
                    title: .iconDesignerAirPodsTestRightBattery,
                    value: customAirPodsSample.rightBattery,
                    setValue: { previewSession.setAirPodsBattery(.right, $0) }
                )
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    presetButton(.both, title: .iconDesignerAirPodsTestBoth)
                    presetButton(.leftOnly, title: .iconDesignerAirPodsTestLeftOnly)
                    presetButton(.rightOnly, title: .iconDesignerAirPodsTestRightOnly)
                    presetButton(.unavailable, title: .iconDesignerAirPodsTestUnavailable)
                }
                .padding(.horizontal, SettingsMetrics.rowPaddingH)
                .padding(.bottom, 10)
            }
        }
        .accessibilityIdentifier("iconDesigner.customAirPodsControls")
    }

    private func batterySlider(
        title: LocalizationKey,
        value: Int,
        setValue: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(localization.string(title))
                Spacer()
                Text("\(value)%")
                    .monospacedDigit()
                    .accessibilityLabel("\(localization.string(title)), \(value)%")
            }
            Slider(value: Binding(
                get: { Double(value) },
                set: { newValue in setValue(newValue) }
            ), in: 0...100, step: 1)
            .accessibilityLabel(localization.string(title))
            .accessibilityValue("\(value)%")
        }
        .font(.system(size: 11))
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
    }

    private func presetButton(_ preset: CustomAirPodsPreviewPreset, title: LocalizationKey) -> some View {
        Button(localization.string(title)) {
            previewSession.applyAirPodsPreset(preset)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func sectionContent(for section: IconDesignerSection) -> some View {
        switch section {
        case .slot:
            EmptyView()
        case .source:
            IconSourceEditor(
                store: store,
                slot: selectedSlot.wrappedValue,
                phaseFiveEnabled: IconDesignerEditingModel.supportsImplementedSources(for: selectedSlot.wrappedValue),
                bluetoothDevices: statusStore.bluetoothDevices,
                statusStore: statusStore
            )
        case .behavior:
            behaviorEditor(target: .primary)
        case .appearance:
            IconAppearanceEditor(
                store: store,
                slot: selectedSlot.wrappedValue,
                bluetoothDevices: statusStore.bluetoothDevices.devices
            )
        case .presets:
            EmptyView()
        }
    }
}
