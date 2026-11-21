import AppKit
import SwiftUI

/// Preset swatches, a custom picker and a reset for the status panel's level
/// slider colour (#359). Mirrors the battery status colour row: an automatic
/// choice first, then recommended colours, the system picker, and a reset.
///
/// `.automatic` follows the label colour, so the default fill is white on the
/// dark panel and black on a light one instead of a pinned white.
struct PanelLevelSliderColorRow: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var localization: Localization

    private struct Preset: Identifiable {
        let id: String
        let selection: PanelLevelSliderColorSelection
        let fill: Color
        let label: LocalizationKey
    }

    private var presets: [Preset] {
        var result: [Preset] = [
            Preset(
                id: "automatic",
                selection: .automatic,
                fill: .primary,
                label: .settingsPanelLevelSliderColorAutomatic
            ),
            Preset(
                id: "white",
                selection: .custom(.white),
                fill: IconAppearanceColorConversion.color(from: .white),
                label: .settingsPanelLevelSliderColorWhite
            )
        ]
        // The panel is always a dark material, so resolve each preset for the
        // dark appearance and store that exact value.
        for palettePreset in BatteryStatusColorPreset.allCases {
            let cgColor = BatteryStatusColorResolver.presetColor(palettePreset, darkAppearance: true)
            let color = Color(cgColor: cgColor)
            let rgba = IconAppearanceColorConversion.iconRGBA(from: color)
            result.append(Preset(
                id: "preset-\(palettePreset.rawValue)",
                selection: .custom(rgba),
                fill: color,
                label: presetKey(palettePreset)
            ))
        }
        return result
    }

    private var currentSelection: PanelLevelSliderColorSelection {
        store.panelLevelSliderColor
    }

    private var currentFill: Color {
        switch currentSelection {
        case .automatic:
            return .primary
        case let .custom(color):
            return IconAppearanceColorConversion.color(from: color)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(presets) { preset in
                Button {
                    store.panelLevelSliderColor = preset.selection
                } label: {
                    swatch(fill: preset.fill, isSelected: currentSelection == preset.selection)
                }
                .buttonStyle(.plain)
                .help(localization.string(preset.label))
                .accessibilityLabel(localization.string(preset.label))
                .accessibilityAddTraits(
                    currentSelection == preset.selection ? [.isSelected] : []
                )
            }

            ColorPicker(
                localization.string(.settingsBatteryColorsCustom),
                selection: Binding(
                    get: { currentFill },
                    set: {
                        store.panelLevelSliderColor = .custom(
                            IconAppearanceColorConversion.iconRGBA(from: $0)
                        )
                    }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(localization.string(.settingsBatteryColorsCustom))

            Button {
                store.panelLevelSliderColor = .automatic
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(localization.string(.settingsBatteryColorsReset))
            .accessibilityLabel(localization.string(.settingsBatteryColorsReset))
            .disabled(currentSelection == .automatic)
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
