import SwiftUI

/// Observing container for the volume row.
///
/// The panel observes `StatusPanelViewModel` as a whole, so a volume tick would
/// otherwise invalidate every section. This wrapper is the only view that
/// observes `VolumeControlModel`, which keeps a tick's invalidation scoped to
/// the volume row (#263).
struct VolumeControlsSection: View {
    @ObservedObject var model: VolumeControlModel
    let actions: StatusPanelActions
    let scrollTargets: PopoverScrollTargets
    let onOpenSoundSettings: () -> Void

    var body: some View {
        VolumeControlsView(
            state: model.volume,
            actions: actions,
            scrollTargets: scrollTargets,
            onOpenSoundSettings: onOpenSoundSettings
        )
    }
}


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
                        .frame(width: PanelSummaryActionMetrics.leadingGlyphSlot)
                        .foregroundStyle(state.muted ? Color.red : Color.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!state.canMute)
                .help(state.muteHelp)
                .accessibilityLabel(state.muteHelp)

                PanelLevelSlider(
                    value: volumeBinding,
                    isEnabled: state.canAdjust,
                    tint: state.muted ? Color.secondary : Color.accentColor,
                    accessibilityLabel: state.sliderLabel,
                    accessibilityValue: percentageText,
                    onEditingChanged: { isEditing in
                        handleVolumeEditing(isEditing)
                    }
                )
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
                    onSelectListeningMode: { actions.setListeningMode(address: $0, mode: $1) },
                    skeleton: state.deviceListPlaceholder
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
