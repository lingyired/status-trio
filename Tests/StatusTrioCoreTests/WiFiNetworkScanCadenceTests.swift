import Foundation
import XCTest
@testable import StatusTrioCore

/// A full `scanForNetworks(withSSID: nil)` sweeps every channel, and it used to
/// run on every Wi-Fi status yield, which is about every five seconds. These
/// tests pin the interval that now floors the automatic path, the explicit path
/// that bypasses it, and the single flight that keeps a running scan from being
/// duplicated.
@MainActor
final class WiFiNetworkScanCadenceTests: XCTestCase {
    private func makeController(
        scanner: FakeWiFiNetworkScanner,
        clock: ManualScanClock = ManualScanClock(),
        minimumScanInterval: TimeInterval = 120,
        periodicRefreshSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) -> WiFiNetworkController {
        WiFiNetworkController(
            scanWorker: scanner,
            now: { clock.now },
            minimumScanInterval: minimumScanInterval,
            periodicRefreshSleep: periodicRefreshSleep
        )
    }

    func testDeniedPermissionNeverScansAndGrantRefreshesImmediately() async {
        let scanner = FakeWiFiNetworkScanner()
        let controller = makeController(scanner: scanner)
        controller.activate(nameAccess: .denied)
        await waitUntil { controller.state == .permissionDenied }
        XCTAssertEqual(scanner.scanCount, 0)
        controller.refreshNow(nameAccess: .denied)
        await Task.yield()
        XCTAssertEqual(scanner.scanCount, 0)
        controller.refresh(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }
        XCTAssertEqual(scanner.scanCount, 1)
        controller.refresh(nameAccess: .restricted)
        await waitUntil { controller.state == .permissionDenied }
        XCTAssertTrue(controller.networks.isEmpty)
        XCTAssertEqual(scanner.scanCount, 1)
        controller.deactivate()
    }

    func testActivationScansOnce() async {
        let scanner = FakeWiFiNetworkScanner()
        let controller = makeController(scanner: scanner)

        controller.activate(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }

        XCTAssertEqual(scanner.scanCount, 1)
        XCTAssertEqual(controller.networks.map(\.ssid), ["Studio"])
        controller.deactivate()
    }

    /// The status-yield path: five yields inside the interval reuse the cached
    /// list instead of sweeping the channels five more times.
    func testStatusYieldsReuseTheCachedScanInsideTheInterval() async {
        let scanner = FakeWiFiNetworkScanner()
        let clock = ManualScanClock()
        let controller = makeController(scanner: scanner, clock: clock)
        controller.activate(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }

        for _ in 0..<5 {
            clock.advance(by: 1)
            controller.refresh(nameAccess: .authorized)
        }
        await Task.yield()

        XCTAssertEqual(scanner.scanCount, 1)
        XCTAssertEqual(controller.networks.map(\.ssid), ["Studio"])
        controller.deactivate()
    }

    func testAutomaticRefreshScansAgainAfterTheInterval() async {
        let scanner = FakeWiFiNetworkScanner()
        let clock = ManualScanClock()
        let controller = makeController(scanner: scanner, clock: clock)
        controller.activate(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }

        scanner.result = .success(WiFiScanPayload(
            networks: [makeScanNetwork("Guest", known: false)],
            details: .unavailable
        ))
        clock.advance(by: 119)
        controller.refresh(nameAccess: .authorized)
        await Task.yield()
        XCTAssertEqual(scanner.scanCount, 1, "inside the interval the cached list is reused")

        clock.advance(by: 1)
        controller.refresh(nameAccess: .authorized)
        await waitUntil { scanner.scanCount == 2 }
        await waitUntil { controller.state == .ready }
        XCTAssertEqual(controller.networks.map(\.ssid), ["Guest"])
        controller.deactivate()
    }

    /// A scan that is still in flight must never be started twice.
    func testAScanInFlightIsNotDuplicated() async {
        let scanner = FakeWiFiNetworkScanner()
        scanner.holdsCompletions = true
        let clock = ManualScanClock()
        let controller = makeController(scanner: scanner, clock: clock)

        controller.activate(nameAccess: .authorized)
        clock.advance(by: 120)
        controller.refresh(nameAccess: .authorized)

        XCTAssertEqual(scanner.scanCount, 1)
        XCTAssertEqual(controller.state, .scanning)

        scanner.completeNext()
        await waitUntil { controller.state == .ready }
        controller.deactivate()
    }

    /// The refresh button asks for a scan now, even if one ran a moment ago.
    func testManualRefreshBypassesTheInterval() async {
        let scanner = FakeWiFiNetworkScanner()
        let clock = ManualScanClock()
        let controller = makeController(scanner: scanner, clock: clock)
        controller.activate(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }

        scanner.result = .success(WiFiScanPayload(
            networks: [makeScanNetwork("Studio 5G")],
            details: .unavailable
        ))
        controller.refreshNow(nameAccess: .authorized)
        await waitUntil { scanner.scanCount == 2 }
        await waitUntil { controller.state == .ready }

        XCTAssertEqual(controller.networks.map(\.ssid), ["Studio 5G"])
        controller.deactivate()
    }

    /// Switching the radio is a user action: the list must not sit on the cached
    /// result from before the radio changed.
    func testPowerToggleScansImmediately() async {
        let scanner = FakeWiFiNetworkScanner()
        let clock = ManualScanClock()
        let controller = makeController(scanner: scanner, clock: clock)
        controller.activate(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }

        controller.setPower(false)
        await waitUntil { scanner.scanCount == 2 }

        XCTAssertEqual(clock.now.timeIntervalSinceReferenceDate, 0, "the clock never moved")
        controller.deactivate()
    }

    /// The panel path stays demand-gated: without an active list a power change
    /// is ignored.
    func testNormalPowerToggleIsIgnoredWhenInactive() {
        let scanner = FakeWiFiNetworkScanner()
        let controller = makeController(scanner: scanner)

        XCTAssertFalse(controller.isActive)
        controller.setPower(false)

        XCTAssertEqual(scanner.powerValues, [])
    }

    /// The menu-bar right-click quick action has no Wi-Fi list demand, so its
    /// power change must reach the radio while the panel is closed.
    func testQuickPowerToggleReachesTheRadioWithoutActivation() async {
        let scanner = FakeWiFiNetworkScanner()
        let controller = makeController(scanner: scanner)

        XCTAssertFalse(controller.isActive)
        controller.setPowerFromQuickAction(false)

        await waitUntil { scanner.powerValues == [false] }
        XCTAssertEqual(scanner.powerValues, [false])
    }

    /// The periodic loop wakes every minute but the scan floor is two minutes:
    /// the loop is a polling heartbeat, not a second cadence.
    func testThePeriodicLoopHonoursTheInterval() async {
        let scanner = FakeWiFiNetworkScanner()
        let clock = ManualScanClock()
        let sleeper = ManualEventSleeper()
        let controller = makeController(
            scanner: scanner,
            clock: clock,
            periodicRefreshSleep: { duration in await sleeper.sleep(duration) }
        )

        controller.activate(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }
        _ = await sleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertEqual(sleeper.durations.first, .seconds(60))

        sleeper.releaseAll()
        await Task.yield()
        XCTAssertEqual(scanner.scanCount, 1, "the loop fired inside the interval")

        clock.advance(by: 60)
        _ = await sleeper.waitForCallCount(2, timeout: .seconds(1))
        sleeper.releaseAll()
        await Task.yield()
        XCTAssertEqual(scanner.scanCount, 1, "one minute is still inside the two-minute floor")

        clock.advance(by: 60)
        _ = await sleeper.waitForCallCount(3, timeout: .seconds(1))
        sleeper.releaseAll()
        await waitUntil { scanner.scanCount == 2 }

        controller.deactivate()
    }

    /// The production default is the two-minute floor: a fresh controller with no
    /// injected interval may not scan again after one minute, and must after two.
    func testTheAutomaticFloorDefaultsToTwoMinutes() async {
        let scanner = FakeWiFiNetworkScanner()
        let clock = ManualScanClock()
        let controller = WiFiNetworkController(
            scanWorker: scanner,
            now: { clock.now }
        )
        controller.activate(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }
        XCTAssertEqual(scanner.scanCount, 1)

        clock.advance(by: 119)
        controller.refresh(nameAccess: .authorized)
        await Task.yield()
        XCTAssertEqual(scanner.scanCount, 1)

        clock.advance(by: 1)
        controller.refresh(nameAccess: .authorized)
        await waitUntil { scanner.scanCount == 2 }

        controller.deactivate()
    }

    /// A scan that is in flight when the page is left used to leave `state` on
    /// `.scanning` permanently: `deactivate()` drops the completion through the
    /// `isActive` guard, and every later `refresh`/`refreshNow` is then blocked
    /// by the `!state.isScanning` guard in `startScan()`, with the view's refresh
    /// button disabled. Leaving the session must end its scan state so that a
    /// later activation starts clean.
    func testReactivatingAfterLeavingMidScanStartsAFreshScan() async {
        let scanner = FakeWiFiNetworkScanner()
        scanner.holdsCompletions = true
        let clock = ManualScanClock()
        let controller = makeController(scanner: scanner, clock: clock)

        controller.activate(nameAccess: .authorized)
        await waitUntil { scanner.scanCount == 1 }
        XCTAssertEqual(controller.state, .scanning)

        controller.deactivate()
        XCTAssertFalse(controller.state.isScanning, "the abandoned scan must not stick")

        // The clock never moves: the fresh activation may only scan because the
        // floor timestamp was cleared with the scan state.
        scanner.holdsCompletions = false
        controller.activate(nameAccess: .authorized)
        await waitUntil { scanner.scanCount == 2 }
        await waitUntil { controller.state == .ready }

        XCTAssertFalse(controller.state.isScanning, "the page must not be stuck scanning")
        controller.deactivate()
    }

    /// Backing out of the Wi-Fi page used to leave the controller active: the
    /// periodic loop kept scanning while the popover stayed open.
    func testLeavingTheWiFiPageStopsThePeriodicScan() async {
        let scanner = FakeWiFiNetworkScanner()
        let clock = ManualScanClock()
        let sleeper = ManualEventSleeper()
        let networks = makeController(
            scanner: scanner,
            clock: clock,
            periodicRefreshSleep: { duration in await sleeper.sleep(duration) }
        )
        let store = SystemStatusStore(
            batteryMonitor: CadenceBatteryMonitor(),
            wifiMonitor: CadenceWiFiMonitor(),
            volumeMonitor: CadenceVolumeMonitor(),
            wifiNetworks: networks
        )

        store.activateWiFiPanel()
        networks.refresh(nameAccess: .authorized)
        await waitUntil { scanner.scanCount == 1 }
        _ = await sleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertTrue(store.hasOpenPopoverPanel)

        store.closeWiFiDetails()

        XCTAssertFalse(networks.isActive)
        XCTAssertFalse(store.hasOpenPopoverPanel)

        clock.advance(by: 60)
        sleeper.releaseAll()
        await Task.yield()
        XCTAssertEqual(scanner.scanCount, 1, "the page was left, so nothing may scan again")
    }

    /// Closing the popover releases the controller too, which is the path
    /// `StatusBarController.popoverDidClose` takes.
    func testClosingThePopoverDetailsStopsTheScan() async {
        let scanner = FakeWiFiNetworkScanner()
        let networks = makeController(scanner: scanner)
        let store = SystemStatusStore(
            batteryMonitor: CadenceBatteryMonitor(),
            wifiMonitor: CadenceWiFiMonitor(),
            volumeMonitor: CadenceVolumeMonitor(),
            wifiNetworks: networks
        )

        store.activateWiFiPanel()
        networks.refresh(nameAccess: .authorized)
        await waitUntil { scanner.scanCount == 1 }
        store.closePopoverDetails()

        XCTAssertFalse(networks.isActive)
        XCTAssertFalse(store.hasOpenPopoverPanel)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for the Wi-Fi network controller")
    }
}

/// The scan fixture: an open network carrying a single candidate.
private func makeScanNetwork(_ ssid: String, known: Bool = true) -> WiFiNetwork {
    WiFiNetwork(
        identity: WiFiNetworkIdentity(ssid: ssid, security: .open),
        candidates: [
            WiFiNetworkCandidate(ssid: ssid, bssid: nil, rssi: -50, channel: 6, security: .open)
        ],
        connectedBSSID: nil,
        isKnown: known
    )
}

/// Answers scans with one known network, and only when the test releases them if
/// `holdsCompletions` is set.
private final class FakeWiFiNetworkScanner: WiFiNetworkScanning, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [@Sendable (WiFiScanWorkerResult) -> Void] = []
    private var count = 0
    private var powerCalls: [Bool] = []

    var holdsCompletions = false
    var result: WiFiScanWorkerResult = .success(
        WiFiScanPayload(networks: [makeScanNetwork("Studio")], details: .unavailable)
    )

    var scanCount: Int { lock.withLock { count } }
    var powerValues: [Bool] { lock.withLock { powerCalls } }

    func scan(completion: @escaping @Sendable (WiFiScanWorkerResult) -> Void) {
        let result = lock.withLock { () -> WiFiScanWorkerResult in
            count += 1
            return self.result
        }
        if holdsCompletions {
            lock.withLock { pending.append(completion) }
        } else {
            completion(result)
        }
    }

    func completeNext() {
        let completion = lock.withLock { pending.isEmpty ? nil : pending.removeFirst() }
        let result = lock.withLock { self.result }
        completion?(result)
    }

    /// Reports the radio change as applied, which is what `setPower` returning
    /// true means, so the controller takes its "changed" path.
    func setPower(_ isOn: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        lock.withLock { powerCalls.append(isOn) }
        completion(true)
    }
}

private final class ManualScanClock {
    private(set) var now = Date(timeIntervalSinceReferenceDate: 0)

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

// The store-level tests only exercise the Wi-Fi panel's lifetime, so the three
// status monitors are inert: they publish nothing and never touch the system.

@MainActor
private final class CadenceBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class CadenceWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class CadenceVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
