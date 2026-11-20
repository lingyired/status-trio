import Combine
import Foundation

/// Bridge between the merged main settings surface and the V1 icon architecture.
///
/// The individual `@Published` icon settings on `SettingsStore` remain the
/// values the settings UI edits. `iconConfiguration` is the V1 representation
/// used by legacy compatibility reads and tests, persisted under
/// `iconConfigurationDefaultsKey` only by explicit updates. `updateIconConfiguration`
/// writes a mutated V1 config back into the individual settings; the runtime
/// renders from the projection derived from those individual settings so the UI
/// stays the source of truth for what is on screen.
@MainActor
extension SettingsStore {
    static let iconConfigurationDefaultsKey = "iconConfigurationV1"
    static let iconSlotBindingsDefaultsKey = "iconSlotBindingsV1"

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

        // Outer ring: the Mac battery by default, or the AirPods battery with a
        // configurable fallback when no AirPods are connected — the Mac battery
        // ring (historical), the custom system-monitoring ring, or nothing
        // (mirroring the centre's network fallback).
        if appearance.outerRingContent == .hardwareMonitor {
            configuration.composition.outerRing = SlotSelection(primary: .hardwareMonitor)
            configuration.behaviors.airPodsRing = .single
            configuration.behaviors.showsAirPodsTopSymbol = false
        } else if appearance.outerRingContent == .airPodsBattery {
            let ringFallback: RingSource = switch appearance.airPodsRingFallback {
            case .battery: .systemBattery
            case .hardwareMonitor: .hardwareMonitor
            }
            configuration.composition.outerRing = SlotSelection(
                primary: .airPodsBattery,
                fallback: ringFallback
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
        // The top-marker size is one shared standard (the battery symbol scale)
        // that also drives the battery percentage/bolt and the AirPods top
        // symbol. Derive the hardware ring's factor from it so all four agree.
        let sharedTopMarkerFactor = appearance.batteryOptions.textScale / BatteryIconOptions.defaultTextScale
        configuration.behaviors.hardwareRing.topMarkerScale =
            HardwareRingConfiguration.normalizedTopMarkerScale(sharedTopMarkerFactor)

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
        // The settings toggle is the live authority for the global
        // network-problem override. The legacy one-time compatibility fold only
        // seeds the stored V1 payload; deriving the runtime scene from that stale
        // payload would ignore later clicks on the toggle.
        configuration.composition.centerOverride.networkProblemOverridesPrimary =
            connection.prioritizesNetworkErrors
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
            bluetoothAudioIconChoice: bluetoothAudioIconOptions.iconChoice,
            bottomIndicatorSource: bottomIndicatorSource
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

    /// AirPods icon device selection, persisted so the settings surface and the
    /// resolver demand bridge can read the same value.
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
    /// defaults for in-memory compatibility reads.
    ///
    /// Launch does not write the resolved value back to V1 or to the individual
    /// settings; only an explicit compatibility update persists it.
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
        // runtime projection reads. Only explicit legacy/test updates mirror back.
        //
        // Do not seed or normalize `iconConfigurationDefaultsKey` at launch
        // either. The retired 2.0 designer's automatic writeback is gone; the
        // stored payload remains a read-compatibility input until an explicit
        // `updateIconConfiguration` call writes a new one. A corrupt payload was
        // left untouched above.
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

    // MARK: - Slot bindings

    /// Bindings used for one published settings snapshot.
    ///
    /// Built-in slot choices follow the individual settings that just changed,
    /// so the same snapshot is correct even though `@Published` delivers the
    /// legacy value before its `didSet` can persist the binding update. External
    /// primaries and fallbacks are preserved verbatim.
    func effectiveIconSlotBindings(
        appearance: StatusIconAppearance,
        inputSourceMarkerStyle: InputSourceMarkerStyle,
        bottomIndicatorSource: BottomIndicatorSource
    ) -> IconSlotBindingsV1 {
        let derived = IconSlotBindingsV1.migrated(
            from: Self.iconConfiguration(
                from: appearance,
                inputSourceMarkerStyle: inputSourceMarkerStyle),
            bottomIndicatorSource: bottomIndicatorSource
        )
        var result = iconSlotBindings
        for slot in IconSlot.allCases {
            let stored = result.selection(for: slot)
            if let primary = stored.primary, !primary.pluginID.hasPrefix("builtin.") {
                continue
            }
            guard stored.primary != nil else { continue }
            let fallbackIsExternal = stored.fallback.map { !$0.pluginID.hasPrefix("builtin.") } ?? false
            var selection = derived.selection(for: slot)
            if fallbackIsExternal { selection.fallback = stored.fallback }
            result.setSelection(selection, for: slot)
        }
        return result.normalized()
    }

    /// Seeds the slot binding store once from the live individual settings.
    ///
    /// A missing payload is migrated and persisted immediately. A malformed or
    /// newer payload is left byte-for-byte intact and the current run falls back
    /// to the per-setting projection without writing over the user's data.
    func bootstrapIconSlotBindings() {
        let stored = defaults.data(forKey: Self.iconSlotBindingsDefaultsKey)
        var resolved: IconSlotBindingsV1
        var loadError: IconSlotBindingsCodecError?
        if let stored {
            do {
                resolved = try IconSlotBindingsCodec.decode(stored)
            } catch {
                loadError = (error as? IconSlotBindingsCodecError) ?? .malformedData
                resolved = IconSlotBindingsV1.migrated(
                    from: derivedIconConfigurationFromSettings(),
                    bottomIndicatorSource: bottomIndicatorSource
                )
            }
        } else {
            resolved = IconSlotBindingsV1.migrated(
                from: derivedIconConfigurationFromSettings(),
                bottomIndicatorSource: bottomIndicatorSource
            )
        }
        iconSlotBindingsLoadError = loadError
        isSyncingIconSlotBindings = true
        iconSlotBindings = resolved.normalized()
        isSyncingIconSlotBindings = false
        canPersistIconSlotBindings = (stored == nil || loadError == nil)
        if stored == nil, let data = try? IconSlotBindingsCodec.encode(resolved) {
            defaults.set(data, forKey: Self.iconSlotBindingsDefaultsKey)
        }
    }

    /// The single setter used by the settings surface and imports.
    ///
    /// Unknown plugin IDs are stored verbatim. Built-in IDs also update the
    /// legacy individual settings so previews, exports and older code paths keep
    /// seeing the same choice; an external or hidden selection leaves the legacy
    /// key untouched.
    func setIconSlotBinding(
        primary: IconContentBinding?,
        fallback: IconContentBinding? = nil,
        for slot: IconSlot
    ) {
        var bindings = iconSlotBindings
        bindings.setSelection(.init(primary: primary, fallback: fallback).normalized(), for: slot)
        applyIconSlotBindings(bindings, updatingLegacySlot: slot)
    }

    /// Applies an external presentation chosen in the slot's source menu.
    ///
    /// When the slot had no fallback, the compiled-in source being replaced is
    /// kept as the fallback. That is what lets a missing or removed package fall
    /// back to the built-in icon instead of leaving the slot blank with no
    /// product path back to a built-in choice.
    func selectExternalIconSlotSource(_ binding: IconContentBinding, for slot: IconSlot) {
        let selection = iconSlotBindings.selection(for: slot)
        let fallback: IconContentBinding?
        if let existing = selection.fallback, existing != binding {
            fallback = existing
        } else if let replaced = selection.primary, replaced != binding, replaced.isBuiltinSource {
            fallback = replaced
        } else {
            fallback = nil
        }
        setIconSlotBinding(primary: binding, fallback: fallback, for: slot)
    }

    func applyIconSlotBindings(_ bindings: IconSlotBindingsV1, updatingLegacySlot slot: IconSlot? = nil) {
        let normalized = bindings.normalized()
        guard normalized != iconSlotBindings else { return }
        isSyncingIconSlotBindings = true
        iconSlotBindings = normalized
        isSyncingIconSlotBindings = false
        canPersistIconSlotBindings = true
        iconSlotBindingsLoadError = nil
        if let data = try? IconSlotBindingsCodec.encode(normalized) {
            defaults.set(data, forKey: Self.iconSlotBindingsDefaultsKey)
        }
        if let slot {
            isSyncingIconSlotBindings = true
            applyIconSlotBindingToLegacySettings(normalized.selection(for: slot), for: slot)
            isSyncingIconSlotBindings = false
        }
    }

    /// Mirrors the live individual settings into one legacy slot binding.
    ///
    /// This is what keeps existing controls and old imports working without a
    /// second source of truth: any built-in selection made through the legacy
    /// property lands in the binding store through this hook.
    func synchronizeSlotBindingFromLegacySettings(for slot: IconSlot) {
        guard !isSyncingIconSlotBindings, iconSlotBindingsLoadError == nil else { return }
        let configuration = derivedIconConfigurationFromSettings()
        var bindings = iconSlotBindings
        switch slot {
        case .outerRing:
            let selection = configuration.composition.outerRing
            bindings.outerRing = .init(
                primary: IconContentLegacyAdapter.binding(for: selection.primary),
                fallback: selection.fallback.flatMap(IconContentLegacyAdapter.binding(for:))
            )
        case .center:
            let selection = configuration.composition.center
            bindings.center = .init(
                primary: IconContentLegacyAdapter.binding(for: selection.primary),
                fallback: selection.fallback.flatMap(IconContentLegacyAdapter.binding(for:))
            )
        case .footer:
            bindings.footer = .init(primary: IconContentLegacyAdapter.binding(for: bottomIndicatorSource))
        }
        guard bindings.normalized() != iconSlotBindings else { return }
        isSyncingIconSlotBindings = true
        iconSlotBindings = bindings.normalized()
        isSyncingIconSlotBindings = false
        canPersistIconSlotBindings = true
        if let data = try? IconSlotBindingsCodec.encode(bindings) {
            defaults.set(data, forKey: Self.iconSlotBindingsDefaultsKey)
        }
    }

    private func applyIconSlotBindingToLegacySettings(
        _ selection: IconSlotBindingSelection,
        for slot: IconSlot
    ) {
        switch slot {
        case .outerRing:
            guard let binding = selection.primary,
                  let source = IconContentLegacyAdapter.ringSource(for: binding) else { return }
            switch source {
            case .systemBattery, .automaticLegacy:
                outerRingContent = .systemBattery
            case .airPodsBattery:
                outerRingContent = .airPodsBattery
                if let fallback = selection.fallback,
                   let fallbackSource = IconContentLegacyAdapter.ringSource(for: fallback) {
                    airPodsRingFallback = fallbackSource == .hardwareMonitor ? .hardwareMonitor : .battery
                }
            case .hardwareMonitor:
                outerRingContent = .hardwareMonitor
            case .none:
                break
            }
        case .center:
            guard let binding = selection.primary,
                  let source = IconContentLegacyAdapter.centerSource(for: binding) else { return }
            switch source {
            case .network, .automaticLegacy:
                connectionCenterSource = .network
            case .inputSource:
                connectionCenterSource = .inputSource
            case .systemBatteryPercentage:
                connectionCenterSource = .batteryPercentage
            case .bluetoothAudioOutput, .connectedBluetoothDevice, .pinnedBluetoothGlyph:
                connectionCenterSource = .bluetoothDevice
            case .chargingStatus:
                connectionCenterSource = .chargingStatus
            case .power:
                connectionCenterSource = .power
            case .none:
                break
            }
        case .footer:
            if let binding = selection.primary,
               let source = IconContentLegacyAdapter.bottomIndicatorSource(for: binding) {
                bottomIndicatorSource = source
            } else if selection.primary == nil {
                bottomIndicatorSource = .hidden
            }
        }
    }
}
