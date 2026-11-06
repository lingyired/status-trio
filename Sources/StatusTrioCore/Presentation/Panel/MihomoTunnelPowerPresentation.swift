struct MihomoTunnelPowerPresentation: Equatable, Sendable {
    let isOn: Bool
    let isChanging: Bool
    let canSetPower: Bool
    let actionLabel: String
    let failureMessage: String?
}
