import SwiftUI

/// The status panel's "quick actions" card (#295): two independent keep-awake
/// toggles, each with an optional timer. "Keep Screen Awake" is a local
/// assertion; "Keep Awake With Lid Closed" needs the privileged helper and is
/// only offered on external power.
struct QuickActionsCardView: View {
    @ObservedObject var control: SleepControlController
    @EnvironmentObject private var localization: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(localization.string(.settingsPopupOrderQuickActions))
                    .font(.system(size: 12, weight: .semibold))
            } icon: {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.secondary)

            row(
                title: localization.string(.quickActionsDisplaySleep),
                subtitle: localization.string(.quickActionsDisplaySleepDescription),
                isOn: displayBinding,
                isEnabled: true,
                isApplying: false,
                timer: TimerMenu(
                    isOn: control.isPreventingDisplaySleep,
                    duration: control.displayTimer,
                    expiry: control.displayExpiry,
                    onSelect: { control.setDisplayTimer($0) }
                )
            )

            Divider().opacity(0.5)

            row(
                title: localization.string(.quickActionsLidSleep),
                subtitle: lidSubtitle,
                isOn: lidBinding,
                isEnabled: control.isPreventingLidSleep || control.canEnableLidSleep,
                isApplying: control.isApplyingLidSleep,
                timer: TimerMenu(
                    isOn: control.isPreventingLidSleep,
                    duration: control.lidTimer,
                    expiry: control.lidExpiry,
                    onSelect: { control.setLidTimer($0) }
                )
            )

            if let error = control.lastError {
                Text(
                    String(
                        format: localization.string(.quickActionsError),
                        locale: localization.resolvedLanguage.locale,
                        arguments: [error]
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let notice = control.notice {
                Text(localization.string(notice.localizationKey))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: control.notice)
    }

    /// While the lid toggle is available the row repeats the one-line reminder
    /// instead of the reason, so the card does not grow a second line of status.
    private var lidSubtitle: String {
        if !control.isPreventingLidSleep, let reason = control.lidUnavailableReason {
            return localization.string(reason.localizationKey)
        }
        return localization.string(.quickActionsLidSleepDescription)
    }

    private var displayBinding: Binding<Bool> {
        Binding(
            get: { control.isPreventingDisplaySleep },
            set: { control.setDisplaySleep($0) }
        )
    }

    private var lidBinding: Binding<Bool> {
        Binding(
            get: { control.isPreventingLidSleep },
            set: { control.setLidSleep($0) }
        )
    }

    private func row<MenuContent: View>(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        isEnabled: Bool,
        isApplying: Bool,
        timer: MenuContent
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)

            if isApplying {
                ProgressView().controlSize(.mini)
            } else {
                timer
            }

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!isEnabled || isApplying)
                .accessibilityLabel(Text(title))
        }
    }
}

/// The per-toggle timer menu. While a countdown is running it shows the time
/// left instead of the chosen option, and updates once a second through a
/// `TimelineView` (no controller-side ticker).
private struct TimerMenu: View {
    let isOn: Bool
    let duration: SleepTimerDuration
    let expiry: Date?
    let onSelect: (SleepTimerDuration) -> Void

    @EnvironmentObject private var localization: Localization

    var body: some View {
        Menu {
            Picker(
                localization.string(.quickActionsTimer),
                selection: Binding(get: { duration }, set: { onSelect($0) })
            ) {
                ForEach(SleepTimerDuration.allCases) { option in
                    Text(localization.string(option.localizationKey)).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            label
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!isOn)
        .help(localization.string(.quickActionsTimer))
    }

    @ViewBuilder
    private var label: some View {
        if let expiry, isOn {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(remainingText(until: expiry, now: context.date))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(localization.string(duration.localizationKey))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func remainingText(until expiry: Date, now: Date) -> String {
        let seconds = max(0, Int(expiry.timeIntervalSince(now).rounded()))
        let formatted: String
        if seconds >= 3600 {
            formatted = String(
                format: "%d:%02d:%02d",
                seconds / 3600,
                (seconds % 3600) / 60,
                seconds % 60
            )
        } else {
            formatted = String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
        return String(
            format: localization.string(.quickActionsRemaining),
            locale: localization.resolvedLanguage.locale,
            arguments: [formatted]
        )
    }
}
