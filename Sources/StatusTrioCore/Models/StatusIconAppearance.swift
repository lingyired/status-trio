import Foundation

/// Everything a status icon is drawn from, apart from the live status itself.
///
/// The menu bar and the Dock both render from one of these. Keeping the inputs
/// in a single value means a new icon setting only has to be added here and to
/// `SettingsStore.iconAppearance` to reach both surfaces; the two hand-written
/// subscriber lists it replaced drifted apart, and a setting no subscription
/// watched only reached the icon on the next status poll — seconds later.
struct StatusIconAppearance: Equatable, Sendable {
    var iconSize: Double
    var batteryOptions: BatteryIconOptions
    var connectionOptions: ConnectionIconOptions
    var volumeOptions: VolumeIconOptions
    var bluetoothAudioOptions: BluetoothAudioIconOptions

    init(
        iconSize: Double,
        batteryOptions: BatteryIconOptions,
        connectionOptions: ConnectionIconOptions,
        volumeOptions: VolumeIconOptions,
        bluetoothAudioOptions: BluetoothAudioIconOptions
    ) {
        self.iconSize = iconSize
        self.batteryOptions = batteryOptions
        self.connectionOptions = connectionOptions
        self.volumeOptions = volumeOptions
        self.bluetoothAudioOptions = bluetoothAudioOptions
    }

    /// Reads every icon input straight from the store. Main-actor isolated
    /// because `SettingsStore` is.
    @MainActor
    init(settings: SettingsStore) {
        self.init(
            iconSize: settings.iconSize,
            batteryOptions: settings.batteryIconOptions,
            connectionOptions: settings.connectionIconOptions,
            volumeOptions: settings.volumeIconOptions,
            bluetoothAudioOptions: settings.bluetoothAudioIconOptions
        )
    }
}
