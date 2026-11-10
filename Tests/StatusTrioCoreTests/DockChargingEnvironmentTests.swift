import AppKit
import Testing
@testable import StatusTrioCore

/// End-to-end wiring for the Dock charging animation: the user's Dock-only
/// placement claims the shared clock, the clock's phases reach the Dock
/// presenter, and going back to a menu-bar placement releases both.
@Suite(.serialized)
@MainActor
struct DockChargingEnvironmentTests {
    @Test func recoveredPresentationReclaimsDockOwnershipBeforeStaticRendering() async throws {
        let presenter = RecordingDockChargingPresenter()
        presenter.failsPulsingAccessory = true
        let fixture = try DockChargingEnvironmentFixture(presenter: presenter)
        defer { fixture.tearDown() }

        fixture.environment.start()
        let deadline = Date().addingTimeInterval(5)
        while presenter.restoreCount == 0, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(presenter.restoreCount > 0)

        fixture.settings.showsChargingBoltHeartbeat = false
        while !presenter.isInstalled, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(presenter.isInstalled)
        #expect(presenter.presentedScenes.last?.outerRing?.effect?.pulsesAccessory == false)

        fixture.environment.appIconController.flushPendingPresentationForTesting()
        let assignmentsBeforeSceneChange = fixture.application.assignments
        fixture.settings.showsBatteryPercentageInConnectionSlot = true
        fixture.environment.appIconController.flushPendingPresentationForTesting()
        #expect(fixture.application.assignments == assignmentsBeforeSceneChange)
    }

    @Test func renderFailureRestoresTheStaticDockWithoutExplicitClear() async throws {
        let presenter = RecordingDockChargingPresenter()
        presenter.presentSucceeds = false
        let timing = ManualChargingClockTiming()
        let sleeper = ManualEventSleeper()
        let clock = ChargingEffectClock(
            now: { Date(timeIntervalSinceReferenceDate: timing.date) },
            sleep: { await sleeper.sleep($0) }
        )
        let fixture = try DockChargingEnvironmentFixture(
            presenter: presenter,
            clock: clock
        )
        defer {
            fixture.tearDown()
            sleeper.releaseAll()
        }

        fixture.environment.start()
        #expect(fixture.clock.isRunning)
        let armed = await sleeper.waitForCallCount(1, timeout: .seconds(5))
        try #require(armed, "The charging clock must schedule its next frame.")
        #expect(presenter.restoreCount > 0)
        let clearsBeforeRepeatedFailure = presenter.clearCount

        for frame in 1...2 {
            let restoresBeforeFrame = presenter.restoreCount
            timing.advance(by: 0.05)
            sleeper.releaseAll()
            let nextTickArmed = await sleeper.waitForCallCount(frame + 1, timeout: .seconds(5))
            try #require(nextTickArmed, "The charging clock must schedule frame \(frame + 1).")
            #expect(presenter.restoreCount == restoresBeforeFrame + 1)
        }
        #expect(presenter.clearCount == clearsBeforeRepeatedFailure)
    }

    @Test func dockOnlyEffectStillRunsTheSharedClockWithTheMenuBarEffectOff() async throws {
        let fixture = try DockChargingEnvironmentFixture(placement: .both)
        defer { fixture.tearDown() }
        fixture.settings.showsMenuBarChargingEffect = false
        fixture.settings.showsDockChargingEffect = true

        fixture.environment.start()
        try await fixture.waitForPresentedPhase()

        #expect(fixture.clock.isRunning)
        #expect(fixture.clock.isDockAnimationActive)
        #expect(!fixture.presenter.presentedPhases.isEmpty)
        #expect(fixture.presenter.presentedScenes.last?.outerRing?.effect != nil)
    }

    @Test func menuBarOnlyEffectLeavesTheDockStatic() async throws {
        let fixture = try DockChargingEnvironmentFixture(placement: .both)
        defer { fixture.tearDown() }
        fixture.settings.showsMenuBarChargingEffect = true
        fixture.settings.showsDockChargingEffect = false

        fixture.environment.start()
        try await Task.sleep(for: .milliseconds(250))

        #expect(fixture.clock.isRunning)
        #expect(!fixture.clock.isDockAnimationActive)
        #expect(fixture.presenter.presentedPhases.isEmpty)
        #expect(fixture.presenter.clearCount > 0)
    }

    @Test func bothSurfaceEffectsOffStopsTheSharedClockAndLeavesTheDockStatic() async throws {
        let fixture = try DockChargingEnvironmentFixture(placement: .both)
        defer { fixture.tearDown() }
        fixture.settings.showsMenuBarChargingEffect = false
        fixture.settings.showsDockChargingEffect = false

        fixture.environment.start()
        try await Task.sleep(for: .milliseconds(250))

        #expect(!fixture.clock.isRunning)
        #expect(!fixture.clock.isDockAnimationActive)
        #expect(fixture.presenter.presentedPhases.isEmpty)
    }

    @Test func dockOnlyPlacementDrivesOneClockIntoTheDockPresenter() async throws {
        let fixture = try DockChargingEnvironmentFixture()
        defer { fixture.tearDown() }

        fixture.environment.start()
        try await fixture.waitForPresentedPhase()

        #expect(fixture.presenter.presentedPhases.isEmpty == false)
        #expect(fixture.presenter.presentedPhases.allSatisfy { $0.stepsPerCycle == 36 })
        #expect(fixture.clock.isDockAnimationActive)
        #expect(fixture.clock.isRunning)
        #expect(fixture.presenter.isInstalled)

        fixture.settings.appIconPlacement = .menuBar
        try await fixture.waitForClockToStop()

        #expect(fixture.clock.isRunning == false)
        #expect(fixture.clock.isDockAnimationActive == false)
        #expect(fixture.presenter.clearCount > 0)
    }

    @Test func chargingWhileDockIsOnlyTemporarilyRegularNeverClaimsTheClock() async throws {
        let fixture = try DockChargingEnvironmentFixture(placement: .menuBar)
        defer { fixture.tearDown() }

        fixture.environment.start()
        fixture.activationPolicy.enterTemporaryRegularMode()
        try await Task.sleep(for: .milliseconds(200))

        #expect(fixture.clock.isDockAnimationActive == false)
        #expect(fixture.presenter.presentedPhases.isEmpty)
        #expect(fixture.application.applicationIconImage != nil)
    }

    @Test func theDevelopmentChargingPreviewDrivesTheDockClockWithoutRealCharging() async throws {
        let timing = ManualChargingClockTiming()
        let sleeper = ManualEventSleeper()
        let clock = ChargingEffectClock(
            now: { Date(timeIntervalSinceReferenceDate: timing.date) },
            sleep: { await sleeper.sleep($0) }
        )
        let fixture = try DockChargingEnvironmentFixture(
            placement: .both,
            batteryIsCharging: false,
            clock: clock
        )
        defer { fixture.tearDown() }
        fixture.settings.setChargingEffectTestEnabled(true)

        fixture.environment.start()
        try await fixture.waitForPresentedPhase()

        #expect(fixture.clock.isRunning)
        #expect(fixture.clock.isDockAnimationActive)
        #expect(fixture.presenter.presentedPhases.isEmpty == false)
        #expect(fixture.clock.phase?.kind == .burst)
        let armed = await sleeper.waitForCallCount(1, timeout: .seconds(5))
        try #require(armed, "The charging clock must schedule its next frame.")
        let burstFrames = Int((ChargingEffectTimeline.burstDuration * 20).rounded())
        for frame in 1...burstFrames {
            timing.advance(by: 0.05)
            sleeper.releaseAll()
            let nextTickArmed = await sleeper.waitForCallCount(frame + 1, timeout: .seconds(5))
            try #require(nextTickArmed, "The charging clock must schedule frame \(frame + 1).")
        }
        timing.advance(by: 0.05)
        sleeper.releaseAll()
        let nextTickArmed = await sleeper.waitForCallCount(burstFrames + 2, timeout: .seconds(5))
        try #require(nextTickArmed, "The charging clock must continue into the steady phase.")
        #expect(fixture.clock.phase?.kind == .steady)
        #expect(fixture.clock.phase?.stepsPerCycle == 36)
        #expect(fixture.presenter.presentedPhases.count == burstFrames + 2)
    }

    @Test func togglingTheRealSettingsStoreReachesTheDockClock() async throws {
        let fixture = try DockChargingEnvironmentFixture(
            placement: .both,
            batteryIsCharging: false
        )
        defer { fixture.tearDown() }

        fixture.environment.start()
        #expect(!fixture.clock.isRunning)

        fixture.settings.setChargingEffectTestEnabled(true)
        try await fixture.waitForPresentedPhase()

        #expect(fixture.clock.isRunning)
        #expect(fixture.clock.isDockAnimationActive)
        #expect(fixture.presenter.presentedPhases.isEmpty == false)
    }

    @Test func theRealStorePublishesTheTestSceneWhenTheTestInputChanges() async throws {
        let fixture = try DockChargingEnvironmentFixture(
            placement: .both,
            batteryIsCharging: false
        )
        defer { fixture.tearDown() }

        fixture.environment.start()
        #expect(fixture.iconPresentation.output.menuBarTestScene == nil)

        fixture.settings.setChargingEffectTestEnabled(true)
        let deadline = Date().addingTimeInterval(5)
        while fixture.iconPresentation.output.menuBarTestScene == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(fixture.iconPresentation.output.menuBarTestScene != nil)
        #expect(fixture.iconPresentation.output.menuBarTestScene?.outerRing?.effect != nil)
    }

    @Test func hiddenDockSuspendsTheDockOnlyAnimationUntilItReturns() async throws {
        let dockVisibility = DockVisibilityMonitorSpy(isDockVisible: false)
        let fixture = try DockChargingEnvironmentFixture(
            placement: .both,
            dockVisibilityMonitor: dockVisibility
        )
        defer { fixture.tearDown() }
        fixture.settings.showsMenuBarChargingEffect = false
        fixture.settings.showsDockChargingEffect = true

        fixture.environment.start()
        try await Task.sleep(for: .milliseconds(250))

        #expect(!fixture.clock.isRunning)
        #expect(!fixture.clock.isDockAnimationActive)
        #expect(fixture.presenter.presentedPhases.isEmpty)

        dockVisibility.setVisible(true)
        try await fixture.waitForPresentedPhase()
        #expect(fixture.clock.isRunning)
        #expect(fixture.clock.isDockAnimationActive)

        dockVisibility.setVisible(false)
        try await fixture.waitForClockToStop()
        #expect(!fixture.clock.isRunning)
        #expect(!fixture.clock.isDockAnimationActive)
        #expect(fixture.presenter.clearCount > 0)
    }

    @Test func hiddenDockDoesNotStopTheMenuBarAnimation() async throws {
        let dockVisibility = DockVisibilityMonitorSpy(isDockVisible: false)
        let fixture = try DockChargingEnvironmentFixture(
            placement: .both,
            dockVisibilityMonitor: dockVisibility
        )
        defer { fixture.tearDown() }
        fixture.settings.showsMenuBarChargingEffect = true
        fixture.settings.showsDockChargingEffect = true

        fixture.environment.start()
        try await fixture.waitForClockToRun()
        try await Task.sleep(for: .milliseconds(250))

        #expect(fixture.clock.isRunning)
        #expect(!fixture.clock.isDockAnimationActive)
        #expect(fixture.presenter.presentedPhases.isEmpty)
    }

    @Test func dockVisibilityPollingStartsOnlyWhileTheDockAnimationIsNeeded() async throws {
        let dockVisibility = DockVisibilityMonitorSpy()
        let fixture = try DockChargingEnvironmentFixture(
            placement: .dock,
            batteryIsCharging: false,
            dockVisibilityMonitor: dockVisibility
        )
        defer { fixture.tearDown() }
        fixture.settings.showsMenuBarChargingEffect = false
        fixture.settings.showsDockChargingEffect = true

        fixture.environment.start()
        try await Task.sleep(for: .milliseconds(250))
        #expect(dockVisibility.startCount == 0)

        fixture.settings.setChargingEffectTestEnabled(true)
        try await fixture.waitForDockVisibilityPolling()
        #expect(dockVisibility.startCount == 1)

        fixture.settings.setChargingEffectTestEnabled(false)
        try await fixture.waitForDockVisibilityPollingToStop()
        #expect(dockVisibility.stopCount == 1)
    }

    @Test func systemAppearancePollRefreshesDockVisibility() async throws {
        let dockVisibility = DockVisibilityMonitorSpy()
        let fixture = try DockChargingEnvironmentFixture(
            placement: .dock,
            dockVisibilityMonitor: dockVisibility
        )
        defer { fixture.tearDown() }
        fixture.settings.showsMenuBarChargingEffect = false
        fixture.settings.showsDockChargingEffect = true

        fixture.environment.start()
        try await fixture.waitForDockVisibilityPolling()
        let refreshCount = dockVisibility.refreshCount

        fixture.environment.appIconController.systemPollDidFire?()

        #expect(dockVisibility.refreshCount == refreshCount + 1)
    }
}

@MainActor
private final class DockChargingEnvironmentFixture {
    let environment: AppEnvironment
    let presenter: RecordingDockChargingPresenter
    let clock: ChargingEffectClock
    let iconPresentation: IconPresentationViewModel
    let settings: SettingsStore
    let activationPolicy: AppActivationPolicy
    let application: DockChargingApplicationSpy
    let dockVisibilityMonitor: DockVisibilityMonitorSpy

    private let suiteName: String
    private let defaults: UserDefaults
    private let store: SystemStatusStore

    init(
        placement: AppIconPlacement = .dock,
        batteryIsCharging: Bool = true,
        dockVisibilityMonitor: DockVisibilityMonitorSpy = DockVisibilityMonitorSpy(),
        presenter: RecordingDockChargingPresenter = RecordingDockChargingPresenter(),
        clock: ChargingEffectClock = ChargingEffectClock()
    ) throws {
        suiteName = "StatusTrioCoreTests.DockChargingEnvironment.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw DockChargingEnvironmentError.missingDefaultsSuite
        }
        defaults.removeTestSuite(named: suiteName)
        self.defaults = defaults

        let settings = SettingsStore(defaults: defaults)
        settings.appIconPlacement = placement
        settings.showsChargingEffect = true
        settings.hasCompletedIconGuideOnboarding = true
        settings.completeTelemetryConsent(sharesAnalytics: false)
        self.settings = settings
        self.presenter = presenter
        self.clock = clock

        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        store = SystemStatusStore(
            batteryMonitor: DockChargingIdleBatteryMonitor(),
            wifiMonitor: DockChargingIdleWiFiMonitor(),
            volumeMonitor: DockChargingIdleVolumeMonitor(),
            refreshInterval: .seconds(60),
            initialSnapshot: StatusSnapshot(
                battery: BatteryStatus(
                    rawPercentage: 62,
                    isPresent: true,
                    isCharging: batteryIsCharging,
                    isLowPowerMode: false,
                    isConnectedToPower: batteryIsCharging
                ),
                wifi: .placeholder,
                volume: .placeholder
            )
        )
        let iconPresentation = makeTestIconPresentation(store: store, settings: settings)
        self.iconPresentation = iconPresentation
        let application = DockChargingApplicationSpy()
        self.application = application
        let activationPolicy = AppActivationPolicy(application: application)
        self.activationPolicy = activationPolicy
        self.dockVisibilityMonitor = dockVisibilityMonitor
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
            isVisible: placement.showsMenuBarIcon,
            openSettings: {},
            quitAction: {},
            chargingEffectClock: clock,
            renderMenuBarBase: { _, _, _, _ in nil },
            renderMenuBarOverlay: { _, _, _, _, _ in nil }
        )
        let appIcon = AppIconController(
            settings: settings,
            iconPresentation: iconPresentation,
            activationPolicy: activationPolicy,
            application: application,
            setMenuBarVisible: { _ in },
            renderDockIcon: { _, _, _ in NSImage(size: NSSize(width: 512, height: 512)) },
            theme: { .default },
            isDarkAppearance: { false },
            notificationCenter: NotificationCenter()
        )
        environment = AppEnvironment(
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
            inputSourceController: InputSourceController(),
            chargingEffectClock: clock,
            chargingEffectMotionMonitor: ChargingEffectMotionMonitor(
                readReduceMotion: { false },
                notificationCenter: NotificationCenter()
            ),
            dockChargingAnimationPresenter: presenter,
            dockVisibilityMonitor: dockVisibilityMonitor,
            telemetryReporter: DockChargingIdleTelemetryReporter()
        )
    }

    func waitForPresentedPhase(timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while presenter.presentedPhases.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard !presenter.presentedPhases.isEmpty else {
            throw DockChargingEnvironmentTestFailure.conditionNotMet(
                "The Dock presenter did not receive a phase.",
                snapshot: snapshot(),
                timeout: timeout
            )
        }
    }

    func waitForClockToStop(timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while clock.isRunning, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard !clock.isRunning else {
            throw DockChargingEnvironmentTestFailure.conditionNotMet(
                "The charging clock did not stop.",
                snapshot: snapshot(),
                timeout: timeout
            )
        }
    }

    func waitForClockToRun(timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !clock.isRunning, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard clock.isRunning else {
            throw DockChargingEnvironmentTestFailure.conditionNotMet(
                "The charging clock did not start.",
                snapshot: snapshot(),
                timeout: timeout
            )
        }
    }

    func waitForDockVisibilityPolling(timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while dockVisibilityMonitor.startCount == 0, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard dockVisibilityMonitor.startCount > 0 else {
            throw DockChargingEnvironmentTestFailure.conditionNotMet(
                "Dock visibility polling did not start.",
                snapshot: snapshot(),
                timeout: timeout
            )
        }
    }

    func waitForDockVisibilityPollingToStop(timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while dockVisibilityMonitor.stopCount == 0, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard dockVisibilityMonitor.stopCount > 0 else {
            throw DockChargingEnvironmentTestFailure.conditionNotMet(
                "Dock visibility polling did not stop.",
                snapshot: snapshot(),
                timeout: timeout
            )
        }
    }

    func tearDown() {
        environment.stop()
        defaults.removeTestSuite(named: suiteName)
    }

    func snapshot() -> DockChargingEnvironmentSnapshot {
        DockChargingEnvironmentSnapshot(
            snapshot: store.snapshot,
            clockRunning: clock.isRunning,
            dockAnimationActive: clock.isDockAnimationActive,
            phase: clock.phase,
            presenterInstalled: presenter.isInstalled,
            presentedPhaseCount: presenter.presentedPhases.count,
            presentedSceneCount: presenter.presentedScenes.count,
            clearCount: presenter.clearCount,
            restoreCount: presenter.restoreCount,
            pollingStarted: dockVisibilityMonitor.startCount > 0,
            pollingStopped: dockVisibilityMonitor.stopCount > 0
        )
    }
}

private struct DockChargingEnvironmentSnapshot: CustomStringConvertible {
    let snapshot: StatusSnapshot
    let clockRunning: Bool
    let dockAnimationActive: Bool
    let phase: ChargingEffectPhase?
    let presenterInstalled: Bool
    let presentedPhaseCount: Int
    let presentedSceneCount: Int
    let clearCount: Int
    let restoreCount: Int
    let pollingStarted: Bool
    let pollingStopped: Bool

    var description: String {
        """
        snapshot: \(snapshot)
        clock running: \(clockRunning)
        dock animation active: \(dockAnimationActive)
        phase: \(String(describing: phase))
        presenter installed: \(presenterInstalled)
        presented phases: \(presentedPhaseCount)
        presented scenes: \(presentedSceneCount)
        clear count: \(clearCount)
        restore count: \(restoreCount)
        polling started: \(pollingStarted)
        polling stopped: \(pollingStopped)
        """
    }
}

private enum DockChargingEnvironmentTestFailure: Error, CustomStringConvertible {
    case conditionNotMet(String, snapshot: DockChargingEnvironmentSnapshot, timeout: TimeInterval)

    var description: String {
        switch self {
        case let .conditionNotMet(message, snapshot, timeout):
            "\(message) Timeout: \(timeout)s.\n\(snapshot)"
        }
    }
}

@MainActor
private final class DockVisibilityMonitorSpy: DockVisibilityMonitoring {
    private(set) var isDockVisible: Bool
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var refreshCount = 0
    var onChange: ((Bool) -> Void)?

    init(isDockVisible: Bool = true) {
        self.isDockVisible = isDockVisible
    }

    func start() {
        startCount += 1
        refresh()
    }

    func stop() {
        stopCount += 1
    }

    func refresh() {
        refreshCount += 1
    }

    func setVisible(_ isVisible: Bool) {
        guard isDockVisible != isVisible else { return }
        isDockVisible = isVisible
        onChange?(isVisible)
    }
}

private enum DockChargingEnvironmentError: Error {
    case missingDefaultsSuite
}

@MainActor
private final class ManualChargingClockTiming {
    var date = Date().timeIntervalSinceReferenceDate

    func advance(by interval: TimeInterval) {
        date += interval
    }
}

@MainActor
private final class RecordingDockChargingPresenter: DockChargingAnimationPresenting {
    private(set) var presentedPhases: [ChargingEffectPhase] = []
    private(set) var presentedScenes: [IconSceneState] = []
    private(set) var clearCount = 0
    private(set) var restoreCount = 0
    private(set) var isInstalled = false
    var presentSucceeds = true
    var failsPulsingAccessory = false

    func present(
        phase: ChargingEffectPhase,
        scene: IconSceneState,
        backgroundStyle: DockIconBackgroundStyle,
        pixelLength: Int
    ) -> Bool {
        presentedPhases.append(phase)
        presentedScenes.append(scene)
        guard presentSucceeds,
              !(failsPulsingAccessory && scene.outerRing?.effect?.pulsesAccessory == true)
        else {
            isInstalled = false
            return false
        }
        isInstalled = true
        return true
    }

    func restoreStaticIcon() {
        restoreCount += 1
        isInstalled = false
    }

    func clear() {
        clearCount += 1
        isInstalled = false
    }
}

@MainActor
private final class DockChargingApplicationSpy: ApplicationActivationPolicyApplying, ApplicationDockIconApplying {
    private(set) var currentActivationPolicy: NSApplication.ActivationPolicy = .accessory
    private(set) var applicationIconImage: NSImage?
    private(set) var assignments = 0

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        currentActivationPolicy = activationPolicy
        return true
    }

    func setApplicationIconImage(_ image: NSImage?) {
        assignments += 1
        applicationIconImage = image
    }
}

@MainActor
private final class DockChargingIdleBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class DockChargingIdleWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class DockChargingIdleVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class DockChargingIdleTelemetryReporter: TelemetryReporting {
    func start() {}
    func stop() {}
}
