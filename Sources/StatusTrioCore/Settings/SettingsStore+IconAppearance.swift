import Combine
import Foundation

extension SettingsStore {
    /// The versioned configuration is the single publisher for every icon setting.
    /// One edit publishes one complete snapshot to both render surfaces.
    var iconAppearancePublisher: AnyPublisher<StatusIconAppearance, Never> {
        $iconConfiguration
            .combineLatest($iconSize)
            .map { configuration, iconSize in
                let legacy = configuration.legacyPresentationConfiguration
                return StatusIconAppearance(
                    iconSize: iconSize,
                    batteryOptions: legacy.battery,
                    connectionOptions: legacy.connection,
                    volumeOptions: legacy.volume,
                    bluetoothAudioOptions: legacy.bluetooth
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
