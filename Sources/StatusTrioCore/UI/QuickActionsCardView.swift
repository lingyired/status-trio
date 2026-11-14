import SwiftUI

/// The status panel's "quick actions" card (#295): two independent keep-awake
/// toggles on one compact row, each with its own optional timer.
///
/// "Keep Screen Awake" is a local assertion; "Keep Awake With Lid Closed" needs
/// the privileged helper and is only offered on external power. The two live
/// side by side so the card costs a single row of panel height; the per-toggle
/// descriptions moved into hover help, and a reason / error / notice line only
/// appears underneath when there is something to say.
struct QuickActionsCardView: View {
    @ObservedObject var control: SleepControlController
    @EnvironmentObject private var localization: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                displayControl
                Divider()
                    .frame(height: 22)
                lidControl
            }
            if let status = statusLine {
                Text(status.text)
                    .font(.system(size: 11))
                    .foregroundStyle(status.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: control.notice)
    }

    private var displayControl: some View {
        compactRow(
            symbol: "sun.max.fill",
            title: localization.string(.quickActionsDisplaySleep),
            help: localization.string(.quickActionsDisplaySleepDescription),
            tint: .orange,
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
    }

    private var lidControl: some View {
        compactRow(
            symbol: "moon.zzz.fill",
            title: localization.string(.quickActionsLidSleep),
            help: localization.string(.quickActionsLidSleepDescription),
            tint: .blue,
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
    }

    /// One line under the row when something needs saying. Only one message is
    /// shown, so the card never grows into a paragraph.
    private var statusLine: (text: String, color: Color)? {
        if let error = control.lastError {
            return (
                String(
                    format: localization.string(.quickActionsError),
                    locale: localization.resolvedLanguage.locale,
                    arguments: [error]
                ),
                .red
            )
        }
        if !control.isPreventingLidSleep, let reason = control.lidUnavailableReason {
            return (localization.string(reason.localizationKey), .secondary)
        }
        if let notice = control.notice {
            return (localization.string(notice.localizationKey), .secondary)
        }
        return nil
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

    private func compactRow<Timer: View>(
        symbol: String,
        title: String,
        help: String,
        tint: Color,
        isOn: Binding<Bool>,
        isEnabled: Bool,
        isApplying: Bool,
        timer: Timer
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isOn.wrappedValue ? tint : Color.secondary)
                .frame(width: 12)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 11))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isEnabled ? .primary : .secondary)

            Spacer(minLength: 2)

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(help)
    }
}

/// A compact per-toggle timer menu: a timer glyph when idle, and the remaining
/// time (m:ss / h:mm) while a countdown runs. Still a menu, so picking another
/// duration is one click away.
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
                ForEach(SleepTimerDuration.allCases, id: \.self) { option in
                    Text(localization.string(option.localizationKey)).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            label
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 34, alignment: .trailing)
        .disabled(!isOn)
        .help(localization.string(.quickActionsTimer))
        .accessibilityLabel(Text(localization.string(.quickActionsTimer)))
    }

    @ViewBuilder
    private var label: some View {
        if let expiry, isOn {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(remaining(until: expiry, now: context.date))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } else {
            Image(systemName: "timer")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func remaining(until expiry: Date, now: Date) -> String {
        let seconds = max(0, Int(expiry.timeIntervalSince(now).rounded()))
        if seconds >= 3600 {
            return String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
