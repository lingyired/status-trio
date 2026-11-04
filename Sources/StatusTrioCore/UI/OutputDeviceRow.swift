import SwiftUI

struct OutputDeviceRow: View {
    @EnvironmentObject private var localization: Localization
    let state: PanelAudioDeviceRow
    let onSelect: () -> Void
    let onSelectListeningMode: (BluetoothListeningMode) -> Void

    @Environment(\.airPodsConversationCache) private var conversationCache
    @State private var expanded = false
    @State private var controls: AirPodsSystemControlsModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                selectionButton
                if state.supportsAirPodsSystemControls {
                    Button {
                        expanded.toggle()
                        if expanded && controls == nil {
                            controls = makeControls()
                        }
                        if !expanded { controls?.stop() }
                    } label: {
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

            if expanded, state.supportsAirPodsSystemControls, let controls {
                AirPodsSystemControlsView(model: controls, listeningMode: state.listeningMode, onSelectListeningMode: onSelectListeningMode)
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
            if controls == nil { controls = makeControls() }
            expanded = true
        }
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
        controls?.stop()
        controls = nil
        expanded = false
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
