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
                        bindings: IconSlotBindingsV1? = nil,
                        registry: IconContentPluginRegistry = BuiltinIconPlugins.makeRegistry()) -> IconResolutionOutput {
        let configuration = rawConfiguration.normalized()
        let effectiveBindings = (bindings ?? IconSlotBindingsV1.migrated(
            from: configuration
        )).normalized()
        let baseLegacy = configuration.compositionLegacyPresentationConfiguration
        let appliedLegacy = inputs.system.runtimeOptions?.applying(to: baseLegacy) ?? baseLegacy
        // The versioned configuration is the single authority for the centre
        // source. The legacy `connectionCenterSource` key must never implicitly
        // turn an `automaticLegacy` centre into the input source — that swap is
        // now an explicit `.inputSource` V1 choice. Non-centre runtime options
        // (battery full threshold, Bluetooth audio glyph choice) still apply.
        let legacy = neutralizingLegacyCenterSource(appliedLegacy)

        let ring = OuterRingResolver.resolve(
            inputs: inputs, configuration: configuration, legacy: legacy,
            behavior: configuration.behaviors.airPodsRing,
            showsAirPodsTopSymbol: configuration.behaviors.showsAirPodsTopSymbol,
            now: now, bindingSelection: effectiveBindings.outerRing, registry: registry)
        let center = CenterResolver.resolve(
            inputs: inputs, configuration: configuration, legacy: legacy, now: now,
            bindingSelection: effectiveBindings.center, registry: registry)
        let footer = FooterResolver.resolve(
            inputs: inputs, configuration: configuration, legacy: legacy, now: now,
            bindingSelection: effectiveBindings.footer, registry: registry)
        // The hardware-monitor ring computes its own per-segment colours (metric
        // base / status / monochrome). The battery ring's colour style must not
        // silently override them; Mac battery and AirPods keep the historical
        // appearance applied bit-for-bit.
        var sceneAppearance = configuration.appearance
        if ring.trace.selectedSourceID == RingSource.hardwareMonitor.rawValue {
            sceneAppearance.outerRing.color = .automatic
        }
        if inputs.system.bottomIndicatorMetric == .memoryPressure,
           footer.trace.binding == IconContentLegacyAdapter.binding(for: .metric) {
            sceneAppearance.footer.color = .automatic
        }
        return IconResolutionOutput(
            scene: IconPaletteResolver.apply(
                IconSceneState(
                    outerRing: ring.state,
                    center: center.state,
                    footer: footer.state,
                    statusColors: configuration.appearance.batteryStatusColors.colors,
                    bluetoothIconColor: configuration.appearance.bluetoothIconColor.selection,
                    // The footer's own resolved source is the only authority for
                    // volume coalescing. Reading the legacy store key here would
                    // mark an external footer as volume whenever the old bottom
                    // indicator happened to be `.volume`, letting the Dock
                    // rate-limit a source it must not treat as continuous volume.
                    bottomIndicatorSource: footerSource(
                        trace: footer.trace, selection: effectiveBindings.footer)
                ),
                appearance: sceneAppearance,
                centerSource: center.source
            ),
            trace: IconResolutionTrace(
                outerRing: ring.trace,
                center: center.trace,
                footer: footer.trace
            ),
            dependencies: dependencies(
                for: [ring.trace, center.trace, footer.trace],
                configuration: configuration,
                bottomIndicatorMetric: inputs.system.bottomIndicatorMetric,
                registry: registry
            ),
            demand: demand(
                bindings: effectiveBindings,
                traces: [ring.trace, center.trace, footer.trace],
                configuration: configuration,
                bottomIndicatorMetric: inputs.system.bottomIndicatorMetric,
                registry: registry
            )
        )
    }

    private static func dependencies(
        for traces: [SlotResolutionTrace],
        configuration: IconConfigurationV1,
        bottomIndicatorMetric: BottomIndicatorMetric,
        registry: IconContentPluginRegistry
    ) -> IconContentDependencies {
        let context = IconContentDependencyContext(
            configuration: configuration, targetIsAudio: false,
            bottomIndicatorMetric: bottomIndicatorMetric)
        var result = IconContentDependencies()
        for trace in traces {
            guard let binding = trace.binding else { continue }
            result.formUnion(registry.dependencies(for: binding, context: context))
        }
        return result
    }

    private static func demand(
        bindings: IconSlotBindingsV1,
        traces: [SlotResolutionTrace],
        configuration: IconConfigurationV1,
        bottomIndicatorMetric: BottomIndicatorMetric,
        registry: IconContentPluginRegistry
    ) -> IconPresentationDemand {
        var selected = Set<IconContentBinding>()
        for trace in traces {
            if let binding = trace.binding { selected.insert(binding) }
        }
        var subscribed = selected
        // A hidden primary contributes nothing. A visible primary stays
        // subscribed so it can recover while its fallback draws. When the
        // primary is currently unresolvable, the fallback also needs a feed even
        // if it has no reading yet — otherwise an external fallback can never be
        // cold-started. Once the primary resolves again the fallback drops out.
        for (selection, trace) in zip(
            [bindings.outerRing, bindings.center, bindings.footer],
            traces
        ) {
            if let primary = selection.primary { subscribed.insert(primary) }
            if trace.primaryFailure != nil,
               let fallback = selection.fallback,
               fallback != selection.primary {
                subscribed.insert(fallback)
            }
        }
        return IconPresentationDemand(
            selectedBindings: selected,
            subscribedBindings: subscribed,
            dependencies: dependencies(
                for: traces, configuration: configuration,
                bottomIndicatorMetric: bottomIndicatorMetric, registry: registry)
        )
    }

    /// The footer metadata carried by the scene. A compiled-in footer keeps its
    /// legacy identity; an external (or unresolved) footer is never reported as
    /// volume, even when the old `bottomIndicatorSource` preference says volume.
    private static func footerSource(
        trace: SlotResolutionTrace,
        selection: IconSlotBindingSelection
    ) -> BottomIndicatorSource {
        if let binding = trace.binding,
           let source = IconContentLegacyAdapter.bottomIndicatorSource(for: binding) {
            return source
        }
        if let primary = selection.primary,
           let source = IconContentLegacyAdapter.bottomIndicatorSource(for: primary) {
            return source
        }
        return .hidden
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
                iconChoice: bluetooth.iconChoice,
                volumeColorRole: bluetooth.volumeColorRole
            )
        )
    }
}
