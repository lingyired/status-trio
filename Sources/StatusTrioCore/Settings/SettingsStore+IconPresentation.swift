import Combine

extension SettingsStore {
    var iconPresentationPublisher: AnyPublisher<IconPresentationSettings, Never> {
        iconAppearancePublisher
            .combineLatest($iconConfiguration, $testsChargingEffect)
            .map { appearance, configuration, testsChargingEffect in
                IconPresentationSettings(
                    configuration: configuration.legacyPresentationConfiguration,
                    menuBarSize: appearance.iconSize,
                    testsChargingEffect: testsChargingEffect,
                    designerConfiguration: configuration
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
