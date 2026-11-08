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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                }
            }

            if state.supportsAirPodsSystemControls, let controls {
                AirPodsSystemControlsView(model: controls, listeningMode: state.listeningMode, onSelectListeningMode: onSelectListeningMode)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: AirPodsControlsHeightKey.self, value: geometry.size.height)
                    })
                    .frame(height: disclosure.presentedHeight, alignment: .top)
                    .clipped()
                    .transaction { $0.animation = nil }
                    .allowsHitTesting(expanded)
                    .accessibilityHidden(!expanded)
            }

            if !state.supportsAirPodsSystemControls, let listeningMode = state.listeningMode, listeningMode.isControllable {
                BluetoothListeningModeControl(
                    presentation: listeningMode,
                    onSelect: onSelectListeningMode
                )
                .padding(.leading, Self.modeLeadingInset)
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
            if expanded, isPresented { controls?.start() }
        }
        .onChange(of: state.supportsAirPodsSystemControls) { supported in
            if !supported { resetControls() }
        }
        .onAppear {
            disclosure.pixelScale = displayScale
            if expanded, isPresented { controls?.start() }
            updateDisclosureTarget()
            // Development aid: lets a resize/jitter investigation drive the
            // expansion without a pointer. Ignored outside `.dev.` bundles.
            guard Self.expandsForResizeProbe,
                  state.supportsAirPodsSystemControls,
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
                if expanded { controls?.start() }
                updateDisclosureTarget()
            } else {
                controls?.stop()
                disclosure.markSettled(at: expanded ? controlsHeight : 0)
            }
        }
    }

    private func toggle() {
        if expanded {
            expanded = false
            controls?.stop()
        } else {
            expanded = true
            if controls == nil { controls = makeControls() }
            if isPresented { controls?.start() }
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
