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
    var fillColor: Color = .primary
    var matchesBrightnessThickness: Bool = false

    var body: some View {
        VolumeControlsView(
            state: model.volume,
            actions: actions,
            scrollTargets: scrollTargets,
            onOpenSoundSettings: onOpenSoundSettings,
            fillColor: fillColor,
            matchesBrightnessThickness: matchesBrightnessThickness
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
    var fillColor: Color = .primary
    var matchesBrightnessThickness: Bool = false

    @State private var interaction: VolumeControlInteraction

    init(
        state: VolumePanelState,
        actions: StatusPanelActions,
        scrollTargets: PopoverScrollTargets,
        onOpenSoundSettings: @escaping () -> Void,
        fillColor: Color = .primary,
        matchesBrightnessThickness: Bool = false
    ) {
        self.state = state
        self.actions = actions
        self.scrollTargets = scrollTargets
        self.onOpenSoundSettings = onOpenSoundSettings
        self.fillColor = fillColor
        self.matchesBrightnessThickness = matchesBrightnessThickness
        _interaction = State(
            initialValue: VolumeControlInteraction(
                setVolume: { actions.setVolume($0) },
                finishVolume: { actions.finishVolumeAdjustment() }
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasNoOutputDevices {
                HStack(alignment: .center, spacing: 10) {
                    PanelAudioEmptyDevicesHint(
                        text: localization.string(.volumeOutputEmpty),
                        systemImage: "questionmark.circle"
                    )
                    settingsButton
                }
                .frame(height: PanelSummaryActionMetrics.actionSlot)
            } else {
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
                        tint: state.muted ? Color.secondary : fillColor,
                        accessibilityLabel: state.sliderLabel,
                        accessibilityValue: percentageText,
                        onEditingChanged: { isEditing in
                            handleVolumeEditing(isEditing)
                        },
                        height: matchesBrightnessThickness
                            ? PanelLevelSliderMetrics.controlHeight
                            : PanelLevelSliderMetrics.compactSlotHeight,
                        barHeight: matchesBrightnessThickness
                            ? PanelLevelSliderMetrics.barHeight
                            : PanelLevelSliderMetrics.compactBarHeight
                    )
                        .background(VolumeControlScrollTarget(targets: scrollTargets))

                    Text(percentageText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 34, alignment: .trailing)
                        .accessibilityHidden(true)

                    settingsButton
                }
            }

            if state.showsDeviceList && hasDeviceListContent {
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

    /// Only a truly absent output means the slider has nothing to control. A
    /// real current output stays adjustable before the device list loads (or
    /// when the list is disabled), and a pending skeleton keeps its layout.
    private var hasNoOutputDevices: Bool {
        !state.hasUsableOutput
            && state.rows.isEmpty
            && state.previewRows.isEmpty
            && state.deviceListPlaceholder == nil
    }

    /// The device list only needs space once it has rows or a skeleton; an
    /// unloaded list must not push an empty card under the live slider.
    private var hasDeviceListContent: Bool {
        !state.rows.isEmpty
            || !state.previewRows.isEmpty
            || state.deviceListPlaceholder != nil
    }

    private var settingsButton: some View {
        Button(action: onOpenSoundSettings) {
            PanelActionGlyph(systemName: "gearshape", size: PanelSummaryActionMetrics.actionSlot)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(localization.string(.volumeActionOpenSettings))
        .accessibilityLabel(localization.string(.volumeActionOpenSettings))
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
            // Tell the store a pointer gesture owns the slider so the panel
            // publishes level changes without its 10 Hz coalescer.
            actions.beginVolumeAdjustment()
            interaction.beginEditing()
        } else {
            interaction.endEditing(identity: state.interactionIdentity)
            // endEditing flushes the draft only on some paths; calling the
            // finish command unconditionally also clears the gesture flag so a
            // cancelled/invalidated drag cannot leave the panel bypassing the
            // coalescer forever.
            actions.finishVolumeAdjustment()
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
