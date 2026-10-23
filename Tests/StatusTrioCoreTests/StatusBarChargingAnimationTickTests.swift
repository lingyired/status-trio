import AppKit
import Combine
import CoreGraphics
import Foundation
import Testing
@testable import StatusTrioCore

/// Pins the split between the static menu-bar presentation and the 20-Hz
/// animation tick.
///
/// A steady tick may hand a new frame to the overlay layer; it must never
/// rasterize the template base, reassign `NSStatusBarButton.image`, or rebuild
/// the pre-rendered frame set. The fixture counts every call into the two
/// renderer seams, so these are call-count assertions rather than timings.
@MainActor
struct StatusBarChargingAnimationTickTests {
    @Test func steadyTicksReuseTheTemplateBaseAndThePreRenderedFrames() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        try await fixture.waitForPresentation()

        let baseRastersAfterPresentation = fixture.baseRasterCount
        let overlayRastersAfterPresentation = fixture.overlayRasterCount
        let framesAfterPresentation = fixture.controller.renderCounters.framesPresented
        let contentsUpdatesAfterPresentation = fixture.controller.animationLayerContentsUpdateCount
        let presentedImage = try #require(fixture.controller.presentedImageForTesting)
        #expect(baseRastersAfterPresentation == 1)
        #expect(overlayRastersAfterPresentation == 1)
        #expect(fixture.controller.renderCounters.buttonImageAssignments == 1)
        #expect(fixture.controller.cachedChargingFrameCount == 0)
        let staticPresentations = fixture.controller.renderCounters.staticPresentations
        let templateBaseRasters = fixture.controller.renderCounters.templateBaseRasters
        let buttonImageAssignments = fixture.controller.renderCounters.buttonImageAssignments

        // The plug-in burst draws one overlay per tick, and none of those ticks
        // may touch the static half.
        fixture.startClock()
        fixture.advanceTicks(11)
        #expect(fixture.burstPhaseCount == 12)
        #expect(fixture.controller.cachedChargingFrameCount == 0)
        let burstOverlayRasters = fixture.overlayRasterCount
        #expect(burstOverlayRasters == overlayRastersAfterPresentation + 12)

        fixture.advanceTicks(72)
        #expect(fixture.steadyPhaseCount == 72)

        // Two full steady cycles cost one frame-set rasterization of 36 frames
        // and nothing else.
        #expect(fixture.controller.cachedChargingFrameRebuildCount == 1)
        #expect(fixture.controller.rasterizedChargingFrameCount == 36)
        #expect(fixture.overlayRasterCount == burstOverlayRasters + 36)
        #expect(fixture.baseRasterCount == baseRastersAfterPresentation)
        #expect(fixture.controller.renderCounters.staticPresentations == staticPresentations)
        #expect(fixture.controller.renderCounters.templateBaseRasters == templateBaseRasters)
        #expect(fixture.controller.renderCounters.buttonImageAssignments == buttonImageAssignments)
        #expect(fixture.controller.renderCounters.fallbackRasters == 0)
        #expect(
            fixture.controller.renderCounters.framesPresented
                == framesAfterPresentation + 12 + 72
        )
        // One contents write per changed frame, and the geometry written once.
        #expect(
            fixture.controller.animationLayerContentsUpdateCount
                == contentsUpdatesAfterPresentation + 12 + 72
        )
        #expect(fixture.controller.animationLayerGeometryUpdateCount == 2)
        #expect(fixture.controller.presentedImageForTesting === presentedImage)
    }

    @Test func aRepeatedPhaseDoesNotWriteTheLayerAgain() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        try await fixture.waitForPresentation()
        fixture.startClock()
        fixture.advanceTicks(11)
        fixture.advanceTicks(36)

        // The second cycle reuses the same 36 bitmaps, so every tick still has to
        // change the layer's contents, but the geometry must already be right.
        let contentsUpdates = fixture.controller.animationLayerContentsUpdateCount
        #expect(fixture.controller.animationLayerGeometryUpdateCount == 2)

        // Re-presenting the phase the layer already shows is a no-op.
        fixture.controller.refreshCurrentPresentation()
        #expect(fixture.controller.animationLayerContentsUpdateCount == contentsUpdates)
        #expect(fixture.baseRasterCount == 1)
    }

    @Test func disablingTheMenuBarEffectIgnoresClockPhasesWhileTheSharedClockKeepsRunning() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        try await fixture.waitForPresentation()

        fixture.settings.showsMenuBarChargingEffect = false
        fixture.controller.flushPendingPresentationForTesting()
        let overlayRastersAtRest = fixture.overlayRasterCount

        fixture.startClock()
        fixture.advanceTicks(12)

        #expect(fixture.burstPhaseCount == 12)
        #expect(fixture.overlayRasterCount == overlayRastersAtRest)
    }

    @Test func staticKeyChangesRebuildTheBaseAndInvalidateTheFrames() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        try await fixture.waitForPresentation()
        fixture.startClock()
        fixture.advanceTicks(11 + 36)
        #expect(fixture.controller.cachedChargingFrameRebuildCount == 1)

        let baseRasters = fixture.baseRasterCount
        let assignments = fixture.controller.renderCounters.buttonImageAssignments
        let rebuilds = fixture.controller.cachedChargingFrameRebuildCount
        let presentedImageBeforeResize = try #require(fixture.controller.presentedImageForTesting)

        fixture.settings.iconSize = 26
        fixture.controller.flushPendingPresentationForTesting()

        // A new icon size is a new static key: the template base is rebuilt and
        // the animation restarts from a frame set for the new key.
        #expect(fixture.baseRasterCount == baseRasters + 1)
        #expect(fixture.controller.renderCounters.buttonImageAssignments == assignments + 1)
        #expect(fixture.controller.cachedChargingFrameRebuildCount == rebuilds + 1)
        #expect(fixture.controller.presentedImageForTesting !== presentedImageBeforeResize)

        // The stale frame set is replaced rather than accumulated.
        fixture.advanceTicks(2)
        #expect(fixture.controller.cachedChargingFrameRebuildCount == rebuilds + 1)
        #expect(fixture.controller.rasterizedChargingFrameCount == 72)
    }

    @Test func aFailedBaseRasterKeepsTheLastImageAndRecoversWithoutDuplicateLayers() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        try await fixture.waitForPresentation()
        fixture.startClock()
        fixture.advanceTicks(11)

        let presentedImage = try #require(fixture.controller.presentedImageForTesting)
        let assignments = fixture.controller.renderCounters.buttonImageAssignments
        let baseRasters = fixture.baseRasterCount
        let sublayers = fixture.buttonSublayerCount
        #expect(sublayers >= 1)

        fixture.baseFails = true
        fixture.settings.iconSize = 30
        fixture.controller.flushPendingPresentationForTesting()

        // The failed raster must not blank the icon, commit the new key, or
        // duplicate the animation layer.
        #expect(fixture.baseRasterCount == baseRasters + 1)
        #expect(fixture.controller.renderCounters.buttonImageAssignments == assignments)
        #expect(fixture.controller.presentedImageForTesting === presentedImage)
        #expect(fixture.controller.hasLayerBackedAnimation)
        #expect(fixture.buttonSublayerCount == sublayers)

        fixture.baseFails = false
        fixture.refreshCurrentPresentation()
        #expect(fixture.controller.presentedImageForTesting !== presentedImage)
        #expect(fixture.controller.renderCounters.buttonImageAssignments == assignments + 1)
        #expect(fixture.controller.hasLayerBackedAnimation)
        #expect(fixture.buttonSublayerCount == sublayers)
    }

    @Test func aFailedOverlayFallsBackToACustomRasterAndRestoresTheTemplate() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        try await fixture.waitForPresentation()
        let presentedImage = try #require(fixture.controller.presentedImageForTesting)

        fixture.overlayFails = true
        fixture.startClock()
        // The burst overlay could not be produced, so the fallback raster takes
        // over for that tick instead of leaving a blank or stale overlay.
        #expect(fixture.controller.renderCounters.fallbackRasters == 1)
        #expect(fixture.controller.presentedImageForTesting !== presentedImage)
        #expect(fixture.controller.hasLayerBackedAnimation == false)

        fixture.advanceTicks(1)
        #expect(fixture.controller.renderCounters.fallbackRasters == 2)

        fixture.overlayFails = false
        fixture.advanceTicks(1)
        // The next usable frame puts the re-tintable template image back and
        // reinstalls the layer.
        #expect(fixture.controller.presentedImageForTesting === presentedImage)
        #expect(fixture.controller.hasLayerBackedAnimation)
    }
}

@MainActor
private final class Fixture {
    private let domain: String
    let defaults: UserDefaults
    let settings: SettingsStore
    let store: SystemStatusStore
    let iconPresentation: IconPresentationViewModel
    let controller: StatusBarController
    let clock: ChargingEffectClock
    let spy = MenuBarRenderSpy()

    private(set) var burstPhaseCount = 0
    private(set) var steadyPhaseCount = 0

    private let time = ManualChargingTime()
    private var phaseCancellable: AnyCancellable?
    private var didPresentStaticContent: Confirmation?
    private let battery = BatteryStatus(
        rawPercentage: 62,
        isPresent: true,
        isCharging: true,
        isLowPowerMode: false,
        isConnectedToPower: true
    )

    init() throws {
        domain = "StatusBarChargingAnimationTickTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: domain))
        settings = SettingsStore(defaults: defaults)
        settings.iconSize = 22

        let battery = self.battery
        store = SystemStatusStore(
            batteryMonitor: TickIdleBatteryMonitor(),
            wifiMonitor: TickIdleWiFiMonitor(),
            volumeMonitor: TickIdleVolumeMonitor(),
            initialSnapshot: StatusSnapshot(
                battery: battery,
                wifi: .placeholder,
                volume: .placeholder
            )
        )
        let defaults = self.defaults
        let time = self.time
        iconPresentation = makeTestIconPresentation(store: store, settings: settings)
        clock = ChargingEffectClock(
            now: { time.now },
            sleep: { _ in try await Task.sleep(for: .seconds(600)) }
        )
        let settings = self.settings
        let clock = self.clock
        let store = self.store
        let iconPresentation = self.iconPresentation
        let spy = self.spy
        // AppKit only settles a status item's effective appearance once the item
        // is installed in the menu bar, and that install lands asynchronously.
        // Left alone, the resulting KVO callback presents the same scene in the
        // settled appearance, which rasterizes the template base a second time —
        // an unrelated presentation that no counter in these tests is about.
        // Pinning the appearance keeps the static key constant so every count
        // below still means exactly one presentation (#133).
        let pinnedAppearance = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        controller = StatusBarController(
            store: store,
            settings: settings,
            iconPresentation: iconPresentation,
            localization: Localization(defaults: defaults, preferredLanguages: ["en"]),
            openSettings: {},
            quitAction: {},
            chargingEffectClock: clock,
            renderMenuBarBase: { _, _, _, _ in spy.renderBase() },
            renderMenuBarOverlay: { _, _, _, _, phase in spy.renderOverlay(for: phase) },
            appearanceProvider: { pinnedAppearance }
        )
        controller.didPresentStaticContent = { [weak self] in
            self?.didPresentStaticContent?.confirm()
        }
        phaseCancellable = clock.$phase.sink { [weak self] phase in
            guard let self, let phase else { return }
            switch phase.kind {
            case .burst: self.burstPhaseCount += 1
            case .steady: self.steadyPhaseCount += 1
            }
        }
        iconPresentation.start()
    }

    var baseRasterCount: Int { spy.baseRasterCount }
    var overlayRasterCount: Int { spy.overlayRasterCount }
    var baseFails: Bool {
        get { spy.baseFails }
        set { spy.baseFails = newValue }
    }
    var overlayFails: Bool {
        get { spy.overlayFails }
        set { spy.overlayFails = newValue }
    }

    func tearDown() {
        clock.stop()
        phaseCancellable = nil
        controller.setVisible(false)
        iconPresentation.stop()
        defaults.removePersistentDomain(forName: domain)
    }

    func startClock() {
        clock.update(
            battery: battery,
            enabled: settings.showsChargingEffect,
            reduceMotion: false,
            displayAsleep: false,
            menuBarVisible: true
        )
    }

    /// Advances the clock by one 20-Hz frame and publishes the new phase. The
    /// battery is unchanged, so this is a plain tick and never a plug-in event.
    func advanceTicks(_ count: Int) {
        for _ in 0..<count {
            time.advance(0.05)
            clock.update(
                battery: battery,
                enabled: true,
                reduceMotion: false,
                displayAsleep: false,
                menuBarVisible: true
            )
        }
    }

    func refreshCurrentPresentation() {
        controller.refreshCurrentPresentation()
    }

    func waitForPresentation() async throws {
        await confirmation("initial static content presents") { confirmation in
            didPresentStaticContent = confirmation
            if controller.presentedImageForTesting != nil {
                confirmation.confirm()
            }
        }
    }

    var buttonSublayerCount: Int {
        controller.presentedImageForTesting == nil ? 0 : statusButtonSublayerCount
    }

    private var statusButtonSublayerCount: Int {
        controller.sublayerCountForTesting
    }
}

/// Counts the calls the controller makes into the two renderer seams and can
/// simulate a rasterization failure for either half.
@MainActor
private final class MenuBarRenderSpy {
    var baseFails = false
    var overlayFails = false
    private(set) var baseRasterCount = 0
    private(set) var overlayRasterCount = 0
    private var overlayImages: [String: CGImage] = [:]

    func renderBase() -> NSImage? {
        baseRasterCount += 1
        guard !baseFails else { return nil }
        return NSImage(size: NSSize(width: 32, height: 32))
    }

    func renderOverlay(for phase: ChargingEffectPhase?) -> CGImage? {
        overlayRasterCount += 1
        guard !overlayFails else { return nil }
        return overlayImage(for: phase)
    }

    /// Memoized so a repeated step hands the presenter the same `CGImage`
    /// identity, exactly like the pre-rendered frame set in production.
    private func overlayImage(for phase: ChargingEffectPhase?) -> CGImage? {
        let key: String
        switch phase?.kind {
        case .burst: key = "burst-\(phase?.step ?? 0)"
        case .steady: key = "steady-\(phase?.step ?? 0)"
        case nil: key = "resting"
        }
        if let cached = overlayImages[key] { return cached }
        guard let context = CGContext(
            data: nil,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = context.makeImage()
        overlayImages[key] = image
        return image
    }
}

@MainActor
private final class ManualChargingTime {
    private let start = Date(timeIntervalSince1970: 1_000)
    private var elapsed: TimeInterval = 0

    var now: Date { start.addingTimeInterval(elapsed) }

    func advance(_ interval: TimeInterval) {
        elapsed += interval
    }
}

@MainActor
private final class TickIdleBatteryMonitor: BatteryMonitoring {
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
private final class TickIdleWiFiMonitor: WiFiMonitoring {
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
private final class TickIdleVolumeMonitor: VolumeMonitoring {
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
