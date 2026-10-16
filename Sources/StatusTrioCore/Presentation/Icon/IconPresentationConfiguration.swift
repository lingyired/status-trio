struct IconPresentationConfiguration: Equatable, Sendable {
    let battery: BatteryIconOptions
    let connection: ConnectionIconOptions
    let volume: VolumeIconOptions
    let bluetooth: BluetoothAudioIconOptions

    static let standard = Self(
        battery: .standard,
        connection: .standard,
        volume: .standard,
        bluetooth: .standard
    )
}

/// Main-branch icon settings that have no field in the persisted V1 designer
/// schema. These are passed with each render and only supplement the legacy
/// projection; V1 source and appearance choices remain authoritative.
struct IconPresentationRuntimeOptions: Equatable, Sendable {
    let connectionCenterSource: ConnectionCenterSource
    let prioritizesNetworkErrorsOverInputSource: Bool
    let batteryFullThreshold: Int
    let bluetoothAudioIconChoice: BluetoothAudioIconChoice

    func applying(to configuration: IconPresentationConfiguration) -> IconPresentationConfiguration {
        let battery = configuration.battery
        let connection = configuration.connection
        let bluetooth = configuration.bluetooth
        return IconPresentationConfiguration(
            battery: BatteryIconOptions(
                showsPercentage: battery.showsPercentage,
                showsChargingIndicator: battery.showsChargingIndicator,
                showsChargingEffect: battery.showsChargingEffect,
                showsChargingBoltHeartbeat: battery.showsChargingBoltHeartbeat,
                usesStatusColors: battery.usesStatusColors,
                criticalThreshold: battery.criticalThreshold,
                showsPercentageWhenConnected: battery.showsPercentageWhenConnected,
                fullThreshold: batteryFullThreshold,
                textScale: battery.textScale,
                ringStrokeScale: battery.ringStrokeScale
            ),
            connection: ConnectionIconOptions(
                showsWiFiIconForEthernet: connection.showsWiFiIconForEthernet,
                showsWiFiIconForHotspot: connection.showsWiFiIconForHotspot,
                showsWiFiIconForTemporaryConnection: connection.showsWiFiIconForTemporaryConnection,
                showsWiFiIconForInternetSharing: connection.showsWiFiIconForInternetSharing,
                showsBatteryPercentageInConnectionSlot: connection.showsBatteryPercentageInConnectionSlot,
                centerSource: connectionCenterSource,
                prioritizesNetworkErrorsOverInputSource: prioritizesNetworkErrorsOverInputSource,
                wifiScale: connection.wifiScale
            ),
            volume: configuration.volume,
            bluetooth: BluetoothAudioIconOptions(
                replacesNetworkIcon: bluetooth.replacesNetworkIcon,
                usesVolumeColor: bluetooth.usesVolumeColor,
                prioritizesNetworkErrors: bluetooth.prioritizesNetworkErrors,
                symbolScale: bluetooth.symbolScale,
                networkIconSymbolOverride: bluetooth.networkIconSymbolOverride,
                iconChoice: bluetoothAudioIconChoice
            )
        )
    }
}

struct IconPresentationInputs: Equatable, Sendable {
    let snapshot: StatusSnapshot
    let audioIcon: IconSymbolSource?
    /// The selected input source, already filtered to an enabled, select-capable
    /// source. `nil` whenever the centre slot must fall back to `.automatic`.
    let inputSource: InputSourceDescriptor?
    /// Runtime-only main settings missing from the V1 schema, carried through
    /// the same input value used by live and preview resolution.
    let runtimeOptions: IconPresentationRuntimeOptions?

    init(
        snapshot: StatusSnapshot,
        audioIcon: IconSymbolSource?,
        inputSource: InputSourceDescriptor? = nil,
        runtimeOptions: IconPresentationRuntimeOptions? = nil
    ) {
        self.snapshot = snapshot
        self.audioIcon = audioIcon
        self.inputSource = inputSource
        self.runtimeOptions = runtimeOptions
    }
}
