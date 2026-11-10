import Foundation

struct IconResolutionInputs: Equatable, Sendable {
    var system: IconPresentationInputs
    var sources: IconSourceSnapshot
}

struct SourceSelectionResult<Source: Codable & Hashable & Sendable>: Equatable, Sendable {
    var source: Source?
    var role: SlotResolutionRole
    var primaryFailure: IconSourceUnavailableReason?
    var reason: SlotResolutionReason
}

func chooseSource<Source: Codable & Hashable & Sendable>(
    _ selection: SlotSelection<Source>,
    none: Source,
    availability: (Source) -> SourceResult<Bool>
) -> SourceSelectionResult<Source> {
    guard selection.primary != none else {
        return SourceSelectionResult(source: nil, role: .none, primaryFailure: nil, reason: .none)
    }
    switch availability(selection.primary) {
    case .available:
        return SourceSelectionResult(source: selection.primary, role: .primary, primaryFailure: nil, reason: .primary)
    case let .unavailable(primaryFailure):
        guard let fallback = selection.fallback, fallback != none else {
            return SourceSelectionResult(source: nil, role: .none, primaryFailure: primaryFailure, reason: .none)
        }
        switch availability(fallback) {
        case .available:
            return SourceSelectionResult(source: fallback, role: .fallback, primaryFailure: primaryFailure,
                                         reason: .fallback(primaryFailure))
        case .unavailable:
            return SourceSelectionResult(source: nil, role: .none, primaryFailure: primaryFailure, reason: .none)
        }
    }
}

enum IconCompositionResolver {
    static func resolve(inputs: IconResolutionInputs, configuration rawConfiguration: IconConfigurationV1, now: Date = .now,
                        registry: IconContentPluginRegistry = BuiltinIconPlugins.makeRegistry()) -> IconResolutionOutput {
        let configuration = rawConfiguration.normalized()
        let baseLegacy = configuration.compositionLegacyPresentationConfiguration
        let appliedLegacy = inputs.system.runtimeOptions?.applying(to: baseLegacy) ?? baseLegacy
        // The versioned configuration is the single authority for the centre
        // source. The legacy `connectionCenterSource` key must never implicitly
        // turn an `automaticLegacy` centre into the input source — that swap is
        // now an explicit `.inputSource` V1 choice. Non-centre runtime options
        // (battery full threshold, Bluetooth audio glyph choice) still apply.
        let legacy = neutralizingLegacyCenterSource(appliedLegacy)

        let ring = OuterRingResolver.resolve(inputs: inputs, configuration: configuration, legacy: legacy,
                                             behavior: configuration.behaviors.airPodsRing,
                                             showsAirPodsTopSymbol: configuration.behaviors.showsAirPodsTopSymbol,
                                             now: now, registry: registry)
        let center = CenterResolver.resolve(inputs: inputs, configuration: configuration, legacy: legacy, now: now, registry: registry)
        let footer = FooterResolver.resolve(inputs: inputs, configuration: configuration, legacy: legacy, now: now, registry: registry)
        return IconResolutionOutput(
            scene: IconPaletteResolver.apply(
                IconSceneState(
                    outerRing: ring.state,
                    center: center.state,
                    footer: footer.state,
                    statusColors: configuration.appearance.batteryStatusColors.colors,
                    bluetoothIconColor: configuration.appearance.bluetoothIconColor.selection
                ),
                appearance: configuration.appearance,
                centerSource: center.source
            ),
            trace: IconResolutionTrace(
                outerRing: ring.trace,
                center: center.trace,
                footer: footer.trace
            )
        )
    }

    private static func neutralizingLegacyCenterSource(
        _ configuration: IconPresentationConfiguration
    ) -> IconPresentationConfiguration {
        // The legacy projection still carries the pre-V1 input-source swap
        // (`connectionCenterSource` + `prioritizesNetworkErrorsOverInputSource`).
        // `.inputSource` is an explicit V1 choice now, and the global
        // `centerOverride` policy checked in `CenterResolver` is the sole
        // network-failure rule for the V1 scene. The old Bluetooth flag
        // `bluetooth.prioritizesNetworkErrors` is neutralized on the projection
        // too: it must never preempt a current Bluetooth audio output when the
        // global rule is off. `replacesNetworkIcon`, `usesVolumeColor` and the
        // legacy glyph choice stay intact, because those define the
        // `.automaticLegacy` mapper's real non-network rendering.
        let connection = configuration.connection
        let bluetooth = configuration.bluetooth
        return IconPresentationConfiguration(
            battery: configuration.battery,
            connection: ConnectionIconOptions(
                showsWiFiIconForEthernet: connection.showsWiFiIconForEthernet,
                showsWiFiIconForHotspot: connection.showsWiFiIconForHotspot,
                showsWiFiIconForTemporaryConnection: connection.showsWiFiIconForTemporaryConnection,
                showsWiFiIconForInternetSharing: connection.showsWiFiIconForInternetSharing,
                centerSource: connection.centerSource,
                prioritizesNetworkErrors: false,
                wifiScale: connection.wifiScale
            ),
            volume: configuration.volume,
            bluetooth: BluetoothAudioIconOptions(
                iconColor: bluetooth.iconColor,
                usesVolumeColor: bluetooth.usesVolumeColor,
                symbolScale: bluetooth.symbolScale,
                networkIconSymbolOverride: bluetooth.networkIconSymbolOverride,
                iconChoice: bluetooth.iconChoice
            )
        )
    }
}
