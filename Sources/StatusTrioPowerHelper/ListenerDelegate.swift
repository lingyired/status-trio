import Darwin
import Foundation
import PowerHelperProtocol

/// Accepts XPC connections from the app and exports the power services.
///
/// The listener itself carries the code-signing requirement
/// (`setConnectionCodeSigningRequirement`), so a mismatched peer is rejected by
/// Foundation before this delegate runs. The delegate re-checks the caller as
/// defense in depth and logs any rejection.
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let lowPowerMode: PowerModeService
    private let legacy: LegacyChargeLimitService?
    private let idleExit: IdleExitMonitor?
    private let buildWatchdog: HelperBuildWatchdog

    init(
        lowPowerMode: PowerModeService,
        legacy: LegacyChargeLimitService? = nil,
        idleExit: IdleExitMonitor? = nil,
        buildWatchdog: HelperBuildWatchdog = HelperBuildWatchdog()
    ) {
        self.lowPowerMode = lowPowerMode
        self.legacy = legacy
        self.idleExit = idleExit
        self.buildWatchdog = buildWatchdog
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // If the app bundle on disk was replaced while this process kept the old
        // binary loaded, serving this connection would run stale code. Exit so
        // launchd relaunches the freshly installed helper on the next connection.
        if buildWatchdog.isStale() {
            NSLog(
                "StatusTrioPowerHelper: app bundle changed on disk; exiting so launchd relaunches the updated helper"
            )
            exit(0)
        }
        guard ClientAuthorization.isCallerAllowed(connection) else {
            NSLog(
                "StatusTrioPowerHelper rejected connection from pid %d",
                connection.processIdentifier
            )
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: PowerHelperCombinedXPCProtocol.self)
        // One proxy per connection: it owns this connection's hardware
        // ownership id, so only this connection can release its own cap.
        let chargeConnection = LegacyChargeConnection(service: legacy)
        connection.exportedObject = PowerHelperService(
            lowPowerMode: lowPowerMode,
            legacy: chargeConnection
        )
        // Every accepted connection is a reason for this root process to exist.
        // Counting them lets the daemon exit once the app is done with it,
        // including when the app quits without invalidating its connection.
        if let idleExit {
            idleExit.connectionOpened()
            let lifetime = ConnectionLifetime { [chargeConnection] in
                // A client that vanishes can leave the battery inhibited. Put
                // the stock values back before the process is allowed to exit;
                // the restore is bounded and journal-backed. Only this
                // connection's cap is released, so an unrelated Low Power Mode
                // session ending cannot disturb it.
                chargeConnection.release()
                idleExit.connectionClosed()
            }
            connection.invalidationHandler = { lifetime.end() }
            connection.interruptionHandler = { lifetime.end() }
        }
        connection.resume()
        return true
    }
}