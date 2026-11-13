import SwiftUI

extension ChargeToFullNowPresentation {
    /// Whether the action area should occupy space at all. `unavailable` has no
    /// button but still explains why the action cannot run; a restored limit
    /// stays visible while the battery charges up to it.
    var showsActionArea: Bool {
        showsButton || self == .unavailable
    }
}

/// The Charge to Full Now row shared by the battery summary and the battery
/// details page. Keeping one view guarantees both surfaces use the same label,
/// progress, cancel confirmation, and error notices.
struct ChargeToFullNowActionView: View {
    @Environment(\.statusPanelMediumTextEnabled) private var panelMediumText
    @EnvironmentObject private var localization: Localization
    let presentation: ChargeToFullNowPresentation
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if presentation.showsButton {
                Button(action: onAction) {
                    HStack(spacing: 7) {
                        if presentation.isApplying || presentation.isCancelling {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 14, height: 14)
                        } else if showsBolt {
                            Image(systemName: "bolt.fill")
                                .frame(width: 14, height: 14)
                        }

                        if let chargingLabel {
                            Text(chargingLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            Spacer(minLength: 8)

                            Text(actionLabel)
                                .font(.caption.weight(panelMediumText ? .medium : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        } else {
                            Text(actionLabel)
                                .font(.caption.weight(panelMediumText ? .medium : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            Spacer(minLength: 0)
                        }
                    }
                    .foregroundStyle(.primary)
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
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(presentation.isApplying || presentation.isCancelling || presentation == .chargingToFull)
                .accessibilityLabel(actionLabel)
            }

            switch presentation {
            case .failed:
                notice(.batteryActionChargeToFullNowFailed)
            case .unavailable:
                notice(
                    localization.string(.batteryActionChargeToFullNowUnavailable),
                    color: .secondary,
                    showsIcon: false
                )
            case .cancelConfirmationRequired:
                notice(
                    localization.string(
                        .batteryActionCancelChargeToFullNowConfirmation
                    ),
                    color: .secondary
                )
            case .cancelPending:
                notice(
                    localization.string(.batteryActionCancelChargeToFullNowPending),
                    color: .secondary,
                    showsIcon: false
                )
            case .cancelFailed(let reason):
                notice(
                    localization.string(
                        reason == .limitChanged
                            ? .batteryActionCancelChargeToFullNowLimitChangedFailed
                            : .batteryActionCancelChargeToFullNowFailed
                    )
                )
            case .cancelLimitChangedConfirmation(let current, let target):
                notice(
                    localization.format(
                        .batteryActionCancelChargeToFullNowLimitChangedConfirmation,
                        current,
                        target
                    ),
                    color: .secondary
                )
            case .hidden,
                 .available,
                 .applying,
                 .chargingToFull,
                 .cancelling:
                EmptyView()
            }
        }
    }

    private var chargingLabel: String? {
        // Charging-to-full is now a disabled status row; the label comes from
        // actionLabel, so no separate prefix is needed.
        nil
    }

    private var actionLabel: String {
        switch presentation {
        case .applying:
            localization.string(.batteryActionChargeToFullNowApplying)
        case .chargingToFull:
            // Cancel removed: show a non-interactive charging status instead.
            localization.string(.batteryActionChargeToFullNowCharging)
        case .cancelling:
            localization.string(.batteryActionCancelChargeToFullNowApplying)
        case .cancelFailed, .cancelPending:
            localization.string(.batteryActionCancelChargeToFullNow)
        case .cancelConfirmationRequired(let limit):
            localization.format(
                .batteryActionCancelChargeToFullNowConfirm,
                limit
            )
        case .cancelLimitChangedConfirmation(_, let target):
            localization.format(
                .batteryActionCancelChargeToFullNowConfirmFallback,
                target
            )
        case .hidden, .available, .failed, .unavailable:
            localization.string(.batteryActionChargeToFullNow)
        }
    }

    private var showsBolt: Bool {
        switch presentation {
        case .available, .failed:
            true
        case .hidden,
             .applying,
             .chargingToFull,
             .unavailable,
             .cancelConfirmationRequired,
             .cancelPending,
             .cancelling,
             .cancelFailed,
             .cancelLimitChangedConfirmation:
            false
        }
    }

    private func notice(_ key: LocalizationKey) -> some View {
        notice(localization.string(key), color: .red)
    }

    private func notice(
        _ text: String,
        color: Color = .red,
        showsIcon: Bool = true
    ) -> some View {
        Group {
            if showsIcon {
                Label(
                    text,
                    systemImage: "exclamationmark.triangle.fill"
                )
            } else {
                Text(text)
            }
        }
        .font(.caption2)
        .foregroundStyle(color)
        .fixedSize(horizontal: false, vertical: true)
    }
}
