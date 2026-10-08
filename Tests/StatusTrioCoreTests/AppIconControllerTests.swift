import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct AppIconControllerTests {
    @Test func dockOnlyActivatesAndRendersBeforeHidingMenuBar() throws {
        let harness = try AppIconControllerHarness()
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.reset()

        harness.settings.appIconPlacement = .dock

        #expect(harness.log.events == ["policy:regular", "dock:image", "menu:false"])
    }

    @Test func rejectedDockActivationKeepsMenuBarVisible() throws {
        let harness = try AppIconControllerHarness(acceptsActivationPolicy: false)
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.reset()

        harness.settings.appIconPlacement = .dock

        #expect(harness.log.events == ["policy:regular", "menu:true"])
    }

    @Test func dockOnlyHidesMenuBarWhileAppIsAlreadyRegular() throws {
        // AppKit reports a redundant policy request as a failure even though the
        // app already has the requested policy, which is what happens while the
        // Settings window keeps the app in regular mode.
        let harness = try AppIconControllerHarness(initialPlacement: .menuBar)
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.activationPolicy.enterTemporaryRegularMode()
        harness.log.reset()

        harness.settings.appIconPlacement = .dock

        #expect(harness.log.events == ["policy:regular", "menu:false"])
        #expect(harness.application.applicationIconImage != nil)
    }

    @Test func menuBarOnlyRestoresMenuBeforeRemovingDock() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.reset()

        harness.settings.appIconPlacement = .menuBar

        #expect(harness.log.events == ["menu:true", "policy:accessory", "dock:nil"])
    }

    @Test func menuBarOnlyShowsLiveDockIconWhileWindowKeepsAppRegular() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .menuBar)
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.reset()

        harness.activationPolicy.enterTemporaryRegularMode()

        #expect(harness.log.events == ["policy:regular", "dock:image"])
        #expect(harness.application.applicationIconImage != nil)
    }

    @Test func menuBarOnlyRemovesLiveDockIconAfterLastWindowCloses() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .menuBar)
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.activationPolicy.enterTemporaryRegularMode()
        harness.log.reset()

        harness.activationPolicy.leaveTemporaryRegularMode()

        #expect(harness.log.events == ["policy:accessory", "dock:nil"])
        #expect(harness.application.applicationIconImage == nil)
    }

    @Test func manualUpdateCheckKeepsTheDockPlacementIcon() throws {
        // Reproduces the "check for updates, dismiss You're up to date, the Dock
        // icon turns back into the app icon" report: a Dock placement owns the
        // regular policy, so a manual check may only borrow it.
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }
        harness.controller.start()
        let presentation = ManualUpdatePresentation(
            activationPolicy: harness.activationPolicy,
            application: AppIconActivationSpy()
        )
        harness.log.reset()

        presentation.begin()
        presentation.end()

        #expect(harness.activationPolicy.isRegularApp)
        #expect(harness.application.currentActivationPolicy == .regular)
        #expect(harness.application.applicationIconImage != nil)
        #expect(harness.log.events.contains("policy:accessory") == false)
        #expect(harness.log.events.contains("dock:nil") == false)
    }

    @Test func manualUpdateCheckRestoresMenuBarOnlyPlacement() throws {
        // A menu-bar-only placement has no persistent Dock tile, so the tile the
        // check borrows must be gone once the update cycle finishes.
        let harness = try AppIconControllerHarness(initialPlacement: .menuBar)
        defer { harness.cleanUp() }
        harness.controller.start()
        let presentation = ManualUpdatePresentation(
            activationPolicy: harness.activationPolicy,
            application: AppIconActivationSpy()
        )
        harness.log.reset()

        presentation.begin()
        #expect(harness.application.applicationIconImage != nil)

        presentation.end()
        #expect(harness.activationPolicy.isRegularApp == false)
        #expect(harness.application.currentActivationPolicy == .accessory)
        #expect(harness.application.applicationIconImage == nil)
    }

    @Test func bothPlacementKeepsMenuBarVisible() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .both)
        defer { harness.cleanUp() }
        harness.log.reset()

        harness.controller.start()

        #expect(harness.log.events == ["policy:regular", "dock:image", "menu:true"])
    }

    @Test func hiddenDockDoesNotRenderStatusChanges() async throws {
        let harness = try AppIconControllerHarness(initialPlacement: .menuBar)
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.reset()

        harness.publishDifferentSnapshot()
        // Let the snapshot debounce and the monitor's AsyncStream consumer
        // settle before asserting that a hidden Dock produced no render.
        try await Task.sleep(for: .seconds(2))

        #expect(harness.log.renderCount == 0)
    }

    @Test func visibleDockRendersStatusChanges() async throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.reset()

        harness.publishDifferentSnapshot()
        try await waitForCoalescedRenders { harness.log.renderCount == 1 }

        #expect(harness.log.renderCount == 1)
    }

    @Test func changingBackgroundPreferenceRendersAgain() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.reset()

        harness.settings.dockIconBackgroundPreference = .dark

        #expect(harness.log.events == ["dock:image"])
        #expect(harness.log.backgroundStyles == [.dark])
    }

    @Test func changingWiFiSymbolScaleRendersWithUpdatedScale() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.reset()

        harness.settings.wifiSymbolScale = 1.5

        #expect(harness.log.renderCount == 1)
        #expect(harness.log.lastCenterScale == 1.5)
    }

    @Test func connectionOptionChangeKeepsConfiguredWiFiSymbolScale() async throws {
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            initialWiFi: WiFiStatus(state: .hotspot, rssi: -51)
        )
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.settings.wifiSymbolScale = 1.5
        harness.log.reset()

        harness.settings.showsWiFiIconForHotspot = true
        try await waitForCoalescedRenders { harness.log.renderCount == 1 }

        #expect(harness.log.renderCount == 1)
        #expect(harness.log.lastCenterScale == 1.5)
    }

    @Test func changingVolumeDisplayStyleRendersWithUpdatedOptions() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.reset()

        harness.settings.volumeDisplayStyle = .arc

        #expect(harness.log.renderCount == 1)
        guard case .arc = harness.log.lastScene?.footer else { Issue.record("Expected the arc footer."); return }
    }

    @Test func changingRingStrokeStyleRendersWithUpdatedOptions() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.reset()

        harness.settings.ringStrokeStyle = .bold

        #expect(harness.log.renderCount == 1)
        #expect(harness.log.lastScene?.outerRing?.strokeScale == RingStrokeStyle.bold.scale)
        #expect(harness.log.lastFooterStrokeScale == RingStrokeStyle.bold.scale)
    }

    /// The stroke width has to survive every other icon option change, on the
    /// Dock path as well as the menu bar path.
    @Test func ringStrokeStyleSurvivesOtherOptionChanges() async throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.settings.ringStrokeStyle = .bold
        harness.log.reset()

        harness.settings.showsBatteryPercentage = false
        harness.settings.volumeDisplayStyle = .arc
        try await waitForCoalescedRenders { harness.log.renderCount > 0 }

        #expect(harness.log.renderCount > 0)
        #expect(harness.log.lastScene?.outerRing?.strokeScale == RingStrokeStyle.bold.scale)
        #expect(harness.log.lastFooterStrokeScale == RingStrokeStyle.bold.scale)
    }

    @Test func changingBluetoothAudioOptionsRendersWithUpdatedOptions() async throws {
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            initialWiFi: WiFiStatus(state: .noInternet, rssi: nil),
            initialVolume: VolumeStatus(
                scalar: 0.5, isMuted: false, deviceName: "AirPods",
                currentDevice: PresentationFixtures.bluetoothDevice
            )
        )
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.reset()

        harness.settings.replacesNetworkIconWithBluetoothAudio = true
        harness.settings.usesBluetoothAudioVolumeColor = true
        harness.settings.prioritizesNetworkErrorsOverBluetoothAudio = false
        try await waitForCoalescedRenders { harness.log.renderCount == 1 }

        // The first change redraws at once; the two that follow within the
        // coalescing interval collapse into one trailing redraw.
        #expect(harness.log.renderCount == 1)
    }

    @Test func changingBluetoothSymbolScaleRendersWithUpdatedScale() async throws {
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            initialWiFi: WiFiStatus(state: .connected, rssi: -50),
            initialVolume: VolumeStatus(
                scalar: 0.5, isMuted: false, deviceName: "AirPods",
                currentDevice: PresentationFixtures.bluetoothDevice
            ),
            initialReplacesNetworkIcon: true
        )
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.reset()

        harness.settings.bluetoothSymbolScale = 1.45
        try await waitForCoalescedRenders { harness.log.renderCount == 1 }

        #expect(harness.log.renderCount == 1)
        #expect(harness.log.lastCenterScale == 1.45)
    }

    /// A slider drag publishes a value per frame. The burst has to collapse into
    /// one trailing redraw that carries the newest options, instead of
    /// allocating one bitmap per frame.
    @Test func sliderBurstRepaintsTheDockIconOnce() async throws {
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            initialBattery: BatteryStatus(
                rawPercentage: 35, isPresent: true, isCharging: false,
                isLowPowerMode: false, isConnectedToPower: false
            )
        )
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.settings.ringStrokeStyle = .bold
        harness.log.reset()

        for threshold in stride(from: 25.0, through: 40.0, by: 1.0) {
            harness.settings.batteryCriticalThreshold = threshold
        }

        #expect(harness.log.renderCount == 0, "A drag must not redraw on every value.")
        try await waitForCoalescedRenders { harness.log.renderCount == 1 }

        #expect(harness.log.renderCount == 1)
        #expect(harness.log.lastScene?.outerRing?.segments.first?.color == .critical)
    }

    /// The icon size slider lives in the App Icon pane and is documented as
    /// menu-bar only: the Dock icon keeps the fixed design size.
    @Test func menuBarIconSizeDoesNotChangeTheDockIcon() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.reset()

        harness.settings.iconSize = 32

        #expect(harness.log.events.isEmpty)
        #expect(harness.log.renderCount == 0)
    }

    @Test func reRendersWhenTheSystemIconStyleChanges() throws {
        let notificationCenter = NotificationCenter()
        var theme = SystemIconAppearanceTheme.default
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            systemTheme: { theme },
            notificationCenter: notificationCenter
        )
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.reset()

        theme = SystemIconAppearanceTheme(style: .clear, appearance: .dark)
        notificationCenter.post(
            name: SystemIconAppearanceMonitor.didChangeNotificationName,
            object: nil
        )

        #expect(harness.log.backgroundStyles == [.clear])
    }

    @Test func systemPreferenceUsesTheDefaultLightBackground() throws {
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            systemTheme: { .default }
        )
        defer { harness.cleanUp() }

        harness.controller.start()

        #expect(harness.log.backgroundStyles == [.light])
    }

    @Test func systemPreferenceUsesDarkForDarkThemes() throws {
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            systemTheme: { SystemIconAppearanceTheme(style: .defaultStyle, appearance: .dark) }
        )
        defer { harness.cleanUp() }

        harness.controller.start()

        #expect(harness.log.backgroundStyles == [.dark])
    }

    @Test func systemPreferenceUsesClearForClearThemes() throws {
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            systemTheme: { SystemIconAppearanceTheme(style: .clear, appearance: .dark) }
        )
        defer { harness.cleanUp() }

        harness.controller.start()

        #expect(harness.log.backgroundStyles == [.clear])
    }

    @Test func systemPreferenceUsesAppearanceForAutomaticThemes() throws {
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            systemTheme: {
                SystemIconAppearanceTheme(style: .defaultStyle, appearance: .automatic)
            },
            isDarkAppearance: true
        )
        defer { harness.cleanUp() }

        harness.controller.start()

        #expect(harness.log.backgroundStyles == [.dark])
    }

    @Test func explicitPreferenceIgnoresTheSystemTheme() throws {
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            systemTheme: { SystemIconAppearanceTheme(style: .clear, appearance: .dark) }
        )
        defer { harness.cleanUp() }
        harness.settings.dockIconBackgroundPreference = .light

        harness.controller.start()

        #expect(harness.log.backgroundStyles == [.light])
    }

    @Test func stopRestoresBundledDockIcon() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }
        harness.controller.start()
        #expect(harness.application.applicationIconImage != nil)

        harness.controller.stop()

        #expect(harness.application.applicationIconImage == nil)
        harness.log.reset()
        harness.controller.stop()
        #expect(harness.log.events.isEmpty)
    }

    /// Waits for the render coalescer's trailing redraw.
    ///
    /// Polling rather than sleeping a fixed interval: every test in the run
    /// starts at once, so the main actor can stay busy for longer than the
    /// coalescing interval before the trailing redraw gets to run. A fixed wait
    /// that is generous locally is not on CI.
    private func waitForCoalescedRenders(
        until condition: () -> Bool,
        timeout: TimeInterval = 5
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("The coalesced redraw did not run within \(timeout) seconds.")
    }
}

@MainActor
final class AppIconControllerHarness {
    let log = AppIconEventLog()
    let application: AppIconApplicationSpy
    let activationPolicy: AppActivationPolicy
    let settings: SettingsStore
    let store: SystemStatusStore
    let controller: AppIconController
    let iconPresentation: IconPresentationViewModel

    private let suiteName: String
    private let defaults: UserDefaults
    private let battery = ControllableBatteryMonitor()
    private let wifi = AppIconControllableWiFiMonitor()
    private let volume = AppIconControllableVolumeMonitor()

    init(
        initialPlacement: AppIconPlacement = .menuBar,
        acceptsActivationPolicy: Bool = true,
        systemTheme: @escaping () -> SystemIconAppearanceTheme = { .default },
        isDarkAppearance: Bool = false,
        notificationCenter: NotificationCenter = .default,
        initialBattery: BatteryStatus = .placeholder,
        initialShowsChargingEffect: Bool = true,
        initialWiFi: WiFiStatus = .placeholder,
        initialVolume: VolumeStatus = .placeholder,
        initialReplacesNetworkIcon: Bool = false,
        snapshotScheduler: any IconPresentationScheduling = TestTaskIconPresentationScheduler()
    ) throws {
        suiteName = "StatusTrioCoreTests.AppIconController.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw AppIconHarnessError.missingDefaultsSuite
        }
        defaults.removeTestSuite(named: suiteName)
        self.defaults = defaults

        let log = self.log
        let application = AppIconApplicationSpy(
            log: log,
            acceptsActivationPolicy: acceptsActivationPolicy
        )
        self.application = application

        let settings = SettingsStore(defaults: defaults)
        settings.appIconPlacement = initialPlacement
        if !initialShowsChargingEffect {
            settings.showsChargingEffect = false
        }
        settings.replacesNetworkIconWithBluetoothAudio = initialReplacesNetworkIcon
        self.settings = settings

        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            initialSnapshot: StatusSnapshot(
                battery: initialBattery,
                wifi: initialWiFi,
                volume: initialVolume
            )
        )
        self.store = store
        let iconPresentation = makeTestIconPresentation(
            store: store,
            settings: settings,
            snapshotScheduler: snapshotScheduler
        )
        iconPresentation.start()
        self.iconPresentation = iconPresentation

        let activationPolicy = AppActivationPolicy(application: application)
        self.activationPolicy = activationPolicy

        controller = AppIconController(
            settings: settings,
            iconPresentation: iconPresentation,
            activationPolicy: activationPolicy,
            application: application,
            setMenuBarVisible: { isVisible in
                log.events.append(isVisible ? "menu:true" : "menu:false")
            },
            renderDockIcon: {
                scene,
                backgroundStyle,
                pixelLength in
                log.renderCount += 1
                log.scenes.append(scene)
                log.backgroundStyles.append(backgroundStyle)
                log.dockRenderKeys.append(DockRenderSurfaceKey(
                    scene: scene,
                    backgroundStyle: backgroundStyle,
                    pixelLength: pixelLength
                ))
                guard !log.failDockRenders else { return nil }
                return NSImage(size: NSSize(width: 512, height: 512))
            },
            theme: systemTheme,
            isDarkAppearance: { isDarkAppearance },
            notificationCenter: notificationCenter
        )

        store.start()
    }

    func publishBattery(_ status: BatteryStatus) {
        battery.send(status)
    }

    func publishWiFi(_ status: WiFiStatus) {
        wifi.send(status)
    }

    func publishVolume(_ status: VolumeStatus) {
        volume.send(status)
    }

    func publishDifferentSnapshot() {
        battery.send(BatteryStatus(
            rawPercentage: 42,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        ))
    }

    func cleanUp() {
        iconPresentation.stop()
        store.stop()
        defaults.removeTestSuite(named: suiteName)
    }
}

private enum AppIconHarnessError: Error {
    case missingDefaultsSuite
}

@MainActor
final class AppIconEventLog {
    var events: [String] = []
    var renderCount = 0
    var backgroundStyles: [DockIconBackgroundStyle] = []
    var dockRenderKeys: [DockRenderSurfaceKey] = []
    var scenes: [IconSceneState] = []
    var failDockRenders = false
    var lastScene: IconSceneState? { scenes.last }
    var lastCenterScale: Double? {
        guard case let .symbol(symbol) = lastScene?.center else { return nil }
        return symbol.scale
    }
    var lastFooterStrokeScale: Double? {
        switch lastScene?.footer {
        case .dots(let dots): dots.strokeScale
        case .arc(let arc): arc.strokeScale
        case nil: nil
        }
    }

    func reset() {
        events.removeAll()
        renderCount = 0
        backgroundStyles.removeAll()
        dockRenderKeys.removeAll()
        scenes.removeAll()
    }
}

struct DockRenderSurfaceKey: Equatable {
    let scene: IconSceneState
    let backgroundStyle: DockIconBackgroundStyle
    let pixelLength: Int
}

@MainActor
final class AppIconApplicationSpy: ApplicationActivationPolicyApplying, ApplicationDockIconApplying {
    private let log: AppIconEventLog
    private let acceptsActivationPolicy: Bool
    private(set) var currentActivationPolicy: NSApplication.ActivationPolicy

    private(set) var applicationIconImage: NSImage?

    init(
        log: AppIconEventLog,
        acceptsActivationPolicy: Bool,
        currentActivationPolicy: NSApplication.ActivationPolicy = .accessory
    ) {
        self.log = log
        self.acceptsActivationPolicy = acceptsActivationPolicy
        self.currentActivationPolicy = currentActivationPolicy
    }

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        log.events.append(activationPolicy == .regular ? "policy:regular" : "policy:accessory")
        guard acceptsActivationPolicy, currentActivationPolicy != activationPolicy else {
            return false
        }
        currentActivationPolicy = activationPolicy
        return true
    }

    func setApplicationIconImage(_ image: NSImage?) {
        applicationIconImage = image
        log.events.append(image == nil ? "dock:nil" : "dock:image")
    }
}

@MainActor
private final class AppIconActivationSpy: ApplicationActivating {
    private(set) var activationCount = 0

    func activate(ignoringOtherApps flag: Bool) {
        activationCount += 1
    }
}

@MainActor
final class ControllableBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    private let continuation: AsyncStream<BatteryStatus>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}

    func send(_ status: BatteryStatus) {
        continuation.yield(status)
    }
}

@MainActor
final class AppIconControllableWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    private let continuation: AsyncStream<WiFiStatus>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func send(_ value: WiFiStatus) { continuation.yield(value) }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
final class AppIconControllableVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    private let continuation: AsyncStream<VolumeStatus>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func send(_ value: VolumeStatus) { continuation.yield(value) }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
