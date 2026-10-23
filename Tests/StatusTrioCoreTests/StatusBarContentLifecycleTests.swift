import AppKit
import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class StatusBarContentLifecycleTests: XCTestCase {
    func testCloseStopsSubscriptionsImmediatelyAndReopenStartsSynchronouslyWithLatestValues() async throws {
        let harness = try ContentLifecycleHarness()
        defer { harness.cleanUp() }

        harness.open()
        XCTAssertNotNil(harness.controller.popoverForTesting.contentViewController)

        harness.localization.setPreference(.language(.simplifiedChinese))
        XCTAssertEqual(harness.scheduler.pendingCount, 1)
        harness.scheduler.runScheduled()

        await closeNativePopover(harness.controller.popoverForTesting)
        harness.scheduler.runScheduled()
        XCTAssertEqual(harness.scheduler.pendingCount, 0)
        harness.localization.setPreference(.language(.english))
        harness.scheduler.runScheduled()
        XCTAssertEqual(
            harness.scheduler.pendingCount,
            0,
            "closing immediately removes the panel's localization subscription"
        )

        let latestBatteryDelivered = expectation(description: "latest battery reaches the store")
        let batteryCancellable = harness.store.$snapshot
            .filter { $0.battery.rawPercentage == 47 }
            .prefix(1)
            .sink { _ in latestBatteryDelivered.fulfill() }
        harness.battery.send(lifecycleBattery(47))
        await fulfillment(of: [latestBatteryDelivered], timeout: 1)
        batteryCancellable.cancel()

        harness.controller.resetPopoverToggleGateForTesting()
        harness.open()
        XCTAssertEqual(harness.controller.panelForTesting.battery.title, "Battery · 47%")

        harness.localization.setPreference(.language(.simplifiedChinese))
        XCTAssertEqual(
            harness.scheduler.pendingCount,
            1,
            "one restarted panel must install exactly one settings subscription"
        )
    }

    func testReleaseTaskUsesFiveSecondGateAndCannotClearReopenedContent() async throws {
        let harness = try ContentLifecycleHarness()
        defer { harness.cleanUp() }
        let released = expectation(description: "latest close ends content ownership")
        harness.controller.onPopoverContentReleased = {
            harness.contentReleaseCount += 1
            released.fulfill()
        }

        harness.open()
        let firstContent = try XCTUnwrap(harness.controller.popoverForTesting.contentViewController)

        await closeNativePopover(harness.controller.popoverForTesting)
        await harness.releaseSleeper.waitForCallCount(1)
        XCTAssertEqual(harness.releaseSleeper.durations, [.seconds(5)])
        XCTAssertTrue(harness.controller.popoverForTesting.contentViewController === firstContent)
        let supersededRelease = try XCTUnwrap(
            harness.controller.popoverContentReleaseTaskForTesting
        )

        harness.controller.resetPopoverToggleGateForTesting()
        harness.open()
        XCTAssertTrue(
            harness.controller.popoverForTesting.contentViewController === firstContent,
            "a reopen inside five seconds reuses the retained hosting"
        )

        XCTAssertTrue(harness.releaseSleeper.releaseNext())
        await supersededRelease.value
        harness.controller.trimForMemoryPressure()
        XCTAssertTrue(
            harness.controller.popoverForTesting.contentViewController === firstContent,
            "visibility pressure must not replace a popover that is still shown"
        )
        XCTAssertEqual(harness.contentReleaseCount, 0)

        await closeNativePopover(harness.controller.popoverForTesting)
        await harness.releaseSleeper.waitForCallCount(2)
        let activeRelease = try XCTUnwrap(
            harness.controller.popoverContentReleaseTaskForTesting
        )
        XCTAssertTrue(harness.releaseSleeper.releaseNext())
        await activeRelease.value
        await fulfillment(of: [released], timeout: 1)

        XCTAssertNil(harness.controller.popoverForTesting.contentViewController)
        XCTAssertEqual(harness.contentReleaseCount, 1)

        harness.controller.setVisible(false)
        XCTAssertEqual(
            harness.contentReleaseCount,
            1,
            "callback fires once per actual content-ownership transition"
        )
        harness.controller.trimForMemoryPressure()
        harness.controller.setVisible(false)
        XCTAssertEqual(harness.contentReleaseCount, 1)
    }

    func testDetailCloseEndsContentOwnershipImmediately() async throws {
        let harness = try ContentLifecycleHarness()
        defer { harness.cleanUp() }

        harness.open()
        harness.store.batteryDetails.activate(state: BatteryPowerState(.placeholder))
        let content = try XCTUnwrap(harness.controller.popoverForTesting.contentViewController)
        let released = expectation(description: "detail close ends content ownership without sleeping")
        harness.controller.onPopoverContentReleased = {
            harness.contentReleaseCount += 1
            released.fulfill()
        }

        await closeNativePopover(harness.controller.popoverForTesting)
        await fulfillment(of: [released], timeout: 1)

        XCTAssertNil(harness.controller.popoverForTesting.contentViewController)
        XCTAssertNotEqual(harness.controller.popoverForTesting.contentViewController, content)
        XCTAssertEqual(harness.releaseSleeper.callCount, 0)
        XCTAssertEqual(harness.contentReleaseCount, 1)
    }

    func testTwentyNativeCloseReopenCyclesKeepLatestValuesWithoutDuplicateSourceSubscriptions() throws {
        let harness = try ContentLifecycleHarness()
        defer { harness.cleanUp() }

        for cycle in 0..<20 {
            let percentage = 20 + cycle
            let hostingReferences = try autoreleasepool {
                harness.controller.resetPopoverToggleGateForTesting()
                harness.open()
                let firstHosting = try XCTUnwrap(
                    harness.controller.popoverForTesting.contentViewController
                )
                let sourceDelivery = expectation(
                    description: "cycle \(cycle) delivers one popup source event"
                )
                sourceDelivery.assertForOverFulfill = false
                var sourceDeliveryCount = 0
                harness.controller.panelForTesting.popupSourceEventForTesting = {
                    sourceDeliveryCount += 1
                    if sourceDeliveryCount == 1 {
                        sourceDelivery.fulfill()
                    }
                }

                harness.battery.send(lifecycleBattery(percentage))
                waitFor(sourceDelivery, cycle: cycle, phase: "source delivery")
                XCTAssertEqual(
                    sourceDeliveryCount,
                    1,
                    "cycle \(cycle) must install one popup source subscription"
                )
                harness.controller.panelForTesting.popupSourceEventForTesting = nil
                XCTAssertEqual(
                    harness.store.popupSnapshot.battery.rawPercentage,
                    percentage
                )
                XCTAssertEqual(
                    harness.controller.panelForTesting.battery.title,
                    "Battery · \(percentage)%",
                    "cycle \(cycle) sees its own source value while open"
                )

                let firstSleeperCall = expectation(
                    description: "cycle \(cycle) arms the first release"
                )
                harness.releaseSleeper.nextCallExpectation = firstSleeperCall
                closeNativePopover(
                    harness.controller.popoverForTesting,
                    cycle: cycle,
                    phase: "first close"
                )
                waitFor(firstSleeperCall, cycle: cycle, phase: "first release gate")
                XCTAssertEqual(harness.releaseSleeper.durations.last, .seconds(5))
                let firstRelease = try XCTUnwrap(
                    harness.controller.popoverContentReleaseTaskForTesting
                )
                let firstReleaseFinished = expectation(
                    description: "cycle \(cycle) finishes the first release task"
                )
                Task { @MainActor in
                    await firstRelease.value
                    firstReleaseFinished.fulfill()
                }
                XCTAssertTrue(harness.releaseSleeper.releaseNext())
                waitFor(
                    firstReleaseFinished,
                    cycle: cycle,
                    phase: "first release completion"
                )
                XCTAssertNil(harness.controller.popoverForTesting.contentViewController)

                harness.controller.resetPopoverToggleGateForTesting()
                harness.open()
                XCTAssertEqual(
                    harness.controller.panelForTesting.battery.title,
                    "Battery · \(percentage)%",
                    "cycle \(cycle) synchronously restarts with the latest stored value"
                )
                let reopenedHosting = try XCTUnwrap(
                    harness.controller.popoverForTesting.contentViewController
                )

                let released = expectation(
                    description: "cycle \(cycle) ends content ownership"
                )
                released.assertForOverFulfill = true
                harness.controller.onPopoverContentReleased = {
                    harness.contentReleaseCount += 1
                    released.fulfill()
                }
                let finalSleeperCall = expectation(
                    description: "cycle \(cycle) arms the final release"
                )
                harness.releaseSleeper.nextCallExpectation = finalSleeperCall
                closeNativePopover(
                    harness.controller.popoverForTesting,
                    cycle: cycle,
                    phase: "final close"
                )
                waitFor(finalSleeperCall, cycle: cycle, phase: "final release gate")
                let finalRelease = try XCTUnwrap(
                    harness.controller.popoverContentReleaseTaskForTesting
                )
                XCTAssertTrue(harness.releaseSleeper.releaseNext())
                waitFor(released, cycle: cycle, phase: "final ownership end")
                awaitTaskCompletion(finalRelease, cycle: cycle, phase: "final release task")
                harness.controller.onPopoverContentReleased = nil
                XCTAssertEqual(harness.contentReleaseCount, cycle + 1)
                XCTAssertNil(
                    harness.controller.popoverContentReleaseTaskForTesting,
                    "the release callback observes a completed task slot"
                )
                XCTAssertNil(harness.controller.popoverForTesting.contentViewController)
                return (
                    WeakHostingReference(firstHosting),
                    WeakHostingReference(reopenedHosting)
                )
            }

            XCTAssertNil(
                hostingReferences.0.value,
                "cycle \(cycle) retained its first hosting controller"
            )
            XCTAssertNil(
                hostingReferences.1.value,
                "cycle \(cycle) retained its reopened hosting controller"
            )
        }
    }

    private func closeNativePopover(_ popover: NSPopover) async {
        guard popover.isShown else { return }
        let didClose = expectation(forNotification: NSPopover.didCloseNotification, object: popover)
        popover.animates = false
        popover.performClose(nil)
        await fulfillment(of: [didClose], timeout: 2)
    }

    private func waitFor(
        _ expectation: XCTestExpectation,
        cycle: Int,
        phase: String
    ) {
        let result = XCTWaiter.wait(for: [expectation], timeout: 1)
        XCTAssertEqual(result, .completed, "cycle \(cycle) did not complete \(phase)")
    }

    private func closeNativePopover(
        _ popover: NSPopover,
        cycle: Int,
        phase: String
    ) {
        guard popover.isShown else { return }
        let didClose = expectation(forNotification: NSPopover.didCloseNotification, object: popover)
        popover.animates = false
        popover.performClose(nil)
        waitFor(didClose, cycle: cycle, phase: phase)
    }

    private func awaitTaskCompletion(
        _ task: Task<Void, Never>,
        cycle: Int,
        phase: String
    ) {
        let completed = expectation(description: "cycle \(cycle) completes \(phase)")
        Task { @MainActor in
            await task.value
            completed.fulfill()
        }
        waitFor(completed, cycle: cycle, phase: phase)
    }
}

@MainActor
private final class ContentLifecycleHarness {
    let defaults: UserDefaults
    let store: SystemStatusStore
    let settings: SettingsStore
    let localization: Localization
    let iconPresentation: IconPresentationViewModel
    let controller: StatusBarController
    let scheduler = ManualPanelUpdateScheduler()
    let releaseSleeper = ContentReleaseSleeper()
    let battery: LifecycleBatteryMonitor
    let anchorPoint: NSPoint
    var contentReleaseCount = 0
    private let suiteName: String

    init() throws {
        suiteName = "StatusTrioCoreTests.StatusBarContentLifecycle.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        settings = SettingsStore(defaults: defaults)
        localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        battery = LifecycleBatteryMonitor()
        store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: LifecycleWiFiMonitor(),
            volumeMonitor: LifecycleVolumeMonitor(),
            popupDebounceSleep: { _ in },
            initialSnapshot: StatusSnapshot(
                battery: lifecycleBattery(80),
                wifi: .placeholder,
                volume: .placeholder
            )
        )
        iconPresentation = makeTestIconPresentation(store: store, settings: settings)
        let releaseSleeperBox = ReleaseSleeperBox(value: releaseSleeper)
        controller = StatusBarController(
            store: store,
            settings: settings,
            iconPresentation: iconPresentation,
            localization: localization,
            openSettings: {},
            quitAction: {},
            panelUpdateScheduler: scheduler,
            popoverContentReleaseSleeper: { duration in
                await releaseSleeperBox.value.sleep(duration)
            },
            renderMenuBarBase: { _, _, _, _ in nil },
            renderMenuBarOverlay: { _, _, _, _, _ in nil }
        )
        let visibleFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1_024, height: 768)
        anchorPoint = NSPoint(x: visibleFrame.midX, y: visibleFrame.minY + 10)
        iconPresentation.start()
        store.start()
    }

    func open() {
        controller.togglePopover(anchoredAtScreenPoint: anchorPoint)
        XCTAssertTrue(controller.popoverForTesting.isShown)
    }

    func cleanUp() {
        controller.popoverForTesting.close()
        controller.setVisible(false)
        iconPresentation.stop()
        store.stop()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class ReleaseSleeperBox {
    let value: ContentReleaseSleeper

    init(value: ContentReleaseSleeper) {
        self.value = value
    }
}

@MainActor
private final class ContentReleaseSleeper {
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var callWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    var nextCallExpectation: XCTestExpectation?
    private(set) var durations: [Duration] = []
    private(set) var callCount = 0
    private(set) var completionCount = 0

    func sleep(_ duration: Duration) async {
        callCount += 1
        durations.append(duration)
        nextCallExpectation?.fulfill()
        nextCallExpectation = nil
        await withCheckedContinuation { continuation in
            pending.append(continuation)
            resumeReadyCallWaiters()
        }
        completionCount += 1
    }

    func waitForCallCount(_ count: Int) async {
        guard callCount < count else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((count, continuation))
        }
    }

    func releaseNext() -> Bool {
        guard !pending.isEmpty else { return false }
        pending.removeFirst().resume()
        return true
    }

    private func resumeReadyCallWaiters() {
        let ready = callWaiters.filter { callCount >= $0.count }
        callWaiters.removeAll { callCount >= $0.count }
        ready.forEach { $0.continuation.resume() }
    }
}

@MainActor
private final class WeakHostingReference {
    weak var value: NSViewController?

    init(_ value: NSViewController) {
        self.value = value
    }
}

private func lifecycleBattery(_ percentage: Int) -> BatteryStatus {
    BatteryStatus(
        rawPercentage: percentage,
        isPresent: true,
        isCharging: false,
        isLowPowerMode: false,
        isConnectedToPower: false
    )
}

@MainActor
private final class LifecycleBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    private let continuation: AsyncStream<BatteryStatus>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func send(_ status: BatteryStatus) {
        continuation.yield(status)
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class LifecycleWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>

    init() {
        (updates, _) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class LifecycleVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>

    init() {
        (updates, _) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func setDetailsVisible(_ visible: Bool) {}
}
