import SwiftUI

struct VolumeControlsView: View {
    @EnvironmentObject private var localization: Localization
    let state: VolumePanelState
    let actions: StatusPanelActions
    let scrollTargets: PopoverScrollTargets

    @State private var draftVolume = 0.0
    @State private var isAdjusting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: { actions.toggleMute() }) {
                    Image(systemName: state.muteSymbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(state.muted ? Color.red : Color.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!state.canMute)
                .help(state.muteHelp)
                .accessibilityLabel(state.muteHelp)

                Slider(value: $draftVolume, in: 0...1, onEditingChanged: { handleVolumeEditing($0) })
                    .tint(state.muted ? Color.secondary : Color.accentColor)
                    .disabled(!state.canAdjust)
                    .accessibilityLabel(state.sliderLabel)
                    .accessibilityValue(percentageText)
                    .padding(.horizontal, 2)
                    .background(VolumeControlScrollTarget(targets: scrollTargets))

                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            if state.showsDeviceList {
                Divider().padding(.top, 2)
                OutputDeviceList(
                    rows: state.rows,
                    previewRows: state.previewRows,
                    visibleLimit: state.visibleLimit,
                    expandLabel: state.expandLabel,
                    collapseLabel: state.collapseLabel,
                    previewLanguageCode: state.previewLanguageCode,
                    onSelect: { actions.selectOutput($0) },
                    onSelectListeningMode: { actions.setListeningMode(address: $0, mode: $1) }
                )
            }
        }
        .onAppear { synchronizeVolume() }
        .onChange(of: draftVolume) { newValue in updateVolume(newValue) }
        .onChange(of: state.scalar) { newValue in
            guard !isAdjusting else { return }
            draftVolume = newValue ?? 0
        }
        .task(id: state.listeningModeTaskID) { actions.volumeListChanged() }
        .onDisappear { actions.volumeListDisappeared() }
    }

    private var percentageText: String {
        guard draftVolume.isFinite else { return "—" }
        return min(1, max(0, draftVolume)).formatted(
            .percent.precision(.fractionLength(0)).locale(localization.resolvedLanguage.locale)
        )
    }

    private func handleVolumeEditing(_ isEditing: Bool) {
        isAdjusting = isEditing
        if !isEditing { actions.finishVolumeAdjustment() }
    }

    private func updateVolume(_ newValue: Double) {
        let scalar = state.scalar ?? -1
        guard scalar.isFinite, abs(newValue - min(1, max(0, scalar))) >= 0.0005 else { return }
        actions.setVolume(newValue)
    }

    private func synchronizeVolume() {
        guard let scalar = state.scalar, scalar.isFinite else {
            draftVolume = 0
            return
        }
        draftVolume = min(1, max(0, scalar))
    }
}
