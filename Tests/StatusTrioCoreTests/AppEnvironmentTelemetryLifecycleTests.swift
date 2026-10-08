import AppKit
import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class AppEnvironmentTelemetryLifecycleTests: XCTestCase {
    func testEnvironmentStartsAndStopsTelemetryAlongsideFakeStatusServices() throws {
        let suiteName = "AppEnvironmentTelemetryLifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        settings.hasCompletedIconGuideOnboarding = true
        settings.completeTelemetryConsent(sharesAnalytics: false)
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let battery = LifecycleBatteryMonitor()
        let wifi = LifecycleWiFiMonitor()
        let volume = LifecycleVolumeMonitor()
        let store = AppEnvironment.makeStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume
        )
        let reporter = LifecycleTelemetryReporter()
        let environment = makeEnvironment(
            store: store, settings: settings, localization: localization, reporter: reporter
        )
        defer { environment.stop() }

        environment.start()

        XCTAssertEqual(reporter.startCount, 1)
        XCTAssertEqual(battery.startCount, 1)
        XCTAssertEqual(wifi.startCount, 1)
        XCTAssertEqual(volume.startCount, 1)

        environment.stop()

        XCTAssertEqual(reporter.stopCount, 1)
        XCTAssertEqual(battery.stopCount, 1)
        XCTAssertEqual(wifi.stopCount, 1)
        XCTAssertEqual(volume.stopCount, 1)
    }

    func testQueuedSettingsEnableThenOptOutDoesNotStartBatteryRead() async throws {
        try await assertRevokedSettingsTupleDoesNotStartBatteryRead { settings in
            settings.refreshesAirPodsBatteryForIcon = false
        }
    }

    func testQueuedSettingsEnableThenClassicDoesNotStartBatteryRead() async throws {
        try await assertRevokedSettingsTupleDoesNotStartBatteryRead { settings in
            settings.updateIconConfiguration { $0 = .classic }
        }
    }

    private func assertRevokedSettingsTupleDoesNotStartBatteryRead(
        revoke: @MainActor (SettingsStore) -> Void
    ) async throws {
        let suiteName = "AppEnvironmentQueuedDemand.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        settings.hasCompletedIconGuideOnboarding = true
        settings.completeTelemetryConsent(sharesAnalytics: false)
        settings.updateIconConfiguration { $0 = .classic }
        settings.refreshesAirPodsBatteryForIcon = false
        let batteryReader = QueuedDemandBatteryReader()
        let batteryEvents = QueuedDemandBatteryEvents()
        let bluetooth = BluetoothDeviceController(
            worker: QueuedDemandDeviceReader(),
            stateMonitor: QueuedDemandStateMonitor(),
            batteryReader: batteryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            accessoryBatteryEvents: batteryEvents
        )

        // A real Settings owner already monitors a connected AirPods device.
        // No visible surface or battery owner is involved in the setup.
        let cachedAirPods = expectation(description: "connected AirPods cache is committed")
        let deviceSubscription = bluetooth.$devices.dropFirst().sink { devices in
            if devices.contains(where: \.isConnected) { cachedAirPods.fulfill() }
        }
        XCTAssertTrue(bluetooth.requestActivation(BluetoothDeviceController.settingsActivationToken))
        await fulfillment(of: [cachedAirPods], timeout: 1)
        deviceSubscription.cancel()
        XCTAssertEqual(bluetooth.devices.count, 1)
        XCTAssertTrue(bluetooth.isActive)

        let store = SystemStatusStore(
            batteryMonitor: LifecycleBatteryMonitor(),
            wifiMonitor: LifecycleWiFiMonitor(),
            volumeMonitor: LifecycleVolumeMonitor(),
            wakeNotificationCenter: NotificationCenter(),
            bluetoothDevices: bluetooth
        )
        let environment = makeEnvironment(
            store: store, settings: settings,
            localization: Localization(defaults: defaults, preferredLanguages: ["en"]),
            reporter: LifecycleTelemetryReporter()
        )
        defer { environment.stop() }
        environment.start()
        await drainMainQueue()
        let readsBefore = batteryReader.readCount
        let claimsBefore = batteryEvents.startCount
        XCTAssertEqual(readsBefore, 0)
        XCTAssertEqual(claimsBefore, 0)

        var airPodsConfiguration = IconConfigurationV1.classic
        airPodsConfiguration.composition.outerRing.primary = .airPodsBattery
        // These are real @Published SettingsStore updates in one main-actor
        // turn. The production subscriptions have not drained when revoked.
        settings.updateIconConfiguration { $0 = airPodsConfiguration }
        settings.refreshesAirPodsBatteryForIcon = true
        revoke(settings)
        await drainMainQueue()
        await drainMainQueue()

        XCTAssertEqual(batteryEvents.startCount, claimsBefore, "a revoked queued tuple must not claim accessory battery events")
        XCTAssertEqual(batteryReader.readCount, readsBefore, "releasing a stale claim cannot undo an already-started I/O read")
        XCTAssertFalse(bluetooth.isBatteryLevelsRequested)
        XCTAssertTrue(bluetooth.isActive, "the independent Settings activation must survive")

        // Positive control: keeping the opt-in committed must still exercise
        // the real AppEnvironment subscription and controller read path.
        settings.updateIconConfiguration { $0 = airPodsConfiguration }
        settings.refreshesAirPodsBatteryForIcon = true
        await drainMainQueue()
        XCTAssertGreaterThan(batteryEvents.startCount, claimsBefore)
        XCTAssertGreaterThan(batteryReader.readCount, readsBefore)
        XCTAssertTrue(bluetooth.isBatteryLevelsRequested)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func makeEnvironment(
        store: SystemStatusStore,
        settings: SettingsStore,
        localization: Localization,
        reporter: LifecycleTelemetryReporter
    ) -> AppEnvironment {
        let iconPresentation = makeTestIconPresentation(store: store, settings: settings)
        let clock = ChargingEffectClock()
        let activationApplication = LifecycleApplicationSpy()
        let activationPolicy = AppActivationPolicy(application: activationApplication)
        let onboarding = OnboardingWindowController(
            settings: settings,
            localization: localization,
            activationPolicy: activationPolicy
        )
        let settingsWindow = SettingsWindowController(
            store: settings,
            statusStore: store,
            localization: localization,
            activationPolicy: activationPolicy,
            showIconGuide: {},
            chargingEffectClock: clock
        )
        let statusBar = StatusBarController(
            store: store,
            settings: settings,
            iconPresentation: iconPresentation,
            localization: localization,
            isVisible: false,
            openSettings: {},
            quitAction: {},
            chargingEffectClock: clock,
            renderMenuBarIcon: { _, _, _, _, _ in nil }
        )
        let appIcon = AppIconController(
            settings: settings,
            iconPresentation: iconPresentation,
            activationPolicy: activationPolicy,
            application: activationApplication,
            setMenuBarVisible: { _ in },
            renderDockIcon: { _, _, _ in nil },
            theme: { .default },
            isDarkAppearance: { false },
            notificationCenter: NotificationCenter()
        )
        return AppEnvironment(
            store: store,
            settings: settings,
            localization: localization,
            iconPresentation: iconPresentation,
            statusBarController: statusBar,
            settingsWindowController: settingsWindow,
            onboardingWindowController: onboarding,
            activationPolicy: activationPolicy,
            appIconController: appIcon,
            mainMenuController: MainMenuController(
                activationPolicy: activationPolicy,
                localization: localization,
                notificationCenter: NotificationCenter(),
                openSettings: {}
            ),
            chargingEffectClock: clock,
            chargingEffectMotionMonitor: ChargingEffectMotionMonitor(
                readReduceMotion: { false },
                notificationCenter: NotificationCenter()
            ),
            telemetryReporter: reporter
        )
    }
}

@MainActor
private final class LifecycleTelemetryReporter: TelemetryReporting {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

@MainActor
private final class LifecycleApplicationSpy: ApplicationActivationPolicyApplying, ApplicationDockIconApplying {
    private(set) var currentActivationPolicy: NSApplication.ActivationPolicy = .accessory
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        currentActivationPolicy = activationPolicy
        return true
    }
    func setApplicationIconImage(_ image: NSImage?) {}
}

@MainActor
private final class LifecycleBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    private(set) var startCount = 0
    private(set) var stopCount = 0
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func refresh() {}
    func recover() {}
}

@MainActor
private final class LifecycleWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    private(set) var startCount = 0
    private(set) var stopCount = 0
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class LifecycleVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    private(set) var startCount = 0
    private(set) var stopCount = 0
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func refresh() {}
    func recover() {}
    func setDetailsVisible(_ visible: Bool) {}
}

@MainActor
private final class QueuedDemandStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed
    func start() { onStateChange?(.allowed, .poweredOn) }
    func stop() {}
}

private final class QueuedDemandDeviceReader: BluetoothPairedDeviceReading {
    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        completion(.success([BluetoothDevice(
            id: "AA:BB:CC:DD:EE:10", name: "AirPods", kind: .audio,
            isConnected: true, airPodsModel: .airPodsPro
        )]))
    }
}

private final class QueuedDemandBatteryReader: BluetoothBatteryReading {
    private let lock = NSLock()
    private var storedReadCount = 0
    var readCount: Int { lock.withLock { storedReadCount } }
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        lock.withLock { storedReadCount += 1 }
        // Count the actual I/O entry without scheduling unrelated completions.
    }
}

private final class QueuedDemandBatteryEvents: BluetoothAccessoryBatteryEventMonitoring {
    private let lock = NSLock()
    private var storedStartCount = 0
    var startCount: Int { lock.withLock { storedStartCount } }
    func start(handler: @escaping @Sendable () -> Void) -> Bool {
        lock.withLock { storedStartCount += 1 }
        return true
    }
    func stop() {}
}
