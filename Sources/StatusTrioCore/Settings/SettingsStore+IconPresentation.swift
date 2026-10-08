import Combine

extension SettingsStore {
    var iconPresentationPublisher: AnyPublisher<IconPresentationSettings, Never> {
        iconAppearancePublisher
            .combineLatest($testsChargingEffect)
            .map { appearance, testsChargingEffect in
                IconPresentationSettings(
                    configuration: IconPresentationConfiguration(
                        battery: appearance.batteryOptions,
                        connection: appearance.connectionOptions,
                        volume: appearance.volumeOptions,
                        bluetooth: appearance.bluetoothAudioOptions
                    ),
                    menuBarSize: appearance.iconSize,
                    testsChargingEffect: testsChargingEffect
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
