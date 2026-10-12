import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconPreviewDataWindowControllerTests: XCTestCase {
    func testRepeatedShowReusesPanelAndEditsTheSharedSession() throws {
        let fixture = makeFixture()
        defer { fixture.status.stop(); TestUserDefaults.removeSuite(named: fixture.suite) }
        let controller = fixture.controller
        let parent = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 900, height: 680), styleMask: [.titled], backing: .buffered, defer: false)

        controller.show(relativeTo: parent)
        let firstPanel = try XCTUnwrap(controller.window)
        controller.show(relativeTo: parent)
        XCTAssertTrue(controller.window === firstPanel)
        XCTAssertEqual(fixture.session.mode, .live,
                       "Opening or re-showing the panel must not silently enable simulated rendering.")
        XCTAssertEqual(firstPanel.contentRect(forFrameRect: firstPanel.frame).size, IconPreviewDataWindowController.contentSize)

        fixture.session.setMacBatteryPercentage(31)
        XCTAssertEqual(fixture.session.samples.macBattery.percentage, 31)
        firstPanel.close()
        XCTAssertNil(controller.window)
        XCTAssertEqual(fixture.session.samples.macBattery.percentage, 31)
    }

    func testClosingAndReopeningCreatesNewPanelWithSameSession() throws {
        let fixture = makeFixture()
        defer { fixture.status.stop(); TestUserDefaults.removeSuite(named: fixture.suite) }
        let parent = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 900, height: 680), styleMask: [.titled], backing: .buffered, defer: false)

        fixture.controller.show(relativeTo: parent)
        let oldPanel = try XCTUnwrap(fixture.controller.window)
        oldPanel.close()
        fixture.controller.show(relativeTo: parent)

        XCTAssertNotNil(fixture.controller.window)
        XCTAssertFalse(fixture.controller.window === oldPanel)
        XCTAssertTrue(fixture.controller.previewSession === fixture.session)
        XCTAssertEqual(fixture.session.mode, .live,
                       "Closing and reopening the panel must preserve the user's explicit mode.")
    }

    func testReopeningPreservesExplicitSimulatedModeAndEditedSamples() throws {
        let fixture = makeFixture()
        defer { fixture.status.stop(); TestUserDefaults.removeSuite(named: fixture.suite) }
        let parent = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 900, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
        fixture.session.mode = .simulated
        fixture.session.setMacBatteryPercentage(19)

        fixture.controller.show(relativeTo: parent)
        fixture.controller.window?.close()
        fixture.controller.show(relativeTo: parent)

        XCTAssertEqual(fixture.session.mode, .simulated)
        XCTAssertEqual(fixture.session.samples.macBattery.percentage, 19)
    }

    private func makeFixture() -> (suite: String, status: SystemStatusStore, session: IconDesignerPreviewSession,
                                    controller: IconPreviewDataWindowController) {
        let suite = "IconPreviewDataWindowControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsStore(defaults: defaults)
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let status = SystemStatusStore(
            batteryMonitor: PanelNoopBatteryMonitor(),
            wifiMonitor: PanelNoopWiFiMonitor(),
            volumeMonitor: PanelNoopVolumeMonitor()
        )
        let session = IconDesignerPreviewSession()
        let controller = IconPreviewDataWindowController(
            store: settings,
            statusStore: status,
            localization: localization,
            previewSession: session
        )
        return (suite, status, session, controller)
    }
}

@MainActor private final class PanelNoopBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>; init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}; func stop() {}; func refresh() {}; func recover() {}
}
@MainActor private final class PanelNoopWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>; init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}; func stop() {}; func refresh() {}; func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}
@MainActor private final class PanelNoopVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>; init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}; func stop() {}; func refresh() {}; func recover() {}; func setDetailsVisible(_ visible: Bool) {}
}
