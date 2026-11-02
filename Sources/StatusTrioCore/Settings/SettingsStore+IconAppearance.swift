import AppKit
import Combine
import Foundation

extension SettingsStore {
    /// Every icon-related setting feeds this one publisher.
    ///
    /// The menu bar and the Dock both subscribe to it, so adding an icon setting
    /// means adding it here once instead of another subscription on each
    /// surface. That is what used to go wrong: a setting no subscription
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
            (groups, style.scale)
        }
        .combineLatest($wifiSymbolScale) { pair, centerScale in
            pair.0.appearance(ringStrokeScale: pair.1, centerScale: centerScale)
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
                $batteryConnectedIndicator,
                $batterySymbolScale,
                $showsChargingBoltHeartbeat,
                $showsMenuBarChargingEffect
            )
        )
        .combineLatest($showsDockChargingEffect)
        .combineLatest($batterySplitGapProgress)
        .map { values, splitGapProgress -> BatteryAppearanceInputs in
            let primaryInputs = values.0.0
            let additionalInputs = values.0.1
            let showsDockChargingEffect = values.1
            return BatteryAppearanceInputs(
                showsPercentage: primaryInputs.0,
                showsChargingIndicator: primaryInputs.1,
                usesStatusColors: primaryInputs.2,
                criticalThreshold: primaryInputs.3,
                connectedIndicator: additionalInputs.0,
                symbolScale: additionalInputs.1,
                showsChargingEffect:
                    additionalInputs.3 || showsDockChargingEffect,
                showsChargingBoltHeartbeat: additionalInputs.2,
                splitGapProgress: splitGapProgress,
                fullThreshold: Self.defaultBatteryFullThreshold,
                batteryStatusColors: .standard
            )
        }
        .combineLatest($batteryFullThreshold) { inputs, fullThreshold in
            var updated = inputs
            updated.fullThreshold = fullThreshold
            return updated
        }
        .combineLatest($batteryStatusColors) { inputs, colors in
            var updated = inputs
            updated.batteryStatusColors = colors
            return updated
        }
        .eraseToAnyPublisher()
    }

    private var connectionOptionsPublisher: AnyPublisher<ConnectionIconOptions, Never> {
        Publishers.CombineLatest(
            Publishers.CombineLatest4(
                $showsWiFiIconForEthernet,
                $showsWiFiIconForHotspot,
                $showsWiFiIconForTemporaryConnection,
                $showsWiFiIconForInternetSharing
            ),
            Publishers.CombineLatest($connectionCenterSource, $prioritizesNetworkErrors)
        )
        .map { pair in
            ConnectionIconOptions(
                showsWiFiIconForEthernet: pair.0.0,
                showsWiFiIconForHotspot: pair.0.1,
                showsWiFiIconForTemporaryConnection: pair.0.2,
                showsWiFiIconForInternetSharing: pair.0.3,
                centerSource: pair.1.0,
                prioritizesNetworkErrors: pair.1.1,
                wifiScale: 1.0
            )
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }

    private var bluetoothOptionsPublisher: AnyPublisher<BluetoothAudioIconOptions, Never> {
        Publishers.CombineLatest(
            $usesBluetoothAudioVolumeColor,
            $bluetoothNetworkIconSymbolName
        )
        .combineLatest($bluetoothAudioIconChoiceRawValue) { values, choiceRawValue in
            BluetoothAudioIconOptions(
                usesVolumeColor: values.0,
                networkIconSymbolOverride: values.1,
                iconChoice: BluetoothAudioIconChoice.persisted(choiceRawValue) { symbol in
                    NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
                }
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
    var connectedIndicator: BatteryConnectedIndicator
    var symbolScale: Double
    var showsChargingEffect: Bool
    var showsChargingBoltHeartbeat: Bool
    var splitGapProgress: Bool
    var fullThreshold: Double
    var batteryStatusColors: BatteryStatusColors

    func options(ringStrokeScale: Double) -> BatteryIconOptions {
        BatteryIconOptions(
            showsPercentage: showsPercentage,
            showsChargingIndicator: showsChargingIndicator,
            showsChargingEffect: showsChargingEffect,
            showsChargingBoltHeartbeat: showsChargingBoltHeartbeat,
            splitGapProgress: splitGapProgress,
            usesStatusColors: usesStatusColors,
            criticalThreshold: Int(criticalThreshold.rounded()),
            connectedIndicator: connectedIndicator,
            fullThreshold: Int(fullThreshold.rounded()),
            textScale: symbolScale * BatteryIconOptions.defaultTextScale,
            ringStrokeScale: ringStrokeScale,
            batteryStatusColors: batteryStatusColors
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

    func appearance(ringStrokeScale: Double, centerScale: Double) -> StatusIconAppearance {
        let scaledConnection = ConnectionIconOptions(
            showsWiFiIconForEthernet: connection.showsWiFiIconForEthernet,
            showsWiFiIconForHotspot: connection.showsWiFiIconForHotspot,
            showsWiFiIconForTemporaryConnection: connection.showsWiFiIconForTemporaryConnection,
            showsWiFiIconForInternetSharing: connection.showsWiFiIconForInternetSharing,
            centerSource: connection.centerSource,
            prioritizesNetworkErrors: connection.prioritizesNetworkErrors,
            wifiScale: centerScale
        )
        let scaledBluetooth = BluetoothAudioIconOptions(
            usesVolumeColor: bluetooth.usesVolumeColor,
            symbolScale: centerScale,
            networkIconSymbolOverride: bluetooth.networkIconSymbolOverride,
            iconChoice: bluetooth.iconChoice
        )
        return StatusIconAppearance(
            iconSize: iconSize,
            batteryOptions: battery.options(ringStrokeScale: ringStrokeScale),
            connectionOptions: scaledConnection,
            volumeOptions: VolumeIconOptions(
                displayStyle: volumeDisplayStyle,
                ringStrokeScale: ringStrokeScale
            ),
            bluetoothAudioOptions: scaledBluetooth
        )
    }
}
