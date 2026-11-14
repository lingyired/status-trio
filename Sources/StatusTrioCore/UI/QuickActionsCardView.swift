import SwiftUI

/// The status panel's keep-awake controls (#295): two split-capsule controls on
/// one row, in the spirit of macOS Control Center.
///
/// Each control is one capsule split into two tappable segments:
///
///     [ ● Title / status    | ⏱ 1h ]
///       └ main: toggle + progress   └ time: neutral, opens a menu
///
/// Only the left main segment carries the blue remaining-time progress. The
/// right time segment is always a neutral gray, so there is never a second blue
/// block. The row reuses `SleepControlController` for every behaviour: the
/// toggles, the timers, the helper gating, power policy and residual cleanup.
struct QuickActionsCardView: View {
    @ObservedObject var control: SleepControlController
    @EnvironmentObject private var localization: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            keepAwakeRow
            if let status = statusLine {
                Text(status.text)
                    .font(.system(size: 11))
                    .foregroundStyle(status.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: control.notice)
    }

    // MARK: - Row

    /// While a finite countdown runs, a low-frequency timeline updates the
    /// progress and remaining text. When nothing is counting down there is no
    /// timeline at all, so an idle panel does not redraw.
    private var keepAwakeRow: some View {
        Group {
            if needsTicker {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    pillRow(now: context.date)
                }
            } else {
                pillRow(now: Date())
            }
        }
    }

    private var needsTicker: Bool {
        (control.isPreventingDisplaySleep && control.displayExpiry != nil)
            || (control.isPreventingLidSleep && control.lidExpiry != nil)
    }

    private func pillRow(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            displayPill(now: now)
            lidPill(now: now)
        }
    }

    private func displayPill(now: Date) -> some View {
        SplitCapsuleControl(
            symbol: "sun.max.fill",
            title: localization.string(.quickActionsDisplaySleep),
            help: localization.string(.quickActionsDisplaySleepDescription),
            subtitle: subtitle(
                isOn: control.isPreventingDisplaySleep,
                expiry: control.displayExpiry,
                timer: control.displayTimer,
                now: now
            ),
            progress: progress(
                isOn: control.isPreventingDisplaySleep,
                expiry: control.displayExpiry,
                timer: control.displayTimer,
                now: now
            ),
            isOn: control.isPreventingDisplaySleep,
            isEnabled: true,
            isApplying: false,
            selectedDuration: control.displayTimer,
            onToggle: { control.setDisplaySleep(!control.isPreventingDisplaySleep) },
            onSelectDuration: { duration in
                control.setDisplayTimer(duration)
                if !control.isPreventingDisplaySleep {
                    control.setDisplaySleep(true)
                }
            }
        )
    }

    private func lidPill(now: Date) -> some View {
        SplitCapsuleControl(
            symbol: "moon.zzz.fill",
            title: localization.string(.quickActionsLidSleep),
            help: localization.string(.quickActionsLidSleepDescription),
            subtitle: subtitle(
                isOn: control.isPreventingLidSleep,
                expiry: control.lidExpiry,
                timer: control.lidTimer,
                now: now
            ),
            progress: progress(
                isOn: control.isPreventingLidSleep,
                expiry: control.lidExpiry,
                timer: control.lidTimer,
                now: now
            ),
            isOn: control.isPreventingLidSleep,
            isEnabled: control.isPreventingLidSleep || control.canEnableLidSleep,
            isApplying: control.isApplyingLidSleep,
            selectedDuration: control.lidTimer,
            onToggle: { control.setLidSleep(!control.isPreventingLidSleep) },
            onSelectDuration: { duration in
                control.setLidTimer(duration)
                if !control.isPreventingLidSleep, control.canEnableLidSleep {
                    control.setLidSleep(true)
                }
            }
        )
    }

    // MARK: - State text / progress

    private func subtitle(
        isOn: Bool,
        expiry: Date?,
        timer: SleepTimerDuration,
        now: Date
    ) -> String {
        guard isOn else { return localization.string(.quickActionsStatusOff) }
        guard timer != .unlimited, let expiry else {
            return localization.string(.quickActionsStatusUnlimited)
        }
        let remaining = SleepProgress.remaining(until: expiry, now: now)
        guard remaining > 0 else { return localization.string(.quickActionsStatusOff) }
        let minutes = SleepProgress.displayMinutes(remaining: remaining)
        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return String(
                format: localization.string(.quickActionsRemainingHoursMinutes),
                locale: localization.resolvedLanguage.locale,
                arguments: [Int32(hours), Int32(rest)]
            )
        }
        return String(
            format: localization.string(.quickActionsRemainingMinutes),
            locale: localization.resolvedLanguage.locale,
            arguments: [Int32(minutes)]
        )
    }

    private func progress(
        isOn: Bool,
        expiry: Date?,
        timer: SleepTimerDuration,
        now: Date
    ) -> Double {
        guard isOn else { return 0 }
        guard let total = timer.timeInterval, let expiry else { return 1 }
        return SleepProgress.fraction(
            remaining: SleepProgress.remaining(until: expiry, now: now),
            total: total
        )
    }

    /// One line under the row when something needs saying (error > unavailable
    /// reason > auto-off notice). Only one message is shown, so the card never
    /// grows into a paragraph.
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
}

// MARK: - Split capsule

/// One Control Center style split capsule: a main toggle with the remaining
/// time as a blue progress fill, and a separate neutral time button.
private struct SplitCapsuleControl: View {
    let symbol: String
    let title: String
    let help: String
    let subtitle: String
    let progress: Double
    let isOn: Bool
    let isEnabled: Bool
    let isApplying: Bool
    let selectedDuration: SleepTimerDuration
    let onToggle: () -> Void
    let onSelectDuration: (SleepTimerDuration) -> Void

    @EnvironmentObject private var localization: Localization

    private static let height: CGFloat = 44
    private static let timeWidth: CGFloat = 40
    private static let segmentRadius: CGFloat = 12
    private static let iconDiameter: CGFloat = 26

    var body: some View {
        HStack(spacing: 2) {
            mainButton
            timeButton
        }
        // Two 12pt rounded segments with a hairline gap, sized like the
        // battery power cards so the panel does not gain a taller row.
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .opacity(isEnabled ? 1 : 0.5)
        .help(help)
    }

    private var mainButton: some View {
        Button(action: onToggle) {
            ZStack(alignment: .leading) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Color.primary.opacity(0.07)
                        Color.blue
                            .opacity(0.32)
                            .frame(width: geometry.size.width * clampedProgress)
                    }
                }

                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.12))
                            .frame(width: Self.iconDiameter, height: Self.iconDiameter)
                        Image(systemName: symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.system(size: 9))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.leading, 6)
                .padding(.trailing, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: Self.segmentRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Self.segmentRadius, style: .continuous))
            .overlay {
                if isApplying {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isApplying)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(subtitle))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(Text(help))
        .focusable(isEnabled)
    }

    private var timeButton: some View {
        Menu {
            Picker(
                localization.string(.quickActionsTimer),
                selection: Binding(
                    get: { selectedDuration },
                    set: { onSelectDuration($0) }
                )
            ) {
                ForEach(SleepTimerDuration.allCases) { option in
                    Text(localization.string(option.localizationKey)).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "timer")
                    .font(.system(size: 10, weight: .medium))
                Text(selectedDuration.shortLabel)
                    .font(.system(size: 9.5, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(width: Self.timeWidth, height: Self.height)
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: Self.segmentRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Self.segmentRadius, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(!isEnabled || isApplying)
        .accessibilityLabel(Text(localization.string(.quickActionsTimer)))
        .accessibilityValue(Text(localization.string(selectedDuration.localizationKey)))
    }

    private var clampedProgress: Double {
        min(1, max(0, progress))
    }
}
