import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class PreviewResourceLifecycleTests: XCTestCase {
    func testClosingOnePreviewOwnerKeepsCacheUntilTheLastOwnerCloses() throws {
        let cache = DockIconPreviewCache(limit: 4)
        try seedPreviewCache(cache)
        let lifecycle = PreviewResourceLifecycle(previewCache: cache)
        lifecycle.start()
        lifecycle.setPreviewOwner(.settings, visible: true)
        lifecycle.setPreviewOwner(.onboarding, visible: true)

        lifecycle.setPreviewOwner(.settings, visible: false)
        XCTAssertEqual(cache.entryCount, 1)

        lifecycle.setPreviewOwner(.onboarding, visible: false)
        XCTAssertEqual(cache.entryCount, 0)
    }

    func testPopoverReleaseCannotClearPreviewsWhileSettingsIsVisible() throws {
        let cache = DockIconPreviewCache(limit: 4)
        try seedPreviewCache(cache)
        let lifecycle = PreviewResourceLifecycle(previewCache: cache)
        lifecycle.start()
        lifecycle.setPreviewOwner(.settings, visible: true)
        lifecycle.setPopoverContentOwned(true)

        lifecycle.setPopoverContentOwned(false)
        XCTAssertEqual(cache.entryCount, 1)

        lifecycle.setPreviewOwner(.settings, visible: false)
        XCTAssertEqual(cache.entryCount, 0)
    }

    func testOwnerAndPopoverCallbacksAreIdempotent() throws {
        let cache = DockIconPreviewCache(limit: 4)
        try seedPreviewCache(cache)
        let lifecycle = PreviewResourceLifecycle(previewCache: cache)
        lifecycle.start()

        lifecycle.setPreviewOwner(.settings, visible: true)
        lifecycle.setPreviewOwner(.settings, visible: true)
        XCTAssertEqual(cache.entryCount, 1)

        lifecycle.setPreviewOwner(.settings, visible: false)
        lifecycle.setPreviewOwner(.settings, visible: false)
        XCTAssertEqual(cache.entryCount, 0)

        try seedPreviewCache(cache)
        lifecycle.setPopoverContentOwned(true)
        lifecycle.setPopoverContentOwned(true)
        lifecycle.setPopoverContentOwned(false)
        XCTAssertEqual(cache.entryCount, 0)

        try seedPreviewCache(cache)
        lifecycle.setPopoverContentOwned(false)
        XCTAssertEqual(cache.entryCount, 1)
    }

    func testStartAndStopDoNotDuplicateObservationOrLeakStoppedEvents() throws {
        let cache = DockIconPreviewCache(limit: 4)
        try seedPreviewCache(cache)
        let lifecycle = PreviewResourceLifecycle(previewCache: cache)

        lifecycle.start()
        lifecycle.start()
        lifecycle.stop()
        lifecycle.stop()
        lifecycle.setPreviewOwner(.settings, visible: false)
        lifecycle.setPopoverContentOwned(false)
        XCTAssertEqual(cache.entryCount, 1)

        lifecycle.start()
        lifecycle.setPreviewOwner(.settings, visible: true)
        lifecycle.setPreviewOwner(.settings, visible: false)
        XCTAssertEqual(cache.entryCount, 0)
    }

    func testIdleReleasePreservesLiveDecodeCacheAndAnimationOwnership() throws {
        let previewCache = DockIconPreviewCache(limit: 4)
        try seedPreviewCache(previewCache)
        let iconURL = URL(fileURLWithPath: "/tmp/preview-resource-live-cache.png")
        let liveImage = try Self.makeBitmapImage(pixelLength: 8)
        _ = IconImageDecodeCache.shared.image(for: iconURL) { _ in liveImage }
        let liveDecodeCount = IconImageDecodeCache.shared.entryCount
        XCTAssertGreaterThan(liveDecodeCount, 0)
        defer { IconImageDecodeCache.shared.reset() }

        let clock = ChargingEffectClock()
        clock.setDockAnimationActive(true)
        XCTAssertTrue(clock.isDockAnimationActive)
        XCTAssertTrue(clock.hasAnimationSurface)

        let lifecycle = PreviewResourceLifecycle(previewCache: previewCache)
        lifecycle.start()
        lifecycle.releaseIfIdle()

        XCTAssertEqual(previewCache.entryCount, 0)
        XCTAssertEqual(IconImageDecodeCache.shared.entryCount, liveDecodeCount)
        XCTAssertTrue(clock.isDockAnimationActive)
        XCTAssertTrue(clock.hasAnimationSurface)
    }

    func testSettingsObservationReportsVisibilityOnceAndStopsSymmetrically() throws {
        let fixture = try DefaultsFixture(prefix: "SettingsPreviewResource")
        defer { fixture.tearDown() }
        let store = makeStatusStore()
        let controller = SettingsWindowController(
            store: SettingsStore(defaults: fixture.defaults),
            statusStore: store,
            localization: Localization(
                defaults: fixture.defaults,
                preferredLanguages: ["en"]
            ),
            activationPolicy: AppActivationPolicy(
                application: PreviewActivationApplication()
            ),
            showIconGuide: {}
        )
        var visibility: [Bool] = []

        controller.startPreviewResourceObservation { visibility.append($0) }
        controller.startPreviewResourceObservation { visibility.append($0) }
        XCTAssertEqual(visibility, [false])

        controller.show()
        controller.show()
        XCTAssertEqual(visibility, [false, true])
        try XCTUnwrap(controller.window).close()
        XCTAssertEqual(visibility, [false, true, false])

        controller.stopPreviewResourceObservation()
        controller.stopPreviewResourceObservation()
        controller.show()
        try XCTUnwrap(controller.window).close()
        XCTAssertEqual(visibility, [false, true, false])
    }

    func testOnboardingObservationReportsVisibilityOnceAndStopsSymmetrically() throws {
        let fixture = try DefaultsFixture(prefix: "OnboardingPreviewResource")
        defer { fixture.tearDown() }
        let controller = OnboardingWindowController(
            settings: SettingsStore(defaults: fixture.defaults),
            localization: Localization(
                defaults: fixture.defaults,
                preferredLanguages: ["en"]
            ),
            activationPolicy: AppActivationPolicy(
                application: PreviewActivationApplication()
            )
        )
        var visibility: [Bool] = []

        controller.startPreviewResourceObservation { visibility.append($0) }
        controller.startPreviewResourceObservation { visibility.append($0) }
        XCTAssertEqual(visibility, [false])

        controller.show()
        controller.show()
        XCTAssertEqual(visibility, [false, true])
        try XCTUnwrap(controller.window).close()
        XCTAssertEqual(visibility, [false, true, false])

        controller.stopPreviewResourceObservation()
        controller.stopPreviewResourceObservation()
        controller.show()
        try XCTUnwrap(controller.window).close()
        XCTAssertEqual(visibility, [false, true, false])
    }

    func testAppEnvironmentTracksPopoverOwnershipAndCancelsItOnStop() throws {
        let fixture = try DefaultsFixture(prefix: "EnvironmentPreviewResource")
        defer { fixture.tearDown() }
        let settings = SettingsStore(defaults: fixture.defaults)
        settings.hasCompletedIconGuideOnboarding = true
        settings.completeTelemetryConsent(sharesAnalytics: false)
        settings.appIconPlacement = .dock
        let localization = Localization(
            defaults: fixture.defaults,
            preferredLanguages: ["en"]
        )
        let store = AppEnvironment.makeStore(
            batteryMonitor: PreviewNoopBatteryMonitor(),
            wifiMonitor: PreviewNoopWiFiMonitor(),
            volumeMonitor: PreviewNoopVolumeMonitor()
        )
        let iconPresentation = makeTestIconPresentation(store: store, settings: settings)
        let clock = ChargingEffectClock()
        let activationApplication = PreviewActivationApplication()
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
            renderMenuBarBase: { _, _, _, _ in nil }
        )
        let appIcon = AppIconController(
            settings: settings,
            iconPresentation: iconPresentation,
            activationPolicy: activationPolicy,
            application: activationApplication,
            setMenuBarVisible: { _ in },
            renderDockIcon: { _, _, pixelLength in
                try? Self.makeBitmapImage(pixelLength: pixelLength)
            },
            theme: { .default },
            isDarkAppearance: { false },
            notificationCenter: NotificationCenter()
        )
        let previewCache = DockIconPreviewCache(limit: 4)
        let previewLifecycle = PreviewResourceLifecycle(previewCache: previewCache)
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
            inputSourceController: InputSourceController(),
            chargingEffectClock: clock,
            chargingEffectMotionMonitor: ChargingEffectMotionMonitor(
                readReduceMotion: { false },
                notificationCenter: NotificationCenter()
            ),
            telemetryReporter: PreviewTelemetryReporter(),
            memoryPressureMonitor: MemoryPressureMonitor { _ in
                PreviewPressureSource()
            },
            bluetoothProfilerCache: BluetoothProfilerReportCache(),
            previewResourceLifecycle: previewLifecycle
        )
        environment.start()
        defer { environment.stop() }

        store.setPopoverVisible(true)
        try seedPreviewCache(previewCache)
        settingsWindow.show()
        try XCTUnwrap(settingsWindow.window).close()
        XCTAssertEqual(
            previewCache.entryCount,
            1,
            "Closing Settings must preserve previews while popover content is owned"
        )

        statusBar.onPopoverContentReleased?()
        XCTAssertEqual(previewCache.entryCount, 0)

        store.setPopoverVisible(false)
        store.setPopoverVisible(true)
        settingsWindow.show()
        try seedPreviewCache(previewCache)
        statusBar.onPopoverContentReleased?()
        XCTAssertEqual(
            previewCache.entryCount,
            1,
            "Popover release must preserve previews while Settings remains visible"
        )
        try XCTUnwrap(settingsWindow.window).close()
        XCTAssertEqual(previewCache.entryCount, 0)

        environment.stop()
        XCTAssertNil(statusBar.onPopoverContentReleased)
        try seedPreviewCache(previewCache)
        store.setPopoverVisible(true)
        statusBar.onPopoverContentReleased?()
        XCTAssertEqual(
            previewCache.entryCount,
            1,
            "Stopped environment observers must not release preview resources"
        )

        environment.start()
        statusBar.onPopoverContentReleased?()
        XCTAssertEqual(
            previewCache.entryCount,
            0,
            "Restarted environment must observe popover release again"
        )
    }

    private func seedPreviewCache(_ cache: DockIconPreviewCache) throws {
        let scene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: .placeholder, audioIcon: nil),
            configuration: .standard
        )
        let key = DockIconRenderKey(
            scene: scene,
            backgroundStyle: .dark,
            pixelLength: 64
        )
        _ = cache.image(for: key) {
            try? Self.makeBitmapImage(pixelLength: 64)
        }
        XCTAssertEqual(cache.entryCount, 1)
    }

    private static func makeBitmapImage(pixelLength: Int) throws -> NSImage {
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelLength,
                pixelsHigh: pixelLength,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: pixelLength * 4,
                bitsPerPixel: 32
            )
        )
        let image = NSImage(size: NSSize(width: pixelLength, height: pixelLength))
        image.addRepresentation(bitmap)
        return image
    }

    private func makeStatusStore() -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: PreviewNoopBatteryMonitor(),
            wifiMonitor: PreviewNoopWiFiMonitor(),
            volumeMonitor: PreviewNoopVolumeMonitor()
        )
    }
}

@MainActor
private struct DefaultsFixture {
    let defaults: UserDefaults
    private let suiteName: String

    init(prefix: String) throws {
        suiteName = "StatusTrioCoreTests.\(prefix).\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class PreviewActivationApplication:
    ApplicationActivationPolicyApplying,
    ApplicationDockIconApplying
{
    private(set) var currentActivationPolicy: NSApplication.ActivationPolicy = .accessory

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        guard currentActivationPolicy != activationPolicy else { return false }
        currentActivationPolicy = activationPolicy
        return true
    }

    func setApplicationIconImage(_ image: NSImage?) {}
}

@MainActor
private final class PreviewTelemetryReporter: TelemetryReporting {
    func start() {}
    func stop() {}
}

@MainActor
private final class PreviewPressureSource: MemoryPressureEventSource {
    func resume() {}
    func cancel() {}
}

@MainActor
private final class PreviewNoopBatteryMonitor: BatteryMonitoring {
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
private final class PreviewNoopWiFiMonitor: WiFiMonitoring {
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
private final class PreviewNoopVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>

    init() {
        (updates, _) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func setDetailsVisible(_ visible: Bool) {}
}
