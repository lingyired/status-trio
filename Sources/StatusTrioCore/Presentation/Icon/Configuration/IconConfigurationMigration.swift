import Foundation

/// Converts the pre-v1 icon options into the versioned slot configuration.
enum IconConfigurationMigration {
    static func makeConfiguration(from legacy: IconPresentationConfiguration) -> IconConfigurationV1 {
        var value = IconConfigurationV1.classic
        value.behaviors.systemBatteryRing = SystemBatteryRingBehavior(
            showsPercentage: legacy.battery.showsPercentage,
            showsChargingIndicator: legacy.battery.showsChargingIndicator,
            showsChargingEffect: legacy.battery.showsChargingEffect,
            showsChargingBoltHeartbeat: legacy.battery.showsChargingBoltHeartbeat,
            usesStatusColors: legacy.battery.usesStatusColors,
            showsPercentageWhenConnected: legacy.battery.showsPercentageWhenConnected,
            criticalThreshold: legacy.battery.criticalThreshold,
            textScale: legacy.battery.textScale
        )
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
    var legacyPresentationConfiguration: IconPresentationConfiguration {
        IconPresentationConfiguration(
            battery: BatteryIconOptions(
                showsPercentage: behaviors.systemBatteryRing.showsPercentage,
                showsChargingIndicator: behaviors.systemBatteryRing.showsChargingIndicator,
                showsChargingEffect: behaviors.systemBatteryRing.showsChargingEffect,
                showsChargingBoltHeartbeat: behaviors.systemBatteryRing.showsChargingBoltHeartbeat,
                usesStatusColors: behaviors.systemBatteryRing.usesStatusColors,
                criticalThreshold: behaviors.systemBatteryRing.criticalThreshold,
                showsPercentageWhenConnected: behaviors.systemBatteryRing.showsPercentageWhenConnected,
                textScale: behaviors.systemBatteryRing.textScale,
                ringStrokeScale: appearance.outerRing.strokeScale
            ),
            connection: ConnectionIconOptions(
                showsWiFiIconForEthernet: behaviors.networkCenter.showsWiFiIconForEthernet,
                showsWiFiIconForHotspot: behaviors.networkCenter.showsWiFiIconForHotspot,
                showsWiFiIconForTemporaryConnection: behaviors.networkCenter.showsWiFiIconForTemporaryConnection,
                showsWiFiIconForInternetSharing: behaviors.networkCenter.showsWiFiIconForInternetSharing,
                showsBatteryPercentageInConnectionSlot: behaviors.networkCenter.showsBatteryPercentageInConnectionSlot,
                wifiScale: behaviors.networkCenter.wifiScale
            ),
            volume: VolumeIconOptions(
                displayStyle: behaviors.systemVolumeFooter.displayStyle,
                ringStrokeScale: appearance.footer.strokeScale
            ),
            bluetooth: BluetoothAudioIconOptions(
                replacesNetworkIcon: behaviors.bluetoothAudioCenter.replacesNetworkIcon,
                usesVolumeColor: behaviors.bluetoothAudioCenter.usesVolumeColor,
                prioritizesNetworkErrors: behaviors.bluetoothAudioCenter.prioritizesNetworkErrors,
                symbolScale: behaviors.bluetoothAudioCenter.symbolScale,
                networkIconSymbolOverride: behaviors.bluetoothAudioCenter.networkIconSymbolOverride
            )
        )
    }
}
