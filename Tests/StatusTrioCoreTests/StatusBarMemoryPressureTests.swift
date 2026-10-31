import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class StatusBarMemoryPressureTests: XCTestCase {
    func testDockPresentationDoesNotForceApplicationActivation() throws {
        let harness = try StatusBarPressureHarness()
        defer { harness.cleanUp() }

        harness.controller.togglePopover(anchoredAtScreenPoint: harness.anchorPoint)

        XCTAssertTrue(harness.controller.popoverForTesting.isShown)
        XCTAssertFalse(harness.didActivateApplication)
    }

    func testShortcutPresentationStillForcesApplicationActivation() throws {
        let harness = try StatusBarPressureHarness(isVisible: false)
        defer { harness.cleanUp() }

        harness.controller.openPopoverFromShortcut()

        XCTAssertTrue(harness.controller.popoverForTesting.isShown)
        XCTAssertTrue(harness.didActivateApplication)
    }

    /// #183: while the app is regular (Settings or the first-run window is open)
    /// activating it from another app's full-screen Space restores that window,
    /// switches away from the Space and the panel dismisses itself. The panel is
    /// non-activating, so presenting must withhold the forced activation.
    func testRegularApplicationPolicyWithholdsShortcutPresentationActivation() throws {
        let harness = try StatusBarPressureHarness(
            isVisible: false,
            isApplicationRegular: true
        )
        defer { harness.cleanUp() }

        harness.controller.openPopoverFromShortcut()

        XCTAssertTrue(harness.controller.popoverForTesting.isShown)
        XCTAssertFalse(
            harness.didActivateApplication,
            "a regular app must not be force-activated from the status panel"
        )
    }

    func testShortcutPresentationTogglesAndCleansItsFallbackAnchor() throws {
        let harness = try StatusBarPressureHarness(isVisible: false)
        defer { harness.cleanUp() }

        let popover = harness.controller.popoverForTesting
        harness.controller.openPopoverFromShortcut()
        XCTAssertTrue(popover.isShown)
        XCTAssertNotNil(harness.controller.popoverAnchorWindowForTesting)

        harness.controller.openPopoverFromShortcut()
        waitUntilClosed(popover)
        XCTAssertFalse(popover.isShown)
        XCTAssertNil(
            harness.controller.popoverAnchorWindowForTesting,
            "closing the panel must release the shortcut fallback anchor"
        )

        harness.controller.openPopoverFromShortcut()
        XCTAssertTrue(popover.isShown)
        XCTAssertNotNil(harness.controller.popoverAnchorWindowForTesting)

        popover.close()
        waitUntilClosed(popover)
        XCTAssertNil(
            harness.controller.popoverAnchorWindowForTesting,
            "closing the panel must release the shortcut fallback anchor"
        )
    }

    func testTrimForMemoryPressureKeepsVisiblePopoverContent() throws {
        let harness = try StatusBarPressureHarness()
        defer { harness.cleanUp() }

        harness.controller.togglePopover(anchoredAtScreenPoint: harness.anchorPoint)
        let popover = harness.controller.popoverForTesting
        XCTAssertTrue(popover.isShown)
        let content = try XCTUnwrap(popover.contentViewController)

        harness.controller.trimForMemoryPressure()

        XCTAssertTrue(popover.isShown)
        XCTAssertTrue(popover.contentViewController === content)
    }

    func testTrimForMemoryPressureReleasesClosedPopoverContent() throws {
        let harness = try StatusBarPressureHarness()
        defer { harness.cleanUp() }

        harness.controller.togglePopover(anchoredAtScreenPoint: harness.anchorPoint)
        let popover = harness.controller.popoverForTesting
        XCTAssertTrue(popover.isShown)
        XCTAssertNotNil(popover.contentViewController)

        let didClose = expectation(forNotification: AnchoredStatusPanel.didCloseNotification, object: popover)
        popover.performClose(nil)
        wait(for: [didClose], timeout: 2)
        XCTAssertFalse(popover.isShown)
        XCTAssertNotNil(
            popover.contentViewController,
            "Closing normally retains content for the existing rapid-reopen path"
        )

        harness.controller.trimForMemoryPressure()

        XCTAssertNil(popover.contentViewController)
    }

    func testNilFirstTeardownReleasesInactivePanelStateWithoutEndingContentOwnership() throws {
        let harness = try StatusBarPressureHarness()
        defer { harness.cleanUp() }

        harness.controller.togglePopover(anchoredAtScreenPoint: harness.anchorPoint)
        let popover = harness.controller.popoverForTesting
        XCTAssertTrue(popover.isShown)
        XCTAssertFalse(harness.controller.panelForTesting.batteryDetails.rows.isEmpty)

        let didClose = expectation(forNotification: AnchoredStatusPanel.didCloseNotification, object: popover)
        popover.performClose(nil)
        wait(for: [didClose], timeout: 2)
        XCTAssertNotNil(popover.contentViewController)

        popover.contentViewController = nil
        var ownershipEndCount = 0
        harness.controller.onPopoverContentReleased = {
            ownershipEndCount += 1
        }
        XCTAssertFalse(harness.controller.panelForTesting.batteryDetails.rows.isEmpty)

        harness.controller.trimForMemoryPressure()

        XCTAssertFalse(harness.store.hasOpenPopoverPanel)
        XCTAssertTrue(harness.controller.panelForTesting.batteryDetails.rows.isEmpty)
        XCTAssertEqual(ownershipEndCount, 0)
    }

    private func waitUntilClosed(_ popover: AnchoredStatusPanel) {
        let deadline = Date().addingTimeInterval(2)
        while popover.isShown, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }
}

@MainActor
private final class StatusBarPressureHarness {
    let defaults: UserDefaults
    let store: SystemStatusStore
    let iconPresentation: IconPresentationViewModel
    let controller: StatusBarController
    let anchorPoint: NSPoint
    private let activationProbe = PressureActivationProbe()
    var didActivateApplication: Bool { activationProbe.didActivate }
    private let suiteName: String

    init(isVisible: Bool = true, isApplicationRegular: Bool = false) throws {
        suiteName = "StatusTrioCoreTests.StatusBarMemoryPressure.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw HarnessError.missingDefaults
        }
        self.defaults = defaults
        let settings = SettingsStore(defaults: defaults)
        store = AppEnvironment.makeStore(
            batteryMonitor: PressureBatteryMonitor(),
            wifiMonitor: PressureWiFiMonitor(),
            volumeMonitor: PressureVolumeMonitor()
        )
        iconPresentation = makeTestIconPresentation(store: store, settings: settings)
        controller = StatusBarController(
            store: store,
            settings: settings,
            iconPresentation: iconPresentation,
            localization: Localization(defaults: defaults, preferredLanguages: ["en"]),
            isVisible: isVisible,
            openSettings: {},
            quitAction: {},
            activatesApplicationForPopover: { [activationProbe] in
                activationProbe.didActivate = true
            },
            isApplicationRegular: { isApplicationRegular },
            renderMenuBarBase: { _, _, _, _ in nil },
            renderMenuBarOverlay: { _, _, _, _, _ in nil }
        )
        let visibleFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1_024, height: 768)
        anchorPoint = NSPoint(x: visibleFrame.midX, y: visibleFrame.minY + 10)
        iconPresentation.start()
    }

    func cleanUp() {
        controller.popoverForTesting.close()
        controller.setVisible(false)
        iconPresentation.stop()
        store.stop()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

enum HarnessError: Error {
    case missingDefaults
}

@MainActor
private final class PressureActivationProbe {
    var didActivate = false
}

@MainActor
private final class PressureBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class PressureWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class PressureVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func setDetailsVisible(_ visible: Bool) {}
}
