import SwiftUI

struct BatteryStatusView: View {
    @EnvironmentObject private var localization: Localization
    let state: PanelSummaryState
    var cautionColor: Color = .yellow
    let onOpenBatteryDetails: () -> Void
    let onOpenBatterySettings: () -> Void
    /// The Low Power Mode write path, shown as a quick toggle beside the gear.
    /// Nil in previews and layout tests, where the row stays read-only.
    var lowPowerMode: LowPowerModeController?
    var showsLowPowerToggle: Bool = false
    /// Shows the High Power Mode state on the battery row. Nil in previews and
    /// layout tests, where the row stays on the plain read-only summary.
    var highPowerMode: HighPowerModeController?
    /// High Power Mode only takes effect on a power adapter, so the quick button
    /// is unavailable on battery instead of accepting a tap that cannot land.
    var isConnectedToPower: Bool = true
    var chargeToFullNow: ChargeToFullNowPresentation = .hidden
    var onChargeToFullNow: () -> Void = {}

    private var hasDetails: Bool { state.intent == .batteryDetails }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryRow

            if let infoBar = state.powerInfoBar, !infoBar.isEmpty {
                PowerInfoBarView(state: infoBar)
            }

            if chargeToFullNow.showsActionArea {
                ChargeToFullNowActionView(
                    presentation: chargeToFullNow,
                    onAction: onChargeToFullNow
                )
            }
        }
    }

    private var summaryRow: some View {
        HStack(alignment: .center, spacing: PanelSummaryActionMetrics.iconGap) {
            Button(action: onOpenBatteryDetails) {
                HStack(spacing: 10) {
                    PanelSymbolView(source: state.symbol)
                        .foregroundStyle(state.tint.color(caution: cautionColor))
                        .frame(
                            width: PanelSummaryActionMetrics.hitTarget,
                            height: PanelSummaryActionMetrics.hitTarget
                        )
                        .accessibilityHidden(true)

                    if let highPowerMode {
                        BatterySummaryLabel(
                            controller: highPowerMode,
                            title: state.title,
                            subtitle: state.subtitle
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.title)
                                .font(.headline)
                                .monospacedDigit()
                            Text(state.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasDetails)
            .accessibilityLabel(state.accessibilityLabel)
            .accessibilityValue(state.accessibilityValue)

            if showsLowPowerToggle, let lowPowerMode {
                PowerModeQuickButtons(
                    lowController: lowPowerMode,
                    highController: highPowerMode,
                    showsHighPower: highPowerMode.map {
                        $0.isSupported || $0.needsHelperUpdate
                    } ?? false,
                    isConnectedToPower: isConnectedToPower,
                    localization: localization
                )
            }

            // The chevron sits immediately left of the gear so its right edge
            // lines up with the same affordance in the rows below; the leaf would
            // otherwise push it one slot to the left.
            if hasDetails {
                Button(action: onOpenBatteryDetails) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, PanelSummaryActionMetrics.iconInset)
                        .frame(height: PanelSummaryActionMetrics.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .accessibilityLabel(localization.string(.batteryDetailsTitle))
                .help(localization.string(.batteryDetailsTitle))
            }

            if state.showsSettings {
                Button(action: onOpenBatterySettings) {
                    Image(systemName: "gearshape")
                        .padding(.horizontal, PanelSummaryActionMetrics.iconInset)
                        .offset(y: -0.25)
                        .frame(height: PanelSummaryActionMetrics.hitTarget)
                        .contentShape(Rectangle())
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(localization.string(.batteryActionOpenSettings))
                .accessibilityLabel(localization.string(.batteryActionOpenSettings))
            }
        }
    }

    var showsDetailAffordance: Bool { hasDetails }
}

/// The battery row's title and subtitle, with the High Power Mode state folded
/// into the subtitle. Observed through the controller so a state that arrives
/// after the row was built (the helper answers asynchronously) still redraws it.
private struct BatterySummaryLabel: View {
    @EnvironmentObject private var localization: Localization
    @ObservedObject var controller: HighPowerModeController
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .monospacedDigit()
            Text(
                controller.isHighPowerMode
                    ? localization.string(.highPowerModeToggle)
                    : subtitle
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
    }
}

/// The summary row's two mode shortcuts: High Power on the left, Low Power on
/// the right.
///
/// They are mutually exclusive states of one system switch, so enabling one
/// clears the other's highlight immediately instead of waiting for the next
/// helper read; the delayed refresh then reconciles both controllers.
private struct PowerModeQuickButtons: View {
    let lowController: LowPowerModeController
    let highController: HighPowerModeController?
    let showsHighPower: Bool
    let isConnectedToPower: Bool
    let localization: Localization

    /// The mode the user just replaced. It keeps the stale controller value
    /// from drawing the replaced mode as still on while the daemon catches up.
    @State private var suppressed: PowerModeSelection?

    var body: some View {
        HStack(spacing: PanelSummaryActionMetrics.iconGap) {
            if showsHighPower, let highController {
                HighPowerQuickButton(
                    controller: highController,
                    suppressed: suppressed,
                    isEnabled: isConnectedToPower,
                    localization: localization,
                    action: { toggleHigh(highController) }
                )
            }
            LowPowerQuickButton(
                controller: lowController,
                suppressed: suppressed,
                localization: localization,
                action: { toggleLow() }
            )
        }
    }

    private func toggleHigh(_ controller: HighPowerModeController) {
        if controller.isHighPowerMode {
            controller.setHighPowerMode(false)
            return
        }
        suppressed = .low
        controller.setHighPowerMode(true)
        refreshAfterWrite()
    }

    private func toggleLow() {
        if lowController.isLowPowerMode {
            lowController.setLowPowerMode(false)
            return
        }
        suppressed = .high
        lowController.setLowPowerMode(true)
        refreshAfterWrite()
    }

    private func refreshAfterWrite() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            lowController.refresh()
            highController?.refresh()
            try? await Task.sleep(for: .milliseconds(300))
            suppressed = nil
        }
    }
}

private struct HighPowerQuickButton: View {
    @ObservedObject var controller: HighPowerModeController
    /// The mode the container just replaced; it keeps the stale read from
    /// drawing the replaced mode as still on.
    let suppressed: PowerModeSelection?
    let isEnabled: Bool
    let localization: Localization
    let action: () -> Void

    /// Derived here, not passed in: this view observes the controller, so a
    /// write redraws it immediately. A value computed by the parent would stay
    /// stale until the parent itself re-rendered (the popover reopening).
    private var isSelected: Bool {
        controller.isHighPowerMode && suppressed != .high
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "bolt.batteryblock.fill")
                .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                .padding(.horizontal, PanelSummaryActionMetrics.iconInset)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.blue : Color.secondary)
        .help(
            localization.string(
                isEnabled ? .highPowerModeToggle : .powerModeHighRequiresPower
            )
        )
        .disabled(controller.isApplying || controller.needsHelperUpdate || !isEnabled)
        .accessibilityLabel(localization.string(.highPowerModeToggle))
        .accessibilityValue(
            localization.string(isSelected ? .batteryDetailsOn : .batteryDetailsOff)
        )
        .frame(height: PanelSummaryActionMetrics.hitTarget)
        .contentShape(Rectangle())
    }
}

private struct LowPowerQuickButton: View {
    @ObservedObject var controller: LowPowerModeController
    let suppressed: PowerModeSelection?
    let localization: Localization
    let action: () -> Void

    /// Derived here for the same reason as the High Power button.
    private var isSelected: Bool {
        controller.isLowPowerMode && suppressed != .low
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: isSelected ? "leaf.fill" : "leaf")
                .foregroundStyle(isSelected ? Color.green : Color.secondary)
                .padding(.horizontal, PanelSummaryActionMetrics.iconInset)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.green : Color.secondary)
        .help(localization.string(.lowPowerModeToggleDescription))
        .disabled(controller.isApplying)
        .accessibilityLabel(localization.string(.lowPowerModeToggle))
        .accessibilityValue(
            localization.string(isSelected ? .batteryDetailsOn : .batteryDetailsOff)
        )
        .frame(height: PanelSummaryActionMetrics.hitTarget)
        .contentShape(Rectangle())
    }
}
