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
                centerSource: connectionCenterSource,
                prioritizesNetworkErrors: prioritizesNetworkErrorsOverInputSource,
                wifiScale: connection.wifiScale
            ),
            volume: configuration.volume,
            bluetooth: BluetoothAudioIconOptions(
                iconColor: bluetooth.iconColor,
                usesVolumeColor: bluetooth.usesVolumeColor,
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
    /// source. `nil` whenever the centre slot must fall back to `.network`.
    let inputSource: InputSourceDescriptor?
    /// Runtime-only main settings missing from the V1 schema, carried through
    /// the same input value used by live and preview resolution.
    let runtimeOptions: IconPresentationRuntimeOptions?
    /// The shared whole-machine power sample when the centre slot is set to
    /// `.power`. `nil` until the sampler has a fresh reading.
    let systemPower: SystemPowerSample?
    /// Whether the system Power Mode switch is in High Power Mode (#235).
    ///
    /// It comes from the privileged helper rather than the IOKit snapshot, so
    /// it is carried alongside the snapshot and drives the battery ring colour
    /// on both the menu bar and the Dock, which share this scene.
    let isHighPowerMode: Bool
    /// Source availability and Bluetooth/AirPods battery snapshot used by the
    /// V1 resolver/plugin layer. `.empty` keeps the legacy projection inputs
    /// usable without BT data.
    var sources: IconSourceSnapshot = .empty

    init(
        snapshot: StatusSnapshot,
        audioIcon: IconSymbolSource?,
        inputSource: InputSourceDescriptor? = nil,
        runtimeOptions: IconPresentationRuntimeOptions? = nil,
        systemPower: SystemPowerSample? = nil,
        isHighPowerMode: Bool = false,
        sources: IconSourceSnapshot = .empty
    ) {
        self.snapshot = snapshot
        self.audioIcon = audioIcon
        self.inputSource = inputSource
        self.runtimeOptions = runtimeOptions
        self.systemPower = systemPower
        self.isHighPowerMode = isHighPowerMode
        self.sources = sources
    }
}
