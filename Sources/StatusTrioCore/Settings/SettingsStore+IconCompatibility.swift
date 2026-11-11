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
        Self.iconConfiguration(
            from: StatusIconAppearance(settings: self),
            inputSourceMarkerStyle: inputSourceMarkerStyle
        )
    }

    /// The single derivation from the settings the icon surface actually edits.
    ///
    /// The settings pane mutates the individual `@Published` icon settings, not
    /// the persisted V1 payload, so the runtime configuration must be derived
    /// from those values on every publish; reading the persisted payload would
    /// leave the menu bar on a stale scene.
    static func iconConfiguration(
        from appearance: StatusIconAppearance,
        inputSourceMarkerStyle: InputSourceMarkerStyle
    ) -> IconConfigurationV1 {
        var configuration = IconConfigurationV1.classic
        let battery = appearance.batteryOptions
        let connection = appearance.connectionOptions
        let bluetooth = appearance.bluetoothAudioOptions
        let volume = appearance.volumeOptions

        // Every non-network centre falls back to the network glyph. The legacy
        // mapper always showed Wi-Fi when the chosen source was unavailable, so
        // without this the slot goes blank instead of reverting to Wi-Fi.
        switch connection.centerSource {
        case .inputSource:
            configuration.composition.center = SlotSelection(primary: .inputSource, fallback: .network)
        case .batteryPercentage:
            configuration.composition.center = SlotSelection(primary: .systemBatteryPercentage, fallback: .network)
        case .chargingStatus:
            configuration.composition.center = SlotSelection(primary: .chargingStatus, fallback: .network)
        case .power:
            configuration.composition.center = SlotSelection(primary: .power, fallback: .network)
        case .bluetoothDevice:
            configuration.composition.center = SlotSelection(primary: .connectedBluetoothDevice, fallback: .network)
        case .network:
            configuration.composition.center = SlotSelection(primary: .automaticLegacy, fallback: .network)
        }

        // Outer ring: the Mac battery by default, or the AirPods battery with the
        // Mac battery as an optional fallback when no AirPods are connected
        // (mirroring the centre's network fallback), or system monitoring.
        if appearance.outerRingContent == .hardwareMonitor {
            configuration.composition.outerRing = SlotSelection(primary: .hardwareMonitor)
            configuration.behaviors.airPodsRing = .single
            configuration.behaviors.showsAirPodsTopSymbol = false
        } else if appearance.outerRingContent == .airPodsBattery {
            configuration.composition.outerRing = SlotSelection(
                primary: .airPodsBattery,
                fallback: appearance.airPodsRingFallsBackToBattery ? .systemBattery : nil
            )
            configuration.behaviors.airPodsRing = appearance.airPodsRingUsesDualRing ? .dual : .single
            configuration.behaviors.showsAirPodsTopSymbol = appearance.showsAirPodsTopSymbolInRing
        } else {
            configuration.composition.outerRing = SlotSelection(primary: .systemBattery)
            configuration.behaviors.airPodsRing = .single
            configuration.behaviors.showsAirPodsTopSymbol = false
        }
        // Carry the hardware-ring configuration regardless of the current
        // selection so switching sources preserves the user's setup.
        configuration.behaviors.hardwareRing = appearance.hardwareRingConfiguration.normalized()

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
        configuration.behaviors.systemBatteryRing.monochromeCharging = battery.monochromeCharging
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
        // Stroke scales are already baked into the appearance's options, so the
        // V1 ring/footer scales must come from there rather than from the store.
        configuration.appearance.outerRing.strokeScale = battery.ringStrokeScale
        configuration.appearance.footer.strokeScale = volume.ringStrokeScale
        configuration.appearance.bluetoothIconColor = BluetoothIconColorConfiguration(bluetooth.iconColor)
        configuration.appearance.inputSourceMarkerStyle = inputSourceMarkerStyle
        configuration.appearance.bluetoothSymbolScale = bluetooth.symbolScale
        // The palette applies `symbolScale / classic` as the centre factor over the
        // neutral legacy scale, so the absolute centre size is classic × wifi.
        configuration.appearance.center.symbolScale =
            CenterAppearance.classic.symbolScale * connection.wifiScale
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
        // A corrupt payload stays on disk untouched until an explicit reset, so
        // the user's bytes are never silently destroyed.
        canPersistIconConfiguration = (stored == nil || loadError == nil)
        // Do not write the seeded configuration back onto the individual
        // settings: those are main's persisted values and are the source the
        // runtime projection reads. Only explicit editor writes mirror back.
        // Always write the resolved configuration back once (a fresh migration
        // seeds the key; a stored payload is rewritten only when normalization
        // changed it). A corrupt payload was left untouched above.
        if loadError == nil, let data = try? IconConfigurationCodec.encode(resolved) {
            defaults.set(data, forKey: Self.iconConfigurationDefaultsKey)
        }
    }

    /// Mutates the V1 configuration, persists it, and mirrors the result onto the
    /// individual settings so the UI and runtime see the same values.
    func updateIconConfiguration(_ update: (inout IconConfigurationV1) -> Void) {
        var configuration = iconConfiguration
        // Keep the persisted V1 payload in step with the individual hardware-ring
        // setting (the runtime source of truth) before applying an editor write,
        // so an unrelated edit never resets the user's system-monitoring setup.
        configuration.behaviors.hardwareRing = hardwareRingConfiguration.normalized()
        update(&configuration)
        configuration = configuration.normalized()
        guard configuration != iconConfiguration else { return }
        isSyncingIconConfiguration = true
        iconConfiguration = configuration
        isSyncingIconConfiguration = false
        canPersistIconConfiguration = true
        iconConfigurationLoadError = nil
        if let data = try? IconConfigurationCodec.encode(configuration) {
            defaults.set(data, forKey: Self.iconConfigurationDefaultsKey)
        }
        applyIconConfigurationToSettings(configuration)
    }

    func resetIconConfiguration(to configuration: IconConfigurationV1 = .classic) {
        iconConfigurationLoadError = nil
        canPersistIconConfiguration = true
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
        case .chargingStatus:
            connectionCenterSource = .chargingStatus
        case .power:
            connectionCenterSource = .power
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
