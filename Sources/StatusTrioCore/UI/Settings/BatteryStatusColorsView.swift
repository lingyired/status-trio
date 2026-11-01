import AppKit
import SwiftUI

/// Per-state choices stay editable when state colouring is off, so switching it
/// off never discards a saved palette.
struct BatteryStatusColorsView: View {
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        ForEach(BatteryStatusColorRole.allCases, id: \.self) { role in
            SettingsDivider()
            BatteryStatusColorRow(
                role: role,
                selection: selectionBinding(for: role)
            )
        }

        SettingsDivider()
        VStack(alignment: .leading, spacing: 8) {
            if !store.usesBatteryStatusColors {
                Text(localization.string(.settingsBatteryColorsInactive))
                    .foregroundStyle(.secondary)
            }
            Text(localization.string(.settingsBatteryColorsReferenceDescription))
                .foregroundStyle(.secondary)
            Button(localization.string(.settingsBatteryColorsResetAll)) {
                store.batteryStatusColors = .standard
            }
            .disabled(!store.batteryStatusColors.hasOverrides)
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, SettingsMetrics.dividerInset)
        .padding(.trailing, SettingsMetrics.rowPaddingH)
        .padding(.vertical, SettingsMetrics.rowPaddingV)
    }

    private func selectionBinding(for role: BatteryStatusColorRole) -> Binding<BatteryStatusColorSelection> {
        Binding(
            get: { store.batteryStatusColors.selection(for: role) },
            set: { store.batteryStatusColors.setSelection($0, for: role) }
        )
    }
}

private struct BatteryStatusColorRow: View {
    let role: BatteryStatusColorRole
    @Binding var selection: BatteryStatusColorSelection
    @EnvironmentObject private var localization: Localization
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Resolve both appearances exactly once per role: each resolution builds
        // an NSAppearance, so recomputing it for the tint, previews and the
        // adjustment note would multiply the cost.
        let light = resolution(dark: false)
        let dark = resolution(dark: true)
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(
                symbol,
                tint: Color(cgColor: (colorScheme == .dark ? dark : light).color),
                title: title
            ) {
                HStack(spacing: 8) {
                    systemSwatch
                    ForEach(BatteryStatusColorPreset.allCases, id: \.self) { preset in
                        presetSwatch(preset)
                    }
                    ColorPicker(
                        localization.string(.settingsBatteryColorsCustom),
                        selection: customColorBinding(startingFrom: light),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("\(title), \(localization.string(.settingsBatteryColorsCustom))")
                    Button {
                        selection = .system
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(selection.isSystem)
                    .help(localization.string(.settingsBatteryColorsReset))
                    .accessibilityLabel("\(title), \(localization.string(.settingsBatteryColorsReset))")
                }
            }

            HStack(spacing: 14) {
                referencePreview(light, dark: false)
                referencePreview(dark, dark: true)
                if case .custom = selection {
                    Text(localization.format(
                        .settingsBatteryColorsReferenceContrast,
                        min(light.referenceContrast, dark.referenceContrast)
                    ))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    if light.wasAdjusted || dark.wasAdjusted {
                        Text(localization.string(.settingsBatteryColorsAdjusted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, SettingsMetrics.dividerInset)
            .padding(.trailing, SettingsMetrics.rowPaddingH)
            .padding(.bottom, SettingsMetrics.rowPaddingV)
        }
    }

    /// A swatch for the system semantic colour; selecting it clears any override.
    /// It always shows the semantic baseline, not the current selection, so a
    /// custom colour never changes the "system default" reference swatch.
    private var systemSwatch: some View {
        let color = Color(cgColor: BatteryStatusColorResolver.resolution(
            for: role,
            selection: .system,
            darkAppearance: colorScheme == .dark
        ).color)
        let isSelected = selection.isSystem
        return Button {
            selection = .system
        } label: {
            swatchCircle(fill: color, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .help(localization.string(.settingsBatteryColorsSystem))
        .accessibilityLabel("\(title), \(localization.string(.settingsBatteryColorsSystem))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func presetSwatch(_ preset: BatteryStatusColorPreset) -> some View {
        let color = Color(cgColor: BatteryStatusColorResolver.presetColor(
            preset,
            darkAppearance: colorScheme == .dark
        ))
        let isSelected = selection == .preset(preset)
        return Button {
            selection = .preset(preset)
        } label: {
            swatchCircle(fill: color, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .help(localization.string(presetKey(preset)))
        .accessibilityLabel("\(title), \(localization.string(presetKey(preset)))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func swatchCircle(fill: Color, isSelected: Bool) -> some View {
        Circle()
            .fill(fill)
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            .overlay(
                Circle().strokeBorder(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                    lineWidth: isSelected ? 2 : 1
                )
            )
            .padding(3)
            .contentShape(Circle())
    }

    private var title: String {
        let key: LocalizationKey = switch role {
        case .charging: .settingsBatteryColorsCharging
        case .lowPower: .settingsBatteryColorsLowPower
        case .critical: .settingsBatteryColorsCritical
        }
        return localization.string(key)
    }

    private var symbol: String {
        switch role {
        case .charging: return "bolt.fill"
        case .lowPower: return "leaf.fill"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }

    private func resolution(dark: Bool) -> BatteryStatusColorResolution {
        BatteryStatusColorResolver.resolution(for: role, selection: selection, darkAppearance: dark)
    }

    /// The colour the picker starts from. A stored custom choice is reused; a
    /// system/preset choice seeds the picker from the light-resolved colour so
    /// switching to custom begins at a visible colour rather than an arbitrary
    /// one. Subsequent edits retain the stored HSB value.
    private func customComponents(startingFrom light: BatteryStatusColorResolution) -> BatteryStatusColorComponents {
        if case .custom(let components) = selection { return components }
        let color = NSColor(cgColor: light.color) ?? .systemGreen
        return BatteryStatusColorResolver.customComponents(from: color)
    }

    private func customColorBinding(startingFrom light: BatteryStatusColorResolution) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: BatteryStatusColorResolver.nsColor(from: customComponents(startingFrom: light))) },
            set: { selection = .custom(BatteryStatusColorResolver.customComponents(from: NSColor($0))) }
        )
    }

    private func referencePreview(_ resolved: BatteryStatusColorResolution, dark: Bool) -> some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .trim(from: 0.08, to: 0.92)
                    .stroke((dark ? Color.white : Color.black).opacity(0.22), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Circle()
                    .trim(from: 0.08, to: 0.72)
                    .stroke(Color(cgColor: resolved.color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            .rotationEffect(.degrees(90))
            .frame(width: 18, height: 18)
            .padding(7)
            .background(dark ? Color.black : Color.white, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.25)))
            .accessibilityHidden(true)
            Text(localization.string(dark ? .settingsPreviewDark : .settingsPreviewLight))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func presetKey(_ preset: BatteryStatusColorPreset) -> LocalizationKey {
        switch preset {
        case .mint: return .settingsBatteryColorsMint
        case .sky: return .settingsBatteryColorsSky
        case .lavender: return .settingsBatteryColorsLavender
        case .amber: return .settingsBatteryColorsAmber
        case .rose: return .settingsBatteryColorsRose
        case .slate: return .settingsBatteryColorsSlate
        }
    }
}
