import Combine
import Foundation

extension SettingsStore {
    /// Every icon-related setting feeds this one publisher.
    ///
    /// The menu bar and the Dock both subscribe to it, so adding an icon setting
    /// means adding it here once instead of another subscription on each
    /// controller. That is what used to go wrong: a setting no subscription
    /// watched did not redraw the icon until the next status poll arrived, which
    /// the refresh interval spaces seconds apart.
    ///
    /// Each input appears exactly once in the chain. A setting that two option
    /// structs share — the ring stroke width — is folded in at the end, so one
    /// change publishes one fully updated appearance instead of a half-updated
    /// intermediate.
    ///
    /// The value is assembled from the delivered values rather than read back
    /// from the store, because `@Published` publishes before the stored value
    /// changes.
    var iconAppearancePublisher: AnyPublisher<StatusIconAppearance, Never> {
        Publishers.CombineLatest4(
            batteryInputsPublisher,
            connectionOptionsPublisher,
            bluetoothOptionsPublisher,
            $volumeDisplayStyle
        )
        .combineLatest($iconSize) { groups, iconSize in
            IconAppearanceGroups(
                battery: groups.0,
                connection: groups.1,
                bluetooth: groups.2,
                volumeDisplayStyle: groups.3,
                iconSize: iconSize
            )
        }
        .combineLatest($ringStrokeStyle) { groups, style in
            groups.appearance(ringStrokeScale: style.scale)
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }

    private var batteryInputsPublisher: AnyPublisher<BatteryAppearanceInputs, Never> {
        Publishers.CombineLatest4(
            $showsBatteryPercentage,
            $showsChargingIndicator,
            $usesBatteryStatusColors,
            $batteryCriticalThreshold
        )
        .combineLatest(
            Publishers.CombineLatest4(
                $showsPercentageWhenConnected,
                $batterySymbolScale,
                $showsChargingEffect,
                $showsChargingBoltHeartbeat
            )
        ) { values, additionalInputs in
            BatteryAppearanceInputs(
                showsPercentage: values.0,
                showsChargingIndicator: values.1,
                usesStatusColors: values.2,
                criticalThreshold: values.3,
                showsPercentageWhenConnected: additionalInputs.0,
                symbolScale: additionalInputs.1,
                showsChargingEffect: additionalInputs.2,
                showsChargingBoltHeartbeat: additionalInputs.3
            )
        }
        .eraseToAnyPublisher()
    }

    private var connectionOptionsPublisher: AnyPublisher<ConnectionIconOptions, Never> {
        Publishers.CombineLatest4(
            $showsWiFiIconForEthernet,
            $showsWiFiIconForHotspot,
            $showsWiFiIconForTemporaryConnection,
            $showsWiFiIconForInternetSharing
        )
        .combineLatest($wifiSymbolScale) { values, wifiScale in
            ConnectionIconOptions(
                showsWiFiIconForEthernet: values.0,
                showsWiFiIconForHotspot: values.1,
                showsWiFiIconForTemporaryConnection: values.2,
                showsWiFiIconForInternetSharing: values.3,
                wifiScale: wifiScale
            )
        }
        .eraseToAnyPublisher()
    }

    private var bluetoothOptionsPublisher: AnyPublisher<BluetoothAudioIconOptions, Never> {
        Publishers.CombineLatest4(
            $replacesNetworkIconWithBluetoothAudio,
            $usesBluetoothAudioVolumeColor,
            $prioritizesNetworkErrorsOverBluetoothAudio,
            $bluetoothSymbolScale
        )
        .combineLatest($bluetoothNetworkIconSymbolName) { values, symbolOverride in
            BluetoothAudioIconOptions(
                replacesNetworkIcon: values.0,
                usesVolumeColor: values.1,
                prioritizesNetworkErrors: values.2,
                symbolScale: values.3,
                networkIconSymbolOverride: symbolOverride
            )
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }
}

/// The battery settings that are not shared with another option group, carried
/// with names so the `CombineLatest` chain never destructures nested tuples.
private struct BatteryAppearanceInputs {
    var showsPercentage: Bool
    var showsChargingIndicator: Bool
    var usesStatusColors: Bool
    var criticalThreshold: Double
    var showsPercentageWhenConnected: Bool
    var symbolScale: Double
    var showsChargingEffect: Bool
    var showsChargingBoltHeartbeat: Bool

    func options(ringStrokeScale: Double) -> BatteryIconOptions {
        BatteryIconOptions(
            showsPercentage: showsPercentage,
            showsChargingIndicator: showsChargingIndicator,
            showsChargingEffect: showsChargingEffect,
            showsChargingBoltHeartbeat: showsChargingBoltHeartbeat,
            usesStatusColors: usesStatusColors,
            criticalThreshold: Int(criticalThreshold.rounded()),
            showsPercentageWhenConnected: showsPercentageWhenConnected,
            textScale: symbolScale * BatteryIconOptions.defaultTextScale,
            ringStrokeScale: ringStrokeScale
        )
    }
}

/// Everything the appearance needs before the shared ring stroke width is known.
private struct IconAppearanceGroups {
    var battery: BatteryAppearanceInputs
    var connection: ConnectionIconOptions
    var bluetooth: BluetoothAudioIconOptions
    var volumeDisplayStyle: VolumeDisplayStyle
    var iconSize: Double

    func appearance(ringStrokeScale: Double) -> StatusIconAppearance {
        StatusIconAppearance(
            iconSize: iconSize,
            batteryOptions: battery.options(ringStrokeScale: ringStrokeScale),
            connectionOptions: connection,
            volumeOptions: VolumeIconOptions(
                displayStyle: volumeDisplayStyle,
                ringStrokeScale: ringStrokeScale
            ),
            bluetoothAudioOptions: bluetooth
        )
    }
}
