import SwiftUI

struct OutputDeviceRow: View {
    @EnvironmentObject private var localization: Localization
    let state: PanelAudioDeviceRow
    let onSelect: () -> Void
    let onSelectListeningMode: (BluetoothListeningMode) -> Void

    @Environment(\.airPodsConversationCache) private var conversationCache
    /// The user's intent: whether the disclosure is logically open.
    @State private var expanded = false
    /// Whether the controls view is kept mounted. It stays mounted briefly while
    /// collapsing so the content can fade out; unmounting at the same instant as
    /// the tap is what made the panel drop while content was still on screen.
    @State private var shouldMountControls = false
    /// Whether the controls are fully shown. Drives the draw-only opacity and
    /// offset transition, which must not feed the layout measurement.
    @State private var contentVisible = false
    @State private var controls: AirPodsSystemControlsModel?
    /// Bumped on every toggle so a pending unmount from an earlier collapse does
    /// not tear down controls a later expand just mounted.
    @State private var transitionGeneration = 0

    /// Opacity/offset duration. Slightly shorter than the window curve so the
    /// content is in place as the panel finishes growing.
    private static let contentTransition: TimeInterval = 0.17
    private static let contentOffset: CGFloat = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                selectionButton
                if state.supportsAirPodsSystemControls {
                    Button(action: { toggle() }) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .frame(width: 24, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localization.string(.airPodsControls))
                    .accessibilityValue(expanded ? localization.string(.commonExpanded) : localization.string(.commonCollapsed))
                    .animation(Self.reducedMotion ? nil : .easeOut(duration: Self.contentTransition), value: expanded)
                }
            }

            if shouldMountControls, state.supportsAirPodsSystemControls, let controls {
                AirPodsSystemControlsView(model: controls, listeningMode: state.listeningMode, onSelectListeningMode: onSelectListeningMode)
                    .opacity(contentVisible ? 1 : 0)
                    .offset(y: contentVisible ? 0 : -Self.contentOffset)
                    .onAppear { controls.start() }
            }

            if !state.supportsAirPodsSystemControls, let listeningMode = state.listeningMode, listeningMode.isControllable {
                BluetoothListeningModeControl(
                    presentation: listeningMode,
                    onSelect: onSelectListeningMode
                )
                .padding(.leading, Self.modeLeadingInset)
            }
        }
        .onChange(of: state.key) { _ in resetControls() }
        .onChange(of: state.name) { _ in resetControls() }
        .onChange(of: state.supportsAirPodsSystemControls) { supported in
            if !supported { resetControls() }
        }
        .onAppear {
            // Development aid: lets a resize/jitter investigation drive the
            // expansion without a pointer. Ignored outside `.dev.` bundles.
            guard Self.expandsForResizeProbe,
                  state.supportsAirPodsSystemControls,
                  !expanded else { return }
            toggle()
        }
    }

    /// Expands or collapses the disclosure.
    ///
    /// Expanding mounts the controls immediately, then reveals them with a short
    /// draw-only transition while the window grows towards the new layout.
    /// Collapsing fades them out first and unmounts after the fade, so the
    /// content never disappears while the panel is still tall.
    private func toggle() {
        transitionGeneration += 1
        let generation = transitionGeneration
        if expanded {
            expanded = false
            reveal(false)
            // Unmount after the visual exit so the window shrinks continuously
            // with the fading content rather than snapping under a full-height
            // body.
            let delay = Self.reducedMotion ? 0 : Self.contentTransition
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard generation == transitionGeneration, !expanded else { return }
                shouldMountControls = false
                contentVisible = false
                controls?.stop()
            }
        } else {
            expanded = true
            if controls == nil { controls = makeControls() }
            shouldMountControls = true
            reveal(true)
        }
    }

    private func reveal(_ visible: Bool) {
        guard !Self.reducedMotion else {
            contentVisible = visible
            return
        }
        withAnimation(.easeOut(duration: Self.contentTransition)) {
            contentVisible = visible
        }
    }

    private static var reducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var expandsForResizeProbe: Bool {
        Bundle.main.bundleIdentifier?.contains(".dev.") == true
            && ProcessInfo.processInfo.environment["STATUS_TRIO_EXPAND_AIRPODS"] == "1"
    }

    private func makeControls() -> AirPodsSystemControlsModel {
        AirPodsSystemControlsModel(
            deviceID: state.key,
            deviceName: state.name,
            conversationCache: state.isPreview ? nil : conversationCache,
            preview: state.isPreview ? ListeningModePreview.systemControlSnapshot(localization) : nil
        )
    }

    private func resetControls() {
        transitionGeneration += 1
        controls?.stop()
        controls = nil
        expanded = false
        shouldMountControls = false
        contentVisible = false
    }

    private var selectionButton: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(state.selected ? Color.accentColor : Color.secondary.opacity(0.14))
                    AudioOutputDeviceIconView(source: state.symbol)
                        .foregroundStyle(state.selected ? Color.white : Color.secondary)
                }
                .frame(width: 24, height: 24)

                Text(state.name)
                    .font(.body.weight(state.selected ? .semibold : .regular))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let volumeText = state.volumeText {
                    Text(volumeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!state.enabled)
        .help(state.helpText)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityValue(state.selected ? localization.string(.volumeOutputCurrent) : "")
    }

    private static let modeLeadingInset: CGFloat =
        BluetoothPanelMetrics.iconColumnWidth + BluetoothPanelMetrics.iconTextSpacing
}