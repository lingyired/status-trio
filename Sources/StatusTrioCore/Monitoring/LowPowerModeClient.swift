import Foundation

/// The app's view of the privileged power helper. Injected so the controller
/// can be exercised without a registered daemon.
protocol LowPowerModeClienting: Sendable {
    /// Reads Low Power Mode through the helper.
    func readLowPowerMode() async throws -> Bool
    /// Sets Low Power Mode and returns the state the daemon observed after.
    func setLowPowerMode(_ enabled: Bool) async throws -> Bool
}

enum LowPowerModeClientError: LocalizedError {
    case helperUnavailable
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .helperUnavailable: "The power helper is not available."
        case let .rejected(reason): reason
        }
    }
}

struct UnavailableLowPowerModeClient: LowPowerModeClienting {
    func readLowPowerMode() async throws -> Bool {
        throw LowPowerModeClientError.helperUnavailable
    }

    func setLowPowerMode(_ enabled: Bool) async throws -> Bool {
        throw LowPowerModeClientError.helperUnavailable
    }
}
