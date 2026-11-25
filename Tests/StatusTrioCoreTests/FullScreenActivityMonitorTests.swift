import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct FullScreenActivityMonitorTests {
    private func makeMonitor(
        probe: @escaping @MainActor () -> Bool
    ) -> FullScreenActivityMonitor {
        FullScreenActivityMonitor(
            probe: probe,
            workspaceNotificationCenter: NotificationCenter(),
            defaultNotificationCenter: NotificationCenter(),
            timing: FullScreenActivityMonitor.Timing { _, action in
                MainActor.assumeIsolated { action() }
            }
        )
    }

    @Test
    func startSeedsTheCurrentState() {
        let monitor = makeMonitor(probe: { true })
        monitor.start()
        #expect(monitor.isFullScreenActive)
        monitor.stop()
    }

    @Test
    func exitingFullScreenInvokesTheCallbackOnce() {
        var fullScreen = true
        let monitor = makeMonitor(probe: { fullScreen })
        monitor.start()

        var exitCount = 0
        monitor.onExitFullScreen = { exitCount += 1 }

        fullScreen = false
        monitor.reevaluate()
        #expect(exitCount == 1)

        monitor.reevaluate()
        #expect(exitCount == 1)
    }

    @Test
    func enteringOrStayingInFullScreenDoesNotInvokeTheCallback() {
        var fullScreen = false
        let monitor = makeMonitor(probe: { fullScreen })
        monitor.start()

        var exitCount = 0
        monitor.onExitFullScreen = { exitCount += 1 }

        fullScreen = true
        monitor.reevaluate()
        #expect(exitCount == 0)

        monitor.reevaluate()
        #expect(exitCount == 0)
    }
}
