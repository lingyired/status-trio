import AppKit
import SwiftUI

/// The "Bottom Indicator" leaf under **App Icon**.
///
/// The data source (volume / Wi-Fi / battery / hidden) and the drawing style
/// (four dots or a bottom arc) are two independent axes: the source decides
/// *what* the indicator reports, the style decides *how* it is drawn. The
/// Bluetooth audio colour rule only applies to the volume source, so it is
/// shown only when that source is selected.
///
/// Only appearance lives here. Volume scrolling, feedback and device selection
/// stay in the Audio category.
struct AppIconBottomIndicatorView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @Binding var previewIsDark: Bool
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsGroup(localization.string(.settingsBottomIndicatorTitle)) {
            sourcePicker

            if store.bottomIndicatorSource.showsStyleOptions {
                // Follows the full-width picker (no leading icon column), so the
                // divider aligns with the picker content edge.
                SettingsDivider(inset: SettingsMetrics.rowPaddingH)
                stylePicker
            }

            if store.bottomIndicatorSource == .volume {
                SettingsDivider()
                SettingsToggleRow(
                    symbol: "speaker.wave.2.fill",
                    tint: .cyan,
                    title: localization.string(.settingsBluetoothVolumeColor),
                    subtitle: localization.string(.settingsBluetoothVolumeColorDescription),
                    isOn: $store.usesBluetoothAudioVolumeColor
                )
            }

            if store.bottomIndicatorSource == .battery {
                batteryColorOptions
            }
        }
    }

    /// The battery status-colour controls that the bottom battery shares with
    /// the top ring. They are the same stored fields, surfaced here so the
    /// source can be tuned without jumping to the ring page.
    @ViewBuilder
    private var batteryColorOptions: some View {
        SettingsDivider()
        SettingsToggleRow(
            symbol: "circle.lefthalf.filled",
            tint: .gray,
            title: localization.string(.settingsBatteryMonochromeCharging),
            subtitle: localization.string(.settingsBatteryMonochromeChargingDescription),
            isOn: Binding(
                get: { store.monochromeChargingRing ?? !effectiveHasBattery },
                set: { store.monochromeChargingRing = $0 }
            )
        )

        SettingsDivider()
        SettingsToggleRow(
            symbol: "paintpalette.fill",
            tint: .orange,
            title: localization.string(.settingsBatteryStatusColors),
            subtitle: localization.string(.settingsBatteryStatusColorsDescription),
            isOn: $store.usesBatteryStatusColors
        )

        BatteryStatusColorsView(store: store)

        if store.usesBatteryStatusColors {
            SettingsDivider()
            SettingsRow(
                "exclamationmark.triangle.fill",
                tint: .red,
                title: localization.string(.settingsBatteryCriticalThreshold),
                subtitle: localization.string(.settingsBatteryCriticalThresholdDescription)
            ) {
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { store.batteryCriticalThreshold },
                            set: { store.batteryCriticalThreshold = $0.rounded() }
                        ),
                        in: SettingsStore.batteryCriticalThresholdRange
                    )
                    .frame(width: 130)
                    .controlSize(.small)
                    .accessibilityLabel(localization.string(.settingsBatteryCriticalThreshold))
                    .accessibilityValue("\(Int(store.batteryCriticalThreshold))%")

                    Text("\(Int(store.batteryCriticalThreshold))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }

    private var effectiveHasBattery: Bool {
        statusStore.snapshot.battery.isPresent && !store.isNoBatterySimulationActive
    }

    /// Graphic cards, matching the middle-icon source chooser. Each card uses a
    /// fixed sample status so no card spins up its own monitor subscription.
    private var sourcePicker: some View {
        SettingsVisualChoicePicker(
            descriptionText: localization.string(.settingsBottomIndicatorDescription),
            choicesAccessibilityLabel: localization.string(.settingsBottomIndicatorSource),
            accessibilityIdentifier: "appIcon.bottomIndicatorSource",
            selection: $store.bottomIndicatorSource,
            options: BottomIndicatorSource.allCases,
            caption: { source in
                switch source {
                case .volume: return localization.string(.settingsBottomIndicatorSourceVolume)
                case .wifi: return localization.string(.settingsBottomIndicatorSourceWiFi)
                case .battery: return localization.string(.settingsBottomIndicatorSourceBattery)
                case .hidden: return localization.string(.settingsBottomIndicatorSourceHidden)
                }
            },
            preview: { source in
                BottomIndicatorSourcePreview(
                    source: source,
                    style: store.volumeDisplayStyle,
                    strokeScale: store.ringStrokeStyle.scale,
                    isDarkBackground: previewIsDark
                )
            }
        )
    }

    /// The shared four-dot / arc appearance chooser, kept from the old volume
    /// indicator so switching the source does not move or restyle this control.
    private var stylePicker: some View {
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
                    source: store.bottomIndicatorSource,
                    isDarkBackground: previewIsDark,
                    store: store,
                    statusStore: statusStore
                )
            }
        )
    }
}

// MARK: - Source card preview

/// A real miniature for one data-source card, drawn from the live mapper with
/// a fixed sample so every card shows exactly what the footer will look like.
private struct BottomIndicatorSourcePreview: View {
    let source: BottomIndicatorSource
    let style: VolumeDisplayStyle
    let strokeScale: Double
    let isDarkBackground: Bool

    var body: some View {
        ZStack {
            MenuBarPreviewBackdrop(isDarkBackground: isDarkBackground, cornerRadius: 6)
            if let image = BottomIndicatorPreviewScene.image(
                for: source,
                style: style,
                strokeScale: strokeScale,
                isDarkBackground: isDarkBackground
            ) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(3)
            }
        }
        .accessibilityHidden(true)
    }
}

@MainActor
private enum BottomIndicatorPreviewScene {
    /// Fixed sample: a battery present at 76 %, Wi-Fi at a strong -56 dBm, and a
    /// mid volume scalar, so each card can demonstrate any source from the same
    /// stable status regardless of the live machine.
    private static let snapshot = StatusSnapshot(
        battery: BatteryStatus(
            rawPercentage: 76,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        ),
        wifi: WiFiStatus(state: .connected, rssi: -56),
        connection: .wifi,
        volume: VolumeStatus(
            scalar: 0.6,
            isMuted: false,
            deviceName: "MacBook Speakers"
        )
    )

    static func image(
        for source: BottomIndicatorSource,
        style: VolumeDisplayStyle,
        strokeScale: Double,
        isDarkBackground: Bool
    ) -> NSImage? {
        let configuration = IconPresentationConfiguration(
            battery: .standard,
            connection: .standard,
            volume: VolumeIconOptions(displayStyle: style, ringStrokeScale: strokeScale),
            bluetooth: .standard
        )
        let inputs = IconPresentationInputs(
            snapshot: snapshot,
            audioIcon: nil,
            bottomIndicatorSource: source
        )
        let scene = IconPresentationMapper.scene(inputs: inputs, configuration: configuration)
        return StatusIconPreviewCache.shared.image(
            scene: scene,
            size: 28,
            scale: 2,
            appearance: MenuBarPreviewBackdrop.appearance(isDarkBackground: isDarkBackground)
        )
    }
}
