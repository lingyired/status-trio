import AppKit
import Foundation
import XCTest
@testable import StatusTrioCore

private final class EnergyReadGate: @unchecked Sendable {
    private let lock = NSLock()
    let gate = DispatchSemaphore(value: 0)
    private var reads = 0
    var count: Int { lock.withLock { reads } }

    func read(_ apps: [EnergyApplication]) -> ApplicationEnergySnapshot {
        let count = lock.withLock { reads += 1; return reads }
        let readAt = ProcessInfo.processInfo.systemUptime
        _ = gate.wait(timeout: .now() + 5)
        return ApplicationEnergySnapshot(readAt: readAt, processes: apps.map {
            ProcessEnergySample(pid: 1, startedAt: 1, app: $0,
                cpuNanoseconds: UInt64(count) * 1_000_000_000,
                energyNanojoules: UInt64(count) * 1_000_000_000)
        })
    }
}

private final class ImmediateEnergyReader: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    var count: Int { lock.withLock { reads } }
    func read(_ apps: [EnergyApplication]) -> ApplicationEnergySnapshot {
        let count = lock.withLock { reads += 1; return reads }
        return ApplicationEnergySnapshot(readAt: ProcessInfo.processInfo.systemUptime, processes: apps.map {
            ProcessEnergySample(pid: 1, startedAt: 1, app: $0,
                cpuNanoseconds: UInt64(count) * 1_000_000_000,
                energyNanojoules: UInt64(count) * 1_000_000_000)
        })
    }
}

@MainActor
final class ApplicationEnergyControllerTests: XCTestCase {
    func testOptInPreparesRankingBeforeThePanelOpensAndOptOutStopsIt() async {
        let reader = ImmediateEnergyReader()
        let controller = ApplicationEnergyController(reader: { reader.read($0) },
            applications: { [EnergyApplication(id: "/App.app", name: "App")] })
        controller.setBackgroundMonitoringEnabled(true)
        await waitUntil { controller.ranking.phase == .ready }
        XCTAssertEqual(controller.ranking.apps.map(\.name), ["App"])
        let cached = controller.ranking
        controller.activate()
        XCTAssertEqual(controller.ranking, cached, "Opening presents the precomputed sample synchronously")
        controller.deactivate()
        XCTAssertEqual(controller.ranking, cached)
        controller.setBackgroundMonitoringEnabled(false)
        let reads = reader.count
        controller.refresh()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(reader.count, reads)
        XCTAssertTrue(controller.ranking.apps.isEmpty)
    }

    func testSleepDropsLateReadsAndWakeStartsWithAFreshBaseline() async {
        let reader = EnergyReadGate()
        let controller = ApplicationEnergyController(reader: { reader.read($0) },
            applications: { [EnergyApplication(id: "/App.app", name: "App")] })
        controller.setBackgroundMonitoringEnabled(true)
        await waitUntil { reader.count == 1 }
        controller.setSuspended(true)
        reader.gate.signal()
        try? await Task.sleep(for: .milliseconds(30))
        controller.refresh()
        XCTAssertEqual(reader.count, 1)
        XCTAssertTrue(controller.ranking.apps.isEmpty)
        controller.setSuspended(false)
        await waitUntil { reader.count == 2 }
        reader.gate.signal()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(controller.ranking.phase, .sampling)
        controller.stop()
    }

    func testAppOwnerBindsOptInPausesForSleepAndStopsAtShutdown() async throws {
        let suite = "ApplicationEnergyControllerTests.Owner.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.showsHighEnergyApps = true
        settings.highEnergyAppsRefreshIntervalSeconds = 30
        let reader = ImmediateEnergyReader()
        let controller = ApplicationEnergyController(reader: { reader.read($0) },
            applications: { [EnergyApplication(id: "/App.app", name: "App")] })
        let notifications = NotificationCenter()
        let store = SystemStatusStore(batteryMonitor: PanelBatteryMonitor(), wifiMonitor: PanelWiFiMonitor(),
            volumeMonitor: PanelVolumeMonitor(), wakeNotificationCenter: notifications,
            batteryDetails: BatteryDetailsController(reader: { _, _ in BatteryDetails() }, energyApps: controller))
        defer { store.stop() }
        store.bindApplicationEnergySettings(settings)
        XCTAssertEqual(reader.count, 0, "Binding before app start does not begin background work")
        store.start()
        XCTAssertEqual(controller.backgroundInterval, .seconds(30))
        settings.highEnergyAppsRefreshIntervalSeconds = 45
        XCTAssertEqual(controller.backgroundInterval, .seconds(45))
        await waitUntil { controller.ranking.phase == .ready }
        for (sleep, wake) in [(NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification),
                              (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification)] {
            notifications.post(name: sleep, object: nil)
            await waitUntil { controller.ranking.phase == .sampling }
            let count = reader.count
            controller.refresh()
            XCTAssertEqual(reader.count, count)
            if sleep == NSWorkspace.screensDidSleepNotification {
                // A network/dark wake is not evidence that the display woke.
                notifications.post(name: NSWorkspace.willSleepNotification, object: nil)
                notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
                try? await Task.sleep(for: .milliseconds(30))
                controller.refresh()
                XCTAssertEqual(reader.count, count, "Dark wake must leave display-sleep sampling paused")
            }
            notifications.post(name: wake, object: nil)
            await waitUntil { controller.ranking.phase == .ready }
        }
        notifications.post(name: NSWorkspace.willSleepNotification, object: nil)
        await waitUntil { controller.ranking.phase == .sampling }
        notifications.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        await waitUntil { controller.ranking.phase == .ready }
        notifications.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        await waitUntil { controller.ranking.phase == .sampling }
        store.setPopoverVisible(true)
        await waitUntil { controller.ranking.phase == .ready }
        store.setPopoverVisible(false)
        settings.showsHighEnergyApps = false
        XCTAssertTrue(controller.ranking.apps.isEmpty)
        let count = reader.count
        controller.refresh()
        XCTAssertEqual(reader.count, count)
        settings.showsHighEnergyApps = true
        await waitUntil { controller.ranking.phase == .ready }
        store.stop()
        let stopped = reader.count
        controller.refresh()
        settings.showsHighEnergyApps = false
        settings.showsHighEnergyApps = true
        XCTAssertEqual(reader.count, stopped)
        XCTAssertTrue(controller.ranking.apps.isEmpty)
    }

    func testChangingBackgroundIntervalReschedulesWithoutUsingTheOldCadence() async {
        let reader = ImmediateEnergyReader()
        let controller = ApplicationEnergyController(reader: { reader.read($0) },
            applications: { [EnergyApplication(id: "/App.app", name: "App")] },
            backgroundInterval: .milliseconds(20))
        controller.setBackgroundMonitoringEnabled(true)
        await waitUntil { controller.ranking.phase == .ready }
        // refresh() rejects intervals shorter than 0.5 seconds, so cross that
        // guard before asserting that the test cadence keeps producing samples.
        try? await Task.sleep(for: .milliseconds(650))
        XCTAssertGreaterThan(reader.count, 2, "The short test cadence should keep sampling")

        controller.setBackgroundInterval(.seconds(60))
        try? await Task.sleep(for: .milliseconds(30))
        let settled = reader.count
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(reader.count, settled, "Changing to 60 seconds must cancel the old cadence")
        controller.stop()
    }

    func testRecentRankingIsAvailableImmediatelyWhenThePanelReopens() async {
        let gate = EnergyReadGate()
        let controller = ApplicationEnergyController(reader: { gate.read($0) },
            applications: { [EnergyApplication(id: "/App.app", name: "App")] })
        controller.activate()
        await waitUntil { gate.count == 1 }
        gate.gate.signal()
        try? await Task.sleep(for: .milliseconds(600))
        controller.refresh()
        await waitUntil { gate.count == 2 }
        gate.gate.signal()
        await waitUntil { controller.ranking.phase == .ready }
        let cached = controller.ranking
        controller.deactivate()
        controller.activate()
        XCTAssertEqual(controller.ranking, cached, "Reopening must immediately present the recent real sample")
        controller.deactivate()
        gate.gate.signal()
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<1_000 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for energy reader")
    }

    func testDisabledCollectorDoesNotReadAndClosingDropsLateResultsAndQueuedReads() async {
        let gate = EnergyReadGate()
        let controller = ApplicationEnergyController(reader: { gate.read($0) },
            applications: { [EnergyApplication(id: "/App.app", name: "App")] })
        controller.refresh()
        XCTAssertEqual(gate.count, 0)
        controller.activate()
        await waitUntil { gate.count == 1 }
        for _ in 0..<20 { controller.refresh() }
        XCTAssertEqual(gate.count, 1)
        controller.deactivate()
        gate.gate.signal()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(gate.count, 1)
        XCTAssertTrue(controller.ranking.apps.isEmpty)
        controller.refresh()
        XCTAssertEqual(gate.count, 1)
    }

    func testReopeningNeverUsesThePreviousSessionBaseline() async {
        let gate = EnergyReadGate()
        let controller = ApplicationEnergyController(reader: { gate.read($0) },
            applications: { [EnergyApplication(id: "/App.app", name: "App")] })
        controller.activate()
        await waitUntil { gate.count == 1 }
        controller.deactivate()
        controller.activate()
        gate.gate.signal()
        await waitUntil { gate.count == 2 }
        XCTAssertTrue(controller.ranking.apps.isEmpty)
        gate.gate.signal()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(controller.ranking.phase, .sampling)
        controller.deactivate()
    }

    func testPublishedRankingExpiresWhileTheNextReadIsBlocked() async {
        let gate = EnergyReadGate()
        let controller = ApplicationEnergyController(reader: { gate.read($0) },
            applications: { [EnergyApplication(id: "/App.app", name: "App")] })
        controller.activate()
        await waitUntil { gate.count == 1 }
        gate.gate.signal()
        // Ensure the two actual samples form a nonzero observation interval.
        try? await Task.sleep(for: .milliseconds(600))
        controller.refresh()
        await waitUntil { gate.count == 2 }
        gate.gate.signal()
        await waitUntil { controller.ranking.phase == .ready }
        XCTAssertEqual(controller.ranking.apps.map(\.name), ["App"])
        controller.refresh(now: ProcessInfo.processInfo.systemUptime + 1)
        await waitUntil { gate.count == 3 }
        controller.refresh(now: ProcessInfo.processInfo.systemUptime + 16)
        XCTAssertTrue(controller.ranking.apps.isEmpty)
        XCTAssertEqual(controller.ranking.phase, .sampling)
        controller.deactivate()
        gate.gate.signal()
    }
}
