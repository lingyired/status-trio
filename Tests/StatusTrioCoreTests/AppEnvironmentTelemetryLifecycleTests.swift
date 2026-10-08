import AppKit
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
        let reporter = LifecycleTelemetryReporter()
        let environment = AppEnvironment(
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
