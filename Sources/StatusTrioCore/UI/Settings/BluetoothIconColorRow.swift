import AppKit
import SwiftUI

/// The middle Bluetooth glyph colour control (#275): default blue, adaptive
/// primary, or a custom colour. It edits only the icon colour; the volume
/// footer's own blue switch stays separate.
struct BluetoothIconColorRow: View {
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsRow(
            "paintpalette.fill",
            tint: .blue,
            title: localization.string(.settingsBluetoothIconColor),
            subtitle: localization.string(.settingsBluetoothIconColorDescription)
        ) {
            HStack(spacing: 8) {
                selectionSwatch(
                    .systemBlue,
                    fill: Color(cgColor: BluetoothIconColorResolver.resolve(
                        .systemBlue,
                        foreground: labelInk,
                        darkAppearance: colorScheme == .dark
                    )),
                    label: localization.string(.settingsBluetoothIconColorBlue)
                )
                selectionSwatch(
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

    private func selectionSwatch(
        _ selection: BluetoothIconColorSelection,
        fill: Color,
        label: String
    ) -> some View {
        let isSelected = store.bluetoothIconColor == selection
        return Button {
            store.bluetoothIconColor = selection
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
                let components = store.bluetoothIconColor.customComponents
                    ?? BatteryStatusColorResolver.customComponents(
                        from: NSColor(cgColor: BluetoothIconColorResolver.resolve(
                            .systemBlue,
                            foreground: labelInk,
                            darkAppearance: colorScheme == .dark
                        )) ?? .systemBlue
                    )
                return Color(nsColor: BatteryStatusColorResolver.nsColor(from: components))
            },
            set: {
                store.bluetoothIconColor = .custom(
                    BatteryStatusColorResolver.customComponents(from: NSColor($0))
                )
            }
        )
    }
}
