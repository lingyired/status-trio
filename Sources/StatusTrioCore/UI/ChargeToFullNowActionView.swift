import SwiftUI

extension ChargeToFullNowPresentation {
    /// Whether the action area should occupy space at all. An unavailable action
    /// shows no button and no explanation — it is hidden entirely rather than
    /// occupying a row with an "unavailable" notice.
    var showsActionArea: Bool {
        showsButton
    }
}

/// The Charge to Full Now row shared by the battery summary and the battery
/// details page. Keeping one view guarantees both surfaces use the same label,
/// progress, cancel confirmation, and error notices.
struct ChargeToFullNowActionView: View {
    @Environment(\.statusPanelMediumTextEnabled) private var panelMediumText
    @EnvironmentObject private var localization: Localization
    @Environment(\.panelCardSurfaceStyle) private var cardStyle
    @Environment(\.colorScheme) private var scheme
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
                    .modifier(
                        ChargeActionSurface(
                            cardStyle: cardStyle,
                            scheme: scheme,
                            isInteractive: isActionEnabled
                        )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isActionEnabled)
                .accessibilityLabel(actionLabel)
            }

            switch presentation {
            case .failed:
                notice(.batteryActionChargeToFullNowFailed)
            case .unavailable:
                // Unavailable actions are hidden entirely (see showsActionArea);
                // no explanatory notice is rendered.
                EmptyView()
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

    /// Mirrors the button's disabled state so the hover sheen only appears on
    /// a button the user can actually press.
    private var isActionEnabled: Bool {
        !(presentation.isApplying
            || presentation.isCancelling
            || presentation == .chargingToFull)
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

/// Panel-aware surface for the Charge to Full Now action: interactive native
/// glass on Liquid Glass, a light wash over the frosted panel, and an opaque
/// adaptive base on solid — with a 10pt corner aligned to the cards.
private struct ChargeActionSurface: ViewModifier {
    let cardStyle: PanelCardSurfaceStyle
    let scheme: ColorScheme
    /// Only a button the user can actually press earns the hover sheen.
    let isInteractive: Bool

    @State private var isHovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    /// The liquid-glass gloss kept in sync with the quick-action pills: a
    /// faint white fill plus a brighter rim, revealed only while the pointer
    /// rests on an enabled button.
    private var showsHoverGloss: Bool {
        isInteractive && isHovering
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        surface(content)
            .overlay {
                if showsHoverGloss {
                    shape.fill(Color.white.opacity(0.06))
                        .overlay {
                            shape.strokeBorder(
                                Color.white.opacity(0.22),
                                lineWidth: 1
                            )
                        }
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.12), value: showsHoverGloss)
            .onHover { hovering in
                if isInteractive {
                    isHovering = hovering
                } else {
                    isHovering = false
                }
            }
    }

    @ViewBuilder
    private func surface(_ content: Content) -> some View {
        switch cardStyle {
        case .glass:
            if #available(macOS 26.0, *), PanelCardSurfaceExperiment.useNative {
                content.glassEffect(.regular.interactive(), in: shape)
            } else {
                content
                    .background(shape.fill(Color.secondary.opacity(0.08)))
                    .overlay { shape.strokeBorder(Color.secondary.opacity(0.12)) }
            }
        case .material:
            content
                .background(shape.fill(Color.secondary.opacity(0.10)))
                .overlay { shape.strokeBorder(Color.secondary.opacity(0.14)) }
        case .solid:
            content
                .background(shape.fill(Color.secondary.opacity(0.06)))
                .background(shape.fill(PanelCardSurfaceStyle.solidBase(scheme: scheme)))
                .overlay { shape.strokeBorder(Color.secondary.opacity(0.18)) }
        }
    }
}
