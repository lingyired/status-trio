import AppKit
import SwiftUI

enum StatusIconPreviewCardContent {
    case standard
    case menuBarOnly
    case designerLarge
    case dockDetails
}

/// Live status icon preview shown at the top of the icon-related settings panes.
///
/// The card renders the real menu bar artwork through `StatusIconRenderer`, so
/// every option that feeds the icon — battery, connection, volume — updates it
/// immediately.
struct StatusIconPreviewCard: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @ObservedObject private var bluetoothDevices: BluetoothDeviceController
    /// The live source the centre slot draws. The card re-renders when
    /// the controller publishes; `nil` in previews with no live controller.
    var inputSourceController: InputSourceController? = nil
    @Binding var isDarkBackground: Bool
    var scenario: IconPreviewScenario = .live
    var customAirPodsSample = CustomAirPodsPreviewSample()
    var previewSession: IconDesignerPreviewSession? = nil
    var largeIconPointSize: CGFloat? = nil
    var showsResolutionExplanation = false
    var selectedSlot: IconSlot? = nil
    var onSelectSlot: ((IconSlot) -> Void)? = nil
    var content: StatusIconPreviewCardContent = .standard
    @EnvironmentObject private var localization: Localization
    @EnvironmentObject private var chargingEffectClock: ChargingEffectClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previewState = IconDesignerPreviewState()
    /// Identifies this card's claim on the shared clock, so a Dock-only menu bar
    /// still animates the preview while it is visible.
    @State private var clockConsumerToken = UUID()

    init(
        store: SettingsStore,
        statusStore: SystemStatusStore,
        isDarkBackground: Binding<Bool>,
        inputSourceController: InputSourceController? = nil,
        scenario: IconPreviewScenario = .live,
        customAirPodsSample: CustomAirPodsPreviewSample = CustomAirPodsPreviewSample(),
        previewSession: IconDesignerPreviewSession? = nil,
        largeIconPointSize: CGFloat? = nil,
        showsResolutionExplanation: Bool = false,
        selectedSlot: IconSlot? = nil,
        onSelectSlot: ((IconSlot) -> Void)? = nil,
        content: StatusIconPreviewCardContent = .standard
    ) {
        self.store = store
        self.statusStore = statusStore
        self._bluetoothDevices = ObservedObject(wrappedValue: statusStore.bluetoothDevices)
        self.inputSourceController = inputSourceController
        self._isDarkBackground = isDarkBackground
        self.scenario = scenario
        self.customAirPodsSample = customAirPodsSample
        self.previewSession = previewSession
        self.largeIconPointSize = largeIconPointSize
        self.showsResolutionExplanation = showsResolutionExplanation
        self.selectedSlot = selectedSlot
        self.onSelectSlot = onSelectSlot
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        InputSourceLivePreview(controller: inputSourceController) {
          Group {
        switch content {
        case .standard:
            VStack(spacing: 8) {
                menuBarPreviewWithLifecycle
                previewGuidance
            }
        case .menuBarOnly:
            menuBarPreviewWithLifecycle
        case .designerLarge:
            VStack(spacing: 8) {
                largeDesignerPreviewWithLifecycle
                previewGuidance
            }
        case .dockDetails:
            dockPreviewDetails
        }
          }
        }
    }

    private func slotTitleKey(_ slot: IconSlot) -> LocalizationKey {
        switch slot {
        case .outerRing: .iconDesignerSlotOuterRing
        case .center: .iconDesignerSlotCenter
        case .footer: .iconDesignerSlotFooter
        }
    }

    private var largeDesignerPreviewWithLifecycle: some View {
        largeDesignerPreview
            .onAppear {
                previewState.setVisible(true)
                previewState.setReduceMotion(reduceMotion)
                previewState.setScenario(scenario)
                if previewSession?.mode == .simulated {
                    updateResolvedSimulatedChargingEffect()
                } else if store.showsChargingEffect {
                    startPreviewIfAllowed()
                }
            }
            .onChange(of: store.showsChargingEffect) { isEnabled in
                if !isEnabled {
                    previewState.stop()
                } else if previewSession?.mode == .simulated {
                    updateResolvedSimulatedChargingEffect()
                } else {
                    startPreviewIfAllowed()
                }
            }
            .onChange(of: resolvedSimulatedChargingEffectEligible) { isEligible in
                previewState.setResolvedSimulatedChargingEffect(isEligible: isEligible, at: Date())
            }
            .onChange(of: scenario) { newScenario in
                previewState.setScenario(newScenario)
                if previewSession?.mode == .simulated {
                    updateResolvedSimulatedChargingEffect()
                } else if newScenario == .batteryCharging && store.showsChargingEffect {
                    startPreviewIfAllowed()
                }
            }
            .onChange(of: isLiveChargingActive) { isActive in
                if isActive { previewState.stop() }
            }
            .onChange(of: reduceMotion) { isEnabled in
                previewState.setReduceMotion(isEnabled)
                if !isEnabled && store.showsChargingEffect && previewSession?.mode != .simulated {
                    startPreviewIfAllowed()
                }
            }
            .onDisappear {
                previewState.setVisible(false)
            }
            .task(id: previewState.playback.startedAt) {
                guard let startedAt = previewState.playback.startedAt else { return }
                let elapsed = Date().timeIntervalSince(startedAt)
                let remaining = max(0, ChargingEffectPreviewPlayback.duration - elapsed)
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                }
                guard !Task.isCancelled else { return }
                previewState.stop()
            }
    }

    @ViewBuilder
    private var largeDesignerPreview: some View {
        if previewState.playback.isPlaying {
            TimelineView(.animation(
                minimumInterval: 1 / Double(ChargingEffectTimeline.framesPerSecond),
                paused: false
            )) { timeline in
                largeDesignerPreviewContent(playbackPhase: previewState.playback.phase(at: timeline.date))
            }
        } else {
            largeDesignerPreviewContent(playbackPhase: nil)
        }
    }

    private func largeDesignerPreviewContent(playbackPhase: ChargingEffectPhase?) -> some View {
        let size = largeIconPointSize ?? IconDesignerLayout.minimumLargePreviewPointSize
        let displayStatus = liveChargingPhase == nil && playbackPhase != nil
            ? Self.chargingPreviewStatus(for: statusStore.snapshot)
            : currentStatus
        let output = displayedResolution(status: displayStatus)
        let scene = output.scene
        let identity = IconPreviewCenterIdentity.make(
            configuration: store.iconConfiguration,
            selectedBluetoothAddress: store.connectedBluetoothIconDeviceAddress
        )
        let phase = Self.largePreviewChargingPhase(
            scenario: scenario,
            livePhase: liveChargingPhase,
            playbackPhase: playbackPhase
        )
        return VStack(spacing: 0) {
            IconAnimatedCenterPreview(
                scene: scene,
                size: size,
                appearance: NSAppearance(named: isDarkBackground ? .darkAqua : .aqua),
                centerIdentity: identity,
                chargingPhase: phase
            )
            .overlay {
                ZStack {
                    if let selectedSlot {
                        IconDesignerSelectionPulseOverlay(
                            slot: selectedSlot,
                            volumeDisplayStyle: store.volumeIconOptions.displayStyle,
                            size: size,
                            lineWidth: max(3, size * 0.025)
                        )
                    }

                    VStack(spacing: 0) {
                        ForEach(IconDesignerPreviewHitRegion.allCases) { region in
                            Button {
                                onSelectSlot?(region.slot)
                            } label: {
                                Rectangle().fill(Color.clear).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .frame(height: size / 3)
                            .accessibilityLabel(localization.string(slotTitleKey(region.slot)))
                            .accessibilityIdentifier("iconDesigner.previewSlot.\(region.slot.rawValue)")
                            .accessibilityAddTraits(selectedSlot == region.slot ? .isSelected : [])
                        }
                    }
                }
            }
            appearanceToggle
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(MenuBarPreviewBackdrop(isDarkBackground: isDarkBackground, cornerRadius: 12))
        .accessibilityIdentifier("iconDesigner.largeRealRendererPreview")
    }

    private var menuBarPreviewWithLifecycle: some View {
        menuBarPreview
            .onAppear {
                previewState.setVisible(true)
                previewState.setReduceMotion(reduceMotion)
                previewState.setScenario(scenario)
                if previewSession?.mode == .simulated {
                    updateResolvedSimulatedChargingEffect()
                } else if store.showsChargingEffect {
                    startPreviewIfAllowed()
                }
            }
            .onChange(of: store.showsChargingEffect) { isEnabled in
                if !isEnabled {
                    previewState.stop()
                } else if previewSession?.mode == .simulated {
                    updateResolvedSimulatedChargingEffect()
                } else {
                    startPreviewIfAllowed()
                }
            }
            .onChange(of: resolvedSimulatedChargingEffectEligible) { isEligible in
                previewState.setResolvedSimulatedChargingEffect(isEligible: isEligible, at: Date())
            }
            .onChange(of: scenario) { newScenario in
                previewState.setScenario(newScenario)
                if previewSession?.mode == .simulated {
                    updateResolvedSimulatedChargingEffect()
                } else if newScenario == .batteryCharging && store.showsChargingEffect {
                    startPreviewIfAllowed()
                }
            }
            .onChange(of: isLiveChargingActive) { isActive in
                if isActive { previewState.stop() }
            }
            .onChange(of: reduceMotion) { isEnabled in
                previewState.setReduceMotion(isEnabled)
                if !isEnabled && store.showsChargingEffect && previewSession?.mode != .simulated {
                    startPreviewIfAllowed()
                }
            }
            .onDisappear {
                previewState.setVisible(false)
            }
            .task(id: previewState.playback.startedAt) {
                guard let startedAt = previewState.playback.startedAt else { return }
                let elapsed = Date().timeIntervalSince(startedAt)
                let remaining = max(0, ChargingEffectPreviewPlayback.duration - elapsed)
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                }
                guard !Task.isCancelled else { return }
                previewState.stop()
            }
    }

    /// Scrolls with the designer controls so the fixed header remains compact.
    /// Resolution, explanation, and sample data all come from this card's inputs.
    private var dockPreviewDetails: some View {
        VStack(spacing: 8) {
            if showsResolutionExplanation { previewGuidance }
            DockIconPreviewTile(
                store: store,
                statusStore: statusStore,
                size: IconDesignerLayout.dockPreviewPointSize,
                resolvedScene: displayedResolution(status: currentStatus).scene
            )
            .accessibilityIdentifier("iconDesigner.dockPreviewTile")
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("iconDesigner.dockPreviewDetails")
    }

    private var previewGuidance: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localization.string(.settingsPreviewHint))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            if showsResolutionExplanation { explanation }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            setClockClaim(enabled: store.showsMenuBarChargingEffect)
        }
        .onChange(of: store.showsMenuBarChargingEffect) { isEnabled in
            setClockClaim(enabled: isEnabled)
            if isEnabled {
                startPreviewIfAllowed()
            } else {
                previewState.stop()
            }
        }
        .onChange(of: isLiveChargingActive) { isActive in
            if isActive { previewState.stop() }
        }
        .onChange(of: reduceMotion) { isEnabled in
            if isEnabled {
                previewState.stop()
            }
        }
        .onDisappear {
            chargingEffectClock.endAnimationPreview(clockConsumerToken)
            previewState.stop()
        }
        .task(id: previewState.playback.startedAt) {
            guard let startedAt = previewState.playback.startedAt else { return }
            let elapsed = Date().timeIntervalSince(startedAt)
            let remaining = max(0, ChargingEffectPreviewPlayback.duration - elapsed)
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard !Task.isCancelled else { return }
            previewState.stop()
        }
    }

    @ViewBuilder
    private var menuBarPreview: some View {
        if let phase = liveChargingPhase {
            previewBar(status: currentStatus, phase: phase)
        } else if previewState.playback.isPlaying {
            TimelineView(.animation(
                minimumInterval: 1 / Double(ChargingEffectTimeline.framesPerSecond),
                paused: false
            )) { timeline in
                let phase = previewState.playback.phase(at: timeline.date)
                previewBar(
                    status: phase == nil ? currentStatus : Self.chargingPreviewStatus(for: statusStore.snapshot),
                    phase: phase
                )
            }
        } else {
            previewBar(status: currentStatus, phase: nil)
        }
    }

    private var designerResolution: IconResolutionOutput {
        designerResolution(for: statusStore.snapshot)
    }

    private func designerResolution(for snapshot: StatusSnapshot) -> IconResolutionOutput {
        if let previewSession {
            let liveInputs = IconResolutionInputs(
                system: Self.presentationInputs(
                    snapshot: snapshot,
                    inputSource: inputSourceController?.selectedDescriptor,
                    runtimeOptions: store.iconRuntimePresentationOptions
                ),
                sources: IconPresentationResourceResolver.sourceSnapshot(
                    snapshot: snapshot,
                    bluetoothDevices: bluetoothDevices.devices,
                    batteryLevels: bluetoothDevices.batteryLevels,
                    batteryLevelsUpdatedAt: bluetoothDevices.batteryLevelsUpdatedAt,
                    selectedAirPodsAddress: store.airPodsIconDeviceAddress,
                    selectedConnectedDeviceAddress: store.connectedBluetoothIconDeviceAddress
                )
            )
            let target = store.connectedBluetoothIconDeviceAddress.map {
                IconDesignerBluetoothTarget.connectedDevice(address: BluetoothBatteryReader.normalizedAddress($0))
            } ?? .currentAudioOutput
            return IconDesignerPreviewResolver.resolve(
                liveInputs: liveInputs,
                configuration: store.iconConfiguration,
                mode: previewSession.mode,
                samples: previewSession.samples,
                target: target,
                now: Date()
            )
        }
        return Self.resolveDesignerScene(
            for: snapshot.replacingBattery(currentStatus.battery),
            bluetoothDevices: bluetoothDevices.devices,
            batteryLevels: bluetoothDevices.batteryLevels,
            batteryLevelsUpdatedAt: bluetoothDevices.batteryLevelsUpdatedAt,
            selectedAirPodsAddress: store.airPodsIconDeviceAddress,
            selectedConnectedDeviceAddress: store.connectedBluetoothIconDeviceAddress,
            configuration: store.iconConfiguration,
            scenario: scenario,
            customAirPodsSample: customAirPodsSample,
            inputSource: inputSourceController?.selectedDescriptor,
            runtimeOptions: store.iconRuntimePresentationOptions
        )
    }

    @MainActor
    static func resolveDisplayedPreviewScene(
        status: MenuBarStatus,
        basedOn snapshot: StatusSnapshot,
        bluetoothDevices: [BluetoothDevice],
        batteryLevels: [String: BluetoothBatteryLevel],
        batteryLevelsUpdatedAt: Date?,
        selectedAirPodsAddress: String?,
        selectedConnectedDeviceAddress: String?,
        configuration: IconConfigurationV1,
        scenario: IconPreviewScenario,
        customAirPodsSample: CustomAirPodsPreviewSample = CustomAirPodsPreviewSample(),
        inputSource: InputSourceDescriptor? = nil,
        runtimeOptions: IconPresentationRuntimeOptions? = nil
    ) -> IconResolutionOutput {
        resolveDesignerScene(
            for: snapshot.replacingBattery(status.battery),
            bluetoothDevices: bluetoothDevices,
            batteryLevels: batteryLevels,
            batteryLevelsUpdatedAt: batteryLevelsUpdatedAt,
            selectedAirPodsAddress: selectedAirPodsAddress,
            selectedConnectedDeviceAddress: selectedConnectedDeviceAddress,
            configuration: configuration,
            scenario: scenario,
            customAirPodsSample: customAirPodsSample,
            inputSource: inputSource,
            runtimeOptions: runtimeOptions
        )
    }

    @MainActor
    static func resolveDesignerScene(
        for snapshot: StatusSnapshot,
        bluetoothDevices: [BluetoothDevice],
        batteryLevels: [String: BluetoothBatteryLevel],
        batteryLevelsUpdatedAt: Date?,
        selectedAirPodsAddress: String?,
        selectedConnectedDeviceAddress: String?,
        configuration: IconConfigurationV1,
        scenario: IconPreviewScenario,
        customAirPodsSample: CustomAirPodsPreviewSample = CustomAirPodsPreviewSample(),
        inputSource: InputSourceDescriptor? = nil,
        runtimeOptions: IconPresentationRuntimeOptions? = nil
    ) -> IconResolutionOutput {
        let inputs = IconResolutionInputs(
            system: presentationInputs(
                snapshot: snapshot,
                inputSource: inputSource,
                runtimeOptions: runtimeOptions
            ),
            sources: IconPresentationResourceResolver.sourceSnapshot(
                snapshot: snapshot,
                bluetoothDevices: bluetoothDevices,
                batteryLevels: batteryLevels,
                batteryLevelsUpdatedAt: batteryLevelsUpdatedAt,
                selectedAirPodsAddress: selectedAirPodsAddress,
                selectedConnectedDeviceAddress: selectedConnectedDeviceAddress
            )
        )
        return IconDesignerPreviewResolver.resolve(
            liveInputs: inputs,
            configuration: configuration,
            scenario: scenario,
            customAirPodsSample: customAirPodsSample
        )
    }

    @MainActor
    private static func presentationInputs(
        snapshot: StatusSnapshot,
        inputSource: InputSourceDescriptor?,
        runtimeOptions: IconPresentationRuntimeOptions?
    ) -> IconPresentationInputs {
        let resolved = IconPresentationResourceResolver.inputs(snapshot: snapshot, inputSource: inputSource)
        return IconPresentationInputs(
            snapshot: resolved.snapshot,
            audioIcon: resolved.audioIcon,
            inputSource: resolved.inputSource,
            runtimeOptions: runtimeOptions
        )
    }

    static func chargingPreviewStatus(for current: StatusSnapshot) -> MenuBarStatus {
        let battery = BatteryStatus(
            rawPercentage: 62,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: current.battery.isLowPowerMode,
            isConnectedToPower: true
        )
        return MenuBarStatus(snapshot: StatusSnapshot(
            battery: battery,
            wifi: current.wifi,
            connection: current.connection,
            volume: current.volume
        ))
    }

    private var explanation: some View {
        let resolution = designerResolution
        let permissionBlockedSlots: Set<IconSlot> = previewSession?.mode == .simulated ? [] : IconResolutionExplanation.permissionBlockedBluetoothFallbackSlots(
            configuration: store.iconConfiguration, trace: resolution.trace,
            authorization: bluetoothDevices.authorization, scenario: scenario)
        let entries = IconResolutionExplanation.entries(for: resolution.trace,
            permissionBlockedSlots: permissionBlockedSlots, bluetoothAuthorization: bluetoothDevices.authorization)
        let slots = selectedSlot.map { [$0] } ?? IconSlot.allCases
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(slots, id: \.self) { slot in
                let trace = IconDesignerInspectorModel.trace(for: slot, in: resolution.trace)
                let index = IconSlot.allCases.firstIndex(of: slot) ?? 0
                let reasons = trace.role == .primary && trace.reason == .primary
                    ? [] : entries[index].reasonKeys.map { localization.string($0) }
                let partial = slot == .outerRing && resolution.scene.outerRing?.isPartial == true
                    ? localization.string(.iconDesignerAirPodsPartialExplanation) : nil
                IconDesignerCurrentDisplay(trace: trace,
                    value: IconDesignerInspectorModel.displayedValue(for: slot, in: resolution.scene),
                    reason: (reasons + [partial].compactMap { $0 }).joined(separator: " · "))
            }
        }

    }

    private var currentStatus: MenuBarStatus {
        ChargingEffectTestMode.status(
            MenuBarStatus(snapshot: statusStore.snapshot),
            enabled: store.testsChargingEffect
        )
    }

    private var liveChargingPhase: ChargingEffectPhase? {
        guard scenario == .live, previewSession?.mode != .simulated else { return nil }
        return Self.livePhase(
            battery: ChargingEffectTestMode.battery(
                statusStore.snapshot.battery,
                enabled: store.testsChargingEffect
            ),
            enabled: store.showsMenuBarChargingEffect,
            reduceMotion: reduceMotion,
            phase: chargingEffectClock.phase
        )
    }

    private var isLiveChargingActive: Bool {
        liveChargingPhase != nil
    }

    private var resolvedSimulatedChargingEffectEligible: Bool {
        guard let previewSession else { return false }
        return IconDesignerPreviewState.simulatedChargingEffectIsEligible(
            mode: previewSession.mode,
            animationEnabled: store.showsChargingEffect,
            resolvedScene: displayedResolution(status: currentStatus).scene
        )
    }

    private func updateResolvedSimulatedChargingEffect() {
        previewState.setResolvedSimulatedChargingEffect(
            isEligible: resolvedSimulatedChargingEffectEligible,
            at: Date()
        )
    }

    static func largePreviewChargingPhase(
        scenario: IconPreviewScenario,
        livePhase: ChargingEffectPhase?,
        playbackPhase: ChargingEffectPhase?
    ) -> ChargingEffectPhase? {
        guard scenario == .live || scenario == .batteryCharging else { return nil }
        return livePhase ?? playbackPhase
    }

    static func livePhase(
        battery: BatteryStatus,
        enabled: Bool,
        reduceMotion: Bool,
        phase: ChargingEffectPhase?
    ) -> ChargingEffectPhase? {
        guard battery.isCharging, enabled, !reduceMotion else { return nil }
        return phase
    }


    private func previewBar(
        status: MenuBarStatus,
        phase: ChargingEffectPhase?
    ) -> some View {
        MenuBarPreviewBar(
            status: status,
            iconSize: largeIconPointSize ?? store.iconSize,
            batteryOptions: store.batteryIconOptions,
            connectionOptions: store.connectionIconOptions,
            volumeOptions: store.volumeIconOptions,
            bluetoothAudioOptions: store.bluetoothAudioIconOptions,
            isDarkBackground: isDarkBackground,
            selectedSlot: selectedSlot,
            onSelectSlot: onSelectSlot,
            phase: phase,
            resolvedScene: displayedResolution(status: status).scene,
            showsChargingEffect: store.showsMenuBarChargingEffect,
            inputSource: inputSourceController?.selectedDescriptor
        ) {
            appearanceToggle
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.iconSize)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.batteryIconOptions)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.connectionIconOptions)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.volumeIconOptions)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.bluetoothAudioIconOptions)
    }

    private func startPreviewIfAllowed() {
        guard store.showsMenuBarChargingEffect,
              !reduceMotion, !isLiveChargingActive,
              scenario == .live || scenario == .batteryCharging else { return }
        previewState.start(at: Date())
    }


    private func displayedResolution(status: MenuBarStatus) -> IconResolutionOutput {
        if previewSession != nil { return designerResolution(for: statusStore.snapshot.replacingBattery(status.battery)) }
        if scenario == .airPodsCustom {
            // Keep the icon and its explanation on this exact resolved sample.
            return designerResolution
        }
        return Self.resolveDisplayedPreviewScene(
            status: status,
            basedOn: statusStore.snapshot,
            bluetoothDevices: bluetoothDevices.devices,
            batteryLevels: bluetoothDevices.batteryLevels,
            batteryLevelsUpdatedAt: bluetoothDevices.batteryLevelsUpdatedAt,
            selectedAirPodsAddress: store.airPodsIconDeviceAddress,
            selectedConnectedDeviceAddress: store.connectedBluetoothIconDeviceAddress,
            configuration: store.iconConfiguration,
            scenario: scenario,
            customAirPodsSample: customAirPodsSample,
            inputSource: inputSourceController?.selectedDescriptor,
            runtimeOptions: store.iconRuntimePresentationOptions
        )
    }

    private func setClockClaim(enabled: Bool) {
        if enabled {
            chargingEffectClock.beginAnimationPreview(clockConsumerToken)
        } else {
            chargingEffectClock.endAnimationPreview(clockConsumerToken)
        }
    }

    private var appearanceToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                isDarkBackground.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isDarkBackground ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 10))
                Text(localization.string(isDarkBackground ? .settingsPreviewDark : .settingsPreviewLight))
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(isDarkBackground ? Color.white.opacity(0.85) : Color.black.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isDarkBackground ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .help(localization.string(.settingsPreviewToggleHelp))
    }
}

/// Small Dock tile preview that mirrors the live Dock icon.
struct DockIconPreviewTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    var inputSourceController: InputSourceController? = nil
    var size: CGFloat = 44
    var overrideStyle: DockIconBackgroundStyle? = nil
    var previewCache: DockIconPreviewCache? = nil
    var resolvedScene: IconSceneState? = nil

    var body: some View {
        InputSourceLivePreview(controller: inputSourceController) {
            tile
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.batteryIconOptions)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.connectionIconOptions)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.volumeIconOptions)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.bluetoothAudioIconOptions)
                .accessibilityHidden(true)
        }
    }

    @MainActor
    var renderKey: DockIconRenderKey { tile.renderKey }

    @MainActor
    var previewImage: NSImage? { tile.previewImage }

    /// The tile the body renders, so a test reads exactly the key the body uses.
    private var tile: DockIconTile {
        DockIconTile(
            status: MenuBarStatus(snapshot: statusStore.snapshot),
            batteryOptions: store.batteryIconOptions,
            connectionOptions: store.connectionIconOptions,
            volumeOptions: store.volumeIconOptions,
            bluetoothAudioOptions: store.bluetoothAudioIconOptions,
            backgroundStyle: resolvedBackgroundStyle,
            size: size,
            resolvedScene: resolvedScene,
            inputSource: inputSourceController?.selectedDescriptor,
            previewCache: previewCache
        )
    }

    private var resolvedBackgroundStyle: DockIconBackgroundStyle {
        if let overrideStyle {
            return overrideStyle
        }
        return DockIconBackgroundResolver.style(
            for: store.dockIconBackgroundPreference,
            theme: SystemIconAppearanceReader.current(),
            isDarkAppearance: NSApplication.shared.effectiveAppearance
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        )
    }
}
