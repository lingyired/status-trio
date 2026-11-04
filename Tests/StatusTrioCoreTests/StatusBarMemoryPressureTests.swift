import AppKit
import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class StatusBarMemoryPressureTests: VisibleUITestCase {
    func testMenuBarPresentationDoesNotForceApplicationActivation() throws {
        let harness = try StatusBarPressureHarness()
        defer { harness.cleanUp() }

        harness.controller.togglePopover()

        XCTAssertTrue(harness.controller.popoverForTesting.isShown)
        XCTAssertFalse(harness.didActivateApplication)
    }

    func testWorkspaceAppSwitchClosesMenuBarPanel() async throws {
        let harness = try StatusBarPressureHarness()
        defer { harness.cleanUp() }
        harness.controller.togglePopover()
        let panel = harness.controller.popoverForTesting
        XCTAssertTrue(panel.isShown)
        let otherApp = try XCTUnwrap(NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && $0.activationPolicy == .regular
        })
        let closed = expectation(
            forNotification: AnchoredStatusPanel.didCloseNotification,
            object: panel
        )

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: otherApp]
        )

        await fulfillment(of: [closed], timeout: 1)
        XCTAssertFalse(panel.isShown)
    }

    func testOwnWorkspaceActivationDoesNotDismissMenuBarPanel() async throws {
        let harness = try StatusBarPressureHarness()
        defer { harness.cleanUp() }
        harness.controller.togglePopover()
        let delivered = expectation(description: "workspace activation delivered")
        let center = NSWorkspace.shared.notificationCenter
        let observer = center.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { _ in delivered.fulfill() }

        center.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current]
        )

        await fulfillment(of: [delivered], timeout: 1)
        withExtendedLifetime(observer) {}
        XCTAssertTrue(harness.controller.popoverForTesting.isShown)
    }

    /// Issue #267, real key handoff (no synthesized notifications): with the
    /// Settings window already open and key, the panel opens and takes key;
    /// making the Settings window key again must close the panel.
    ///
    /// `VisibleUITestCase`: skipped by default. `isKeyWindow` is only meaningful
    /// while the app is active, so this needs an authorized visible session.
    func testRealKeyHandoffFromPanelBackToSettingsClosesPanel() throws {
        let harness = try StatusBarPressureHarness()
        defer { harness.cleanUp() }

        let app = NSApplication.shared
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(ignoringOtherApps: true)
        }

        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 360, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.isReleasedWhenClosed = false
        addTeardownBlock {
            settingsWindow.orderOut(nil)
            settingsWindow.close()
        }

        settingsWindow.makeKeyAndOrderFront(nil)
        XCTAssertTrue(
            settingsWindow.isKeyWindow,
            "the Settings window must start as the key window"
        )

        harness.controller.togglePopover()
        let panel = harness.controller.popoverForTesting
        XCTAssertTrue(panel.isShown)
        XCTAssertTrue(
            panel.isKeyWindow,
            "the non-activating panel takes key when it opens over Settings"
        )

        settingsWindow.makeKey()
        waitUntilClosed(panel)
        XCTAssertFalse(panel.isShown, "clicking Settings must close the panel")
        XCTAssertTrue(
            settingsWindow.isKeyWindow,
            "focus stays on the Settings window; the panel does not take it back"
        )
    }

    /// Notification-wiring check for the `didBecomeMain` path. This posts a
    /// synthetic notification; it does not prove a real key/main handoff (see
    /// `testRealKeyHandoffFromPanelBackToSettingsClosesPanel`).
    func testSynthesizedMainNotificationClosesThePanel() async throws {
        let harness = try StatusBarPressureHarness()
        defer { harness.cleanUp() }
        harness.controller.togglePopover()
        let panel = harness.controller.popoverForTesting
        XCTAssertTrue(panel.isShown)

        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.isReleasedWhenClosed = false
        defer { settingsWindow.close() }
        // Visible UI test: order the window in so `isVisible` is true, exactly
        // as a real Settings window is while the panel is open.
        settingsWindow.orderFront(nil)
        let closed = expectation(
            forNotification: AnchoredStatusPanel.didCloseNotification,
            object: panel
        )

        NotificationCenter.default.post(
            name: NSWindow.didBecomeMainNotification,
            object: settingsWindow
        )

        await fulfillment(of: [closed], timeout: 1)
        XCTAssertFalse(panel.isShown)
    }

    /// Synthetic-only check that the panel's own key transition keeps it open.
    /// A real transition is covered by `testRealKeyHandoffFromPanelBackToSettingsClosesPanel`.
    func testSynthesizedPanelKeyNotificationKeepsThePanelOpen() async throws {
        let harness = try StatusBarPressureHarness()
        defer { harness.cleanUp() }
        harness.controller.togglePopover()
        let panel = harness.controller.popoverForTesting
        XCTAssertTrue(panel.isShown)
        let panelWindow = try XCTUnwrap(panel.contentViewController?.view.window)

        NotificationCenter.default.post(
            name: NSWindow.didBecomeKeyNotification,
            object: panelWindow
        )
        // Give the main-actor sink a turn before asserting.
        await Task.yield()

        XCTAssertTrue(panel.isShown)
    }

    /// A panel-owned sheet (confirmation) becomes key at a modal level with a
    /// sheet parent; it must not dismiss the panel underneath.
    func testSynthesizedPanelSheetKeyNotificationKeepsThePanelOpen() async throws {
        let harness = try StatusBarPressureHarness()
        defer { harness.cleanUp() }
        harness.controller.togglePopover()
        let panel = harness.controller.popoverForTesting
        XCTAssertTrue(panel.isShown)
        let panelWindow = try XCTUnwrap(panel.contentViewController?.view.window)

        let sheetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheetWindow.isReleasedWhenClosed = false
        defer { sheetWindow.close() }
        // Use the completion-handler form: the async `beginSheet(_:)` overlay
        // would suspend until the sheet is dismissed, which never happens here.
        panelWindow.beginSheet(sheetWindow, completionHandler: { _ in })
        defer { panelWindow.endSheet(sheetWindow) }

        NotificationCenter.default.post(
            name: NSWindow.didBecomeKeyNotification,
            object: sheetWindow
        )
        await Task.yield()

        XCTAssertTrue(panel.isShown)
    }

    /// A floating/menu-level window (e.g. an NSMenu or alert) must not dismiss
    /// the panel.
    func testSynthesizedFloatingLevelKeyNotificationKeepsThePanelOpen() async throws {
        let harness = try StatusBarPressureHarness()
        defer { harness.cleanUp() }
        harness.controller.togglePopover()
        let panel = harness.controller.popoverForTesting
        XCTAssertTrue(panel.isShown)

        let floatingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        floatingWindow.isReleasedWhenClosed = false
        floatingWindow.level = .floating
        defer { floatingWindow.close() }

        NotificationCenter.default.post(
            name: NSWindow.didBecomeKeyNotification,
            object: floatingWindow
        )
        await Task.yield()

        XCTAssertTrue(panel.isShown)
    }

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
