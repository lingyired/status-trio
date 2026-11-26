import SwiftUI

/// Shared by the main battery card and battery details. Reads existing state;
/// rendering either surface never probes hardware or starts a battery monitor.
@MainActor
struct LegacyChargeLimitPanelRow: View {
    enum Style {
        /// Details page: ceiling, status and one action.
        case full
        /// Battery card: a single action, never the ceiling.
        case actionOnly
    }

    @ObservedObject var controller: LegacyChargeLimitController
    var style: Style = .full
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
        if style == .actionOnly {
            actionOnly
        } else {
            fullRow
        }
    }

    /// The card keeps the panel minimal: only the one-tap action.
    private var actionOnly: some View {
        let action = LegacyChargeLimitPanelMapper.cardAction(
            availability: controller.availability,
            status: controller.status,
            selectedLimit: controller.selectedLimit
        )
        let busy = controller.isApplying
        return Group {
            if busy {
                // Same 28pt shell as the button so the row height never changes
                // while a command applies; the spinner is centered inside it.
                actionBox {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(localization.string(.settingsBatteryChargeLimitApplying))
                }
            } else if showsActions, let key = LegacyChargeLimitPanelMapper.actionTitleKey(for: action) {
                Button {
                    perform(action)
                } label: {
                    actionBox {
                        HStack(spacing: 7) {
                            Image(systemName: action == .cancelFullCharge ? "xmark" : "bolt.fill")
                                .frame(width: 14, height: 14)
                            Text(localization.string(key))
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localization.string(key))
            }
        }
    }

    /// Identical shell for the action button and its in-place loading state so
    /// the row height never changes while a command is applying (the loading
    /// indicator stays centered inside the same 28pt box).
    private func actionBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.12))
            }
    }

    @ViewBuilder
    private var fullRow: some View {
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
