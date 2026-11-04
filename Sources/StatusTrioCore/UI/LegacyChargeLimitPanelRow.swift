import SwiftUI

/// Shared by the main battery card and battery details. Reads existing state;
/// rendering either surface never probes hardware or starts a battery monitor.
@MainActor
struct LegacyChargeLimitPanelRow: View {
    @ObservedObject var controller: LegacyChargeLimitController
    var showsActions = true
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
        if state.isVisible, let status = state.status, let target = state.targetLimit {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "battery.100")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(localization.string(.settingsBatteryChargeLimitTitle))
                        Text("\(target)%")
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    .font(.caption)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(localization.format(.settingsBatteryChargeLimitActive, target))

                    if let message = statusMessage(status, isBusy: state.isBusy) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 0)

                if state.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(localization.string(.settingsBatteryChargeLimitApplying))
                } else if showsActions && state.action.isEnabled {
                    Button(actionTitle(state.action)) { perform(state.action) }
                        .font(.caption)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("legacy-charge-limit-row")
        }
    }

    private func statusMessage(
        _ status: LegacyChargeLimitPanelState.Status, isBusy: Bool
    ) -> String? {
        if isBusy { return localization.string(.settingsBatteryChargeLimitApplying) }
        switch status {
        case .holding:
            return nil // The target already states the active ceiling.
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
