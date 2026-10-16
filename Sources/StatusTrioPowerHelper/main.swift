import Foundation
import PowerHelperProtocol

// Privileged LaunchDaemon entry point. Runs as root under launchd, started on
// demand when the app first connects to the Mach service and idle-exits when no
// connection remains. It never daemonizes itself: launchd owns the service name.

// launchd keeps an on-demand job running until the job exits itself, so the
// daemon owns its own lifetime: the monitor ends the process once the app's
// connections are gone instead of leaving a root daemon behind.
let idleExit = IdleExitMonitor()
let delegate = ListenerDelegate(service: PowerModeService(), idleExit: idleExit)
let listener = NSXPCListener(machServiceName: PowerHelperConstants.machServiceName)
listener.delegate = delegate
// Authoritative client gate: Foundation evaluates this against the peer's audit
// token before consulting the delegate, so a wrongly signed caller never
// reaches the service. A malformed requirement throws here, which fails the
// daemon loudly rather than silently accepting every client.
listener.setConnectionCodeSigningRequirement(ClientRequirement.string)
listener.activate()
idleExit.start()
dispatchMain()
