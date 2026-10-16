import Foundation
import PowerHelperProtocol

/// Accepts XPC connections from the app and exports the power-mode service.
///
/// The listener itself carries the code-signing requirement
/// (`setConnectionCodeSigningRequirement`), so a mismatched peer is rejected by
/// Foundation before this delegate runs. The delegate re-checks the caller as
/// defense in depth and logs any rejection.
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: PowerModeService
    private let idleExit: IdleExitMonitor?

    init(service: PowerModeService, idleExit: IdleExitMonitor? = nil) {
        self.service = service
        self.idleExit = idleExit
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard ClientAuthorization.isCallerAllowed(connection) else {
            NSLog(
                "StatusTrioPowerHelper rejected connection from pid %d",
                connection.processIdentifier
            )
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: PowerHelperXPCProtocol.self)
        connection.exportedObject = service
        // Every accepted connection is a reason for this root process to exist.
        // Counting them lets the daemon exit once the app is done with it,
        // including when the app quits without invalidating its connection.
        if let idleExit {
            idleExit.connectionOpened()
            let lifetime = ConnectionLifetime { idleExit.connectionClosed() }
            connection.invalidationHandler = { lifetime.end() }
            connection.interruptionHandler = { lifetime.end() }
        }
        connection.resume()
        return true
    }
}
