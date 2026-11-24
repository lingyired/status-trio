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

            if store.bottomIndicatorSource == .metric {
                // Style sits at the top of the metric section, then the metric
                // picker, then the colour options mirrored from the top arc.
                SettingsDivider()
                stylePicker
                SettingsDivider()
                metricPicker
                if let metric = store.bottomIndicatorMetric.hardwareMetric {
                    metricColorRows(for: metric)
                    SettingsDivider()
                    HardwareMetricAdvancedRow(store: store, metric: metric)
                } else {
                    SettingsDivider()
                    memoryPressureLegend
                }
            }

            LocalIconPluginSlotPicker(slot: .footer, store: store)

            if store.bottomIndicatorSource != .metric,
               store.bottomIndicatorSource.showsStyleOptions {
                // Follows the full-width picker (no leading icon column), so the
                // divider aligns with the picker content edge.
                SettingsDivider(inset: SettingsMetrics.rowPaddingH)
                stylePicker
            }

            if store.bottomIndicatorSource == .volume {
                SettingsDivider()
                SettingsRow(
                    "speaker.wave.2.fill",
                    tint: .blue,
                    title: localization.string(.settingsBluetoothVolumeColor),
                    subtitle: localization.string(.settingsBluetoothVolumeColorDescription)
                ) {
                    BluetoothVolumeColorRow(store: store)
                }
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
                case .metric: return localization.string(.settingsBottomIndicatorSourceMetric)
                case .hidden: return localization.string(.settingsBottomIndicatorSourceHidden)
                }
            },
            preview: { source in
                BottomIndicatorSourcePreview(
                    source: source,
                    metric: store.bottomIndicatorMetric,
                    baseColor: store.bottomIndicatorMetric.hardwareMetric.map { store.hardwareColor(for: $0) },
                    bluetoothOptions: store.bluetoothVolumePreviewOptions,
                    style: store.bottomIndicatorStyle(for: source),
                    strokeScale: store.ringStrokeStyle.scale,
                    isDarkBackground: previewIsDark
                )
            }
        )
    }

    private var metricPicker: some View {
        SettingsGroupedMenuRow(
            symbol: store.bottomIndicatorMetric.systemImage,
            tint: .gray,
            title: localization.string(.settingsBottomIndicatorMetric),
            subtitle: localization.string(.settingsBottomIndicatorMetricDescription),
            selection: $store.bottomIndicatorMetric,
            groups: footerMetricGroups,
            label: { localization.string($0.titleKey) }
        )
    }

    /// The CPU and GPU groups follow the ring's temperature monitoring setting.
    private var footerMetricGroups: [(title: String, options: [BottomIndicatorMetric])] {
        let cpu: [BottomIndicatorMetric] =
            store.hardwareTemperatureMonitoringEnabled ? [.cpuUsage, .cpuTemperature] : [.cpuUsage]
        let gpu: [BottomIndicatorMetric] =
            store.hardwareTemperatureMonitoringEnabled ? [.gpuUsage, .gpuTemperature] : [.gpuUsage]
        return [
            ("CPU", cpu),
            ("GPU", gpu),
            (localization.string(.hardwareDetailTitleMemory), [.memoryUsage, .memoryPressure]),
            (localization.string(.settingsHardwareRingGroupOther),
             [.batteryTemperature, .fan, .downloadSpeed, .uploadSpeed]),
        ]
    }

    /// Colour options for the metric bottom source, mirroring the top arc's
    /// colour group. They edit the shared hardware-monitor colour settings, so a
    /// change takes effect on the top arc, the bottom indicator and the system
    /// monitoring panel alike.
    @ViewBuilder
    private func metricColorRows(for metric: HardwareMonitorMetric) -> some View {
        SettingsDivider()
        SettingsToggleRow(
            symbol: "circle.lefthalf.filled",
            tint: .purple,
            title: localization.string(.settingsHardwareRingMonochrome),
            subtitle: localization.string(.settingsHardwareRingMonochromeDescription),
            isOn: Binding(
                get: { store.hardwareRingConfiguration.color.monochrome },
                set: { setColorMonochrome($0) }
            )
        )
        SettingsDivider()
        SettingsToggleRow(
            symbol: "exclamationmark.triangle",
            tint: .orange,
            title: localization.string(.settingsHardwareRingThresholdColors),
            subtitle: localization.string(.settingsHardwareRingThresholdColorsDescription),
            isOn: Binding(
                get: { store.hardwareRingConfiguration.color.thresholdColors },
                set: { setColorThresholdColors($0) }
            )
        )
        .disabled(store.hardwareRingConfiguration.color.monochrome)
        if !store.hardwareRingConfiguration.color.monochrome {
            SettingsDivider()
            SettingsRow(
                title: localization.string(metric.titleKey),
                subtitle: nil,
                leading: {
                    SettingsIcon(symbol: metric.systemImage, tint: .purple)
                },
                trailing: {
                    IconDesignerColorWell(
                        selection: Binding(
                            get: {
                                IconAppearanceColorConversion.color(
                                    from: store.hardwareColor(for: metric))
                            },
                            set: {
                                store.setHardwareColor(
                                    IconAppearanceColorConversion.iconRGBA(from: $0),
                                    for: metric)
                            }
                        ),
                        onEditingChanged: { _ in }
                    )
                    .frame(width: 44, height: 22)
                }
            )
        }
    }

    private var memoryPressureLegend: some View {
        SettingsRow(
            title: localization.string(.hardwareDetailPressure),
            leading: { SettingsIcon(symbol: "memorychip", tint: .purple) },
            trailing: {
                HStack(spacing: 12) {
                    pressureLabel(.normal, title: .hardwareDetailPressureNormal)
                    pressureLabel(.warning, title: .hardwareDetailPressureWarning)
                    pressureLabel(.critical, title: .hardwareDetailPressureCritical)
                }
                .font(.system(size: 11))
            }
        )
    }

    private func pressureLabel(_ level: MemoryPressureLevel, title: LocalizationKey) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(MemoryPressureFooterMapper.color(for: level)
                    .map { IconAppearanceColorConversion.color(from: $0) } ?? Color.secondary)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(localization.string(title))
                .foregroundStyle(.secondary)
        }
    }

    private func setColorMonochrome(_ on: Bool) {
        var configuration = store.hardwareRingConfiguration
        configuration.color.monochrome = on
        store.hardwareRingConfiguration = configuration
    }

    private func setColorThresholdColors(_ on: Bool) {
        var configuration = store.hardwareRingConfiguration
        configuration.color.thresholdColors = on
        store.hardwareRingConfiguration = configuration
    }
    /// The shared four-dot / arc appearance chooser, kept from the old volume
    /// indicator so switching the source does not move or restyle this control.
    private var stylePicker: some View {
        SettingsPictureRow(
            "waveform",
            tint: .indigo,
            title: localization.string(.settingsAudioIndicatorStyle),
            subtitle: localization.string(.settingsAudioIndicatorStyleDescription),
            selection: Binding(
                get: { store.effectiveBottomIndicatorStyle },
                set: { newValue in
                    switch store.bottomIndicatorSource {
                    case .volume, .hidden: store.volumeDisplayStyle = newValue
                    case .wifi: store.wifiBottomIndicatorStyle = newValue
                    case .battery: store.batteryBottomIndicatorStyle = newValue
                    case .metric: store.metricBottomIndicatorStyle = newValue
                    }
                }
            ),
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
                    sourceMetric: store.bottomIndicatorMetric,
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
    let metric: BottomIndicatorMetric
    let baseColor: IconRGBA?
    let bluetoothOptions: BluetoothAudioIconOptions
    let style: VolumeDisplayStyle
    let strokeScale: Double
    let isDarkBackground: Bool

    var body: some View {
        ZStack {
            MenuBarPreviewBackdrop(isDarkBackground: isDarkBackground, cornerRadius: 6)
            if let image = BottomIndicatorPreviewScene.image(
                for: source,
                metric: metric,
                baseColor: baseColor,
                bluetoothOptions: bluetoothOptions,
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
            deviceName: "AirPods",
            currentDevice: AudioOutputDevice(
                id: 0,
                name: "AirPods",
                uid: "bottom-indicator.preview.bluetooth",
                isCurrent: true,
                volume: 0.6,
                transport: .bluetooth
            )
        )
    )

    static func image(
        for source: BottomIndicatorSource,
        metric: BottomIndicatorMetric,
        baseColor: IconRGBA?,
        bluetoothOptions: BluetoothAudioIconOptions,
        style: VolumeDisplayStyle,
        strokeScale: Double,
        isDarkBackground: Bool
    ) -> NSImage? {
        if source == .metric {
            let scene = BottomIndicatorMetricPreview.scene(
                metric: metric, style: style, strokeScale: strokeScale,
                baseColor: baseColor)
            return StatusIconPreviewCache.shared.image(
                scene: scene,
                size: 28,
                scale: 2,
                appearance: MenuBarPreviewBackdrop.appearance(isDarkBackground: isDarkBackground)
            )
        }
        let configuration = IconPresentationConfiguration(
            battery: .standard,
            connection: .standard,
            volume: VolumeIconOptions(displayStyle: style, ringStrokeScale: strokeScale),
            bluetooth: bluetoothOptions
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
