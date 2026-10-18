import Combine

extension SettingsStore {
    var iconPresentationPublisher: AnyPublisher<IconPresentationSettings, Never> {
        iconAppearancePublisher
            .combineLatest($iconConfiguration, $testsChargingEffect)
            .map { appearance, configuration, testsChargingEffect in
                let runtimeOptions = appearance.runtimeOptions ?? IconPresentationRuntimeOptions(
                    connectionCenterSource: .automatic,
                    prioritizesNetworkErrorsOverInputSource: true,
                    batteryFullThreshold: Int(appearance.batteryOptions.fullThreshold),
                    bluetoothAudioIconChoice: appearance.bluetoothAudioOptions.iconChoice
                )
                let legacy = runtimeOptions.applying(to: configuration.legacyPresentationConfiguration)
                return IconPresentationSettings(
                    configuration: legacy,
                    menuBarSize: appearance.iconSize,
                    testsChargingEffect: testsChargingEffect,
                    designerConfiguration: configuration,
                    runtimeOptions: runtimeOptions
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
