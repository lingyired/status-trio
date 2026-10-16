import AppKit
import Combine
import Foundation

extension SettingsStore {
    /// The versioned configuration is the single publisher for every icon setting.
    /// One edit publishes one complete snapshot to both render surfaces.
    var iconAppearancePublisher: AnyPublisher<StatusIconAppearance, Never> {
        $iconConfiguration
            .combineLatest($iconSize)
            .combineLatest($batteryFullThreshold)
            .combineLatest($connectionCenterSource)
            .combineLatest($prioritizesNetworkErrorsOverInputSource)
            .combineLatest($bluetoothAudioIconChoiceRawValue)
            .map { values, bluetoothAudioIconChoiceRawValue in
                let (((configurationAndSize, fullThreshold), centerSource), prioritizesInputSource) = values
                let (configuration, iconSize) = configurationAndSize
                let bluetoothAudioIconChoice = BluetoothAudioIconChoice(rawValue: bluetoothAudioIconChoiceRawValue) ?? .automatic
                let runtimeOptions = IconPresentationRuntimeOptions(
                    connectionCenterSource: centerSource,
                    prioritizesNetworkErrorsOverInputSource: prioritizesInputSource,
                    batteryFullThreshold: Int(fullThreshold.rounded()),
                    bluetoothAudioIconChoice: bluetoothAudioIconChoice
                )
                let legacy = runtimeOptions.applying(to: configuration.legacyPresentationConfiguration)
                return StatusIconAppearance(
                    iconSize: iconSize,
                    batteryOptions: legacy.battery,
                    connectionOptions: legacy.connection,
                    volumeOptions: legacy.volume,
                    bluetoothAudioOptions: legacy.bluetooth,
                    runtimeOptions: runtimeOptions
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
