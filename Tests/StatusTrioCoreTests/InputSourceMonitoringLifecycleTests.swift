import AppKit
import XCTest
@testable import StatusTrioCore

/// 性能验收 at the unit level: the shipped defaults draw no input source at
/// all, so they must cost neither a TIS read nor a distributed observer. The
/// controller is started and stopped by the two settings that can draw one.
@MainActor
final class InputSourceMonitoringLifecycleTests: XCTestCase {
    func testMonitoringFollowsTheTwoFeaturesThatDrawAnInputSource() throws {
        let suiteName = "InputSourceMonitoringLifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        settings.hasCompletedIconGuideOnboarding = true
        let reader = CountingInputSourceReader()
        let controller = InputSourceController(reader: reader)
        let environment = makeEnvironment(
            settings: settings,
            defaults: defaults,
            controller: controller
        )
        defer { environment.stop() }

        environment.start()
        XCTAssertEqual(reader.readCount, 0, "the shipped defaults must not read TIS")

        settings.connectionCenterSource = .inputSource
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(controller.state.selectedID, CountingInputSourceReader.abcID)

        settings.connectionCenterSource = .automatic
        XCTAssertEqual(reader.readCount, 1, "turning the centre slot off stops the reader")

        settings.setPopupSection(.inputSource, enabled: true)
        XCTAssertEqual(reader.readCount, 2, "the panel section starts it again")

        settings.setPopupSection(.inputSource, enabled: false)
        XCTAssertEqual(reader.readCount, 2, "turning the panel section off stops it again")
    }

    private func makeEnvironment(
        settings: SettingsStore,
        defaults: UserDefaults,
        controller: InputSourceController
    ) -> AppEnvironment {
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let store = AppEnvironment.makeStore(
            batteryMonitor: LifecycleStubBatteryMonitor(),
            wifiMonitor: LifecycleStubWiFiMonitor(),
            volumeMonitor: LifecycleStubVolumeMonitor()
        )
        let clock = ChargingEffectClock()
        let application = LifecycleStubApplication()
        let activationPolicy = AppActivationPolicy(application: application)
        let iconPresentation = makeTestIconPresentation(store: store, settings: settings)

        return AppEnvironment(
            store: store,
            settings: settings,
            localization: localization,
            iconPresentation: iconPresentation,
            statusBarController: StatusBarController(
                store: store,
                settings: settings,
                iconPresentation: iconPresentation,
                localization: localization,
                isVisible: false,
                openSettings: {},
                quitAction: {},
                chargingEffectClock: clock,
                renderMenuBarBase: { _, _, _, _ in nil },
                inputSourceController: controller
            ),
            settingsWindowController: SettingsWindowController(
                store: settings,
                statusStore: store,
                localization: localization,
                activationPolicy: activationPolicy,
                showIconGuide: {},
                chargingEffectClock: clock,
                inputSourceController: controller,
                launchAtLogin: LaunchAtLoginManager()
            ),
            onboardingWindowController: OnboardingWindowController(
                settings: settings,
                localization: localization,
                activationPolicy: activationPolicy
            ),
            activationPolicy: activationPolicy,
            appIconController: AppIconController(
                settings: settings,
                iconPresentation: iconPresentation,
                activationPolicy: activationPolicy,
                application: application,
                setMenuBarVisible: { _ in },
                renderDockIcon: { _, _, _ in nil },
                theme: { .default },
                isDarkAppearance: { false },
                notificationCenter: NotificationCenter()
            ),
            mainMenuController: MainMenuController(
                activationPolicy: activationPolicy,
                localization: localization,
                notificationCenter: NotificationCenter(),
                openSettings: {}
            ),
            inputSourceController: controller,
            chargingEffectClock: clock,
            chargingEffectMotionMonitor: ChargingEffectMotionMonitor(
                readReduceMotion: { false },
                notificationCenter: NotificationCenter()
            ),
            telemetryReporter: LifecycleStubTelemetryReporter()
        )
    }
}

/// Counts every read the controller makes, which is what the "off by default"
/// acceptance criterion is about.
private final class CountingInputSourceReader: InputSourceReading {
    static let abcID = "com.apple.keylayout.ABC"
    static let pinyinID = "com.tencent.inputmethod.wetype.pinyin"

    private(set) var readCount = 0

    func currentKeyboardInputSourceID() -> String? { Self.abcID }

    func keyboardInputSources() -> [RawInputSource] {
        readCount += 1
        return [
            RawInputSource(
                id: Self.abcID,
                localizedName: "ABC",
                languages: ["en"],
                iconImageURL: nil,
                isEnabled: true,
                isSelectCapable: true
            )
        ]
    }
}

@MainActor
private final class LifecycleStubTelemetryReporter: TelemetryReporting {
    func start() {}
    func stop() {}
}

@MainActor
private final class LifecycleStubApplication: ApplicationActivationPolicyApplying, ApplicationDockIconApplying {
    private(set) var currentActivationPolicy: NSApplication.ActivationPolicy = .accessory
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool { true }
    func setApplicationIconImage(_ image: NSImage?) {}
}

@MainActor
private final class LifecycleStubBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class LifecycleStubWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class LifecycleStubVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
