import AppKit
import Carbon
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsWindowControllerTests: VisibleUITestCase {
    func testShowCreatesReusesAndLocalizesSingleWindow() throws {
        let suiteName = "StatusTrioCoreTests.SettingsWindow.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removeTestSuite(named: suiteName) }

        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.simplifiedChinese))
        let activationApplication = SettingsActivationPolicyApplicationSpy()
        let controller = SettingsWindowController(
            store: SettingsStore(defaults: defaults),
            statusStore: makeStatusStore(),
            localization: localization,
            activationPolicy: AppActivationPolicy(application: activationApplication),
            showIconGuide: {}
        )
        XCTAssertNil(controller.window)

        controller.show()
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }

        XCTAssertEqual(window.title, "设置")
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(activationApplication.policies, [.regular])

        localization.setPreference(.language(.german))
        XCTAssertEqual(window.title, "Einstellungen")

        controller.show()
        XCTAssertTrue(controller.window === window)
        XCTAssertEqual(activationApplication.policies, [.regular])
    }

    func testClosingWindowReleasesContentForNextPresentation() throws {
        let suiteName = "StatusTrioCoreTests.SettingsWindowRelease.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removeTestSuite(named: suiteName) }

        let activationApplication = SettingsActivationPolicyApplicationSpy()
        let controller = SettingsWindowController(
            store: SettingsStore(defaults: defaults),
            statusStore: makeStatusStore(),
            localization: Localization(defaults: defaults, preferredLanguages: ["en"]),
            activationPolicy: AppActivationPolicy(application: activationApplication),
            showIconGuide: {}
        )

        controller.show()
        let firstWindow = try XCTUnwrap(controller.window)
        firstWindow.close()
        XCTAssertNil(controller.window)
        XCTAssertEqual(activationApplication.policies, [.regular, .accessory])

        controller.show()
        let secondWindow = try XCTUnwrap(controller.window)
        XCTAssertFalse(firstWindow === secondWindow)
        secondWindow.close()
    }

    func testClosingSettingsKeepsUserSelectedDockPolicyRegular() throws {
        let suiteName = "StatusTrioCoreTests.SettingsDockPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removeTestSuite(named: suiteName) }

        let activationApplication = SettingsActivationPolicyApplicationSpy()
        let policy = AppActivationPolicy(application: activationApplication)
        XCTAssertTrue(policy.setDockIconVisible(true))
        let controller = SettingsWindowController(
            store: SettingsStore(defaults: defaults),
            statusStore: makeStatusStore(),
            localization: Localization(defaults: defaults, preferredLanguages: ["en"]),
            activationPolicy: policy,
            showIconGuide: {}
        )

        controller.show()
        try XCTUnwrap(controller.window).close()

        XCTAssertEqual(activationApplication.policies, [.regular, .regular, .regular])
    }

    func testSettingsWindowTogglesVolumeDetailsVisibility() throws {
        let suiteName = "StatusTrioCoreTests.SettingsVolumeDetails.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removeTestSuite(named: suiteName) }

        let volume = NoopVolumeMonitor()
        let statusStore = SystemStatusStore(
            batteryMonitor: NoopBatteryMonitor(),
            wifiMonitor: NoopWiFiMonitor(),
            volumeMonitor: volume
        )
        let activationApplication = SettingsActivationPolicyApplicationSpy()
        let controller = SettingsWindowController(
            store: SettingsStore(defaults: defaults),
            statusStore: statusStore,
            localization: Localization(defaults: defaults, preferredLanguages: ["en"]),
            activationPolicy: AppActivationPolicy(application: activationApplication),
            showIconGuide: {}
        )

        controller.show()
        XCTAssertEqual(volume.detailsVisibility, [true])

        try XCTUnwrap(controller.window).close()
        XCTAssertEqual(volume.detailsVisibility, [true, false])
    }

    func testFirstBluetoothAuthorizationReadDoesNotOpenSettings() throws {
        for authorization in [BluetoothAuthorizationStatus.allowed, .denied, .restricted] {
            try withAuthorizationFixture { controller, statusStore, monitor, application in
                monitor.authorization = authorization
                statusStore.setPopoverVisible(true)
                defer {
                    statusStore.setPopoverVisible(false)
                    controller.window?.close()
                }

                XCTAssertTrue(statusStore.isPopoverVisible)
                XCTAssertEqual(statusStore.bluetoothDevices.authorizationStatus, authorization)
                XCTAssertNil(controller.window)
                XCTAssertTrue(application.policies.isEmpty)
            }
        }
    }

    func testBluetoothAuthorizationChangeDoesNotReopenClosedSettings() throws {
        try withAuthorizationFixture { controller, statusStore, monitor, application in
            controller.show()
            try XCTUnwrap(controller.window).close()
            let policies = application.policies

            monitor.authorization = .allowed
            statusStore.bluetoothDevices.prepareForPresentation()
            defer { controller.window?.close() }

            XCTAssertNil(controller.window)
            XCTAssertEqual(application.policies, policies)
        }
    }

    func testPermissionDecisionResurfacesExistingSettingsWindow() throws {
        try withAuthorizationFixture { controller, statusStore, monitor, application in
            controller.show()
            let window = try XCTUnwrap(controller.window)
            defer { window.close() }
            window.orderOut(nil)
            let policies = application.policies

            monitor.authorization = .allowed
            statusStore.bluetoothDevices.prepareForPresentation()

            XCTAssertTrue(controller.window === window)
            XCTAssertTrue(window.isVisible)
            XCTAssertEqual(application.policies, policies)
        }
    }

    func testFirstPopoverAuthorizationReadDoesNotResurfaceExistingSettings() throws {
        try withAuthorizationFixture { controller, statusStore, monitor, application in
            controller.show()
            let window = try XCTUnwrap(controller.window)
            defer {
                statusStore.setPopoverVisible(false)
                window.close()
            }
            window.orderOut(nil)
            let policies = application.policies

            monitor.authorization = .allowed
            statusStore.setPopoverVisible(true)

            XCTAssertTrue(statusStore.isPopoverVisible)
            XCTAssertTrue(controller.window === window)
            XCTAssertFalse(window.isVisible, "a popover permission refresh must not front Settings")
            XCTAssertEqual(application.policies, policies)
        }
    }

    func testAlreadyKnownAuthorizationDoesNotResurfaceSettingsOnRefresh() throws {
        try withAuthorizationFixture(initialAuthorization: .allowed) {
            controller, statusStore, _, _ in
            controller.show()
            let window = try XCTUnwrap(controller.window)
            defer { window.close() }
            window.orderOut(nil)

            statusStore.bluetoothDevices.prepareForPresentation()

            XCTAssertFalse(window.isVisible)
        }
    }

    func testResurfaceDoesNotCreateAnUnopenedSettingsWindow() throws {
        try withAuthorizationFixture { controller, statusStore, _, application in
            controller.resurface()
            defer { controller.window?.close() }

            XCTAssertNil(controller.window)
            XCTAssertTrue(application.policies.isEmpty)
        }
    }

    func testClosingSettingsEndsShortcutRecordingAndRestoresRegistration() throws {
        let suiteName = "StatusTrioCoreTests.SettingsShortcutClose.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removeTestSuite(named: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        settings.statusPanelShortcut = StatusPanelShortcut(
            keyCode: 0,
            modifiers: UInt32(cmdKey)
        )
        let backend = SettingsShortcutBackend()
        let shortcutController = GlobalShortcutController(
            settings: settings,
            backend: backend,
            action: {}
        )
        shortcutController.start()
        let controller = SettingsWindowController(
            store: settings,
            statusStore: makeStatusStore(),
            localization: Localization(defaults: defaults, preferredLanguages: ["en"]),
            activationPolicy: AppActivationPolicy(application: SettingsActivationPolicyApplicationSpy()),
            showIconGuide: {},
            globalShortcutController: shortcutController
        )

        controller.show()
        shortcutController.beginRecording()
        XCTAssertTrue(backend.liveShortcutCount == 0)

        try XCTUnwrap(controller.window).close()

        XCTAssertFalse(shortcutController.isRecording)
        XCTAssertEqual(backend.liveShortcutCount, 1)
    }

    func testShowWithBatterySectionAnnouncesTabRequest() throws {
        let suiteName = "StatusTrioCoreTests.SettingsSectionRoute.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removeTestSuite(named: suiteName) }
        let controller = SettingsWindowController(
            store: SettingsStore(defaults: defaults),
            statusStore: makeStatusStore(),
            localization: Localization(defaults: defaults, preferredLanguages: ["en"]),
            activationPolicy: AppActivationPolicy(application: SettingsActivationPolicyApplicationSpy()),
            showIconGuide: {}
        )
        let request = expectation(forNotification: .settingsSelectSection, object: nil)

        controller.show(section: .battery)
        wait(for: [request], timeout: 1)

        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        XCTAssertTrue(window.isVisible)
    }

    func testShowWithSubtopicAnnouncesAndQueuesOneLeafRequest() throws {
        let suiteName = "StatusTrioCoreTests.SettingsSubtopicRoute.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removeTestSuite(named: suiteName) }
        let controller = SettingsWindowController(
            store: SettingsStore(defaults: defaults),
            statusStore: makeStatusStore(),
            localization: Localization(defaults: defaults, preferredLanguages: ["en"]),
            activationPolicy: AppActivationPolicy(application: SettingsActivationPolicyApplicationSpy()),
            showIconGuide: {}
        )
        let request = expectation(forNotification: .settingsSelectSection, object: nil)

        controller.show(subtopic: .appIconRing)
        wait(for: [request], timeout: 1)

        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        XCTAssertTrue(window.isVisible)
        // The category and its leaf are consumed together, so a second read
        // yields nothing rather than leaking a stale request into the next open.
        XCTAssertNil(controller.takePendingSection())
        XCTAssertNil(controller.takePendingSubtopic())
    }

    #if DEBUG
    func testBackgroundPresentationReusesClosesAndRebuildsWithoutRegularPolicy() throws {
        var presentations: [SettingsWindowPresentation] = []
        try withAuthorizationFixture(
            configuration: BackgroundUITestingConfiguration(arguments: ["--background-ui-testing"]),
            presentWindow: { window, mode in
                presentations.append(mode)
                window.orderFront(nil)
            }
        ) { controller, statusStore, _, application in
            var visibility: [Bool] = []
            controller.startPreviewResourceObservation { visibility.append($0) }
            controller.show()
            let first = try XCTUnwrap(controller.window)
            XCTAssertEqual(first.frameAutosaveName, "")
            controller.show(section: .battery)
            XCTAssertTrue(controller.window === first)
            XCTAssertEqual(presentations, [.background, .background])
            XCTAssertTrue(application.policies.isEmpty)
            first.close()
            XCTAssertNil(controller.window)
            controller.show()
            let second = try XCTUnwrap(controller.window)
            XCTAssertFalse(first === second)
            second.close()
            XCTAssertEqual(visibility, [false, true, false, true, false])
            XCTAssertTrue(application.policies.isEmpty)
            statusStore.setSettingsVisible(false)
        }
    }

    func testBackgroundPermissionDecisionDoesNotPresentOrReopenSettings() throws {
        var presentations = 0
        try withAuthorizationFixture(
            configuration: BackgroundUITestingConfiguration(arguments: ["--background-ui-testing"]),
            presentWindow: { window, _ in
                presentations += 1
                window.orderFront(nil)
            }
        ) { controller, statusStore, monitor, application in
            controller.show()
            let window = try XCTUnwrap(controller.window)
            window.orderOut(nil)
            monitor.authorization = .allowed
            statusStore.bluetoothDevices.prepareForPresentation()
            XCTAssertFalse(window.isVisible)
            XCTAssertEqual(presentations, 1)
            window.close()
            controller.resurface()
            XCTAssertNil(controller.window)
            XCTAssertEqual(presentations, 1)
            XCTAssertTrue(application.policies.isEmpty)
        }
    }
    #endif

    func testNormalPresentationKeepsActivatingStrategyAndAutosave() throws {
        var presentations: [SettingsWindowPresentation] = []
        try withAuthorizationFixture(presentWindow: { _, mode in presentations.append(mode) }) {
            controller, _, _, application in
            controller.show()
            let window = try XCTUnwrap(controller.window)
            defer { window.close() }
            controller.resurface()
            XCTAssertEqual(presentations, [.activating, .activating])
            XCTAssertEqual(application.policies, [.regular])
            XCTAssertEqual(window.frameAutosaveName, "SettingsWindow.Sidebar.v1")
        }
    }

    private func withAuthorizationFixture(
        initialAuthorization: BluetoothAuthorizationStatus = .notDetermined,
        configuration: BackgroundUITestingConfiguration = .disabled,
        presentWindow: @escaping @MainActor (NSWindow, SettingsWindowPresentation) -> Void = {
            window, mode in mode.present(window)
        },
        _ body: (SettingsWindowController, SystemStatusStore,
                 SettingsBluetoothStateMonitor, SettingsActivationPolicyApplicationSpy) throws -> Void
    ) throws {
        let suiteName = "StatusTrioCoreTests.SettingsAuthorization.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removeTestSuite(named: suiteName) }
        let monitor = SettingsBluetoothStateMonitor()
        monitor.authorization = initialAuthorization
        let bluetooth = BluetoothDeviceController(stateMonitor: monitor)
        bluetooth.prepareForPresentation()
        let statusStore = SystemStatusStore(
            batteryMonitor: NoopBatteryMonitor(),
            wifiMonitor: NoopWiFiMonitor(),
            volumeMonitor: NoopVolumeMonitor(),
            bluetoothDevices: bluetooth
        )
        defer { statusStore.stop() }
        let application = SettingsActivationPolicyApplicationSpy()
        let controller = SettingsWindowController(
            store: SettingsStore(defaults: defaults),
            statusStore: statusStore,
            localization: Localization(defaults: defaults, preferredLanguages: ["en"]),
            activationPolicy: AppActivationPolicy(application: application),
            showIconGuide: {},
            backgroundUITesting: configuration,
            presentWindow: presentWindow
        )
        try body(controller, statusStore, monitor, application)
    }

    private func makeStatusStore() -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: NoopBatteryMonitor(),
            wifiMonitor: NoopWiFiMonitor(),
            volumeMonitor: NoopVolumeMonitor()
        )
    }
}

@MainActor
private final class SettingsActivationPolicyApplicationSpy: ApplicationActivationPolicyApplying {
    private(set) var policies: [NSApplication.ActivationPolicy] = []
    private(set) var currentActivationPolicy: NSApplication.ActivationPolicy = .accessory

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        policies.append(activationPolicy)
        guard currentActivationPolicy != activationPolicy else { return false }
        currentActivationPolicy = activationPolicy
        return true
    }
}

@MainActor
private final class SettingsShortcutBackend: GlobalShortcutRegistering {
    private var tokens: Set<UUID> = []

    var liveShortcutCount: Int { tokens.count }

    func register(
        _ shortcut: StatusPanelShortcut,
        action: @escaping @MainActor () -> Void
    ) throws -> UUID {
        let token = UUID()
        tokens.insert(token)
        return token
    }

    func unregister(_ token: UUID) {
        tokens.remove(token)
    }

    func stop() {
        tokens.removeAll()
    }
}

@MainActor
private final class NoopBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>

    init() {
        (updates, _) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class NoopWiFiMonitor: WiFiMonitoring {
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
private final class NoopVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    private(set) var detailsVisibility: [Bool] = []

    init() {
        (updates, _) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func setDetailsVisible(_ visible: Bool) {
        detailsVisibility.append(visible)
    }
}

@MainActor
private final class SettingsBluetoothStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    var authorization: BluetoothAuthorizationStatus = .notDetermined

    func start() {}
    func stop() {}
}
