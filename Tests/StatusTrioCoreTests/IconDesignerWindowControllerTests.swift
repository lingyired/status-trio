import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconDesignerWindowControllerTests: XCTestCase {
    func testDesignerRootUsesTheControllerSharedPreviewAppearance() throws {
        let fixture = makeFixture()
        defer { fixture.status.stop(); TestUserDefaults.removeSuite(named: fixture.suite) }
        let controller = fixture.designer
        let configurationBeforePreviewChange = fixture.settings.iconConfiguration
        let root = controller.makeDesignerView()

        XCTAssertTrue(root.previewSession === controller.previewSession)
        XCTAssertTrue(root.previewIsDarkBackground.wrappedValue)
        root.previewIsDarkBackground.wrappedValue = false
        XCTAssertFalse(controller.previewSession.isDarkBackground)
        XCTAssertEqual(fixture.settings.iconConfiguration, configurationBeforePreviewChange)
        XCTAssertEqual(controller.previewSession.mode, .live)

        let otherPreviewBinding = controller.makeDesignerView().previewIsDarkBackground
        XCTAssertFalse(otherPreviewBinding.wrappedValue)
    }

    func testRepeatedShowReusesTheWindowAndOneActivationLease() throws {
        let fixture = makeFixture()
        defer { fixture.status.stop(); TestUserDefaults.removeSuite(named: fixture.suite) }
        let controller = fixture.designer

        controller.show(slot: .center)
        let firstWindow = try XCTUnwrap(controller.window)
        controller.show(slot: .footer)
        XCTAssertTrue(controller.window === firstWindow)
        XCTAssertEqual(controller.previewSession.selectedSlot, .footer)
        XCTAssertEqual(fixture.application.currentActivationPolicy, .regular)
        XCTAssertEqual(fixture.application.policies.filter { $0 == .regular }.count, 1)

        firstWindow.close()
        XCTAssertNil(controller.window)
        XCTAssertEqual(fixture.application.currentActivationPolicy, .accessory)
    }

    func testSettingsAndDesignerCanCloseInEitherOrderWithoutReleasingActivationEarly() throws {
        let fixture = makeFixture()
        defer { fixture.status.stop(); TestUserDefaults.removeSuite(named: fixture.suite) }
        let settings = SettingsWindowController(
            store: fixture.settings,
            statusStore: fixture.status,
            localization: fixture.localization,
            activationPolicy: fixture.policy,
            showIconGuide: {}
        )
        let designer = fixture.designer

        settings.show()
        designer.show()
        try XCTUnwrap(settings.window).close()
        XCTAssertEqual(fixture.application.currentActivationPolicy, .regular)
        try XCTUnwrap(designer.window).close()
        XCTAssertEqual(fixture.application.currentActivationPolicy, .accessory)

        designer.show()
        settings.show()
        try XCTUnwrap(designer.window).close()
        XCTAssertEqual(fixture.application.currentActivationPolicy, .regular)
        try XCTUnwrap(settings.window).close()
        XCTAssertEqual(fixture.application.currentActivationPolicy, .accessory)
    }

    func testInitializationAndResurfaceAfterCloseDoNotCreateOrReopenWindow() {
        let fixture = makeFixture()
        defer { fixture.status.stop(); TestUserDefaults.removeSuite(named: fixture.suite) }
        let controller = fixture.designer

        XCTAssertNil(controller.window)
        controller.resurface()
        XCTAssertNil(controller.window)
        controller.show()
        controller.window?.close()
        XCTAssertNil(controller.window)
        controller.resurface()
        XCTAssertNil(controller.window)
    }

    func testCenteredFrameFitsVisibleFrameWithoutConvertingContentSizeToFrameSize() {
        let visible = NSRect(x: 0, y: 0, width: 1280, height: 800)
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let frame = IconDesignerWindowController.centeredFrame(
            contentSize: IconDesignerWindowController.initialContentSize,
            in: visible,
            styleMask: style
        )
        let content = NSWindow.contentRect(forFrameRect: frame, styleMask: style)
        XCTAssertGreaterThanOrEqual(content.width, IconDesignerWindowController.minimumContentSize.width)
        XCTAssertGreaterThanOrEqual(content.height, IconDesignerWindowController.minimumContentSize.height)
        XCTAssertLessThanOrEqual(content.width, IconDesignerWindowController.initialContentSize.width)
        XCTAssertLessThanOrEqual(content.height, IconDesignerWindowController.initialContentSize.height)
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY)
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY)
    }

    private func makeFixture() -> (suite: String, settings: SettingsStore, status: SystemStatusStore,
                                  localization: Localization, application: ActivationApplicationSpy,
                                  policy: AppActivationPolicy, designer: IconDesignerWindowController) {
        let suite = "IconDesignerWindowControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsStore(defaults: defaults)
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let status = SystemStatusStore(
            batteryMonitor: WindowNoopBatteryMonitor(),
            wifiMonitor: WindowNoopWiFiMonitor(),
            volumeMonitor: WindowNoopVolumeMonitor()
        )
        let application = ActivationApplicationSpy()
        let policy = AppActivationPolicy(application: application)
        let designer = IconDesignerWindowController(
            store: settings,
            statusStore: status,
            localization: localization,
            activationPolicy: policy,
            chargingEffectClock: ChargingEffectClock()
        )
        return (suite, settings, status, localization, application, policy, designer)
    }
}

@MainActor
private final class ActivationApplicationSpy: ApplicationActivationPolicyApplying {
    private(set) var policies: [NSApplication.ActivationPolicy] = []
    private(set) var currentActivationPolicy: NSApplication.ActivationPolicy = .accessory

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        policies.append(activationPolicy)
        let changed = currentActivationPolicy != activationPolicy
        currentActivationPolicy = activationPolicy
        return changed
    }
}

@MainActor
private final class WindowNoopBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class WindowNoopWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class WindowNoopVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func setDetailsVisible(_ visible: Bool) {}
}
