import SwiftUI

/// One compact row on the battery details page: the held ceiling, the current
/// state, and at most one action. It reads the existing controller state and
/// does not sample the battery itself.
@MainActor
struct LegacyChargeLimitPanelRow: View {
    @ObservedObject var controller: LegacyChargeLimitController
    @EnvironmentObject private var localization: Localization

    private var mapped: LegacyChargeLimitPanelState {
        LegacyChargeLimitPanelMapper.map(
            availability: controller.availability,
            status: controller.status,
            selectedLimit: controller.selectedLimit,
            isApplying: controller.isApplying
        )
    }

    var body: some View {
        let state = mapped
        if state.isVisible, let status = state.status {
            HStack(spacing: 8) {
                PanelSymbolView(source: .symbol(name: "bolt.batteryblock", variableValue: nil, fallback: "battery.100"))
                    .foregroundStyle(state.isBusy ? Color.secondary : Color.orange)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(localization.string(.settingsBatteryLegacyChargeLimitTitle))
                        .font(.caption.weight(.medium))
                    Text(statusText(status, state: state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if state.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(
                            localization.string(.settingsBatteryLegacyChargeLimitChecking)
                        )
                } else if state.action != .none {
                    Button(actionTitle(state.action)) {
                        perform(state.action)
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }

    private func statusText(
        _ status: LegacyChargeLimitPanelState.Status,
        state: LegacyChargeLimitPanelState
    ) -> String {
        switch status {
        case let .holding(limit):
            return localization.format(.settingsBatteryLegacyChargeLimitHolding, limit)
        case .temporarilyFull:
            return localization.string(.settingsBatteryLegacyChargeLimitTemporaryFull)
        case .checking:
            return localization.string(.settingsBatteryLegacyChargeLimitChecking)
        case .failed:
            return localization.string(.settingsBatteryLegacyChargeLimitFailed)
        case .externalChange:
            return localization.string(.settingsBatteryLegacyChargeLimitExternalChange)
        case .restoreFailed:
            return localization.string(.settingsBatteryLegacyChargeLimitRestoreFailed)
        case .unverified:
            return localization.string(.settingsBatteryLegacyChargeLimitUnverified)
        }
    }

    private func actionTitle(_ action: LegacyChargeLimitPanelState.Action) -> String {
        switch action {
        case .chargeToFull:
            return localization.string(.settingsBatteryLegacyChargeLimitChargeToFull)
        case .cancelFullCharge:
            return localization.string(.settingsBatteryLegacyChargeLimitCancel)
        case .none:
            return ""
        }
    }

    private func perform(_ action: LegacyChargeLimitPanelState.Action) {
        switch action {
        case .chargeToFull:
            Task { @MainActor in _ = await controller.chargeToFullOnce() }
        case .cancelFullCharge:
            Task { @MainActor in _ = await controller.cancelChargeToFull() }
        case .none:
            break
        }
    }
}