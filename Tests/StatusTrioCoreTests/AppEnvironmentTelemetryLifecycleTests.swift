import AppKit
import Carbon
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
        settings.appIconPlacement = .dock
        settings.statusPanelShortcut = try XCTUnwrap(
            StatusPanelShortcut(
                keyCode: 49,
                modifiers: UInt32(cmdKey | optionKey)
            )
        )
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
        let shortcutBackend = LifecycleGlobalShortcutBackend()
        let shortcutController = GlobalShortcutController(
            settings: settings,
            backend: shortcutBackend,
            action: {}
        )
        let settingsWindow = SettingsWindowController(
            store: settings,
            statusStore: store,
            localization: localization,
            activationPolicy: activationPolicy,
            showIconGuide: {},
            chargingEffectClock: clock,
            globalShortcutController: shortcutController,
            launchAtLogin: LaunchAtLoginManager()
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
        let dockImageCache = DockIconImageCache()
        let appIcon = AppIconController(
            settings: settings,
            iconPresentation: iconPresentation,
            activationPolicy: activationPolicy,
            application: activationApplication,
            setMenuBarVisible: { _ in },
            renderDockIcon: { _, _, pixelLength in
                Self.makeBitmapImage(pixelLength: pixelLength)
            },
            theme: { .default },
            isDarkAppearance: { false },
            notificationCenter: NotificationCenter(),
            imageCache: dockImageCache
        )
        let reporter = LifecycleTelemetryReporter()
        let profilerCache = BluetoothProfilerReportCache()
        var pressureSources: [LifecyclePressureSource] = []
        let memoryPressure = MemoryPressureMonitor { handler in
            let source = LifecyclePressureSource(handler: handler)
            pressureSources.append(source)
            return source
        }
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
            globalShortcutController: shortcutController,
            telemetryReporter: reporter,
            memoryPressureMonitor: memoryPressure,
            bluetoothProfilerCache: profilerCache
        )
        defer { environment.stop() }

        environment.start()

        XCTAssertEqual(shortcutBackend.registerCount, 1)
        XCTAssertEqual(reporter.startCount, 1)
        XCTAssertEqual(battery.startCount, 1)
        XCTAssertEqual(wifi.startCount, 1)
        XCTAssertEqual(volume.startCount, 1)
        let currentDockImage = try XCTUnwrap(activationApplication.applicationIconImage)
        let applicationImageAssignments = activationApplication.applicationImageAssignments
        XCTAssertEqual(dockImageCache.entryCount, 1)

        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 32, bitsPerPixel: 32))
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.addRepresentation(bitmap)
        let iconURL = URL(fileURLWithPath: "/tmp/environment-memory-pressure-test.png")
        _ = IconImageDecodeCache.shared.image(for: iconURL) { _ in image }
        XCTAssertGreaterThan(IconImageDecodeCache.shared.entryCount, 0)

        let previewKey = DockIconRenderKey(
            scene: iconPresentation.output.scene,
            backgroundStyle: .dark,
            pixelLength: 128
        )
        _ = DockIconPreviewCache.shared.image(for: previewKey) { image }
        XCTAssertGreaterThan(DockIconPreviewCache.shared.entryCount, 0)

        _ = DockIconRenderer.tileImage(
            scene: iconPresentation.output.scene,
            backgroundStyle: .dark,
            pixelLength: 128
        )
        XCTAssertGreaterThan(DockIconRenderer.scratchResidentByteCount, 0)

        XCTAssertEqual(pressureSources.count, 1)
        pressureSources[0].fire()
        XCTAssertEqual(IconImageDecodeCache.shared.entryCount, 0)
        XCTAssertEqual(dockImageCache.entryCount, 0)
        XCTAssertEqual(DockIconPreviewCache.shared.entryCount, 0)
        XCTAssertEqual(DockIconRenderer.scratchResidentByteCount, 0)
        XCTAssertTrue(activationApplication.applicationIconImage === currentDockImage)
        XCTAssertEqual(
            activationApplication.applicationImageAssignments,
            applicationImageAssignments,
            "Pressure must preserve the current application image without rerendering"
        )

        profilerCache.store(Data([1, 2, 3]))
        XCTAssertEqual(profilerCache.storedEntryCount, 1)
        let externalReader = profilerCache.acquireReader()
        environment.stop()
        XCTAssertEqual(shortcutBackend.stopCount, 1)
        XCTAssertEqual(
            profilerCache.storedEntryCount,
            1,
            "environment stop must preserve a report with a live external reader"
        )
        XCTAssertEqual(profilerCache.activeReaderCount, 1)
        profilerCache.releaseReader(externalReader)
        XCTAssertEqual(profilerCache.storedEntryCount, 0)

        XCTAssertEqual(reporter.stopCount, 1)
        XCTAssertEqual(battery.stopCount, 1)
        XCTAssertEqual(wifi.stopCount, 1)
        XCTAssertEqual(volume.stopCount, 1)
        XCTAssertTrue(pressureSources[0].isCancelled)
        _ = IconImageDecodeCache.shared.image(for: iconURL) { _ in image }
        pressureSources[0].fire()
        XCTAssertGreaterThan(IconImageDecodeCache.shared.entryCount, 0,
            "A cancelled environment must ignore an already queued pressure event")
        IconImageDecodeCache.shared.reset()
    }

    private static func makeBitmapImage(pixelLength: Int) -> NSImage? {
        let bitmap = NSBitmapImageRep(
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
        guard let bitmap else { return nil }
        let image = NSImage(size: NSSize(width: pixelLength, height: pixelLength))
        image.addRepresentation(bitmap)
        return image
    }
}

@MainActor
private final class LifecyclePressureSource: MemoryPressureEventSource {
    private let handler: @MainActor () -> Void
    private(set) var isCancelled = false
    init(handler: @escaping @MainActor () -> Void) { self.handler = handler }
    func resume() {}
    func cancel() { isCancelled = true }
    func fire() { handler() }
}

@MainActor
private final class LifecycleTelemetryReporter: TelemetryReporting {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

@MainActor
private final class LifecycleGlobalShortcutBackend: GlobalShortcutRegistering {
    private(set) var registerCount = 0
    private(set) var stopCount = 0

    func register(
        _ shortcut: StatusPanelShortcut,
        action: @escaping @MainActor () -> Void
    ) throws -> UUID {
        registerCount += 1
        return UUID()
    }

    func unregister(_ token: UUID) {}

    func stop() {
        stopCount += 1
    }
}

@MainActor
private final class LifecycleApplicationSpy: ApplicationActivationPolicyApplying, ApplicationDockIconApplying {
    private(set) var currentActivationPolicy: NSApplication.ActivationPolicy = .accessory
    private(set) var applicationIconImage: NSImage?
    private(set) var applicationImageAssignments = 0
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        currentActivationPolicy = activationPolicy
        return true
    }
    func setApplicationIconImage(_ image: NSImage?) {
        applicationIconImage = image
        applicationImageAssignments += 1
    }
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
