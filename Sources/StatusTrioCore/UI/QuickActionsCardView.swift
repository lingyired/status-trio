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
    /// Whether each pill is shown at all (Settings → 保持唤醒). The lid pill is
    /// additionally hidden while the privileged helper is not usable.
    var showsDisplay: Bool = true
    var showsLid: Bool = true
    @EnvironmentObject private var localization: Localization

    /// Hide the lid pill entirely until the helper can actually back it, instead
    /// of showing a permanently-grey button and a "需要特权辅助程序" line.
    private var shouldShowLid: Bool {
        guard showsLid else { return false }
        switch control.lidUnavailableReason {
        case .helperUnavailable, .helperNeedsUpdate: return false
        default: return true
        }
    }

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
            if showsDisplay {
                displayPill(now: now)
            }
            if shouldShowLid {
                lidPill(now: now)
            }
        }
    }

    private func displayPill(now: Date) -> some View {
        UnifiedCountdownControl(
            role: .displayAwake,
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
        UnifiedCountdownControl(
            role: .lidAwake,
            title: localization.string(.quickActionsLidSleep),
            help: localization.string(.quickActionsLidSleepDescription),
            subtitle: lidSubtitle(now: now),
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

    /// The lid pill's second line: keep "已关闭" and append the reason it can't
    /// be turned on (e.g. "接通电源后才能开启") right under it, inside the pill.
    private func lidSubtitle(now: Date) -> String {
        let base = subtitle(
            isOn: control.isPreventingLidSleep,
            expiry: control.lidExpiry,
            timer: control.lidTimer,
            now: now
        )
        if !control.isPreventingLidSleep, control.lidUnavailableReason == .requiresPower {
            return base + "\n" + localization.string(.quickActionsRequiresPower)
        }
        return base
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
        if shouldShowLid, let external = control.lidSleepExternalState {
            return (localization.string(external.localizationKey), .secondary)
        }
        if shouldShowLid, !control.isPreventingLidSleep,
           let reason = control.lidUnavailableReason, reason != .requiresPower {
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
private struct UnifiedCountdownControl: View {
    let role: KeepAwakeRole
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.panelCardSurfaceStyle) private var cardStyle
    @State private var isHoveringTime = false
    @State private var isHoveringCapsule = false

    private static let height: CGFloat = 54
    private static let cornerRadius: CGFloat = 13
    private static let timeWidth: CGFloat = 68
    private static let iconDiameter: CGFloat = 32

    var body: some View {
        HStack(spacing: 0) {
            mainButton
            divider
            timeButton
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background { progressBackground }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
        // System-like hover glow: the interactive glass lights up as the pointer
        // enters, without needing a click (matches Control Center modules).
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(isHoveringCapsule ? 0.06 : 0))
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(isHoveringCapsule ? 0.22 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onHover { isHoveringCapsule = $0 }
        .opacity(isEnabled ? 1 : 0.55)
        .help(help)
    }

    /// One neutral layer and one blue layer spanning the whole capsule. The
    /// blue is drawn at the container width, so a full countdown also tints the
    /// time region — it is the same continuous background, not a second block.
    /// The full-strength role colour used to tint the native glass base.
    private var semanticTint: Color {
        role == .displayAwake ? srgb(0xFFBE45) : Color.blue
    }

    private var progressBackground: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                baseLayer
                progressColor
                    .frame(width: geometry.size.width * clampedProgress)
            }
        }
    }

    /// The capsule's resting surface for the current panel style. Solid gets an
    /// opaque, appearance-adaptive base so it never reads as glass; glass and
    /// material keep a faint neutral wash so the panel still shows through.
    @ViewBuilder
    private var baseLayer: some View {
        switch cardStyle {
        case .glass:
            if #available(macOS 26.0, *), PanelCardSurfaceExperiment.useNative {
                if isOn {
                    Rectangle()
                        .fill(.clear)
                        .glassEffect(
                            .regular.tint(semanticTint.opacity(colorScheme == .dark ? 0.32 : 0.26)).interactive(),
                            in: .rect(cornerRadius: 13)
                        )
                } else {
                    Rectangle()
                        .fill(.clear)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 13))
                }
            } else {
                Color.primary.opacity(0.06)
            }
        case .material:
            Color.primary.opacity(0.08)
        case .solid:
            PanelCardSurfaceStyle.solidBase(scheme: colorScheme)
        }
    }

    /// Progress fill by role *and* panel style: the colour names the function
    /// (gold = keep screen, blue = keep lid-sleep off), while the opacity adapts
    /// so a coloured block does not overpower a frosted or solid capsule.
    private var progressColor: Color {
        switch (role, cardStyle) {
        case (.displayAwake, .glass):
            return srgb(0xFFBE45).opacity(colorScheme == .dark ? 0.55 : 0.50)
        case (.lidAwake, .glass):
            return Color.blue.opacity(colorScheme == .dark ? 0.62 : 0.50)
        case (.displayAwake, .material):
            return srgb(0xFFBE45).opacity(colorScheme == .dark ? 0.55 : 0.48)
        case (.lidAwake, .material):
            return Color.blue.opacity(colorScheme == .dark ? 0.66 : 0.46)
        case (.displayAwake, .solid):
            return srgb(0xFFBE45).opacity(colorScheme == .dark ? 0.85 : 0.85)
        case (.lidAwake, .solid):
            return Color.blue.opacity(colorScheme == .dark ? 0.85 : 0.85)
        }
    }

    private var iconPalette: KeepAwakeIconPalette {
        KeepAwakeIconPalette.resolve(role: role, isOn: isOn, isDark: colorScheme == .dark)
    }

    private var mainButton: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(iconPalette.circle(for: cardStyle))
                    Image(systemName: role.symbol)
                        .font(.system(size: role.glyphSize, weight: .semibold))
                        .foregroundStyle(iconPalette.glyph)
                }
                .frame(width: Self.iconDiameter, height: Self.iconDiameter)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
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
        .suppressFocusRing()
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1)
            .padding(.vertical, 10)
            .accessibilityHidden(true)
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
            VStack(spacing: 2) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .medium))
                HStack(spacing: 2) {
                    Text(selectedDuration.shortLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    // The chevron is part of the resting label, never a hover
                    // affordance: the time area has to read as a menu without
                    // the pointer first having to find it.
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(isHoveringTime ? 0.06 : 0))
            .contentShape(Rectangle())
            .onHover { isHoveringTime = $0 }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Self.timeWidth)
        .focusable(isEnabled)
        .suppressFocusRing()
        .disabled(!isEnabled || isApplying)
        .help(localization.string(.quickActionsTimerChoose))
        .accessibilityLabel(Text(localization.string(.quickActionsTimerChoose)))
        .accessibilityValue(Text(localization.string(selectedDuration.localizationKey)))
    }

    private var clampedProgress: Double {
        min(1, max(0, progress))
    }
}


private enum KeepAwakeRole {
    case displayAwake
    case lidAwake

    var symbol: String {
        switch self {
        case .displayAwake: "lightbulb.fill"
        case .lidAwake: "moon.zzz.fill"
        }
    }

    /// Slightly larger glyph for the bulb so it balances the wider moon in the
    /// same 32pt circle.
    var glyphSize: CGFloat {
        switch self {
        case .displayAwake: 16
        case .lidAwake: 15
        }
    }
}

/// The semantic icon colours, kept apart from the blue countdown progress.
/// Warm / bright for "keep the screen lit", soft cool for "keep the Mac awake
/// with the lid closed", neutral gray when off.
private struct KeepAwakeIconPalette {
    let circle: Color
    let glyph: Color

    static func resolve(role: KeepAwakeRole, isOn: Bool, isDark: Bool) -> KeepAwakeIconPalette {
        guard isOn else {
            return KeepAwakeIconPalette(circle: Color.primary.opacity(0.12), glyph: .secondary)
        }
        switch (role, isDark) {
        // Active glyphs are deliberately dark so they stay legible on the now
        // saturated gold/blue fill; the pale disc keeps a clear separation ring.
        case (.displayAwake, true):
            return KeepAwakeIconPalette(circle: srgb(0xFFF4DB), glyph: srgb(0x6B4A00))
        case (.displayAwake, false):
            return KeepAwakeIconPalette(circle: srgb(0xFFF0CC), glyph: srgb(0x7A5200))
        case (.lidAwake, true):
            return KeepAwakeIconPalette(circle: srgb(0xEFF3F5), glyph: srgb(0x0B4A80))
        case (.lidAwake, false):
            return KeepAwakeIconPalette(circle: srgb(0xE6F1F3), glyph: srgb(0x0E5A8A))
        }
    }

    /// The icon disc adapted to the panel card surface: a light translucent
    /// disc over glass, a softer one over material, an opaque but low-contrast
    /// one over solid. The glyph colour is untouched so the function's colour
    /// still reads on every background. This replaces the old opaque white
    /// sticker look.
    func circle(for style: PanelCardSurfaceStyle) -> Color {
        switch style {
        case .glass: return circle.opacity(0.70)
        case .material: return circle.opacity(0.85)
        case .solid: return circle
        }
    }
}

private func srgb(_ rgb: UInt32) -> Color {
    Color(
        red: Double((rgb >> 16) & 0xFF) / 255,
        green: Double((rgb >> 8) & 0xFF) / 255,
        blue: Double(rgb & 0xFF) / 255
    )
}

private extension View {
    /// Keeps the control keyboard-focusable without painting the blue focus
    /// ring when it is clicked. `focusEffectDisabled` exists on macOS 14+; on
    /// macOS 13 the ring stays as the only platform-provided affordance.
    @ViewBuilder
    func suppressFocusRing() -> some View {
        if #available(macOS 14.0, *) {
            focusEffectDisabled()
        } else {
            self
        }
    }
}
