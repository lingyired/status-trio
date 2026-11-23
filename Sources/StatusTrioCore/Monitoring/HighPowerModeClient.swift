import Foundation

/// The app's view of the helper's High Power Mode surface. Injected so the
/// controller can be exercised without a registered daemon.
protocol HighPowerModeClienting: Sendable {
    /// The XPC protocol version the running daemon reports.
    func protocolVersion() async throws -> Int
    /// Whether this Mac reports High Power Mode support (`pmset -g cap`).
    func highPowerModeSupported() async throws -> Bool
    /// The current High Power Mode state.
    func readHighPowerMode() async throws -> Bool
    /// Sets High Power Mode and returns the state the daemon observed after.
    func setHighPowerMode(_ enabled: Bool) async throws -> Bool
    /// Whether the daemon still answers the original Low Power Mode read.
    ///
    /// A missing answer is the one signal that separates "this helper predates
    /// the version handshake" (it still reads Low Power Mode but cannot name a
    /// version) from "there is no helper at all".
    func canReadLowPowerMode() async -> Bool
}

enum HighPowerModeClientError: LocalizedError {
    case helperUnavailable
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .helperUnavailable: "The power helper is not available."
        case let .rejected(reason): reason
        }
    }
}

/// The app's view of the helper's `disablesleep` surface (#295). Reuses the same
/// XPC connection plumbing as the power-mode client; the daemon must be protocol
/// version `PowerHelperProtocolVersion.disableSleep` or newer.
protocol DisableSleepClienting: Sendable {
    /// The XPC protocol version the running daemon reports.
    func protocolVersion() async throws -> Int
    /// Whether `pmset -a disablesleep 1` is currently in effect.
    func readDisableSleep() async throws -> Bool
    /// Sets `disablesleep` and returns the state the daemon observed afterwards.
    func setDisableSleep(_ enabled: Bool) async throws -> Bool
}

final class UnavailableHighPowerModeClient: HighPowerModeClienting, Sendable {
    func protocolVersion() async throws -> Int { throw HighPowerModeClientError.helperUnavailable }
    func highPowerModeSupported() async throws -> Bool { throw HighPowerModeClientError.helperUnavailable }
    func readHighPowerMode() async throws -> Bool { throw HighPowerModeClientError.helperUnavailable }
    func setHighPowerMode(_ enabled: Bool) async throws -> Bool { throw HighPowerModeClientError.helperUnavailable }
    func canReadLowPowerMode() async -> Bool { false }
}

final class UnavailableDisableSleepClient: DisableSleepClienting, Sendable {
    func protocolVersion() async throws -> Int { throw HighPowerModeClientError.helperUnavailable }
    func readDisableSleep() async throws -> Bool { throw HighPowerModeClientError.helperUnavailable }
    func setDisableSleep(_ enabled: Bool) async throws -> Bool { throw HighPowerModeClientError.helperUnavailable }
}
