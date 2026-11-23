import SwiftUI

/// The listening-mode control toggle plus the developer-only preview options.
/// Shared so AirPods/headphone controls live together on the Audio page instead
/// of being split across Bluetooth and Audio.
struct AirPodsListeningModeSettingsRows: View {
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization
    /// Low-frequency preview tuning stays collapsed so the group is quiet.
    @State private var showsPreviewOptions = false

    var body: some View {
        SettingsToggleRow(
            symbol: "earbuds",
            tint: .purple,
            title: localization.string(.settingsBluetoothListeningModeTitle),
            subtitle: localization.string(.settingsBluetoothListeningModeDescription),
            isOn: $store.showsBluetoothListeningMode
        )

        // Preview injection is developer-only, so a packaged release never
        // offers the synthetic rows.
        if AppMetadata.isDevelopmentBuild && store.showsBluetoothListeningMode {
            SettingsDivider()

            SettingsToggleRow(
                symbol: "eyeglasses",
                tint: .purple,
                title: localization.string(.settingsBluetoothListeningModePreview),
                subtitle: localization.string(.settingsBluetoothListeningModePreviewDescription),
                isOn: $store.previewsBluetoothListeningMode
            )
        }

        if AppMetadata.isDevelopmentBuild
            && store.showsBluetoothListeningMode
            && store.previewsBluetoothListeningMode {
            SettingsDivider()

            DisclosureGroup(isExpanded: $showsPreviewOptions) {
                SettingsRow(
                    "character.cursor.ibeam",
                    tint: .purple,
                    title: localization.string(.settingsBluetoothListeningModePreviewDeviceName),
                    subtitle: localization.string(.settingsBluetoothListeningModePreviewDeviceNameDescription)
                ) {
                    TextField(
                        localization.string(.settingsBluetoothListeningModePreviewDeviceName),
                        text: $store.bluetoothListeningModePreviewDeviceName
                    )
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 150)
                    .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(
                    "number.square",
                    tint: .purple,
                    title: localization.string(.settingsBluetoothListeningModePreviewDeviceCount),
                    subtitle: localization.string(.settingsBluetoothListeningModePreviewDeviceCountDescription)
                ) {
                    HStack(spacing: 10) {
                        Text("\(store.bluetoothListeningModePreviewDeviceCount)")
                            .font(.system(size: 13, design: .monospaced))
                            .frame(minWidth: 22, alignment: .trailing)

                        Stepper(
                            localization.string(.settingsBluetoothListeningModePreviewDeviceCount),
                            value: $store.bluetoothListeningModePreviewDeviceCount,
                            in: SettingsStore.bluetoothListeningModePreviewDeviceCountRange
                        )
                        .labelsHidden()
                    }
                }

                SettingsDivider()

                SettingsRow(
                    SymbolFallback.name("translate", "character.bubble", "globe"),
                    tint: .purple,
                    title: localization.string(.settingsBluetoothListeningModePreviewLanguage),
                    subtitle: localization.string(.settingsBluetoothListeningModePreviewLanguageDescription)
                ) {
                    Picker(
                        localization.string(.settingsBluetoothListeningModePreviewLanguage),
                        selection: $store.bluetoothListeningModePreviewLanguage
                    ) {
                        Text(localization.string(.settingsLanguageFollowSystem))
                            .tag("")

                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.nativeName)
                                .tag(lang.rawValue)
                        }
                    }
                    .labelsHidden()
                    .settingsMenuPickerWidth()
                }
            } label: {
                Text(localization.string(.settingsBluetoothListeningModePreviewOptions))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.leading, SettingsMetrics.rowPaddingH)
            }
        }
    }
}
