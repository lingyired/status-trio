import AppKit
import SwiftUI

/// Preset swatches, a custom picker and a reset for the status panel's level
/// slider fill colour (#359). Mirrors the battery status colour row so both
/// colour controls behave the same way: recommended swatches first, then the
/// system colour picker, then a reset back to white.
struct PanelLevelSliderColorRow: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var localization: Localization

    private struct Preset: Identifiable {
        let id: String
        let rgba: IconRGBA
        let label: LocalizationKey
    }

    private var presets: [Preset] {
        var result: [Preset] = [
            Preset(id: "white", rgba: .white, label: .settingsPanelLevelSliderColorWhite)
        ]
        // The panel is always a dark material, so resolve each preset for the
        // dark appearance and store that exact value.
        for preset in BatteryStatusColorPreset.allCases {
            let cgColor = BatteryStatusColorResolver.presetColor(preset, darkAppearance: true)
            let color = Color(cgColor: cgColor)
            result.append(Preset(
                id: "preset-\(preset.rawValue)",
                rgba: IconAppearanceColorConversion.iconRGBA(from: color),
                label: presetKey(preset)
            ))
        }
        return result
    }

    private var currentColor: IconRGBA { store.panelLevelSliderFillColor }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(presets) { preset in
                Button {
                    store.panelLevelSliderFillColor = preset.rgba
                } label: {
                    swatch(
                        fill: IconAppearanceColorConversion.color(from: preset.rgba),
                        isSelected: nearlyEqual(currentColor, preset.rgba)
                    )
                }
                .buttonStyle(.plain)
                .help(localization.string(preset.label))
                .accessibilityLabel(localization.string(preset.label))
                .accessibilityAddTraits(
                    nearlyEqual(currentColor, preset.rgba) ? [.isSelected] : []
                )
            }

            ColorPicker(
                localization.string(.settingsBatteryColorsCustom),
                selection: Binding(
                    get: { IconAppearanceColorConversion.color(from: currentColor) },
                    set: {
                        store.panelLevelSliderFillColor =
                            IconAppearanceColorConversion.iconRGBA(from: $0)
                    }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(localization.string(.settingsBatteryColorsCustom))

            Button {
                store.panelLevelSliderFillColor = .white
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(localization.string(.settingsBatteryColorsReset))
            .accessibilityLabel(localization.string(.settingsBatteryColorsReset))
            .disabled(nearlyEqual(currentColor, .white))
        }
    }

    private func swatch(fill: Color, isSelected: Bool) -> some View {
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

    private func nearlyEqual(_ lhs: IconRGBA, _ rhs: IconRGBA) -> Bool {
        abs(lhs.red - rhs.red) < 0.005
            && abs(lhs.green - rhs.green) < 0.005
            && abs(lhs.blue - rhs.blue) < 0.005
            && abs(lhs.alpha - rhs.alpha) < 0.005
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
