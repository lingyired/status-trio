import AppKit
import SwiftUI

/// Colour control for the Bluetooth audio volume indicator, replacing the old
/// "use blue" switch: an automatic choice (follows the primary colour), our blue
/// preset second, then the shared preset palette plus a system picker and reset.
struct BluetoothVolumeColorRow: View {
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization

    private struct Preset: Identifiable {
        let id: String
        let selection: BluetoothVolumeColorSelection
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
            )
        ]
        // Our blue sits second (after automatic), per the volume-colour spec.
        let ordered: [BatteryStatusColorPreset] = [.sky, .mint, .lavender, .amber, .rose, .slate]
        for palettePreset in ordered {
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

    private var currentSelection: BluetoothVolumeColorSelection {
        store.bluetoothVolumeColor
    }

    private var currentFill: Color {
        switch currentSelection {
        case .automatic: return .primary
        case let .custom(color): return IconAppearanceColorConversion.color(from: color)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(presets) { preset in
                Button {
                    store.bluetoothVolumeColor = preset.selection
                } label: {
                    swatch(fill: preset.fill, isSelected: currentSelection == preset.selection)
                }
                .buttonStyle(.plain)
                .help(localization.string(preset.label))
                .accessibilityLabel(localization.string(preset.label))
                .accessibilityAddTraits(currentSelection == preset.selection ? [.isSelected] : [])
            }

            ColorPicker(
                localization.string(.settingsBatteryColorsCustom),
                selection: Binding(
                    get: { currentFill },
                    set: { store.bluetoothVolumeColor = .custom(IconAppearanceColorConversion.iconRGBA(from: $0)) }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(localization.string(.settingsBatteryColorsCustom))

            Button {
                store.bluetoothVolumeColor = .automatic
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
