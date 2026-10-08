import AppKit
import SwiftUI

/// Live status icon preview shown at the top of the icon-related settings panes.
///
/// The card renders the real menu bar artwork through `StatusIconRenderer`, so
/// every option that feeds the icon — battery, connection, volume — updates it
/// immediately.
struct StatusIconPreviewCard: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @Binding var isDarkBackground: Bool
    var scenario: IconPreviewScenario = .live
    var showsResolutionExplanation = false
    @EnvironmentObject private var localization: Localization
    @EnvironmentObject private var chargingEffectClock: ChargingEffectClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previewState = IconDesignerPreviewState()

    var body: some View {
        VStack(spacing: 8) {
            menuBarPreview

            Text(localization.string(.settingsPreviewHint))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            if showsResolutionExplanation { explanation }
        }
        .onAppear {
            previewState.setVisible(true)
            previewState.setReduceMotion(reduceMotion)
            previewState.setScenario(scenario)
            if store.showsChargingEffect { startPreviewIfAllowed() }
        }
        .onChange(of: store.showsChargingEffect) { isEnabled in
            if isEnabled {
                startPreviewIfAllowed()
            } else {
                previewState.stop()
            }
        }
        .onChange(of: scenario) { newScenario in
            previewState.setScenario(newScenario)
            if newScenario == .batteryCharging && store.showsChargingEffect {
                startPreviewIfAllowed()
            }
        }
        .onChange(of: isLiveChargingActive) { isActive in
            if isActive { previewState.stop() }
        }
        .onChange(of: reduceMotion) { isEnabled in
            previewState.setReduceMotion(isEnabled)
            if !isEnabled && store.showsChargingEffect { startPreviewIfAllowed() }
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
                    status: phase == nil ? currentStatus : chargingPreviewStatus,
                    phase: phase
                )
            }
        } else {
            previewBar(status: currentStatus, phase: nil)
        }
    }

    private var designerResolution: IconResolutionOutput {
        let live = IconResolutionInputs(
            system: IconPresentationResourceResolver.inputs(snapshot: statusStore.snapshot),
            sources: IconPresentationResourceResolver.sourceSnapshot(snapshot: statusStore.snapshot)
        )
        return IconDesignerPreviewResolver.resolve(liveInputs: live, configuration: store.iconConfiguration,
                                                   scenario: scenario)
    }

    private var explanation: some View {
        let entries = IconResolutionExplanation.entries(for: designerResolution.trace)
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                let role = localization.string(entry.slotName)
                let reason = entry.reasonKeys.map { localization.string($0) }.joined(separator: " · ")
                Text(localization.format(.iconDesignerPreviewReasonFormat, role, reason))
                    .accessibilityLabel(localization.format(.iconDesignerPreviewReasonFormat, role, reason))
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private var currentStatus: MenuBarStatus {
        ChargingEffectTestMode.status(
            MenuBarStatus(snapshot: statusStore.snapshot),
            enabled: store.testsChargingEffect
        )
    }

    private var liveChargingPhase: ChargingEffectPhase? {
        guard scenario == .live else { return nil }
        return Self.livePhase(
            battery: ChargingEffectTestMode.battery(
                statusStore.snapshot.battery,
                enabled: store.testsChargingEffect
            ),
            enabled: store.showsChargingEffect,
            reduceMotion: reduceMotion,
            phase: chargingEffectClock.phase
        )
    }

    private var isLiveChargingActive: Bool {
        liveChargingPhase != nil
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

    private var chargingPreviewStatus: MenuBarStatus {
        let current = statusStore.snapshot
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

    private func previewBar(
        status: MenuBarStatus,
        phase: ChargingEffectPhase?
    ) -> some View {
        MenuBarPreviewBar(
            status: status,
            iconSize: store.iconSize,
            batteryOptions: store.batteryIconOptions,
            connectionOptions: store.connectionIconOptions,
            volumeOptions: store.volumeIconOptions,
            bluetoothAudioOptions: store.bluetoothAudioIconOptions,
            isDarkBackground: isDarkBackground,
            phase: phase,
            resolvedScene: designerResolution.scene
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
        guard !reduceMotion, !isLiveChargingActive,
              scenario == .live || scenario == .batteryCharging else { return }
        previewState.start(at: Date())
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
    var size: CGFloat = 44
    var overrideStyle: DockIconBackgroundStyle? = nil
    var previewCache: DockIconPreviewCache? = nil
    var resolvedScene: IconSceneState? = nil

    var body: some View {
        tile
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.batteryIconOptions)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.connectionIconOptions)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.volumeIconOptions)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.bluetoothAudioIconOptions)
            .accessibilityHidden(true)
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
