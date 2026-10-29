import SwiftUI

struct VolumeControlsView: View {
    private struct SynchronizationSnapshot: Equatable {
        let scalar: Double?
        let identity: VolumeControlInteractionIdentity
        let canAdjust: Bool
    }

    @EnvironmentObject private var localization: Localization
    let state: VolumePanelState
    let actions: StatusPanelActions
    let scrollTargets: PopoverScrollTargets
    let onOpenSoundSettings: () -> Void

    @State private var interaction: VolumeControlInteraction

    init(
        state: VolumePanelState,
        actions: StatusPanelActions,
        scrollTargets: PopoverScrollTargets,
        onOpenSoundSettings: @escaping () -> Void
    ) {
        self.state = state
        self.actions = actions
        self.scrollTargets = scrollTargets
        self.onOpenSoundSettings = onOpenSoundSettings
        _interaction = State(
            initialValue: VolumeControlInteraction(
                setVolume: { actions.setVolume($0) },
                finishVolume: { actions.finishVolumeAdjustment() }
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Button(action: {
                    VolumePanelActionGate.toggleMute(in: state) {
                        actions.toggleMute()
                    }
                }) {
                    PanelActionGlyph(
                        systemName: state.muteSymbol,
                        font: .system(size: 15, weight: .medium)
                    )
                        .foregroundStyle(state.muted ? Color.red : Color.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!state.canMute)
                .help(state.muteHelp)
                .accessibilityLabel(state.muteHelp)

                Slider(
                    value: volumeBinding,
                    in: 0...1,
                    onEditingChanged: { isEditing in
                        handleVolumeEditing(isEditing)
                    }
                )
                    .tint(state.muted ? Color.secondary : Color.accentColor)
                    .disabled(!state.canAdjust)
                    .accessibilityLabel(state.sliderLabel)
                    .accessibilityValue(percentageText)
                    .padding(.horizontal, 2)
                    .background(VolumeControlScrollTarget(targets: scrollTargets))

                Text(percentageText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 34, alignment: .trailing)
                    .accessibilityHidden(true)

                Button(action: onOpenSoundSettings) {
                    PanelActionGlyph(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(localization.string(.volumeActionOpenSettings))
                .accessibilityLabel(localization.string(.volumeActionOpenSettings))
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
        .onAppear { synchronizeVolume(synchronizationSnapshot) }
        .onChange(of: synchronizationSnapshot) { snapshot in
            synchronizeVolume(snapshot)
        }
    }

    private var percentageText: String {
        guard state.scalar != nil, interaction.value.isFinite else { return "—" }
        return min(1, max(0, interaction.value)).formatted(
            .percent.precision(.fractionLength(0)).locale(localization.resolvedLanguage.locale)
        )
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { interaction.value },
            set: { newValue in
                interaction.setSliderValue(
                    newValue,
                    identity: state.interactionIdentity,
                    canAdjust: state.canAdjust
                )
            }
        )
    }

    private func handleVolumeEditing(_ isEditing: Bool) {
        if isEditing {
            interaction.beginEditing()
        } else {
            interaction.endEditing(identity: state.interactionIdentity)
        }
    }

    private var synchronizationSnapshot: SynchronizationSnapshot {
        SynchronizationSnapshot(
            scalar: state.scalar,
            identity: state.interactionIdentity,
            canAdjust: state.canAdjust
        )
    }

    private func synchronizeVolume(_ snapshot: SynchronizationSnapshot) {
        interaction.receiveSystemState(
            identity: snapshot.identity,
            scalar: snapshot.scalar,
            canAdjust: snapshot.canAdjust
        )
    }
}
