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
    /// source. `nil` whenever the centre slot must fall back to `.automatic`.
    let inputSource: InputSourceDescriptor?
    /// The shared whole-machine power sample when the centre slot is set to
    /// `.power`. `nil` until the sampler has a fresh reading.
    let systemPower: SystemPowerSample?

    init(
        snapshot: StatusSnapshot,
        audioIcon: IconSymbolSource?,
        inputSource: InputSourceDescriptor? = nil,
        systemPower: SystemPowerSample? = nil
    ) {
        self.snapshot = snapshot
        self.audioIcon = audioIcon
        self.inputSource = inputSource
        self.systemPower = systemPower
    }
}
