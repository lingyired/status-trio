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

struct IconPresentationInputs: Equatable, Sendable {
    let snapshot: StatusSnapshot
    let audioIcon: IconSymbolSource?
    /// The selected input source, already filtered to an enabled, select-capable
    /// source. `nil` whenever the centre slot must fall back to `.network`.
    let inputSource: InputSourceDescriptor?
    /// The shared whole-machine power sample when the centre slot is set to
    /// `.power`. `nil` until the sampler has a fresh reading.
    let systemPower: SystemPowerSample?
    /// Whether the system Power Mode switch is in High Power Mode (#235).
    ///
    /// It comes from the privileged helper rather than the IOKit snapshot, so
    /// it is carried alongside the snapshot and drives the battery ring colour
    /// on both the menu bar and the Dock, which share this scene.
    let isHighPowerMode: Bool

    init(
        snapshot: StatusSnapshot,
        audioIcon: IconSymbolSource?,
        inputSource: InputSourceDescriptor? = nil,
        systemPower: SystemPowerSample? = nil,
        isHighPowerMode: Bool = false
    ) {
        self.snapshot = snapshot
        self.audioIcon = audioIcon
        self.inputSource = inputSource
        self.systemPower = systemPower
        self.isHighPowerMode = isHighPowerMode
    }
}
