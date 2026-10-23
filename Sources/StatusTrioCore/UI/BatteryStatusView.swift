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

    private var hasDetails: Bool { state.intent == .batteryDetails }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onOpenBatteryDetails) {
                HStack(spacing: 10) {
                    PanelSymbolView(source: state.symbol)
                        .foregroundStyle(state.tint.color(caution: cautionColor))
                        .frame(
                            width: PanelSummaryActionMetrics.hitTarget,
                            height: PanelSummaryActionMetrics.hitTarget
                        )
                        .accessibilityHidden(true)

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

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasDetails)
            .accessibilityLabel(state.accessibilityLabel)
            .accessibilityValue(state.accessibilityValue)

            if showsLowPowerToggle, let lowPowerMode {
                lowPowerToggleButton(lowPowerMode)
            }

            // The chevron sits immediately left of the gear so its right edge
            // lines up with the same affordance in the rows below; the leaf would
            // otherwise push it one slot to the left.
            if hasDetails {
                PanelActionGlyph(
                    systemName: "chevron.right",
                    font: .caption.weight(.semibold)
                )
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            if state.showsSettings {
                Button(action: onOpenBatterySettings) {
                    PanelActionGlyph(
                        systemName: "gearshape",
                        verticalOpticalOffset: 0
                    )
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(localization.string(.batteryActionOpenSettings))
                .accessibilityLabel(localization.string(.batteryActionOpenSettings))
            }
        }
    }

    /// A one-click Low Power Mode switch, mirroring the system battery menu's
    /// quick toggle. Filled when on, outlined when off.
    private func lowPowerToggleButton(_ controller: LowPowerModeController) -> some View {
        // A dedicated observing subview: the row itself holds the controller as a
        // plain value, so reading `isLowPowerMode` here would not re-render the
        // leaf when the state changes.
        LowPowerModeToggleButton(controller: controller, localization: localization)
    }

    var showsDetailAffordance: Bool { hasDetails }
}

/// The leaf switch, split out so it observes the controller and re-renders when
/// the Low Power Mode state changes.
private struct LowPowerModeToggleButton: View {
    @ObservedObject var controller: LowPowerModeController
    let localization: Localization

    var body: some View {
        Button {
            controller.setLowPowerMode(!controller.isLowPowerMode)
        } label: {
            PanelActionGlyph(
                systemName: controller.isLowPowerMode ? "leaf.fill" : "leaf"
            )
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(controller.isLowPowerMode ? Color.green : Color.secondary)
        .help(localization.string(.lowPowerModeToggleDescription))
        .disabled(controller.isApplying)
        .accessibilityLabel(localization.string(.lowPowerModeToggle))
        .accessibilityValue(
            localization.string(controller.isLowPowerMode ? .batteryDetailsOn : .batteryDetailsOff)
        )
        .frame(
            width: PanelSummaryActionMetrics.hitTarget,
            height: PanelSummaryActionMetrics.hitTarget
        )
    }
}
