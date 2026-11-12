import Combine

extension SettingsStore {
    var iconPresentationPublisher: AnyPublisher<IconPresentationSettings, Never> {
        // One publication per icon-settings change, carrying both the legacy
        // projection and the V1 configuration derived from the *same* appearance
        // snapshot.
        //
        // The settings pane mutates the individual `@Published` icon settings;
        // the persisted V1 payload (`$iconConfiguration`) is only rewritten by
        // the editor API. Deriving the V1 configuration from the appearance here
        // (instead of combining `$iconConfiguration`) is what keeps the menu bar
        // in step with the settings surface.
        Publishers.CombineLatest4(
            iconAppearancePublisher,
            $testsChargingEffect,
            $inputSourceMarkerStyle,
            $bottomIndicatorSource
        )
        .map { appearance, testsChargingEffect, markerStyle, bottomIndicatorSource in
            IconPresentationSettings(
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
                    bottomIndicatorSource: bottomIndicatorSource
                )
            )
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }
}
