import SwiftUI

/// The "Bottom Indicator" leaf under **App Icon**: the visual style of the
/// volume indicator drawn at the bottom of the status icon, plus the Bluetooth
/// audio colour rule that affects that same area.
///
/// Only appearance lives here. Volume scrolling, feedback and device selection
/// stay in the Audio category.
struct AppIconBottomIndicatorView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @Binding var previewIsDark: Bool
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsGroup(localization.string(.settingsAudioIndicatorStyleTitle)) {
            SettingsPictureRow(
                "waveform",
                tint: .indigo,
                title: localization.string(.settingsAudioIndicatorStyle),
                subtitle: localization.string(.settingsAudioIndicatorStyleDescription),
                selection: $store.volumeDisplayStyle,
                options: [VolumeDisplayStyle.dots, .arc],
                previewSize: CGSize(width: 68, height: 44),
                caption: { style in
                    switch style {
                    case .dots: return localization.string(.settingsAudioIndicatorStyleDots)
                    case .arc: return localization.string(.settingsAudioIndicatorStyleArc)
                    }
                },
                preview: { style in
                    VolumeIndicatorPreview(
                        style: style,
                        isDarkBackground: previewIsDark,
                        store: store,
                        statusStore: statusStore
                    )
                }
            )

            SettingsDivider()

            SettingsToggleRow(
                symbol: "speaker.wave.2.fill",
                tint: .cyan,
                title: localization.string(.settingsBluetoothVolumeColor),
                subtitle: localization.string(.settingsBluetoothVolumeColorDescription),
                isOn: $store.usesBluetoothAudioVolumeColor
            )
        }
    }
}
