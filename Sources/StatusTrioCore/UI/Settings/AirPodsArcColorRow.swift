import AppKit
import SwiftUI

/// One AirPods ring arc colour control: historical blue, adaptive primary, or a
/// custom colour. Mirrors `BluetoothIconColorRow` but edits a caller-owned
/// selection so the left-ear, right-ear and single-arc colours stay separate.
struct AirPodsArcColorRow: View {
    @EnvironmentObject private var localization: Localization
    @Environment(\.colorScheme) private var colorScheme

    let titleKey: LocalizationKey
    let subtitleKey: LocalizationKey
    @Binding var selection: BluetoothIconColorSelection

    var body: some View {
        SettingsRow(
            "paintpalette.fill",
            tint: .blue,
            title: localization.string(titleKey),
            subtitle: localization.string(subtitleKey)
        ) {
            HStack(spacing: 8) {
                swatch(
                    .systemBlue,
                    fill: Color(cgColor: BluetoothIconColorResolver.resolve(
                        .systemBlue,
                        foreground: labelInk,
                        darkAppearance: colorScheme == .dark
                    )),
                    label: localization.string(.settingsBluetoothIconColorBlue)
                )
                swatch(
                    .primary,
                    fill: Color.primary,
                    label: localization.string(.settingsBluetoothIconColorPrimary)
                )
                ColorPicker(
                    localization.string(.settingsBluetoothIconColorCustom),
                    selection: customColorBinding,
                    supportsOpacity: false
                )
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(localization.string(.settingsBluetoothIconColorCustom))
            }
        }
    }

    private var labelInk: CGColor {
        CGColor(gray: colorScheme == .dark ? 1 : 0, alpha: 1)
    }

    private func swatch(
        _ candidate: BluetoothIconColorSelection,
        fill: Color,
        label: String
    ) -> some View {
        let isSelected = selection == candidate
        return Button {
            selection = candidate
        } label: {
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
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: {
                // Show the colour that is actually in effect: the picked custom
                // value, the adaptive primary ink, or the Bluetooth blue. Falling
                // back to blue here made a `.primary` default look blue in the
                // picker even though the arc drew white.
                let resolved = BluetoothIconColorResolver.resolve(
                    selection,
                    foreground: labelInk,
                    darkAppearance: colorScheme == .dark
                )
                return Color(cgColor: resolved)
            },
            set: {
                selection = .custom(
                    BatteryStatusColorResolver.customComponents(from: NSColor($0))
                )
            }
        )
    }
}
