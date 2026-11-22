import Combine

extension SettingsStore {
    var iconPresentationPublisher: AnyPublisher<IconPresentationSettings, Never> {
        // One publication per icon-settings change, carrying both the legacy
        // projection and the V1 configuration derived from the *same* appearance
        // snapshot.
        //
        // The settings pane mutates the individual `@Published` icon settings;
        // the persisted V1 payload (`$iconConfiguration`) is only rewritten by
        // an explicit legacy compatibility update. Deriving the V1 configuration
        // from the appearance here
        // (instead of combining `$iconConfiguration`) is what keeps the menu bar
        // in step with the settings surface.
        Publishers.CombineLatest(
            Publishers.CombineLatest4(
                iconAppearancePublisher,
                $testsChargingEffect,
                $inputSourceMarkerStyle,
                $bottomIndicatorSource
            ),
            Publishers.CombineLatest4(
                $bottomIndicatorMetric,
                Publishers.CombineLatest4(
                    $wifiBottomIndicatorStyle,
                    $batteryBottomIndicatorStyle, $metricBottomIndicatorStyle,
                    $bluetoothVolumeColor
                ),
                $iconSlotBindings, $iconConfiguration
            )
        )
        .map { appearanceAndFlags, metricAndBindings in
            let (appearance, testsChargingEffect, markerStyle, bottomIndicatorSource) = appearanceAndFlags
            let (bottomIndicatorMetric, styles, _, _) = metricAndBindings
            let bottomIndicatorStyle: VolumeDisplayStyle
            switch bottomIndicatorSource {
            case .volume, .hidden: bottomIndicatorStyle = appearance.volumeOptions.displayStyle
            case .wifi: bottomIndicatorStyle = styles.0
            case .battery: bottomIndicatorStyle = styles.1
            case .metric: bottomIndicatorStyle = styles.2
            }
            // `styles.3` is the publisher's NEW Bluetooth volume colour, so this
            // avoids the `@Published` willSet lag of reading the live store.
            let bluetoothVolumeColorRole: IconColorRole? = {
                switch styles.3 {
                case .automatic: return nil
                case let .custom(color): return .custom(color)
                }
            }()
            let slotBindings = self.effectiveIconSlotBindings(
                appearance: appearance,
                inputSourceMarkerStyle: markerStyle,
                bottomIndicatorSource: bottomIndicatorSource,
                bottomIndicatorMetric: bottomIndicatorMetric
            )
            return IconPresentationSettings(
                configuration: IconPresentationConfiguration(
                    battery: appearance.batteryOptions,
                    connection: appearance.connectionOptions,
                    volume: appearance.volumeOptions,
                    bluetooth: appearance.bluetoothAudioOptions
                ),
                menuBarSize: appearance.iconSize,
                testsChargingEffect: testsChargingEffect,
                iconConfiguration: SettingsStore.iconConfiguration(
                    from: appearance,
                    inputSourceMarkerStyle: markerStyle
                ),
                runtimeOptions: IconPresentationRuntimeOptions(
                    connectionCenterSource: appearance.connectionOptions.centerSource,
                    prioritizesNetworkErrorsOverInputSource: appearance.connectionOptions.prioritizesNetworkErrors,
                    batteryFullThreshold: appearance.batteryOptions.fullThreshold,
                    bluetoothAudioIconChoice: appearance.bluetoothAudioOptions.iconChoice,
                    bottomIndicatorSource: bottomIndicatorSource,
                    bottomIndicatorMetric: bottomIndicatorMetric,
                    bottomIndicatorStyle: bottomIndicatorStyle,
                    bluetoothVolumeColorRole: bluetoothVolumeColorRole
                ),
                slotBindings: slotBindings,
                hardwareMetricColors: appearance.hardwareMetricColors,
                hardwareDownloadCapMbps: appearance.hardwareDownloadCapMbps,
                hardwareUploadCapMbps: appearance.hardwareUploadCapMbps
            )
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }
}
