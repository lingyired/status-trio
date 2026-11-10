import Foundation

/// Converts the pre-v1 icon options into the versioned slot configuration.
enum IconConfigurationMigration {
    /// Explicit, persisted pre-V1 centre preferences. A `nil` field means the
    /// key was never written, so the shipped default must NOT be treated as a
    /// user choice (that would silently switch a clean install on).
    struct LegacyCenterPreferences: Equatable, Sendable {
        var connectionCenterSource: ConnectionCenterSource?
        var prioritizesNetworkErrorsOverInputSource: Bool?
        var prioritizesNetworkErrorsOverBluetoothAudio: Bool?

        @MainActor
        static func read(from defaults: UserDefaults) -> Self {
            Self(
                connectionCenterSource: defaults
                    .string(forKey: SettingsStore.connectionCenterSourceDefaultsKey)
                    .flatMap(ConnectionCenterSource.init(rawValue:)),
                prioritizesNetworkErrorsOverInputSource: defaults
                    .object(forKey: SettingsStore.prioritizesNetworkErrorsOverInputSourceDefaultsKey) as? Bool,
                prioritizesNetworkErrorsOverBluetoothAudio: defaults
                    .object(forKey: SettingsStore.prioritizesNetworkErrorsOverBluetoothAudioDefaultsKey) as? Bool
            )
        }

        /// The legacy centre slot actually drew the input source.
        var choosesInputSource: Bool { connectionCenterSource == .inputSource }
    }

    /// One-time compatibility fold, run only at the storage read boundary.
    ///
    /// - With a stored V1 payload the V1 centre and the V1 global policy are
    ///   authoritative: only `.network`/`.automaticLegacy` fold to
    ///   `.inputSource`, and an existing `centerOverride` (even `false`) is
    ///   never re-enabled by a legacy default.
    /// - Without a stored V1 payload the explicit legacy flags seed the global
    ///   policy once; missing keys keep the shipped default (off).
    static func applyingCenterCompatibility(
        _ preferences: LegacyCenterPreferences,
        to configuration: IconConfigurationV1,
        hadStoredV1: Bool
    ) -> IconConfigurationV1 {
        guard (configuration.centerSourceMigrationVersion ?? 0) < 1 else { return configuration }
        var copy = configuration
        if preferences.choosesInputSource {
            switch copy.composition.center.primary {
            case .network, .automaticLegacy:
                copy.composition.center.primary = .inputSource
            case .inputSource, .bluetoothAudioOutput, .pinnedBluetoothGlyph,
                 .connectedBluetoothDevice, .systemBatteryPercentage,
                 .chargingStatus, .power, .none:
                break
            }
        }
        if !hadStoredV1 {
            copy.composition.centerOverride.networkProblemOverridesPrimary =
                preferences.prioritizesNetworkErrorsOverInputSource == true
                    || preferences.prioritizesNetworkErrorsOverBluetoothAudio == true
        }
        copy.centerSourceMigrationVersion = 1
        return copy.normalized()
    }

    static func makeConfiguration(from legacy: IconPresentationConfiguration) -> IconConfigurationV1 {
        var value = IconConfigurationV1.classic
        // Legacy icon settings had no AirPods source or ring mode. The new
        // designer default is dual; existing encoded V1 payloads still decode
        // a missing airPodsRing field as single in IconBehaviorConfiguration.
        value.behaviors.airPodsRing = .dual
        value.behaviors.systemBatteryRing = SystemBatteryRingBehavior(
            showsPercentage: legacy.battery.showsPercentage,
            showsChargingIndicator: legacy.battery.showsChargingIndicator,
            showsChargingEffect: legacy.battery.showsChargingEffect,
            showsChargingBoltHeartbeat: legacy.battery.showsChargingBoltHeartbeat,
            usesStatusColors: legacy.battery.usesStatusColors,
            showsPercentageWhenConnected: legacy.battery.showsPercentageWhenConnected,
            criticalThreshold: legacy.battery.criticalThreshold,
            textScale: legacy.battery.textScale,
            fullThreshold: legacy.battery.fullThreshold,
            connectedIndicator: legacy.battery.connectedIndicator,
            monochromeCharging: legacy.battery.monochromeCharging
        )
        value.appearance.batteryStatusColors = BatteryStatusColorsConfiguration(legacy.battery.batteryStatusColors)
        value.appearance.bluetoothIconColor = BluetoothIconColorConfiguration(legacy.bluetooth.iconColor)
        value.behaviors.splitGapProgress = legacy.battery.splitGapProgress
        // Keep the legacy Wi-Fi multiplier: normalization resets
        // networkCenter.wifiScale, so store it on the centre appearance whose
        // symbolScale is the shared centre size.
        value.appearance.center.symbolScale =
            CenterAppearance.classic.symbolScale * legacy.connection.wifiScale
        value.appearance.outerRing.strokeScale = legacy.battery.ringStrokeScale
        value.appearance.footer.strokeScale = legacy.volume.ringStrokeScale
        value.wifiScaleMigrationVersion = nil
        value.centerSourceMigrationVersion = nil
        // Legacy's "battery in the connection slot" flag is a source preference
        // inside the legacy mapper, not an explicit V1 centre choice; keep the
        // automatic slot and let the projection carry the flag back.
        value.composition.center = SlotSelection(primary: .automaticLegacy)
        value.behaviors.networkCenter = NetworkCenterBehavior(
            showsWiFiIconForEthernet: legacy.connection.showsWiFiIconForEthernet,
            showsWiFiIconForHotspot: legacy.connection.showsWiFiIconForHotspot,
            showsWiFiIconForTemporaryConnection: legacy.connection.showsWiFiIconForTemporaryConnection,
            showsWiFiIconForInternetSharing: legacy.connection.showsWiFiIconForInternetSharing,
            showsBatteryPercentageInConnectionSlot: legacy.connection.showsBatteryPercentageInConnectionSlot,
            wifiScale: legacy.connection.wifiScale
        )
        value.behaviors.bluetoothAudioCenter = BluetoothAudioCenterBehavior(
            replacesNetworkIcon: legacy.bluetooth.replacesNetworkIcon,
            usesVolumeColor: legacy.bluetooth.usesVolumeColor,
            prioritizesNetworkErrors: legacy.bluetooth.prioritizesNetworkErrors,
            symbolScale: legacy.bluetooth.symbolScale,
            networkIconSymbolOverride: legacy.bluetooth.networkIconSymbolOverride
        )
        value.behaviors.systemVolumeFooter = SystemVolumeFooterBehavior(displayStyle: legacy.volume.displayStyle)
        value.appearance.outerRing.strokeScale = legacy.battery.ringStrokeScale
        value.appearance.footer.strokeScale = legacy.volume.ringStrokeScale
        return value.normalized()
    }

    @MainActor
    static func legacyConfiguration(defaults: UserDefaults) -> IconPresentationConfiguration {
        let storedBatteryScale = (defaults.object(forKey: SettingsStore.batterySymbolScaleDefaultsKey) as? NSNumber)?.doubleValue
            ?? SettingsStore.defaultBatterySymbolScale
        let storedThreshold = (defaults.object(forKey: SettingsStore.batteryCriticalThresholdDefaultsKey) as? NSNumber)?.doubleValue
            ?? SettingsStore.defaultBatteryCriticalThreshold
        let wifiScale = (defaults.object(forKey: SettingsStore.wifiSymbolScaleDefaultsKey) as? NSNumber)?.doubleValue
            ?? SettingsStore.defaultWifiSymbolScale
        let bluetoothScale = (defaults.object(forKey: SettingsStore.bluetoothSymbolScaleDefaultsKey) as? NSNumber)?.doubleValue
            ?? SettingsStore.defaultBluetoothSymbolScale
        let stroke = defaults.string(forKey: SettingsStore.ringStrokeStyleDefaultsKey)
            .flatMap(RingStrokeStyle.init(rawValue:)) ?? SettingsStore.defaultRingStrokeStyle
        let volumeStyle = defaults.string(forKey: SettingsStore.volumeDisplayStyleDefaultsKey)
            .flatMap(VolumeDisplayStyle.init(rawValue:)) ?? SettingsStore.defaultVolumeDisplayStyle

        func bool(_ key: String, default fallback: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? fallback
        }
        return IconPresentationConfiguration(
            battery: BatteryIconOptions(
                showsPercentage: bool(SettingsStore.showsBatteryPercentageDefaultsKey, default: true),
                showsChargingIndicator: bool(SettingsStore.showsChargingIndicatorDefaultsKey, default: true),
                showsChargingEffect: bool(SettingsStore.showsChargingEffectDefaultsKey, default: true),
                showsChargingBoltHeartbeat: bool(SettingsStore.showsChargingBoltHeartbeatDefaultsKey, default: true),
                usesStatusColors: bool(SettingsStore.usesBatteryStatusColorsDefaultsKey, default: true),
                criticalThreshold: Int(SettingsStore.clampedBatteryCriticalThreshold(storedThreshold).rounded()),
                showsPercentageWhenConnected: bool(SettingsStore.showsPercentageWhenConnectedDefaultsKey, default: false),
                textScale: SettingsStore.clampedBatterySymbolScale(storedBatteryScale) * BatteryIconOptions.defaultTextScale,
                ringStrokeScale: stroke.scale
            ),
            connection: ConnectionIconOptions(
                showsWiFiIconForEthernet: bool(SettingsStore.showsWiFiIconForEthernetDefaultsKey, default: false),
                showsWiFiIconForHotspot: bool(SettingsStore.showsWiFiIconForHotspotDefaultsKey, default: false),
                showsWiFiIconForTemporaryConnection: bool(SettingsStore.showsWiFiIconForTemporaryConnectionDefaultsKey, default: false),
                showsWiFiIconForInternetSharing: bool(SettingsStore.showsWiFiIconForInternetSharingDefaultsKey, default: false),
                showsBatteryPercentageInConnectionSlot: bool(SettingsStore.showsBatteryPercentageInConnectionSlotDefaultsKey, default: false),
                wifiScale: SettingsStore.clampedWifiSymbolScale(wifiScale)
            ),
            volume: VolumeIconOptions(displayStyle: volumeStyle, ringStrokeScale: stroke.scale),
            bluetooth: BluetoothAudioIconOptions(
                replacesNetworkIcon: bool(SettingsStore.replacesNetworkIconWithBluetoothAudioDefaultsKey, default: false),
                usesVolumeColor: bool(SettingsStore.usesBluetoothAudioVolumeColorDefaultsKey, default: false),
                prioritizesNetworkErrors: bool(SettingsStore.prioritizesNetworkErrorsOverBluetoothAudioDefaultsKey, default: true),
                symbolScale: SettingsStore.clampedBluetoothSymbolScale(bluetoothScale),
                networkIconSymbolOverride: defaults.string(forKey: SettingsStore.bluetoothNetworkIconSymbolNameDefaultsKey)
            )
        )
    }
}

extension IconConfigurationV1 {
    /// Compatibility projection for callers that render these options without
    /// the center Appearance pass.
    var legacyPresentationConfiguration: IconPresentationConfiguration {
        // Migration retains the original legacy Wi-Fi multiplier in
        // `appearance.center.symbolScale` (networkCenter.wifiScale is reset to
        // the classic 1 by normalization), so derive it from there.
        let wifiScale = appearance.center.symbolScale / CenterAppearance.classic.symbolScale
        return makePresentationConfiguration(wifiScale: wifiScale)
    }

    /// The composition resolver applies center Appearance after mapping, so
    /// source-level Wi-Fi scaling must be neutral to avoid applying it twice.
    var compositionLegacyPresentationConfiguration: IconPresentationConfiguration {
        // Source-level Wi-Fi scaling is applied by the centre Appearance pass
        // (`centerScaleFactor`), so keep it neutral here to avoid double-scaling.
        makePresentationConfiguration(wifiScale: NetworkCenterBehavior.classic.wifiScale)
    }

    private func makePresentationConfiguration(wifiScale: Double) -> IconPresentationConfiguration {
        IconPresentationConfiguration(
            battery: BatteryIconOptions(
                showsPercentage: behaviors.systemBatteryRing.showsPercentage,
                showsChargingIndicator: behaviors.systemBatteryRing.showsChargingIndicator,
                showsChargingEffect: behaviors.systemBatteryRing.showsChargingEffect,
                showsChargingBoltHeartbeat: behaviors.systemBatteryRing.showsChargingBoltHeartbeat,
                splitGapProgress: behaviors.splitGapProgress,
                usesStatusColors: behaviors.systemBatteryRing.usesStatusColors,
                criticalThreshold: behaviors.systemBatteryRing.criticalThreshold,
                connectedIndicator: behaviors.systemBatteryRing.connectedIndicator,
                fullThreshold: behaviors.systemBatteryRing.fullThreshold,
                textScale: behaviors.systemBatteryRing.textScale,
                ringStrokeScale: appearance.outerRing.strokeScale,
                batteryStatusColors: appearance.batteryStatusColors.colors,
                onBatteryMarker: behaviors.batteryMarkers == .classic ? nil : behaviors.batteryMarkers.onBattery,
                chargingMarker: behaviors.batteryMarkers == .classic ? nil : behaviors.batteryMarkers.charging,
                connectedMarker: behaviors.batteryMarkers == .classic ? nil : behaviors.batteryMarkers.connected,
                noBatteryMarker: behaviors.batteryMarkers == .classic ? nil : behaviors.batteryMarkers.noBattery,
                monochromeCharging: behaviors.systemBatteryRing.monochromeCharging
            ),
            connection: ConnectionIconOptions(
                showsWiFiIconForEthernet: behaviors.networkCenter.showsWiFiIconForEthernet,
                showsWiFiIconForHotspot: behaviors.networkCenter.showsWiFiIconForHotspot,
                showsWiFiIconForTemporaryConnection: behaviors.networkCenter.showsWiFiIconForTemporaryConnection,
                showsWiFiIconForInternetSharing: behaviors.networkCenter.showsWiFiIconForInternetSharing,
                showsBatteryPercentageInConnectionSlot:
                    composition.center.primary == .systemBatteryPercentage
                    || behaviors.networkCenter.showsBatteryPercentageInConnectionSlot,
                centerSource: legacyCenterSource,
                wifiScale: wifiScale
            ),
            volume: VolumeIconOptions(
                displayStyle: behaviors.systemVolumeFooter.displayStyle,
                ringStrokeScale: appearance.footer.strokeScale
            ),
            bluetooth: BluetoothAudioIconOptions(
                iconColor: appearance.bluetoothIconColor.selection,
                usesVolumeColor: behaviors.bluetoothAudioCenter.usesVolumeColor,
                symbolScale: behaviors.bluetoothAudioCenter.symbolScale,
                networkIconSymbolOverride: behaviors.bluetoothAudioCenter.networkIconSymbolOverride
            )
        )
    }

    /// The connection-slot source the legacy mapper branches on. Charging status
    /// and whole-machine power are real centre modes on main; the mapper only
    /// draws them when `centerSource` says so, so the projection must carry them.
    private var legacyCenterSource: ConnectionCenterSource {
        switch composition.center.primary {
        case .inputSource: .inputSource
        case .systemBatteryPercentage: .batteryPercentage
        case .chargingStatus: .chargingStatus
        case .power: .power
        case .connectedBluetoothDevice, .bluetoothAudioOutput, .pinnedBluetoothGlyph:
            .bluetoothDevice
        case .network, .automaticLegacy, .none:
            .network
        }
    }
}
