import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct DockVisibilityMonitorTests {
    @Test func onScreenDockWindowIsVisible() {
        let dockPID: pid_t = 42
        let dockWindow = window(ownerPID: dockPID, layer: 20)

        #expect(DockVisibilityMonitor.isDockVisible(
            in: [dockWindow],
            onScreenWindows: [dockWindow],
            dockPID: dockPID
        ))
    }

    @Test func hiddenDockWindowIsNotVisible() {
        let dockPID: pid_t = 42
        let allWindows = [
            window(ownerPID: dockPID, layer: 20)
        ]
        let onScreenWindows = [
            window(ownerPID: 99, layer: 20)
        ]

        #expect(!DockVisibilityMonitor.isDockVisible(
            in: allWindows,
            onScreenWindows: onScreenWindows,
            dockPID: dockPID
        ))
    }

    @Test func anotherProcessCannotMakeTheDockVisible() {
        let dockPID: pid_t = 42
        let allWindows = [
            window(ownerPID: dockPID, layer: 20)
        ]
        let onScreenWindows = [
            window(ownerPID: 99, layer: 20)
        ]

        #expect(!DockVisibilityMonitor.isDockVisible(
            in: allWindows,
            onScreenWindows: onScreenWindows,
            dockPID: dockPID
        ))
    }

    @Test func unavailableDockWindowFailsOpen() {
        let dockPID: pid_t = 42

        #expect(DockVisibilityMonitor.isDockVisible(
            in: [],
            onScreenWindows: [],
            dockPID: dockPID
        ))
    }

    @Test func pollsItsOwnCadenceAndStopsAfterStop() async throws {
        let probe = VisibilityProbe()
        var changes: [Bool] = []
        let monitor = DockVisibilityMonitor(
            probe: {
                probe.probes += 1
                return probe.isVisible
            },
            pollingInterval: 0.01
        )
        monitor.onChange = { changes.append($0) }
        monitor.start()
        probe.isVisible = true

        try await Task.sleep(for: .milliseconds(80))
        #expect(monitor.isDockVisible)
        #expect(changes == [false, true])

        monitor.stop()
        let probesAfterStop = probe.probes
        try await Task.sleep(for: .milliseconds(50))
        #expect(probe.probes == probesAfterStop)
    }

    @Test func monitorPublishesOnlyVisibilityChanges() {
        let probe = VisibilityProbe()
        var changes: [Bool] = []
        let monitor = DockVisibilityMonitor(probe: { probe.isVisible })
        monitor.onChange = { changes.append($0) }

        monitor.start()
        probe.isVisible = true
        monitor.refresh()
        monitor.refresh()

        #expect(changes == [false, true])
        #expect(monitor.isDockVisible)
    }

    private func window(ownerPID: pid_t, layer: Int) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: NSNumber(value: ownerPID),
            kCGWindowLayer as String: NSNumber(value: layer)
        ]
    }
}

@MainActor
private final class VisibilityProbe {
    var isVisible = false
    var probes = 0
}
