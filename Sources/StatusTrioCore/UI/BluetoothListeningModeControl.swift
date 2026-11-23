import SwiftUI

/// Shared metrics for the compact AirPods capsule controls. The capsule height is
/// fixed so a shrunken (long-language) label never changes the pill's height, and
/// the Adaptive strength bar matches it exactly.
enum AirPodsControlMetrics {
    static let capsuleHeight: CGFloat = 20
}

/// The AirPods listening-mode quick switch: one capsule per supported mode, the
/// current one marked, the tapped one busy until the read-back confirms it.
///
/// It is a pure function of the `BluetoothListeningModePresentation` the controller
/// publishes — it never reads a device or calls CoreAudio. The presentation already
/// decided which modes are worth drawing and which is selected, so every rule the
/// control obeys (hide a single mode, disable a re-tap, mark the in-flight target)
/// is a rule the model was tested to hold.
///
/// The control is deliberately keyboard- and VoiceOver-first: selection is carried
/// by the `.isSelected` trait and a solid accent fill with a white label (Apple's
/// own selected-control language), not colour alone, and a mode that
/// is already selected or a change already in flight disables the button rather than
/// firing a redundant write.
struct BluetoothListeningModeControl: View {
    let presentation: BluetoothListeningModePresentation
    let onSelect: (BluetoothListeningMode) -> Void

    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(presentation.availableModes, id: \.self) { mode in
                capsule(mode)
            }
            if presentation.isFailed {
                failureMark
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localization.string(.bluetoothListeningModeGroup))
    }

    @ViewBuilder
    private func capsule(_ mode: BluetoothListeningMode) -> some View {
        let isSelected = presentation.selectedMode == mode
        // A re-tap of the selected capsule asks the device to turn off. `off` is
        // never drawn as its own capsule on an AirPods row, so the spinner for that
        // request belongs on the selected capsule, not a phantom "off" button.
        let isTurningOff = isSelected && presentation.isChanging(to: .off)
        let isTarget = presentation.isChanging(to: mode) || isTurningOff
        // Only a change in flight locks the group: the write is per device, so
        // tapping a second capsule while the first is settling would stack a
        // request the controller already refuses. The selected capsule stays
        // enabled — Apple's selected control reads as chosen, not greyed out, and
        // disabling it would drop the whole pill to SwiftUI's dimmed opacity,
        // turning the white label and accent fill muddy. A re-tap on it requests
        // `off`, turning the active mode back off.
        let isDisabled = presentation.isChanging

        Button {
            onSelect(mode)
        } label: {
            HStack(spacing: 3) {
                // The busy spinner takes over the icon slot instead of sitting
                // beside it, so tapping a capsule never changes its width/position.
                Group {
                    if isTarget {
                        busyMark
                    } else {
                        Image(nsImage: AirPodsControlSymbols.image(symbol(for: mode)))
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 13, height: 13)
                Text(localization.string(mode.titleKey))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(height: AirPodsControlMetrics.capsuleHeight)
            .background(
                Capsule().fill(
                    isSelected
                        ? Color.accentColor
                        : Color.secondary.opacity(0.10)
                )
            )
            // Apple's own selected control — the volume slider, the output-device
            // row — is a solid accent fill with white text, so the chosen capsule
            // matches that language: filled with the accent and labelled in white.
            // A tinted fill under an accent-coloured label read as low contrast
            // whenever the accent is dark or pale, which is what this replaces.
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(localization.string(mode.titleKey))
        // VoiceOver says "selected" from the trait, so the highlight is not carried
        // by colour alone; the selected pill stays enabled (a re-tap turns the mode
        // off) precisely so it renders as chosen rather than greyed-out.
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// A failed switch is marked on the control without a word stealing the row's
    /// trailing space: the observed mode gets a warning ring and the accessibility
    /// value carries the reason. The failure clears itself shortly after, per the
    /// controller.
    private var failureMark: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption2)
            .foregroundStyle(.red)
            .accessibilityLabel(localization.string(.bluetoothListeningModeChangeFailed))
    }

    /// The in-flight marker on the capsule the user tapped. It animates normally, but
    /// honours the system's Reduce Motion with a static dot so a change is still
    /// marked busy without spinning.
    @ViewBuilder
    private var busyMark: some View {
        if reduceMotion {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 5, height: 5)
        } else {
            ProgressView()
                .controlSize(.mini)
                .progressViewStyle(.circular)
        }
    }

    /// Control Center's private listening-mode artwork, matching the option
    /// icons the full panel uses.
    private func symbol(for mode: BluetoothListeningMode) -> String {
        switch mode {
        case .transparency: return "person.open.fill"
        case .adaptive: return "person.and.sparkles.fill"
        case .noiseCancellation: return "person.closed.fill"
        case .off: return "nosign"
        }
    }
}
