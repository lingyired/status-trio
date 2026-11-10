import Combine
import Foundation

/// Bridge between the merged main settings surface and the V1 icon architecture.
///
/// The individual `@Published` icon settings on `SettingsStore` remain the
/// values the settings UI edits. `iconConfiguration` is the V1 representation
/// that the editor/tests read and write, persisted under
/// `iconConfigurationDefaultsKey`. `updateIconConfiguration` writes a mutated
/// V1 config back into the individual settings; the runtime renders from the
/// projection derived from those individual settings so the UI stays the
/// source of truth for what is on screen.
@MainActor
extension SettingsStore {
    static let iconConfigurationDefaultsKey = "iconConfigurationV1"

    /// V1 projection of the current individual icon settings. Used by the
    /// runtime (`AppEnvironment`'s mapScene) so settings-surface edits render.
    func derivedIconConfigurationFromSettings() -> IconConfigurationV1 {
        var configuration = IconConfigurationV1.classic
        let battery = batteryIconOptions
        let connection = connectionIconOptions
        let bluetooth = bluetoothAudioIconOptions
        let volume = volumeIconOptions

        switch connection.centerSource {
        case .inputSource:
            configuration.composition.center = SlotSelection(primary: .inputSource)
        case .batteryPercentage, .chargingStatus:
            configuration.composition.center = SlotSelection(primary: .systemBatteryPercentage)
        case .bluetoothDevice:
            configuration.composition.center = SlotSelection(primary: .connectedBluetoothDevice)
        case .network, .power:
            configuration.composition.center = SlotSelection(primary: .automaticLegacy)
        }

        configuration.behaviors.systemBatteryRing = SystemBatteryRingBehavior(
            showsPercentage: battery.showsPercentage,
            showsChargingIndicator: battery.showsChargingIndicator,
            showsChargingEffect: battery.showsChargingEffect,
            showsChargingBoltHeartbeat: battery.showsChargingBoltHeartbeat,
            usesStatusColors: battery.usesStatusColors,
            showsPercentageWhenConnected: battery.showsPercentageWhenConnected,
            criticalThreshold: battery.criticalThreshold,
            textScale: battery.textScale
        )
        configuration.behaviors.batteryMarkers = BatteryMarkerBehavior(
            onBattery: battery.onBatteryMarker,
            charging: battery.chargingMarker,
            connected: battery.connectedMarker,
            noBattery: battery.noBatteryMarker
        )
        configuration.behaviors.splitGapProgress = battery.splitGapProgress
        configuration.behaviors.networkCenter = NetworkCenterBehavior(
            showsWiFiIconForEthernet: connection.showsWiFiIconForEthernet,
            showsWiFiIconForHotspot: connection.showsWiFiIconForHotspot,
            showsWiFiIconForTemporaryConnection: connection.showsWiFiIconForTemporaryConnection,
            showsWiFiIconForInternetSharing: connection.showsWiFiIconForInternetSharing,
            showsBatteryPercentageInConnectionSlot: connection.showsBatteryPercentageInConnectionSlot,
            wifiScale: connection.wifiScale
        )
        configuration.behaviors.bluetoothAudioCenter = BluetoothAudioCenterBehavior(
            replacesNetworkIcon: bluetooth.replacesNetworkIcon,
            usesVolumeColor: bluetooth.usesVolumeColor,
            prioritizesNetworkErrors: bluetooth.prioritizesNetworkErrors,
            symbolScale: bluetooth.symbolScale,
            networkIconSymbolOverride: bluetooth.networkIconSymbolOverride
        )
        configuration.behaviors.systemVolumeFooter = SystemVolumeFooterBehavior(
            displayStyle: volume.displayStyle
        )
        configuration.appearance.outerRing.strokeScale = ringStrokeStyle.scale
        configuration.appearance.footer.strokeScale = volume.ringStrokeScale
        configuration.appearance.bluetoothIconColor = BluetoothIconColorConfiguration(bluetooth.iconColor)
        configuration.appearance.inputSourceMarkerStyle = inputSourceMarkerStyle
        configuration.appearance.bluetoothSymbolScale = bluetooth.symbolScale
        configuration.appearance.batteryStatusColors = BatteryStatusColorsConfiguration(
            battery.batteryStatusColors
        )
        return configuration
    }

    var iconConfigurationPublisher: AnyPublisher<IconConfigurationV1, Never> {
        $iconConfiguration.eraseToAnyPublisher()
    }

    /// Runtime-only options that have no V1 schema field.
    var iconRuntimePresentationOptions: IconPresentationRuntimeOptions {
        IconPresentationRuntimeOptions(
            connectionCenterSource: connectionIconOptions.centerSource,
            prioritizesNetworkErrorsOverInputSource: connectionIconOptions.prioritizesNetworkErrors,
            batteryFullThreshold: batteryIconOptions.fullThreshold,
            bluetoothAudioIconChoice: bluetoothAudioIconOptions.iconChoice
        )
    }

    var legacyPresentationConfiguration: IconPresentationConfiguration {
        IconPresentationConfiguration(
            battery: batteryIconOptions,
            connection: connectionIconOptions,
            volume: volumeIconOptions,
            bluetooth: bluetoothAudioIconOptions
        )
    }

    var iconPresentationConfiguration: IconPresentationConfiguration { legacyPresentationConfiguration }

    var showsBatteryPercentageInConnectionSlot: Bool {
        get { connectionIconOptions.centerSource == .batteryPercentage }
        set {}
    }
    var replacesNetworkIconWithBluetoothAudio: Bool {
        get { bluetoothAudioIconOptions.replacesNetworkIcon }
        set {}
    }

    /// AirPods icon device selection, persisted so the retained designer model
    /// and the resolver demand bridge can read the same value.
    private static let airPodsIconDeviceAddressDefaultsKey = "airPodsIconDeviceAddress"
    private static let connectedBluetoothIconDeviceAddressDefaultsKey = "connectedBluetoothIconDeviceAddress"
    private static let refreshesAirPodsBatteryForIconDefaultsKey = "refreshesAirPodsBatteryForIcon"

    var airPodsIconDeviceAddress: String? {
        get { _airPodsIconDeviceAddress }
        set { _airPodsIconDeviceAddress = newValue }
    }
    var connectedBluetoothIconDeviceAddress: String? {
        get { _connectedBluetoothIconDeviceAddress }
        set { _connectedBluetoothIconDeviceAddress = newValue }
    }
    var refreshesAirPodsBatteryForIcon: Bool {
        get { _refreshesAirPodsBatteryForIcon }
        set { _refreshesAirPodsBatteryForIcon = newValue }
    }

    // MARK: - V1 persistence

    /// Seeds `iconConfiguration` from stored V1 data or migrates the legacy
    /// defaults, then mirrors it onto the individual settings.
    func bootstrapIconConfiguration() {
        let stored = defaults.data(forKey: Self.iconConfigurationDefaultsKey)
        var resolved: IconConfigurationV1
        var loadError: IconConfigurationCodecError?
        if let stored {
            do {
                resolved = try IconConfigurationCodec.decode(stored)
            } catch {
                loadError = (error as? IconConfigurationCodecError) ?? .malformedData
                resolved = IconConfigurationMigration.makeConfiguration(
                    from: IconConfigurationMigration.legacyConfiguration(defaults: defaults)
                )
            }
        } else {
            resolved = IconConfigurationMigration.makeConfiguration(
                from: IconConfigurationMigration.legacyConfiguration(defaults: defaults)
            )
        }
        resolved = IconConfigurationMigration.applyingCenterCompatibility(
            IconConfigurationMigration.LegacyCenterPreferences.read(from: defaults),
            to: resolved,
            hadStoredV1: stored != nil
        )
        iconConfigurationLoadError = loadError
        isSyncingIconConfiguration = true
        iconConfiguration = resolved
        isSyncingIconConfiguration = false
        canPersistIconConfiguration = true
        // Do not write the seeded configuration back onto the individual
        // settings: those are main's persisted values and are the source the
        // runtime projection reads. Only explicit editor writes mirror back.
        if stored == nil, let data = try? IconConfigurationCodec.encode(resolved) {
            defaults.set(data, forKey: Self.iconConfigurationDefaultsKey)
        }
    }

    /// Mutates the V1 configuration, persists it, and mirrors the result onto the
    /// individual settings so the UI and runtime see the same values.
    func updateIconConfiguration(_ update: (inout IconConfigurationV1) -> Void) {
        var configuration = iconConfiguration
        update(&configuration)
        configuration = configuration.normalized()
        isSyncingIconConfiguration = true
        iconConfiguration = configuration
        isSyncingIconConfiguration = false
        canPersistIconConfiguration = true
        if let data = try? IconConfigurationCodec.encode(configuration) {
            defaults.set(data, forKey: Self.iconConfigurationDefaultsKey)
        }
        applyIconConfigurationToSettings(configuration)
    }

    func resetIconConfiguration(to configuration: IconConfigurationV1 = .classic) {
        updateIconConfiguration { $0 = configuration }
    }

    /// Mirrors a V1 configuration into the individual `@Published` settings.
    func applyIconConfigurationToSettings(_ configuration: IconConfigurationV1) {
        let behaviors = configuration.behaviors
        let appearance = configuration.appearance

        batteryOnBatteryMarker = behaviors.batteryMarkers.onBattery
        batteryChargingMarker = behaviors.batteryMarkers.charging
        batteryConnectedMarker = behaviors.batteryMarkers.connected
        batteryNoBatteryMarker = behaviors.batteryMarkers.noBattery
        batterySplitGapProgress = behaviors.splitGapProgress
        batteryCriticalThreshold = Double(behaviors.systemBatteryRing.criticalThreshold)
        batteryStatusColors = appearance.batteryStatusColors.colors

        switch configuration.composition.center.primary {
        case .inputSource:
            connectionCenterSource = .inputSource
        case .systemBatteryPercentage:
            connectionCenterSource = .batteryPercentage
        case .bluetoothAudioOutput, .pinnedBluetoothGlyph, .connectedBluetoothDevice:
            connectionCenterSource = .bluetoothDevice
        case .network, .automaticLegacy, .none:
            connectionCenterSource = .network
        }
        showsWiFiIconForEthernet = behaviors.networkCenter.showsWiFiIconForEthernet
        showsWiFiIconForHotspot = behaviors.networkCenter.showsWiFiIconForHotspot
        showsWiFiIconForTemporaryConnection = behaviors.networkCenter.showsWiFiIconForTemporaryConnection
        showsWiFiIconForInternetSharing = behaviors.networkCenter.showsWiFiIconForInternetSharing

        bluetoothIconColor = appearance.bluetoothIconColor.selection
        bluetoothSymbolScale = appearance.bluetoothSymbolScale
        bluetoothNetworkIconSymbolName = behaviors.bluetoothAudioCenter.networkIconSymbolOverride
        inputSourceMarkerStyle = appearance.inputSourceMarkerStyle
        volumeDisplayStyle = behaviors.systemVolumeFooter.displayStyle
        ringStrokeStyle = RingStrokeStyle.allCases.min {
            abs($0.scale - appearance.outerRing.strokeScale)
                < abs($1.scale - appearance.outerRing.strokeScale)
        } ?? .regular
    }
}
