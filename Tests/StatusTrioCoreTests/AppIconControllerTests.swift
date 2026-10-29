import AppKit
import Combine
import Testing
@testable import StatusTrioCore

@Suite(.serialized)
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
        let visibleScheduler = ManualIconPresentationScheduler()
        let visibleHarness = try AppIconControllerHarness(
            initialPlacement: .dock,
            snapshotScheduler: visibleScheduler
        )
        defer { visibleHarness.cleanUp() }
        let hiddenScheduler = ManualIconPresentationScheduler()
        let hiddenHarness = try AppIconControllerHarness(
            initialPlacement: .menuBar,
            snapshotScheduler: hiddenScheduler
        )
        defer { hiddenHarness.cleanUp() }
        visibleHarness.controller.start()
        hiddenHarness.controller.start()
        visibleHarness.log.reset()
        hiddenHarness.log.reset()

        try await waitForStoresToReceiveSnapshots([visibleHarness, hiddenHarness]) {
            visibleHarness.publishDifferentSnapshot()
            hiddenHarness.publishDifferentSnapshot()
        }
        try #require(
            visibleScheduler.hasPendingAction && hiddenScheduler.hasPendingAction,
            "Both status updates must schedule the controlled presentation debounce."
        )
        visibleScheduler.runScheduled()
        hiddenScheduler.runScheduled()
        visibleHarness.controller.flushPendingPresentationForTesting()
        hiddenHarness.controller.flushPendingPresentationForTesting()

        #expect(visibleHarness.log.renderCount == 1)
        #expect(hiddenHarness.log.renderCount == 0)
    }

    @Test func visibleDockRendersStatusChanges() async throws {
        let scheduler = ManualIconPresentationScheduler()
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            snapshotScheduler: scheduler
        )
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.reset()

        try await waitForStoreSnapshot(harness) {
            harness.publishDifferentSnapshot()
        }
        try #require(
            scheduler.hasPendingAction,
            "The status update must schedule the controlled presentation debounce."
        )
        scheduler.runScheduled()
        harness.controller.flushPendingPresentationForTesting()

        #expect(harness.log.renderCount == 1)
    }

    @Test func storeSnapshotWaiterTimesOutAndCancelsItsSubscription() async throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }
        let startedAt = ContinuousClock.now

        let waiter = StoreSnapshotWait.start(
            [harness],
            timeout: .milliseconds(20),
            whilePublishing: {}
        )
        await waiter.finished.wait()

        guard case let .timedOut(error) = waiter.outcome,
              error.isStoreSnapshotTimeout
        else {
            Issue.record("The waiter must report a bounded timeout.")
            return
        }
        #expect(waiter.didReleaseTestResources)
        #expect(startedAt.duration(to: .now) < .seconds(5))
    }

    @Test func storeSnapshotWaitCompletesWhenInFlightTaskIsCancelled() async throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }

        let waiter = StoreSnapshotWait.start(
            [harness],
            timeout: .seconds(5),
            whilePublishing: {}
        )
        await waiter.ready.wait()
        await waiter.cancelAndJoin()

        guard case .cancelled = waiter.outcome
        else {
            Issue.record("Cancellation must end the in-flight waiter.")
            return
        }
        #expect(waiter.didReleaseTestResources)
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
        harness.controller.flushPendingPresentationForTesting()

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
        harness.controller.flushPendingPresentationForTesting()

        #expect(harness.log.renderCount > 0)
        #expect(harness.log.lastScene?.outerRing?.strokeScale == RingStrokeStyle.bold.scale)
        #expect(harness.log.lastFooterStrokeScale == RingStrokeStyle.bold.scale)
    }

    @Test func changingBluetoothAudioOptionsRendersWithUpdatedOptions() async throws {
        let sleeper = ManualEventSleeper()
        let fixedDate = Date()
        let coalescer = IconRenderCoalescer(
            now: { fixedDate },
            sleep: { duration in await sleeper.sleep(duration) }
        )
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            initialWiFi: WiFiStatus(state: .noInternet, rssi: nil),
            initialVolume: VolumeStatus(
                scalar: 0.5, isMuted: false, deviceName: "AirPods",
                currentDevice: PresentationFixtures.bluetoothDevice
            ),
            renderCoalescer: coalescer
        )
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.settings.ringStrokeStyle = .bold
        harness.controller.flushPendingPresentationForTesting()
        harness.log.reset()

        harness.settings.replacesNetworkIconWithBluetoothAudio = true
        harness.settings.usesBluetoothAudioVolumeColor = true
        harness.settings.prioritizesNetworkErrorsOverBluetoothAudio = false
        #expect(harness.log.renderCount == 0, "The burst must wait for the controlled drain.")
        harness.controller.flushPendingPresentationForTesting()

        // All three changes land inside one coalescing window and collapse
        // into one trailing redraw with the newest options.
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
        let sleeper = ManualEventSleeper()
        let fixedDate = Date()
        let coalescer = IconRenderCoalescer(
            now: { fixedDate },
            sleep: { duration in await sleeper.sleep(duration) }
        )
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            initialBattery: BatteryStatus(
                rawPercentage: 35, isPresent: true, isCharging: false,
                isLowPowerMode: false, isConnectedToPower: false
            ),
            renderCoalescer: coalescer
        )
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.settings.ringStrokeStyle = .bold
        harness.log.reset()

        for threshold in stride(from: 25.0, through: 40.0, by: 1.0) {
            harness.settings.batteryCriticalThreshold = threshold
        }

        #expect(harness.log.renderCount == 0, "A drag must not redraw on every value.")
        let didSchedule = await sleeper.waitForCallCount(1, timeout: .seconds(5))
        try #require(didSchedule, "The burst must schedule a trailing redraw.")
        #expect(harness.log.renderCount == 0, "The redraw must wait for the controlled scheduler.")
        sleeper.releaseAll()
        try await waitForCoalescedRenders { harness.log.renderCount == 1 }

        #expect(harness.log.renderCount == 1)
        #expect(harness.log.lastScene?.outerRing?.segments.first?.color == .critical)
    }

    /// Issue #105. Charge limiting holds the battery below 100%, so the user
    /// picks the level that closes the ring. The Dock draws the same scene as
    /// the menu bar, so a threshold that only reached one surface would leave
    /// the other stale.
    @Test func fullRingThresholdRedrawsTheDockIconWithAClosedRing() async throws {
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            initialBattery: BatteryStatus(
                rawPercentage: 80, isPresent: true, isCharging: true,
                isLowPowerMode: false, isConnectedToPower: true
            )
        )
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.reset()

        harness.settings.batteryFullThreshold = 80
        harness.controller.flushPendingPresentationForTesting()

        #expect(harness.log.renderCount > 0)
        #expect(harness.log.lastScene?.outerRing?.segments.first?.progress == 1.0)
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

    @Test func leavingDockClearsTheStaticCacheSoShowingAgainRenders() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }
        harness.controller.start()
        #expect(harness.log.renderCount == 1)

        harness.settings.appIconPlacement = .menuBar
        harness.settings.appIconPlacement = .dock

        #expect(harness.log.renderCount == 2)
    }

    @Test func releasingCachedImagesKeepsTheCurrentApplicationImage() throws {
        let imageCache = DockIconImageCache()
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            imageCache: imageCache
        )
        defer { harness.cleanUp() }
        harness.controller.start()
        let currentImage = try #require(harness.application.applicationIconImage)
        #expect(imageCache.entryCount == 1)
        #expect(harness.log.renderCount == 1)
        harness.log.reset()

        harness.controller.releaseCachedImages()

        #expect(imageCache.entryCount == 0)
        #expect(imageCache.residentByteCount == 0)
        #expect(harness.application.applicationIconImage === currentImage)
        #expect(harness.log.events.isEmpty)
        #expect(harness.log.renderCount == 0)
    }

    @Test func stopReleasesTheStaticCacheEvenWithoutADockIcon() throws {
        let imageCache = DockIconImageCache()
        let harness = try AppIconControllerHarness(
            initialPlacement: .menuBar,
            imageCache: imageCache
        )
        defer { harness.cleanUp() }
        harness.controller.start()
        let scene = harness.controller.latestScene.withChargingEffectEnabled(
            harness.settings.showsDockChargingEffect
        )
        let key = DockIconRenderKey(
            scene: scene,
            backgroundStyle: harness.controller.currentDockBackgroundStyle,
            pixelLength: DockIconRenderer.pixelSize
        )
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 64,
            pixelsHigh: 64,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.addRepresentation(representation)
        imageCache.store(image, for: key)
        #expect(imageCache.entryCount == 1)
        #expect(harness.application.applicationIconImage == nil)

        harness.controller.stop()

        #expect(imageCache.entryCount == 0)
        #expect(imageCache.residentByteCount == 0)
    }

    @Test func repeatedStartAndStopRendersFreshAfterEachStop() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }

        for expectedRenderCount in 1...3 {
            harness.controller.start()
            #expect(harness.log.renderCount == expectedRenderCount)
            harness.controller.stop()
        }
    }

    @Test func stopAfterLifetimeAlreadyEndedStillReleasesTheStaticCache() throws {
        let imageCache = DockIconImageCache()
        let harness = try AppIconControllerHarness(
            initialPlacement: .menuBar,
            imageCache: imageCache
        )
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.controller.stop()
        let scene = harness.controller.latestScene.withChargingEffectEnabled(
            harness.settings.showsDockChargingEffect
        )

        imageCache.store(
            makeControllerBitmapImage(width: 64, height: 64),
            for: DockIconRenderKey(
                scene: scene,
                backgroundStyle: harness.controller.currentDockBackgroundStyle,
                pixelLength: DockIconRenderer.pixelSize
            )
        )

        harness.controller.stop()

        #expect(imageCache.entryCount == 0)
        #expect(imageCache.residentByteCount == 0)
    }

    @Test func temporaryRegularSurfaceClearsRasterWhenItEnds() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .menuBar)
        defer { harness.cleanUp() }
        harness.controller.start()

        harness.activationPolicy.enterTemporaryRegularMode()
        #expect(harness.log.renderCount == 1)
        harness.activationPolicy.leaveTemporaryRegularMode()
        harness.activationPolicy.enterTemporaryRegularMode()

        #expect(harness.log.renderCount == 2)
    }

    @Test func repeatedlyEndingTemporaryRegularModeDoesNotRenderWhenAlreadyAccessory() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .menuBar)
        defer { harness.cleanUp() }
        harness.controller.start()

        for _ in 0..<4 {
            harness.activationPolicy.leaveTemporaryRegularMode()
        }

        #expect(harness.log.renderCount == 0)
    }

    @Test func automaticHiddenDockReusesTheStaticRaster() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }
        harness.controller.start()
        #expect(harness.log.renderCount == 1)

        harness.activationPolicy.leaveTemporaryRegularMode()
        harness.activationPolicy.enterTemporaryRegularMode()

        #expect(harness.log.renderCount == 1)
    }

    @Test func temporaryAnimatedSurfaceReusesTheStaticRaster() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }
        harness.controller.start()
        #expect(harness.log.renderCount == 1)

        harness.controller.setDockChargingAnimationActive(true)
        harness.controller.setDockChargingAnimationActive(false)

        #expect(harness.log.renderCount == 1)
    }

    /// The Dock animation's claim follows the user's own placement: a window
    /// that borrows the regular policy is not a Dock placement.
    @Test func dockAnimationEligibilityFollowsThePlacementNotTheRegularPolicy() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .menuBar)
        defer { harness.cleanUp() }
        harness.controller.start()

        #expect(harness.controller.isDockChargingAnimationEligible == false)

        harness.activationPolicy.enterTemporaryRegularMode()

        #expect(harness.controller.isDockChargingAnimationEligible == false)

        harness.settings.appIconPlacement = .dock

        #expect(harness.controller.isDockChargingAnimationEligible)

        harness.settings.appIconPlacement = .both

        #expect(harness.controller.isDockChargingAnimationEligible)

        harness.settings.appIconPlacement = .menuBar

        #expect(harness.controller.isDockChargingAnimationEligible == false)
    }

    @Test func dockAnimationEligibilityCallbackFiresOnEverySurfaceChange() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }
        var transitions: [Bool] = []
        harness.controller.dockChargingAnimationEligibilityDidChange = {
            transitions.append(harness.controller.isDockChargingAnimationEligible)
        }

        harness.controller.start()
        harness.settings.appIconPlacement = .menuBar

        #expect(transitions == [true, false])
    }

    /// While the Dock presenter owns the animated tile, writing
    /// `applicationIconImage` would replace it with a static image, so the
    /// static path has to stay quiet until the animation releases the surface.
    @Test func animatedDockTileSuppressesStaticImageWrites() async throws {
        let scheduler = ManualIconPresentationScheduler()
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            snapshotScheduler: scheduler
        )
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.controller.setDockChargingAnimationActive(true)
        harness.log.reset()

        try await waitForStoreSnapshot(harness) {
            harness.publishDifferentSnapshot()
        }
        scheduler.runScheduled()
        harness.controller.flushPendingPresentationForTesting()

        #expect(harness.log.renderCount == 0)
        #expect(harness.log.events.isEmpty)

        harness.controller.setDockChargingAnimationActive(false)

        #expect(harness.controller.isDockChargingAnimationEligible)
        #expect(harness.log.events == ["dock:image"])
    }

    @Test func disablingTheDockEffectRemovesItFromTheDockAnimationScene() throws {
        let harness = try AppIconControllerHarness(
            initialPlacement: .both,
            initialBattery: BatteryStatus(
                rawPercentage: 62,
                isPresent: true,
                isCharging: true,
                isLowPowerMode: false,
                isConnectedToPower: true
            )
        )
        defer { harness.cleanUp() }
        harness.controller.start()
        #expect(harness.controller.latestAnimationScene.outerRing?.effect != nil)

        harness.settings.showsDockChargingEffect = false

        #expect(harness.controller.latestAnimationScene.outerRing?.effect == nil)
        #expect(harness.settings.showsMenuBarChargingEffect)
        #expect(harness.settings.showsChargingEffect)
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
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw AppIconTestFailure.coalescedRedrawTimeout(
            timeout: timeout,
            elapsed: Date().timeIntervalSince(startedAt)
        )
    }

    private func waitUntil(
        _ failureMessage: String,
        timeout: TimeInterval = 5,
        condition: () -> Bool
    ) async throws {
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw AppIconTestFailure.conditionNotMet(
            message: failureMessage,
            timeout: timeout,
            elapsed: Date().timeIntervalSince(startedAt)
        )
    }

    private func makeControllerBitmapImage(width: Int, height: Int) -> NSImage {
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(representation)
        return image
    }

    private func waitForStoreSnapshot(
        _ harness: AppIconControllerHarness,
        timeout: Duration = .seconds(5),
        whilePublishing publish: @escaping () -> Void
    ) async throws {
        try await waitForStoreSnapshots([harness], timeout: timeout, whilePublishing: publish)
    }

    private func waitForStoresToReceiveSnapshots(
        _ harnesses: [AppIconControllerHarness],
        timeout: Duration = .seconds(5),
        whilePublishing publish: @escaping () -> Void
    ) async throws {
        try await waitForStoreSnapshots(harnesses, timeout: timeout, whilePublishing: publish)
    }

    /// Subscribes before the monitor update so Combine delivers the resulting
    /// snapshot even if the store's consumer runs immediately.
    private func waitForStoreSnapshots(
        _ harnesses: [AppIconControllerHarness],
        timeout: Duration,
        whilePublishing publish: @escaping () -> Void
    ) async throws {
        let waiter = StoreSnapshotWait.start(
            harnesses,
            timeout: timeout,
            whilePublishing: publish
        )
        await waiter.ready.wait()
        await waiter.finished.wait()

        if case let .timedOut(error) = waiter.outcome {
            throw error
        }
        if case .cancelled = waiter.outcome {
            throw CancellationError()
        }
        if case let .failed(error) = waiter.outcome {
            throw error
        }
    }
}

@MainActor
private final class StoreSnapshotWait {
    let ready: StoreSnapshotWaitMarker
    let finished: StoreSnapshotWaitMarker
    private(set) var task: Task<Void, Never>
    private(set) var outcome: StoreSnapshotWaitOutcome
    private(set) var didReleaseTestResources = false

    private init(
        ready: StoreSnapshotWaitMarker,
        finished: StoreSnapshotWaitMarker,
        outcome: StoreSnapshotWaitOutcome
    ) {
        self.ready = ready
        self.finished = finished
        self.outcome = outcome
        task = Task {}
    }

    static func start(
        _ harnesses: [AppIconControllerHarness],
        timeout: Duration,
        whilePublishing publish: @escaping () -> Void
    ) -> StoreSnapshotWait {
        let startedAt = ContinuousClock.now
        let ready = StoreSnapshotWaitMarker()
        let finished = StoreSnapshotWaitMarker()
        let wait = StoreSnapshotWait(
            ready: ready,
            finished: finished,
            outcome: .failed(.conditionNotMet(
                message: "The snapshot waiter did not publish an outcome.",
                timeout: 5,
                elapsed: 5
            ))
        )
        wait.task = Task { @MainActor [weak wait] in
            guard let wait else { return }
            guard !Task.isCancelled else {
                wait.outcome = .cancelled
                wait.ready.finish()
                wait.finished.signal()
                return
            }

            var streams: [AsyncStream<Int?>] = []
            var continuations: [AsyncStream<Int?>.Continuation] = []
            var cancellables: [AnyCancellable] = []
            defer {
                for cancellable in cancellables {
                    cancellable.cancel()
                }
                for continuation in continuations {
                    continuation.finish()
                }
                wait.didReleaseTestResources = true
                wait.finished.signal()
            }

            for harness in harnesses {
                let (stream, continuation) = AsyncStream.makeStream(
                    of: Int?.self,
                    bufferingPolicy: .bufferingNewest(1)
                )
                streams.append(stream)
                continuations.append(continuation)
                cancellables.append(
                    harness.store.$snapshot
                        .map(\.battery.rawPercentage)
                        .sink { continuation.yield($0) }
                )
            }
            wait.ready.signal()
            publish()

            let allReceivedExpectedSnapshot = await withTaskGroup(of: Bool.self) { group in
                for stream in streams {
                    group.addTask {
                        var iterator = stream.makeAsyncIterator()
                        while let percentage = await iterator.next() {
                            if percentage == 42 { return true }
                        }
                        return false
                    }
                }
                group.addTask {
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return false
                    }
                    return false
                }

                var matchedStreamCount = 0
                while let matched = await group.next() {
                    guard matched else {
                        group.cancelAll()
                        return false
                    }
                    matchedStreamCount += 1
                    if matchedStreamCount == streams.count {
                        group.cancelAll()
                        return true
                    }
                }
                return false
            }

            if allReceivedExpectedSnapshot {
                wait.outcome = .completed
            } else if Task.isCancelled {
                wait.outcome = .cancelled
            } else {
                wait.outcome = .timedOut(
                    .storeSnapshotTimeout(
                        expectedPercentage: 42,
                        actualPercentages: harnesses.map {
                            $0.store.snapshot.battery.rawPercentage
                        },
                        timeout: timeout,
                        elapsed: startedAt.duration(to: .now)
                    )
                )
            }
        }
        return wait
    }

    func cancelAndJoin() async {
        await ready.wait()
        task.cancel()
        await finished.wait()
        await task.value
    }
}

private enum StoreSnapshotWaitOutcome {
    case completed
    case timedOut(AppIconTestFailure)
    case cancelled
    case failed(AppIconTestFailure)
}

@MainActor
private final class StoreSnapshotWaitMarker {
    private let stream: AsyncStream<Void>
    private let signalContinuation: AsyncStream<Void>.Continuation
    private var didSignal = false

    init() {
        (stream, signalContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    func signal() {
        didSignal = true
        signalContinuation.yield()
        signalContinuation.finish()
    }

    func finish() {
        didSignal = true
        signalContinuation.finish()
    }

    func wait() async {
        if didSignal { return }
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
    }
}

private enum AppIconTestFailure: Error, CustomStringConvertible {
    case coalescedRedrawTimeout(timeout: TimeInterval, elapsed: TimeInterval)
    case conditionNotMet(message: String, timeout: TimeInterval, elapsed: TimeInterval)
    case storeSnapshotTimeout(
        expectedPercentage: Int,
        actualPercentages: [Int?],
        timeout: Duration,
        elapsed: Duration
    )

    var isStoreSnapshotTimeout: Bool {
        if case .storeSnapshotTimeout = self { return true }
        return false
    }

    var description: String {
        switch self {
        case let .coalescedRedrawTimeout(timeout, elapsed):
            "The coalesced redraw did not run within \(timeout) seconds (elapsed \(elapsed))."
        case let .conditionNotMet(message, timeout, elapsed):
            "\(message) Timeout: \(timeout)s. Elapsed: \(elapsed)s."
        case let .storeSnapshotTimeout(expectedPercentage, actualPercentages, timeout, elapsed):
            """
            The status updates did not reach every store.
            expected battery percentage: \(expectedPercentage)
            actual battery percentages: \(actualPercentages)
            timeout: \(timeout)
            elapsed: \(elapsed)
            """
        }
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
        initialShowsDockChargingEffect: Bool? = nil,
        initialWiFi: WiFiStatus = .placeholder,
        initialVolume: VolumeStatus = .placeholder,
        initialReplacesNetworkIcon: Bool = false,
        snapshotScheduler: any IconPresentationScheduling = TestTaskIconPresentationScheduler(),
        renderCoalescer: IconRenderCoalescer? = nil,
        imageCache: DockIconImageCache? = nil
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
        if let initialShowsDockChargingEffect {
            settings.showsDockChargingEffect = initialShowsDockChargingEffect
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
                let representation = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: 512,
                    pixelsHigh: 512,
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                )!
                let image = NSImage(size: NSSize(width: 512, height: 512))
                image.addRepresentation(representation)
                return image
            },
            theme: systemTheme,
            isDarkAppearance: { isDarkAppearance },
            notificationCenter: notificationCenter,
            renderCoalescer: renderCoalescer,
            imageCache: imageCache
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
