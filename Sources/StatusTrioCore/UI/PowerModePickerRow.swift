import SwiftUI

/// The battery details page's Power Mode control: one segmented picker for the
/// three mutually exclusive system states instead of two toggles that could
/// disagree.
struct PowerModePickerRow: View {
    @EnvironmentObject private var localization: Localization
    @ObservedObject var lowController: LowPowerModeController
    @ObservedObject var highController: HighPowerModeController
    let isConnectedToPower: Bool

    /// The choice the user just made, shown immediately.
    ///
    /// The two controllers report the one system switch independently and
    /// update optimistically, so a switch from Low to Automatic (or the other
    /// way) leaves both reading on for a moment. Deriving the selection from
    /// them alone would flash the higher-priority segment before the other
    /// controller catches up. This local value bridges that window.
    @State private var pendingSelection: PowerModeSelection?

    private var observedSelection: PowerModeSelection {
        PowerModeSelectionLogic.selection(
            isLow: lowController.isLowPowerMode,
            isHigh: highController.isHighPowerMode
        )
    }

    private var selection: PowerModeSelection {
        pendingSelection ?? observedSelection
    }

    private var isBusy: Bool {
        lowController.isApplying
            || highController.isApplying
            || highController.needsHelperUpdate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // A hand-built segmented control instead of `Picker(.segmented)`:
            // macOS renders only text in a segmented Picker, and the three
            // states need their icons (leaf / flame / forward) at equal widths.
            HStack(spacing: 0) {
                ForEach(PowerModeSelection.allCases, id: \.self) { option in
                    Button {
                        apply(option)
                    } label: {
                        Label {
                            Text(title(for: option))
                        } icon: {
                            optionIcon(option)
                        }
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == option ? Color.white : Color.primary)
                    .background(
                        selection == option ? Color.accentColor : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
            .padding(3)
            // A translucent track instead of the opaque .controlBackgroundColor
            // slab: the panel behind this row is Liquid Glass (or its material /
            // solid fallback), and a solid system grey reads as a flat block
            // sitting on top of it. Primary at 6% plus a hairline rim lets the
            // panel show through, so the control belongs to the glass rather
            // than covering it. The selected segment keeps the app's accent-fill
            // + white-label language used by the other panel capsules.
            .background(
                Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            // Deliberately not `.disabled(isBusy)`: disabling re-styles the
            // whole control mid-write, which reads as a flash. Re-entry is
            // ignored by `apply` instead.
            .accessibilityElement(children: .contain)
            .accessibilityLabel(localization.string(.powerModeTitle))
            .accessibilityValue(accessibilityValue)
            .frame(maxWidth: .infinity)

            if highController.needsHelperUpdate {
                Label {
                    Text(localization.string(.highPowerModeHelperNeedsUpdate))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if !isConnectedToPower {
                Text(localization.string(.powerModeHighRequiresPower))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = highController.lastError {
                Text(localization.string(.highPowerModeFailure))
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(error)
            }
            if let error = lowController.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func title(for option: PowerModeSelection) -> String {
        switch option {
        case .automatic: localization.string(.powerModeAutomatic)
        case .low: localization.string(.powerModeLow)
        case .high: localization.string(.powerModeHigh)
        }
    }

    /// High Power uses the same vector glyph as the summary row's shortcut;
    /// Low Power keeps the leaf and Automatic the neutral gauge.
    @ViewBuilder
    private func optionIcon(_ option: PowerModeSelection) -> some View {
        switch option {
        case .automatic:
            Image(systemName: "gauge")
        case .low:
            Image(systemName: "leaf.fill")
        case .high:
            Image(systemName: "bolt.batteryblock.fill")
        }
    }

    private var accessibilityValue: String {
        switch selection {
        case .automatic: localization.string(.powerModeAutomatic)
        case .low: localization.string(.powerModeLow)
        case .high: localization.string(.powerModeHigh)
        }
    }

    private func apply(_ target: PowerModeSelection) {
        // The control stays enabled so it does not re-style mid-write; ignore
        // taps while a write or a helper update is already in flight.
        guard !isBusy else { return }
        let transition = PowerModeSelectionLogic.transition(
            to: target,
            isLow: lowController.isLowPowerMode,
            isHigh: highController.isHighPowerMode
        )
        guard !transition.isNoOp else { return }

        pendingSelection = target
        if transition.turnOffLow { lowController.setLowPowerMode(false) }
        if transition.turnOnLow { lowController.setLowPowerMode(true) }
        if transition.turnOffHigh { highController.setHighPowerMode(false) }
        if transition.turnOnHigh { highController.setHighPowerMode(true) }

        // The two controllers read the one system switch independently, and the
        // daemon clears the other mode itself. Re-read both after the write has
        // had time to land so the picker and the other controller agree instead
        // of keeping the pre-switch value.
        Task { @MainActor [weak lowController, weak highController] in
            try? await Task.sleep(for: .milliseconds(700))
            lowController?.refresh()
            highController?.refresh()
            // Let the re-read land before dropping the local highlight, so the
            // control settles on the observed state in one step.
            try? await Task.sleep(for: .milliseconds(350))
            pendingSelection = nil
        }
    }
}
