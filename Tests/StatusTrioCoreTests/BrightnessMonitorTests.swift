import AppKit
import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class BrightnessMonitorTests: XCTestCase {
    private final class FakeCatalog: DisplayCatalogProviding {
        var displays: [DisplayDescriptor]
        init(_ displays: [DisplayDescriptor]) { self.displays = displays }
        func currentDisplays() -> [DisplayDescriptor] { displays }
    }

    private final class QuietTransport: DDCFeatureTransport, @unchecked Sendable {
        private let readLock = NSLock()
        private var readCount = 0
        var featureReadCount: Int {
            readLock.lock()
            defer { readLock.unlock() }
            return readCount
        }
        func resolve(uid: String) -> DDCDisplayTarget? { DDCDisplayTarget(uid: uid, service: nil) }
        func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult { .reply(DDCVolumeReply(current: 50, maximum: 100)) }
        func read(_ target: DDCDisplayTarget, feature: UInt8) -> DDCVolumeReadResult {
            readLock.lock()
            readCount += 1
            readLock.unlock()
            return read(target)
        }
        func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool { true }
        func write(_ target: DDCDisplayTarget, value: UInt16, feature: UInt8) -> Bool { true }
    }

    private final class QuietBetterDisplayClient: BetterDisplayRequesting {
        func start(onEvent: @escaping @MainActor (BetterDisplayEvent) -> Void) {}
        func stop() {}
        func request(commands: [String], parameters: [String: String?]) async throws -> String? {
            "0.5,0,1"
        }
    }

    private final class CountingBetterDisplayClient: BetterDisplayRequesting {
        private(set) var requestCount = 0
        func start(onEvent: @escaping @MainActor (BetterDisplayEvent) -> Void) {}
        func stop() {}
        func request(commands: [String], parameters: [String: String?]) async throws -> String? {
            requestCount += 1
            return "0.5,0,1"
        }
    }

    private func descriptor(_ id: String) -> DisplayDescriptor {
        DisplayDescriptor(id: id, name: id, isBuiltin: false, displayID: 1)
    }

    func testTopologyChangeRebuildsAndDropsRetainedBackend() {
        let catalog = FakeCatalog([descriptor("A")])
        var made: [DDCBrightnessCoordinator] = []
        let monitor = BrightnessMonitor(
            catalog: catalog,
            makeDDC: { _, onUpdate in
                let coordinator = DDCBrightnessCoordinator(
                    transport: QuietTransport(), pollInterval: .seconds(600), onUpdate: onUpdate
                )
                made.append(coordinator)
                return coordinator
            }
        )
        monitor.start()
        monitor.setDetailsVisible(true)
        XCTAssertEqual(made.count, 1, "Opening the section builds one backend per display")
        let first = made[0]
        let firstGeneration = first.generation

        catalog.displays = [descriptor("A"), descriptor("B")]
        monitor.topologyChanged()

        XCTAssertGreaterThan(first.generation, firstGeneration,
                             "The retained display's old backend must be invalidated on a topology change")
        XCTAssertEqual(made.count, 3, "A hot-plug rebuilds the retained backend and adds the new display")
        monitor.stop()
    }

    func testScreenParameterNotificationTriggersTopologyRebuild() {
        let catalog = FakeCatalog([descriptor("A")])
        let center = NotificationCenter()
        var made: [DDCBrightnessCoordinator] = []
        let monitor = BrightnessMonitor(
            catalog: catalog,
            makeDDC: { _, onUpdate in
                let coordinator = DDCBrightnessCoordinator(
                    transport: QuietTransport(), pollInterval: .seconds(600), onUpdate: onUpdate
                )
                made.append(coordinator)
                return coordinator
            },
            notificationCenter: center
        )
        monitor.start()
        monitor.setDetailsVisible(true)
        XCTAssertEqual(made.count, 1)

        catalog.displays = [descriptor("A"), descriptor("B")]
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        let rebuilt = expectation(description: "screen notification rebuilds the brightness list")
        DispatchQueue.main.async { rebuilt.fulfill() }
        wait(for: [rebuilt], timeout: 2)
        XCTAssertEqual(made.count, 3, "The screen-parameters notification must rebuild the list")
        monitor.stop()
    }

    func testBuiltInDisplayKeepsItsDescriptorUUIDForBetterDisplay() {
        let builtin = DisplayDescriptor(id: "cg-uuid", name: "Built-in", isBuiltin: true, displayID: 5)
        let resolved = BrightnessMonitor.resolvedBetterDisplayUUID(
            for: builtin,
            cgUUID: { _ in "unused-cg-uuid" }
        )
        XCTAssertEqual(
            resolved, "cg-uuid",
            "Built-in displays are already keyed by the CG UUID BetterDisplay uses"
        )
    }

    func testExternalDisplayResolvesTheCGUUIDNotTheEDIDUUID() {
        let external = DisplayDescriptor(
            id: "EDID-UUID",
            name: "External",
            isBuiltin: false,
            displayID: 7
        )
        let resolved = BrightnessMonitor.resolvedBetterDisplayUUID(
            for: external,
            cgUUID: { displayID in
                XCTAssertEqual(displayID, 7)
                return "CG-UUID"
            }
        )
        XCTAssertEqual(
            resolved, "CG-UUID",
            "BetterDisplay addresses external displays by CG UUID, not the EDID UUID"
        )
        XCTAssertNotEqual(resolved, external.id)
    }

    func testExternalDisplayWithNoCGUUIDFailsClosed() {
        let external = DisplayDescriptor(id: "EDID-UUID", name: "External", isBuiltin: false, displayID: 7)
        let resolved = BrightnessMonitor.resolvedBetterDisplayUUID(
            for: external,
            cgUUID: { _ in "display-7" }
        )
        // `display-<id>` is the catalog's failure sentinel, not a real CG UUID.
        // BetterDisplay cannot address the display, so it must be unavailable
        // rather than silently falling back to some other identity.
        XCTAssertNil(resolved)
    }

    func testExternalDisplayWithZeroDisplayIDNeverResolvesAndNeverQueriesCG() {
        let external = DisplayDescriptor(id: "EDID-UUID", name: "External", isBuiltin: false, displayID: 0)
        var called = false
        let resolved = BrightnessMonitor.resolvedBetterDisplayUUID(
            for: external,
            cgUUID: { _ in
                called = true
                return "CG-UUID"
            }
        )
        XCTAssertNil(resolved, "displayID 0 must not be turned into a CG UUID")
        XCTAssertFalse(called, "CGDisplayCreateUUIDFromDisplayID(0) would target the built-in display")
    }

    func testExplicitBetterDisplayUUIDWinsEvenWithoutACGID() {
        let external = DisplayDescriptor(id: "EDID-UUID", name: "External", isBuiltin: false, displayID: 0)
        var called = false
        let resolved = BrightnessMonitor.resolvedBetterDisplayUUID(
            for: external,
            explicit: "EXPLICIT-UUID",
            cgUUID: { _ in
                called = true
                return "CG-UUID"
            }
        )
        XCTAssertEqual(resolved, "EXPLICIT-UUID")
        XCTAssertFalse(called)
    }

    func testDirectDDCUsesEDIDIdentityWhileBetterDisplayUsesCGUUID() {
        let external = DisplayDescriptor(id: "EDID-UUID", name: "XV272U", isBuiltin: false, displayID: 5)
        var ddcIDs: [String] = []
        let monitor = BrightnessMonitor(
            catalog: FakeCatalog([external]),
            makeDDC: { id, onUpdate in
                ddcIDs.append(id)
                return DDCBrightnessCoordinator(
                    transport: QuietTransport(), pollInterval: .seconds(600), onUpdate: onUpdate
                )
            }
        )
        monitor.start()
        monitor.setDetailsVisible(true)
        XCTAssertEqual(ddcIDs, ["EDID-UUID"], "DDC keys on the EDID UUID")
        XCTAssertEqual(
            BrightnessMonitor.resolvedBetterDisplayUUID(for: external, cgUUID: { id in
                XCTAssertEqual(id, 5)
                return "CG-UUID"
            }),
            "CG-UUID",
            "BetterDisplay keys on the real CG UUID for the same display"
        )
        monitor.stop()
    }

    func testForcedRebuildRecreatesControllerWhenDescriptorIdentityChanges() {
        let catalog = FakeCatalog([
            DisplayDescriptor(id: "CG-1", name: "External", isBuiltin: false, displayID: 5)
        ])
        var madeIDs: [String] = []
        let monitor = BrightnessMonitor(
            catalog: catalog,
            makeDDC: { id, onUpdate in
                madeIDs.append(id)
                return DDCBrightnessCoordinator(
                    transport: QuietTransport(), pollInterval: .seconds(600), onUpdate: onUpdate
                )
            }
        )
        monitor.start()
        monitor.setDetailsVisible(true)
        XCTAssertEqual(madeIDs, ["CG-1"])

        // A reconnect can change the descriptor identity (e.g. a new CG UUID
        // while the old one is gone). The forced rebuild must drop and recreate
        // the backend rather than reuse the stale one.
        catalog.displays = [
            DisplayDescriptor(id: "CG-2", name: "External", isBuiltin: false, displayID: 7)
        ]
        monitor.topologyChanged()

        XCTAssertEqual(madeIDs, ["CG-1", "CG-2"])
        monitor.stop()
    }

    func testExternalDisplayServicesWithZeroDisplayIDFailsClosed() {
        let external = DisplayDescriptor(id: "EDID-UUID", name: "External", isBuiltin: false, displayID: 0)
        let monitor = BrightnessMonitor(
            catalog: FakeCatalog([external]),
            makeDDC: { _, onUpdate in
                DDCBrightnessCoordinator(
                    transport: QuietTransport(), pollInterval: .seconds(600), onUpdate: onUpdate
                )
            },
            makeDisplayServices: { _, _ in
                XCTFail("DisplayServices must not be constructed for displayID 0")
                return DisplayServicesBrightnessController(displayID: 0) { _ in }
            }
        )
        monitor.setExternalBrightnessConfigurations([
            "EDID-UUID": ExternalBrightnessConfiguration(backend: .displayServices, betterDisplayUUID: nil)
        ])
        monitor.start()
        monitor.setDetailsVisible(true)

        let status = latestStatus(monitor)
        XCTAssertEqual(status?.displays.first?.source, .unavailable(.noBackend))
        XCTAssertEqual(status?.displays.first?.canAdjust, false)
        monitor.stop()
    }

    func testNonForcedRebuildRecreatesBackendWhenDisplayIDChanges() {
        let catalog = FakeCatalog([
            DisplayDescriptor(id: "EDID-UUID", name: "External", isBuiltin: false, displayID: 5)
        ])
        var madeIDs: [String] = []
        let monitor = BrightnessMonitor(
            catalog: catalog,
            makeDDC: { id, onUpdate in
                madeIDs.append(id)
                return DDCBrightnessCoordinator(
                    transport: QuietTransport(), pollInterval: .seconds(600), onUpdate: onUpdate
                )
            }
        )
        monitor.start()
        monitor.setDetailsVisible(true)
        XCTAssertEqual(madeIDs.count, 1)

        // Same descriptor id, different resolved CG display id (e.g. mapping
        // became available or the display moved). Reusing the old controller
        // would target the old screen, so a rebuild must recreate it.
        catalog.displays = [
            DisplayDescriptor(id: "EDID-UUID", name: "External", isBuiltin: false, displayID: 7)
        ]
        monitor.setBackend(.directDDC, forDisplayID: "EDID-UUID")
        XCTAssertEqual(madeIDs.count, 2)
        monitor.stop()
    }

    func testUnmappedBetterDisplayNeverConstructsBackendAndPublishesUnavailable() {
        let external = DisplayDescriptor(id: "EDID", name: "External", isBuiltin: false, displayID: 0)
        var madeUUIDs: [String] = []
        let monitor = BrightnessMonitor(
            catalog: FakeCatalog([external]),
            makeBetterDisplay: { uuid, update in
                madeUUIDs.append(uuid)
                return BetterDisplayBrightnessCoordinator(
                    client: QuietBetterDisplayClient(), displayUUID: uuid, onUpdate: update
                )
            }
        )
        monitor.setBackend(.betterDisplay, forDisplayID: "EDID")
        monitor.start()
        monitor.setDetailsVisible(true)
        XCTAssertTrue(madeUUIDs.isEmpty)
        let state = latestStatus(monitor)?.displays.first
        XCTAssertEqual(state?.source, .unavailable(.noBackend))
        XCTAssertEqual(state?.canAdjust, false)
        monitor.setBrightness(0.8, forDisplayID: "EDID")
        monitor.refresh()
        XCTAssertTrue(madeUUIDs.isEmpty)
        monitor.stop()
    }

    func testExplicitBetterDisplayUUIDConstructsBackendForUnmappedDisplay() {
        let external = DisplayDescriptor(id: "EDID", name: "External", isBuiltin: false, displayID: 0)
        var madeUUIDs: [String] = []
        let monitor = BrightnessMonitor(
            catalog: FakeCatalog([external]),
            makeBetterDisplay: { uuid, update in
                madeUUIDs.append(uuid)
                return BetterDisplayBrightnessCoordinator(
                    client: QuietBetterDisplayClient(), displayUUID: uuid, onUpdate: update
                )
            }
        )
        monitor.setExternalBrightnessConfigurations([
            "EDID": ExternalBrightnessConfiguration(backend: .betterDisplay, betterDisplayUUID: "EXPLICIT")
        ])
        monitor.start()
        monitor.setDetailsVisible(true)
        XCTAssertEqual(madeUUIDs, ["EXPLICIT"])
        monitor.stop()
    }

    func testDisplayServicesControllerRejectsZeroDisplayID() {
        var updates: [DisplayServicesBrightnessUpdate] = []
        let controller = DisplayServicesBrightnessController(displayID: 0) { updates.append($0) }
        controller.start()
        XCTAssertEqual(updates.last?.source, .unavailable(.noBackend))
        XCTAssertEqual(updates.last?.canAdjust, false)
        controller.stop()
    }

    func testAutomaticBackendFollowsBetterDisplayRunningState() {
        var running = false
        var ddcMade = 0
        var betterDisplayMade = 0
        let external = DisplayDescriptor(id: "EDID", name: "External", isBuiltin: false, displayID: 5)
        let monitor = BrightnessMonitor(
            catalog: FakeCatalog([external]),
            makeDDC: { _, onUpdate in
                ddcMade += 1
                return DDCBrightnessCoordinator(
                    transport: QuietTransport(), pollInterval: .seconds(600), onUpdate: onUpdate
                )
            },
            makeBetterDisplay: { uuid, update in
                betterDisplayMade += 1
                return BetterDisplayBrightnessCoordinator(
                    client: QuietBetterDisplayClient(), displayUUID: uuid, onUpdate: update
                )
            },
            defaultExternalBackend: .automatic,
            isBetterDisplayRunning: { running },
            workspaceNotificationCenter: NotificationCenter()
        )
        monitor.setExternalBrightnessConfigurations([
            "EDID": ExternalBrightnessConfiguration(
                backend: .automatic, betterDisplayUUID: "EXPLICIT"
            )
        ])
        monitor.start()
        monitor.setDetailsVisible(true)
        XCTAssertEqual(ddcMade, 1)
        XCTAssertEqual(betterDisplayMade, 0)
        XCTAssertEqual(latestStatus(monitor)?.displays.first?.backend, .directDDC)

        running = true
        monitor.betterDisplayAvailabilityChanged()
        XCTAssertEqual(betterDisplayMade, 1)
        XCTAssertEqual(latestStatus(monitor)?.displays.first?.backend, .betterDisplay)

        running = false
        monitor.betterDisplayAvailabilityChanged()
        XCTAssertEqual(ddcMade, 2)
        XCTAssertEqual(betterDisplayMade, 1)
        XCTAssertEqual(latestStatus(monitor)?.displays.first?.backend, .directDDC)
        monitor.stop()
    }

    func testVisibleFallbackLoopLeavesDDCOnItsOwnTimer() async {
        let transport = QuietTransport()
        let sleeper = ManualEventSleeper()
        let client = CountingBetterDisplayClient()
        var ddc: DDCBrightnessCoordinator?
        let monitor = BrightnessMonitor(
            catalog: FakeCatalog([descriptor("DDC"), descriptor("BD")]),
            makeDDC: { _, onUpdate in
                let coordinator = DDCBrightnessCoordinator(
                    transport: transport, pollInterval: .seconds(600), onUpdate: onUpdate
                )
                ddc = coordinator
                return coordinator
            },
            makeBetterDisplay: { uuid, update in
                BetterDisplayBrightnessCoordinator(client: client, displayUUID: uuid, onUpdate: update)
            },
            externalRefreshSleep: { await sleeper.sleep($0) }
        )
        monitor.setExternalBrightnessConfigurations([
            "BD": ExternalBrightnessConfiguration(backend: .betterDisplay, betterDisplayUUID: "UUID")
        ])
        monitor.start()
        monitor.setDetailsVisible(true)
        await ddc?.waitForWorkerIdle()
        XCTAssertEqual(transport.featureReadCount, 1)
        let waiting = await sleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertTrue(waiting)
        await waitForRequests(client, count: 1)
        sleeper.releaseOldest()
        await waitForRequests(client, count: 2)
        await ddc?.waitForWorkerIdle()
        XCTAssertEqual(
            transport.featureReadCount, 1,
            "the fallback reads BetterDisplay without bypassing DDC's own timer or failure backoff"
        )
        monitor.stop()
        sleeper.releaseAll()
    }

    func testExternalBackendRefreshesWhileVisibleAndStopsWhenHidden() async {
        let client = CountingBetterDisplayClient()
        let external = DisplayDescriptor(id: "EDID", name: "External", isBuiltin: false, displayID: 5)
        let monitor = BrightnessMonitor(
            catalog: FakeCatalog([external]),
            makeBetterDisplay: { uuid, update in
                BetterDisplayBrightnessCoordinator(client: client, displayUUID: uuid, onUpdate: update)
            },
            externalRefreshInterval: .milliseconds(20),
            externalRefreshSleep: { try await Task.sleep(for: $0) }
        )
        monitor.setExternalBrightnessConfigurations([
            "EDID": ExternalBrightnessConfiguration(backend: .betterDisplay, betterDisplayUUID: "UUID")
        ])
        monitor.start()
        monitor.setDetailsVisible(true)
        try? await Task.sleep(for: .milliseconds(120))
        let visibleReads = client.requestCount
        XCTAssertGreaterThan(visibleReads, 1, "external changes have no push notification; visible polling must refresh")

        monitor.setDetailsVisible(false)
        let hiddenReads = client.requestCount
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(client.requestCount, hiddenReads, "hiding the panel must stop external polling")
        XCTAssertLessThanOrEqual(hiddenReads, visibleReads + 1)
        monitor.stop()
    }

    private func waitForRequests(_ client: CountingBetterDisplayClient, count: Int) async {
        for _ in 0..<1000 {
            if client.requestCount >= count { return }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private func latestStatus(_ monitor: BrightnessMonitor) -> BrightnessStatus? {
        let expectation = expectation(description: "monitor publishes a status")
        var result: BrightnessStatus?
        let task = Task { @MainActor in
            for await status in monitor.updates {
                result = status
                expectation.fulfill()
                break
            }
        }
        wait(for: [expectation], timeout: 2)
        task.cancel()
        return result
    }
}
