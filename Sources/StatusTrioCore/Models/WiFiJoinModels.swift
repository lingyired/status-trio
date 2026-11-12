import Foundation

/// How a join obtains the passphrase. A typed password only ever travels as a
/// function argument; it is never part of any published state.
enum WiFiJoinCredential: Equatable, Sendable {
    /// An open network: no passphrase.
    case none
    /// The passphrase this app saved after an earlier successful join.
    case stored
    /// A passphrase the person just typed.
    case typed(String)
}

/// What the CoreWLAN worker reports for one join attempt.
enum WiFiJoinOutcome: Equatable, Sendable {
    case joined
    /// No saved passphrase exists, so the person has to type one.
    case needsPassword
    /// A directed scan did not find the network.
    case notInRange
    /// The system refused the association (wrong passphrase, weak signal that
    /// timed out, or a refusal before authentication).
    case rejected
    /// No interface, the radio is off, or the scan itself failed.
    case unavailable
}

enum WiFiJoinFailure: Equatable, Sendable {
    case notInRange
    case rejected
    case unavailable
}

/// The join flow as the controller publishes it. It names the network by its
/// identity only; the passphrase is never in this state.
enum WiFiJoinState: Equatable, Sendable {
    case idle
    case joining(WiFiNetworkIdentity)
    /// `retry` is true when the previous attempt with a passphrase was refused,
    /// so the form can say so.
    case needsPassword(WiFiNetworkIdentity, retry: Bool)
    case failed(WiFiNetworkIdentity, WiFiJoinFailure)

    var isJoining: Bool {
        if case .joining = self { return true }
        return false
    }
}
