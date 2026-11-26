import SwiftUI

/// The three memory-pressure colour wells (#398), shared by the hardware-ring
/// colour group and the bottom-indicator pressure section. Both places edit the
/// same stored colours so the top marker and the footer can never disagree.
struct MemoryPressureColorRows: View {
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        row(level: .normal,
            title: .hardwareDetailPressureNormal,
            symbol: "circle.fill",
            tint: .green,
            keyPath: \.memoryPressureNormalColor)
        SettingsDivider()
        row(level: .warning,
            title: .hardwareDetailPressureWarning,
            symbol: "exclamationmark.triangle.fill",
            tint: .orange,
            keyPath: \.memoryPressureWarningColor)
        SettingsDivider()
        row(level: .critical,
            title: .hardwareDetailPressureCritical,
            symbol: "exclamationmark.octagon.fill",
            tint: .red,
            keyPath: \.memoryPressureCriticalColor)
    }

    private func row(
        level: MemoryPressureLevel,
        title: LocalizationKey,
        symbol: String,
        tint: Color,
        keyPath: WritableKeyPath<HardwareRingColorConfiguration, IconRGBA>
    ) -> some View {
        SettingsRow(
            title: localization.string(title),
            leading: { SettingsIcon(symbol: symbol, tint: tint) },
            trailing: {
                IconDesignerColorWell(
                    selection: binding(keyPath),
                    onEditingChanged: { _ in }
                )
                .frame(width: 44, height: 22)
            }
        )
        .accessibilityIdentifier("memoryPressureColor.\(level.rawValue)")
    }

    private func binding(
        _ keyPath: WritableKeyPath<HardwareRingColorConfiguration, IconRGBA>
    ) -> Binding<Color> {
        Binding(
            get: {
                IconAppearanceColorConversion.color(
                    from: store.hardwareRingConfiguration.color[keyPath: keyPath])
            },
            set: { color in
                var configuration = store.hardwareRingConfiguration
                configuration.color[keyPath: keyPath] =
                    IconAppearanceColorConversion.iconRGBA(from: color)
                store.hardwareRingConfiguration = configuration
            }
        )
    }
}
