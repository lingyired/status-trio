import Foundation

/// Abstraction over the privileged power helper that shared controllers/UI use.
///
/// Direct injects `PrivilegedHelperManager.shared`; the App Store target injects
/// `UnavailablePrivilegedHelper` so the shared source never references the
/// Direct-only manager (which owns LaunchDaemon registration and XPC).
@MainActor
protocol PrivilegedHelperControlling: AnyObject, Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
    func refreshAfterActivation()
}

/// Fallback used where no privileged helper is available (Store / tests).
@MainActor
final class UnavailablePrivilegedHelper: PrivilegedHelperControlling {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) {}
    func refreshAfterActivation() {}
}
