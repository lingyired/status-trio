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
    /// The live source the centre slot draws. The card re-renders when
    /// the controller publishes; `nil` in previews with no live controller.
    var inputSourceController: InputSourceController? = nil
    @Binding var isDarkBackground: Bool
    @EnvironmentObject private var localization: Localization
    @EnvironmentObject private var chargingEffectClock: ChargingEffectClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previewPlayback = ChargingEffectPreviewPlayback()
    /// Identifies this card's claim on the shared clock, so a Dock-only menu bar
    /// still animates the preview while it is visible.
    @State private var clockConsumerToken = UUID()

    var body: some View {
        InputSourceLivePreview(controller: inputSourceController) {
            card
        }
    }

    private var card: some View {
        VStack(spacing: 8) {
            menuBarPreview

            Text(localization.string(.settingsPreviewHint))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .onAppear {
            setClockClaim(enabled: store.showsMenuBarChargingEffect)
        }
        .onChange(of: store.showsMenuBarChargingEffect) { isEnabled in
            setClockClaim(enabled: isEnabled)
            if isEnabled {
                startPreviewIfAllowed()
            } else {
                previewPlayback.stop()
            }
        }
        .onChange(of: isLiveChargingActive) { isActive in
            if isActive { previewPlayback.stop() }
        }
        .onChange(of: reduceMotion) { isEnabled in
            if isEnabled {
                previewPlayback.stop()
            }
        }
        .onDisappear {
            chargingEffectClock.endAnimationPreview(clockConsumerToken)
            previewPlayback.stop()
        }
        .task(id: previewPlayback.startedAt) {
            guard let startedAt = previewPlayback.startedAt else { return }
            let elapsed = Date().timeIntervalSince(startedAt)
            let remaining = max(0, ChargingEffectPreviewPlayback.duration - elapsed)
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard !Task.isCancelled else { return }
            previewPlayback.stop()
        }
    }

    @ViewBuilder
    private var menuBarPreview: some View {
        if let phase = liveChargingPhase {
            previewBar(status: currentStatus, phase: phase)
        } else if previewPlayback.isPlaying {
            TimelineView(.animation(
                minimumInterval: 1 / Double(ChargingEffectTimeline.framesPerSecond),
                paused: false
            )) { timeline in
                let phase = previewPlayback.phase(at: timeline.date)
                previewBar(
                    status: phase == nil ? currentStatus : chargingPreviewStatus,
                    phase: phase
                )
            }
        } else {
            previewBar(status: currentStatus, phase: nil)
        }
    }

    private var currentStatus: MenuBarStatus {
        ChargingEffectTestMode.status(
            MenuBarStatus(snapshot: statusStore.snapshot),
            enabled: store.testsChargingEffect
        )
    }

    private var liveChargingPhase: ChargingEffectPhase? {
        Self.livePhase(
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
              !reduceMotion,
              !isLiveChargingActive
        else { return }
        previewPlayback.start(at: Date())
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
