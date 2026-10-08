import SwiftUI

struct OutputDeviceRow: View {
    @EnvironmentObject private var localization: Localization
    let state: PanelAudioDeviceRow
    let onSelect: () -> Void
    let onSelectListeningMode: (BluetoothListeningMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            selectionButton

            if let listeningMode = state.listeningMode, listeningMode.isControllable {
                BluetoothListeningModeControl(
                    presentation: listeningMode,
                    onSelect: onSelectListeningMode
                )
                .padding(.leading, Self.modeLeadingInset)
            }
        }
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
