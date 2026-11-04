import SwiftUI

extension ChargeToFullNowPresentation {
    /// Whether the action area should occupy space at all. `unavailable` has no
    /// button but still explains why the action cannot run; a restored limit
    /// stays visible while the battery charges up to it.
    var showsActionArea: Bool {
        showsButton || self == .unavailable || isRestoredLimit
    }
}

/// The Charge to Full Now row shared by the battery summary and the battery
/// details page. Keeping one view guarantees both surfaces use the same label,
/// progress, cancel confirmation, and error notices.
struct ChargeToFullNowActionView: View {
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
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        } else {
                            Text(actionLabel)
                                .font(.caption.weight(.medium))
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
                .disabled(presentation.isApplying || presentation.isCancelling)
                .accessibilityLabel(actionLabel)
            }

            if case .limitRestored(let limit) = presentation {
                restoredLimitRow(limit: limit)
            }

            switch presentation {
            case .failed:
                notice(.batteryActionChargeToFullNowFailed)
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
                 .cancelling,
                 .unavailable,
                 .limitRestored:
                EmptyView()
            }
        }
    }

    private var chargingLabel: String? {
        presentation == .chargingToFull
            ? localization.string(.batteryActionChargeToFullNowCharging)
            : nil
    }

    private var actionLabel: String {
        switch presentation {
        case .applying:
            localization.string(.batteryActionChargeToFullNowApplying)
        case .chargingToFull:
            localization.string(.batteryActionCancelChargeToFullNow)
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
        case .hidden, .available, .failed, .unavailable, .limitRestored:
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
             .cancelLimitChangedConfirmation,
             .limitRestored:
            false
        }
    }

    /// A static confirmation replaces the button until the battery finishes
    /// charging to the restored limit, so cancelling cannot bounce the user
    /// straight back into another Charge to Full Now request.
    private func restoredLimitRow(limit: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .frame(width: 14, height: 14)
                .foregroundStyle(.green)

            Text(restoredLimitText(limit))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func restoredLimitText(_ limit: Int) -> String {
        localization.format(.batteryActionCancelChargeToFullNowRestored, limit)
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
