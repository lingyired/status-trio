import Combine
import Foundation

/// Phase-1 compatibility bridge between the merged main settings surface and
/// the retained V1 icon architecture.
///
/// After merging `origin/main`, `SettingsStore` is main's implementation: the
/// legacy option structs (`batteryIconOptions`, `connectionIconOptions`, …) are
/// the stored settings. The V1 `IconConfigurationV1` / resolver / plugin layer
/// is kept compiled during Phase 1 by deriving a read-only configuration from
/// those settings. Later phases make `iconConfiguration` the single source of
/// truth and move this mapping in the other direction.
@MainActor
extension SettingsStore {
    /// Read-only V1 projection of the current main settings.
    var iconConfiguration: IconConfigurationV1 {
        var configuration = IconConfigurationV1.classic
        switch connectionIconOptions.centerSource {
        case .inputSource:
            configuration.composition.center = SlotSelection(primary: .inputSource)
        case .batteryPercentage, .chargingStatus:
            configuration.composition.center = SlotSelection(primary: .systemBatteryPercentage)
        case .bluetoothDevice:
            configuration.composition.center = SlotSelection(primary: .connectedBluetoothDevice)
        case .network, .power:
            configuration.composition.center = SlotSelection(primary: .automaticLegacy)
        }
        configuration.behaviors.systemBatteryRing.showsPercentage =
            batteryIconOptions.showsPercentage
        configuration.behaviors.systemBatteryRing.showsChargingIndicator =
            batteryIconOptions.showsChargingIndicator
        return configuration
    }

    /// Emits the derived configuration whenever any setting changes.
    var iconConfigurationPublisher: AnyPublisher<IconConfigurationV1, Never> {
        objectWillChange
            .map { _ in self.iconConfiguration }
            .eraseToAnyPublisher()
    }

    /// Runtime-only options that have no V1 schema field, mirroring the values
    /// the merged store keeps for the legacy presentation pipeline.
    var iconRuntimePresentationOptions: IconPresentationRuntimeOptions {
        IconPresentationRuntimeOptions(
            connectionCenterSource: connectionIconOptions.centerSource,
            prioritizesNetworkErrorsOverInputSource: connectionIconOptions.prioritizesNetworkErrors,
            batteryFullThreshold: batteryIconOptions.fullThreshold,
            bluetoothAudioIconChoice: bluetoothAudioIconOptions.iconChoice
        )
    }

    /// Legacy presentation options assembled from the merged store.
    var legacyPresentationConfiguration: IconPresentationConfiguration {
        IconPresentationConfiguration(
            battery: batteryIconOptions,
            connection: connectionIconOptions,
            volume: volumeIconOptions,
            bluetooth: bluetoothAudioIconOptions
        )
    }
}

@MainActor
extension SettingsStore {
    /// Phase-1 compatibility: the designer editing model still calls this API,
    /// but the merged store owns the settings during Phase 1. Writes are
    /// intentionally ignored until the V1 store becomes the source of truth.
    func updateIconConfiguration(_ update: (inout IconConfigurationV1) -> Void) {}
    func resetIconConfiguration(to configuration: IconConfigurationV1 = .classic) {}

    /// Phase-1 compatibility: the retained designer model still reads/writes
    /// these legacy AirPods demand fields. They are not persisted while main
    /// owns the runtime; Phase 4 moves them into the V1 configuration/plugins.
    var airPodsIconDeviceAddress: String? {
        get { nil }
        set {}
    }
    var connectedBluetoothIconDeviceAddress: String? {
        get { nil }
        set {}
    }
    var refreshesAirPodsBatteryForIcon: Bool {
        get { false }
        set {}
    }
}


@MainActor
extension SettingsStore {
    static let iconConfigurationDefaultsKey = "iconConfigurationV1"

    var iconConfigurationLoadError: IconConfigurationCodecError? { nil }
    var iconPresentationConfiguration: IconPresentationConfiguration { legacyPresentationConfiguration }

    var showsBatteryPercentageInConnectionSlot: Bool {
        get { connectionIconOptions.centerSource == .batteryPercentage }
        set {}
    }
    var replacesNetworkIconWithBluetoothAudio: Bool {
        get { false }
        set {}
    }
}
