import AppKit
import SwiftUI

/// Observing container for the volume row.
///
/// The panel observes `StatusPanelViewModel` as a whole, so a volume tick used
/// to invalidate every section. This wrapper is the only view that observes
/// `VolumeControlModel`, which keeps a drag's invalidation scoped to the volume
/// row (#263).
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

/// The volume section's layout. It holds no gesture state of its own, so the
/// slider's drag cannot rebuild the device list underneath it.
struct VolumeControlsView: View {
    let state: VolumePanelState
    let actions: StatusPanelActions
    let scrollTargets: PopoverScrollTargets
    let onOpenSoundSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VolumeSliderRow(
                state: state,
                actions: actions,
                scrollTargets: scrollTargets,
                onOpenSoundSettings: onOpenSoundSettings
            )

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
    }
}

/// The slider, mute control and percentage.
///
/// The slider is AppKit-backed on purpose. A SwiftUI `Slider` writes its binding
/// on every pointer event, and each write invalidated the hosting view: layout,
/// display list and CA commit for the whole panel window (#263). Here the drag
/// stays inside AppKit; SwiftUI only hears about the coalesced volume model.
private struct VolumeSliderRow: View {
    @EnvironmentObject private var localization: Localization
    let state: VolumePanelState
    let actions: StatusPanelActions
    let scrollTargets: PopoverScrollTargets
    let onOpenSoundSettings: () -> Void

    var body: some View {
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

            VolumeSliderControl(
                scalar: state.scalar,
                canAdjust: state.canAdjust,
                identity: state.interactionIdentity,
                muted: state.muted,
                label: state.sliderLabel,
                valueText: percentageText,
                actions: actions
            )
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
    }

    private var percentageText: String {
        guard let scalar = state.scalar, scalar.isFinite else { return "—" }
        return min(1, max(0, scalar)).formatted(
            .percent.precision(.fractionLength(0)).locale(localization.resolvedLanguage.locale)
        )
    }
}

/// AppKit slider that reports through `VolumeControlInteraction`.
///
/// `updateNSView` is the only source of truth for the displayed value, except
/// while the pointer is tracking: then AppKit owns the position and the draft
/// must not be overwritten mid-gesture.
private struct VolumeSliderControl: NSViewRepresentable {
    let scalar: Double?
    let canAdjust: Bool
    let identity: VolumeControlInteractionIdentity
    let muted: Bool
    let label: String
    let valueText: String
    let actions: StatusPanelActions

    func makeCoordinator() -> Coordinator {
        Coordinator(actions: actions)
    }

    func makeNSView(context: Context) -> VolumeNativeSlider {
        let slider = VolumeNativeSlider(
            value: 0,
            minValue: 0,
            maxValue: 1,
            target: context.coordinator,
            action: #selector(Coordinator.sliderChanged(_:))
        )
        slider.isContinuous = true
        slider.controlSize = .regular
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        slider.onEditingBegan = { [weak coordinator = context.coordinator] in
            coordinator?.beginEditing()
        }
        slider.onEditingEnded = { [weak coordinator = context.coordinator] in
            coordinator?.endEditing()
        }
        return slider
    }

    func updateNSView(_ slider: VolumeNativeSlider, context: Context) {
        context.coordinator.actions = actions
        slider.isEnabled = canAdjust
        slider.setAccessibilityLabel(label)
        slider.setAccessibilityValueDescription(valueText)
        slider.trackFillColor = muted ? .secondaryLabelColor : .controlAccentColor
        let synchronized = context.coordinator.synchronize(
            scalar: scalar,
            identity: identity,
            canAdjust: canAdjust
        )
        guard !context.coordinator.isEditing else { return }
        if abs(slider.doubleValue - synchronized) > 0.0005 {
            slider.doubleValue = synchronized
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: VolumeNativeSlider,
        context: Context
    ) -> CGSize? {
        CGSize(width: proposal.width ?? 120, height: 20)
    }

    @MainActor
    final class Coordinator: NSObject {
        var actions: StatusPanelActions
        private(set) var isEditing = false
        private var identity: VolumeControlInteractionIdentity
        private var canAdjust = true
        private var interaction: VolumeControlInteraction

        init(actions: StatusPanelActions) {
            self.actions = actions
            self.identity = VolumeControlInteractionIdentity(
                output: nil,
                configuration: .default
            )
            self.interaction = VolumeControlInteraction(
                setVolume: { actions.setVolume($0) },
                finishVolume: { actions.finishVolumeAdjustment() }
            )
        }

        func synchronize(
            scalar: Double?,
            identity: VolumeControlInteractionIdentity,
            canAdjust: Bool
        ) -> Double {
            self.identity = identity
            self.canAdjust = canAdjust
            interaction.receiveSystemState(
                identity: identity,
                scalar: scalar,
                canAdjust: canAdjust
            )
            if !isEditing {
                isEditing = interaction.isEditing
            }
            return interaction.value
        }

        func beginEditing() {
            isEditing = true
            interaction.beginEditing()
        }

        func endEditing() {
            isEditing = false
            interaction.endEditing(identity: identity)
        }

        @objc func sliderChanged(_ sender: NSSlider) {
            interaction.setSliderValue(
                sender.doubleValue,
                identity: identity,
                canAdjust: canAdjust
            )
            // Arrow keys have no mouse-up; every change is a completed edit.
            if !isEditing {
                interaction.endEditing(identity: identity)
            }
        }
    }
}

/// `NSSlider` sends its action continuously while the pointer tracks. The
/// begin/end hooks bracket that tracking loop so the interaction can tell a
/// live gesture from an external update.
private final class VolumeNativeSlider: NSSlider {
    var onEditingBegan: (() -> Void)?
    var onEditingEnded: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onEditingBegan?()
        super.mouseDown(with: event)
        onEditingEnded?()
    }
}
