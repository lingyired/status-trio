import Combine
import SwiftUI

struct OutputDeviceRow: View {
    @EnvironmentObject private var localization: Localization
    let state: PanelAudioDeviceRow
    let onSelect: () -> Void
    let onSelectListeningMode: (BluetoothListeningMode) -> Void
    var controlsFactory: ((PanelAudioDeviceRow) -> AirPodsSystemControlsModel)? = nil

    @Environment(\.airPodsConversationCache) private var conversationCache
    @Environment(\.statusPanelVisibility) private var panelVisibility
    @Environment(\.statusPanelAnimatesDisclosures) private var animatesDisclosures
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @StateObject private var disclosure = StatusPanelResizeCoordinator()
    @State private var isPresented = true
    @State private var controlsHeight: CGFloat = 0
    /// The user's intent: whether the disclosure is logically open.
    @State private var expanded = false
    // Retain the model for this stable row identity. Only the clipped container's
    // actual layout height animates; hardware demand follows user intent.
    @State private var controls: AirPodsSystemControlsModel?

    /// Spatial Audio and Conversation Awareness are the groups behind the
    /// chevron. They only exist on AirPods rows that can render system controls.
    private var hasExtraGroups: Bool {
        state.supportsAirPodsSystemControls
            && (state.airPodsSpatialSupported || state.airPodsConversationSupported)
    }

    /// With two groups the chevron discloses them; with one group it is drawn
    /// inline and no chevron is shown; with none there is nothing extra.
    private var showsExtraToggle: Bool {
        state.supportsAirPodsSystemControls
            && state.airPodsSpatialSupported && state.airPodsConversationSupported
    }

    private var showsInlineExtraGroup: Bool {
        hasExtraGroups && !showsExtraToggle
    }

    /// AirPods controls align with the device icon's left edge (no text-column
    /// inset). This is deliberate: it frees horizontal width so longer localized
    /// labels (e.g. English) fit without truncation.
    private var contentLeading: CGFloat { 0 }

    /// A compact Adaptive Audio strength bar appears below the listening row
    /// whenever the Adaptive mode is the selected one.
    private var showsAdaptiveBar: Bool {
        state.supportsAirPodsSystemControls
            && state.listeningMode?.selectedMode == .adaptive
    }

    /// Rows that start their model as soon as the panel is visible: only the
    /// inline single group. The Adaptive bar is deliberately excluded — showing
    /// it eagerly used to open the AACP Bluetooth channel on every panel open,
    /// which dropped the headset's audio route (#323). It now loads on expansion.
    private var wantsInlineModel: Bool {
        showsInlineExtraGroup
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            selectionButton

            if state.supportsAirPodsSystemControls {
                airPodsControls
            } else if let listeningMode = state.listeningMode, listeningMode.isControllable {
                BluetoothListeningModeControl(
                    presentation: listeningMode,
                    onSelect: onSelectListeningMode
                )
                .padding(.leading, contentLeading)
                .padding(.top, 2)
            }
        }
        .onPreferenceChange(AirPodsControlsHeightKey.self) { height in
            controlsHeight = height
            updateDisclosureTarget()
        }
        .onChange(of: displayScale) { scale in
            disclosure.pixelScale = scale
            updateDisclosureTarget()
        }
        .onChange(of: state.key) { _ in resetControls() }
        .onChange(of: state.name) { _ in
            // The backend verifies the current route's name as well as its ID.
            // Refresh that meaningful dependency without discarding user intent.
            guard controls != nil else { return }
            controls?.stop()
            controls = makeControls()
            if (expanded || wantsInlineModel), isPresented { controls?.start() }
        }
        .onChange(of: state.supportsAirPodsSystemControls) { supported in
            if !supported { resetControls() }
        }
        .onChange(of: state.listeningMode?.selectedMode) { mode in
            // Switching to Adaptive only reveals the strength bar. The AACP
            // channel that the bar needs is opened by the bar's own drag, never
            // from here, so the panel never touches it passively (#323).
            if expanded, isPresented, mode == .adaptive {
                ensureControlsStarted()
            } else if !expanded, !showsInlineExtraGroup {
                controls?.stop()
            }
        }
        .onAppear {
            disclosure.pixelScale = displayScale
            if wantsInlineModel, isPresented {
                ensureControlsStarted()
            } else if expanded, isPresented {
                ensureControlsStarted()
            }
            updateDisclosureTarget()
            // Development aid: lets a resize/jitter investigation drive the
            // expansion without a pointer. Ignored outside `.dev.` bundles.
            guard Self.expandsForResizeProbe,
                  showsExtraToggle,
                  !expanded else { return }
            toggle()
        }
        .onDisappear {
            controls?.stop()
            disclosure.cancel()
        }
        .onReceive(panelVisibility) { visible in
            isPresented = visible
            if visible {
                if expanded { ensureControlsStarted() }
                else if wantsInlineModel { ensureControlsStarted() }
                updateDisclosureTarget()
            } else {
                controls?.stop()
                disclosure.markSettled(at: expanded ? controlsHeight : 0)
            }
        }
    }

    /// The listening-mode quick switch stays visible at all times. When two
    /// extra groups are available a chevron sits at the right end of this row;
    /// otherwise the row is the whole control.
    @ViewBuilder private var airPodsControls: some View {
        if let listeningMode = state.listeningMode, listeningMode.isControllable {
            HStack(alignment: .center, spacing: 6) {
                BluetoothListeningModeControl(
                    presentation: listeningMode,
                    onSelect: onSelectListeningMode
                )
                if showsExtraToggle {
                    Spacer(minLength: 6)
                    expandButton
                }
            }
            .padding(.leading, contentLeading)
            .padding(.top, 2)
        } else if showsExtraToggle {
            HStack {
                Spacer(minLength: 0)
                expandButton
            }
            .padding(.leading, contentLeading)
            .padding(.top, 2)
        }

        if showsAdaptiveBar, let controls {
            AirPodsAdaptiveBar(model: controls)
                .padding(.leading, contentLeading)
                .padding(.top, 2)
        }

        if showsExtraToggle, let controls {
            AirPodsSpatialConversationView(model: controls)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, contentLeading)
                .padding(.top, 4)
                .padding(.bottom, 6)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: AirPodsControlsHeightKey.self, value: geometry.size.height)
                })
                .frame(height: disclosure.presentedHeight, alignment: .top)
                .clipped()
                .transaction { $0.animation = nil }
                .allowsHitTesting(expanded)
                .accessibilityHidden(!expanded)
        } else if showsInlineExtraGroup, let controls {
            AirPodsSpatialConversationView(model: controls)
                .fixedSize(horizontal: false, vertical: true)
                // No listening-mode row above: align the group with the device
                // name's text column and give it room to read as its own block.
                .padding(.leading, contentLeading)
                .padding(.top, 6)
                .padding(.bottom, 6)
        }
    }

    private var expandButton: some View {
        Button(action: { toggle() }) {
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.semibold))
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localization.string(.airPodsControls))
        .accessibilityValue(expanded ? localization.string(.commonExpanded) : localization.string(.commonCollapsed))
    }

    private func ensureControlsStarted(includeAdaptive: Bool = false) {
        if controls == nil { controls = makeControls() }
        controls?.start(includeAdaptive: includeAdaptive)
    }

    private func toggle() {
        guard showsExtraToggle else { return }
        if expanded {
            expanded = false
            controls?.stop()
        } else {
            expanded = true
            ensureControlsStarted()
        }
        updateDisclosureTarget()
    }

    private func updateDisclosureTarget() {
        let target = expanded ? controlsHeight : 0
        if !isPresented || reduceMotion || !animatesDisclosures {
            disclosure.markSettled(at: target)
        } else if !disclosure.isAtTarget(target) {
            disclosure.retarget(to: target, fromHeight: disclosure.presentedHeight)
        }
    }

    static var expandsForResizeProbe: Bool {
        Bundle.main.bundleIdentifier?.contains(".dev.") == true
            && ProcessInfo.processInfo.environment["STATUS_TRIO_EXPAND_AIRPODS"] == "1"
    }

    private func makeControls() -> AirPodsSystemControlsModel {
        if let controlsFactory { return controlsFactory(state) }
        return AirPodsSystemControlsModel(
            deviceID: state.key,
            deviceName: state.name,
            conversationCache: state.isPreview ? nil : conversationCache,
            preview: state.isPreview ? ListeningModePreview.systemControlSnapshot(localization) : nil
        )
    }

    private func resetControls() {
        controls?.stop()
        controls = nil
        expanded = false
        disclosure.markSettled(at: 0)
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

private struct AirPodsControlsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
