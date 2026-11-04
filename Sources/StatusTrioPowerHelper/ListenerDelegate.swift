import Foundation
import PowerHelperProtocol

/// Accepts XPC connections from the app and exports the power services.
///
/// The listener itself carries the code-signing requirement
/// (`setConnectionCodeSigningRequirement`), so a mismatched peer is rejected by
/// Foundation before this delegate runs. The delegate re-checks the caller as
/// defense in depth and logs any rejection.
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: PowerHelperService
    private let legacy: LegacyChargeLimitService?
    private let idleExit: IdleExitMonitor?

    init(
        service: PowerHelperService,
        legacy: LegacyChargeLimitService? = nil,
        idleExit: IdleExitMonitor? = nil
    ) {
        self.service = service
        self.legacy = legacy
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
        connection.exportedInterface = NSXPCInterface(with: PowerHelperCombinedXPCProtocol.self)
        connection.exportedObject = service
        // Every accepted connection is a reason for this root process to exist.
        // Counting them lets the daemon exit once the app is done with it,
        // including when the app quits without invalidating its connection.
        if let idleExit {
            idleExit.connectionOpened()
            let lifetime = ConnectionLifetime { [legacy] in
                // A client that vanishes can leave the battery inhibited. Put
                // the stock values back before the process is allowed to exit;
                // the restore is bounded and journal-backed. A failed restore is
                // logged and the journal is retained so the next app launch can
                // reconcile and retry; it is never reported as success.
                let restored = legacy?.restoreForClientLoss() ?? true
                if !restored {
                    NSLog("StatusTrioPowerHelper: charge restore is pending after client loss")
                }
                idleExit.connectionClosed()
            }
            connection.invalidationHandler = { lifetime.end() }
            connection.interruptionHandler = { lifetime.end() }
        }
        connection.resume()
        return true
    }
}