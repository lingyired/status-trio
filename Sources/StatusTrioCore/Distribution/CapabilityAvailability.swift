enum CapabilityAvailability: Equatable, Sendable {
    case available
    case permissionRequired
    case unsupported(reason: String)
    case temporarilyUnavailable(reason: String)
    case notVerified

    var isActionable: Bool {
        if case .available = self {
            true
        } else {
            false
        }
    }
}
