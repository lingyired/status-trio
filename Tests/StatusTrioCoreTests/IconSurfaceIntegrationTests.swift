import AppKit
import Testing
@testable import StatusTrioCore

@Suite(.serialized)
@MainActor
struct IconSurfaceIntegrationTests {
    @Test func effectiveDesignerScaleEditUpdatesMenuBarAndDockScenesTogether() async throws {
        let harness = try AppIconControllerHarness(
            initialPlacement: .both,
            initialWiFi: WiFiStatus(state: .connected, rssi: -48)
        )
        defer { harness.cleanUp() }
        harness.settings.updateIconConfiguration { configuration in
            configuration.composition.center = SlotSelection(primary: .network)
            IconDesignerEditingModel.settingEffectiveCenterScale(2.35, in: &configuration)
        }

        var menuBarScenes: [IconSceneState] = []
        let menuBar = StatusBarController(
            store: harness.store,
            settings: harness.settings,
            iconPresentation: harness.iconPresentation,
            localization: Localization(preferredLanguages: ["en"]),
            openSettings: {},
            quitAction: {},
            renderMenuBarBase: { scene, _, _, _ in
                menuBarScenes.append(scene)
                return NSImage(size: NSSize(width: 32, height: 32))
            },
            renderMenuBarOverlay: { _, _, _, _, _ in nil }
        )
        defer { menuBar.setVisible(false) }
        harness.controller.start()

        try await waitUntil {
            guard case let .symbol(symbol)? = harness.iconPresentation.output.scene.center else { return false }
            return abs(symbol.scale - 2.35) < 1e-12
                && menuBarScenes.last == harness.iconPresentation.output.scene
                && harness.log.lastScene == harness.iconPresentation.output.scene
        }
        #expect(harness.settings.iconConfiguration.appearance.center.effectiveSymbolScale == 2.35)
        #expect(menuBarScenes.last == harness.log.lastScene)
    }

    @Test func specifiedBluetoothAudioUsesLiveResolverAcrossMenuBarAndDock() async throws {
        let target = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:31", name: "Designated headset", kind: .audio, isConnected: true
        )
        let builtInOutput = AudioOutputDevice(
            id: 1, name: "Built-in Output", isCurrent: true, transport: .builtIn
        )
        let harness = try AppIconControllerHarness(
            initialPlacement: .both,
            initialWiFi: WiFiStatus(state: .connected, rssi: -48),
            initialVolume: VolumeStatus(
                scalar: 0, isMuted: false, deviceName: builtInOutput.name, currentDevice: builtInOutput
            ),
            resolveSourceSnapshot: { snapshot in
                IconPresentationResourceResolver.sourceSnapshot(
                    snapshot: snapshot,
                    bluetoothDevices: [target],
                    selectedConnectedDeviceAddress: "aa-bb-cc-dd-ee-31"
                )
            }
        )
        defer { harness.cleanUp() }
        harness.settings.updateIconConfiguration {
            $0.composition.center = SlotSelection(primary: .connectedBluetoothDevice, fallback: .network)
            $0.composition.centerOverride.networkProblemOverridesPrimary = true
            $0.behaviors.bluetoothAudioCenter.networkIconSymbolOverride = "airpods.pro"
            $0.behaviors.bluetoothAudioCenter.usesVolumeColor = true
        }

        var menuBarScenes: [IconSceneState] = []
        let menuBar = StatusBarController(
            store: harness.store,
            settings: harness.settings,
            iconPresentation: harness.iconPresentation,
            localization: Localization(preferredLanguages: ["en"]),
            openSettings: {},
            quitAction: {},
            renderMenuBarBase: { scene, _, _, _ in
                menuBarScenes.append(scene)
                return NSImage(size: NSSize(width: 32, height: 32))
            },
            renderMenuBarOverlay: { _, _, _, _, _ in nil }
        )
        defer { menuBar.setVisible(false) }
        harness.controller.start()
        try await waitUntil {
            guard case let .symbol(symbol)? = harness.iconPresentation.output.scene.center else { return false }
            return symbol.source == .symbol(
                name: "airpods.pro", variableValue: nil, fallback: BluetoothDeviceRowIcon.genericSymbol
            ) && symbol.color == .primary
                && menuBarScenes.last == harness.iconPresentation.output.scene
                && harness.log.lastScene == harness.iconPresentation.output.scene
        }

        // The designated headset is not the current output: tint follows the
        // built-in system output's live scalar, and both surfaces consume one scene.
        harness.publishVolume(VolumeStatus(
            scalar: 0.5, isMuted: false, deviceName: builtInOutput.name, currentDevice: builtInOutput
        ))
        try await waitUntil {
            guard case let .symbol(symbol)? = harness.iconPresentation.output.scene.center else { return false }
            return symbol.color == .bluetooth
                && menuBarScenes.last == harness.iconPresentation.output.scene
                && harness.log.dockRenderKeys.last?.scene == harness.iconPresentation.output.scene
        }

        harness.publishWiFi(WiFiStatus(state: .noInternet, rssi: -48))
        try await waitUntil {
            harness.iconPresentation.output.trace.center.reason == .overridden(.networkProblem)
                && menuBarScenes.last == harness.iconPresentation.output.scene
                && harness.log.dockRenderKeys.last?.scene == harness.iconPresentation.output.scene
        }
        #expect(harness.iconPresentation.output.trace.center.selectedSourceID == CenterSource.network.rawValue)
    }

    @Test func bothSurfacesRenderTheSameDeliveredScene() async throws {
        let harness = try AppIconControllerHarness(initialPlacement: .both)
        defer { harness.cleanUp() }
        var menuBarScenes: [IconSceneState] = []
        let localization = Localization(preferredLanguages: ["en"])
        let menuBar = StatusBarController(
            store: harness.store,
            settings: harness.settings,
            iconPresentation: harness.iconPresentation,
            localization: localization,
            openSettings: {},
            quitAction: {},
            renderMenuBarBase: { scene, _, _, _ in
                menuBarScenes.append(scene)
                return NSImage(size: NSSize(width: 32, height: 32))
            },
            renderMenuBarOverlay: { _, _, _, _, _ in nil }
        )
        defer { menuBar.setVisible(false) }
        harness.controller.start()
        try await waitUntil { !menuBarScenes.isEmpty && harness.log.renderCount > 0 }

        harness.settings.ringStrokeStyle = .bold
        try await waitUntil {
            menuBarScenes.last?.outerRing?.strokeScale == RingStrokeStyle.bold.scale
                && harness.log.lastScene?.outerRing?.strokeScale == RingStrokeStyle.bold.scale
        }

        #expect(menuBarScenes.last == harness.log.lastScene)
    }

    @Test func hiddenMenuBarRestoresWithLatestSceneAndFailedRasterRetries() async throws {
        let scheduler = ManualIconPresentationScheduler()
        let harness = try AppIconControllerHarness(
            initialPlacement: .both,
            snapshotScheduler: scheduler
        )
        defer { harness.cleanUp() }
        let rasterSpy = MenuBarRasterSpy()
        let menuBar = StatusBarController(
            store: harness.store,
            settings: harness.settings,
            iconPresentation: harness.iconPresentation,
            localization: Localization(preferredLanguages: ["en"]),
            openSettings: {},
            quitAction: {},
            renderMenuBarBase: { scene, size, _, _ in
                rasterSpy.render(scene, size: size)
            },
            renderMenuBarOverlay: { _, _, _, _, _ in nil }
        )
        defer { menuBar.setVisible(false) }
        harness.controller.start()
        try await waitUntil { rasterSpy.calls > 0 }
        menuBar.flushPendingPresentationForTesting()
        harness.controller.flushPendingPresentationForTesting()
        let settledVisibleCalls = rasterSpy.calls

        menuBar.setVisible(false)
        harness.settings.iconSize = 32
        harness.settings.ringStrokeStyle = .bold
        try await waitUntil {
            harness.iconPresentation.output.menuBarSize == 32
                && harness.iconPresentation.output.scene.outerRing?.strokeScale == RingStrokeStyle.bold.scale
        }
        harness.publishWiFi(WiFiStatus(state: .connected, rssi: -20))
        try await waitUntil { harness.store.snapshot.wifi.rssi == -20 }
        #expect(scheduler.hasPendingAction)
        scheduler.runScheduled()
        menuBar.flushPendingPresentationForTesting()
        harness.controller.flushPendingPresentationForTesting()
        #expect(rasterSpy.calls == settledVisibleCalls)

        rasterSpy.allowSuccess = true
        menuBar.setVisible(true)
        try await waitUntil { rasterSpy.calls > settledVisibleCalls }
        menuBar.flushPendingPresentationForTesting()
        try await waitUntil {
            harness.log.lastScene?.outerRing?.strokeScale == RingStrokeStyle.bold.scale
        }
        #expect(rasterSpy.scenes.last == harness.iconPresentation.output.scene)
        #expect(rasterSpy.sizes.last == 32)
        #expect(harness.log.lastScene?.outerRing?.strokeScale == RingStrokeStyle.bold.scale)
    }

    @Test func bothSurfacesKeepLastSuccessAndRetryFailedKeyWithoutVisibilityReset() async throws {
        let harness = try AppIconControllerHarness(initialPlacement: .both)
        defer { harness.cleanUp() }
        let rasterSpy = MenuBarRasterSpy()
        rasterSpy.allowSuccess = true
        let stableAppearance = try #require(NSAppearance(named: .aqua))
        var renderedAppearances: [NSAppearance.Name] = []
        let menuBar = StatusBarController(
            store: harness.store,
            settings: harness.settings,
            iconPresentation: harness.iconPresentation,
            localization: Localization(preferredLanguages: ["en"]),
            openSettings: {},
            quitAction: {},
            renderMenuBarBase: { scene, size, _, appearance in
                renderedAppearances.append(appearance.name)
                return rasterSpy.render(scene, size: size)
            },
            renderMenuBarOverlay: { _, _, _, _, _ in nil },
            appearanceProvider: { stableAppearance }
        )
        defer { menuBar.setVisible(false) }
        harness.controller.start()
        try await waitUntil {
            rasterSpy.successfulImage != nil && harness.application.applicationIconImage != nil
                && rasterSpy.scenes.last == harness.iconPresentation.output.scene
                && harness.log.lastScene == harness.iconPresentation.output.scene
        }
        menuBar.flushPendingPresentationForTesting()
        harness.controller.flushPendingPresentationForTesting()
        let sceneA = harness.iconPresentation.output.scene
        let imageA = try #require(rasterSpy.successfulImage)
        let dockImageA = try #require(harness.application.applicationIconImage)
        #expect(!renderedAppearances.isEmpty)
        #expect(renderedAppearances.allSatisfy { $0 == stableAppearance.name })
        let menuCallsBeforeB = rasterSpy.calls
        let dockCallsBeforeB = harness.log.renderCount

        rasterSpy.allowSuccess = false
        harness.log.failDockRenders = true
        harness.settings.ringStrokeStyle = .bold
        try await waitUntil {
            harness.iconPresentation.output.scene != sceneA
                && rasterSpy.scenes.last == harness.iconPresentation.output.scene
                && harness.log.lastScene == harness.iconPresentation.output.scene
        }
        menuBar.flushPendingPresentationForTesting()
        harness.controller.flushPendingPresentationForTesting()
        let sceneB = harness.iconPresentation.output.scene
        #expect(rasterSpy.calls > menuCallsBeforeB)
        #expect(harness.log.renderCount > dockCallsBeforeB)
        #expect(menuBar.presentedImageForTesting === imageA)
        #expect(harness.application.applicationIconImage === dockImageA)

        let menuCallsAfterB = rasterSpy.calls
        let dockCallsAfterB = harness.log.renderCount
        menuBar.refreshCurrentPresentation()
        harness.controller.refreshCurrentPresentation()
        #expect(rasterSpy.calls == menuCallsAfterB + 1)
        #expect(harness.log.renderCount == dockCallsAfterB + 1)
        #expect(rasterSpy.scenes.last == sceneB)
        #expect(harness.log.lastScene == sceneB)
        #expect(menuBar.presentedImageForTesting === imageA)
        #expect(harness.application.applicationIconImage === dockImageA)

        // The failed B render deliberately left image A installed, so image
        // identity alone can satisfy a restore wait before A's queued request
        // has been consumed. Keep failures enabled until both presentation
        // queues are drained; then a delayed appearance callback cannot turn
        // that stale retained image into a false success.
        harness.settings.ringStrokeStyle = .regular
        try await waitUntil { harness.iconPresentation.output.scene == sceneA }
        #expect(menuBar.presentedImageForTesting === imageA)
        #expect(harness.application.applicationIconImage === dockImageA)
        menuBar.flushPendingPresentationForTesting()
        harness.controller.flushPendingPresentationForTesting()
        await Task.yield()
        menuBar.flushPendingPresentationForTesting()
        harness.controller.flushPendingPresentationForTesting()
        #expect(rasterSpy.calls == menuCallsAfterB + 1)
        #expect(menuBar.presentedImageForTesting === imageA)
        #expect(harness.application.applicationIconImage === dockImageA)

        harness.log.failDockRenders = false
        rasterSpy.allowSuccess = true
        menuBar.refreshCurrentPresentation()
        harness.controller.refreshCurrentPresentation()
        #expect(rasterSpy.calls == menuCallsAfterB + 1)
        #expect(menuBar.presentedImageForTesting === imageA)
        #expect(harness.application.applicationIconImage === dockImageA)
    }

    @Test func latestSceneIsUsedAfterBackgroundPlacementAndControllerRestart() async throws {
        let harness = try AppIconControllerHarness(initialPlacement: .both)
        defer { harness.cleanUp() }
        harness.controller.start()
        try await waitUntil { harness.log.lastScene == harness.iconPresentation.output.scene }

        harness.settings.ringStrokeStyle = .bold
        try await waitUntil { harness.iconPresentation.output.scene.outerRing?.strokeScale == RingStrokeStyle.bold.scale }
        let sceneAfterSettings = harness.iconPresentation.output.scene

        harness.settings.dockIconBackgroundPreference = .dark
        try await waitUntil {
            harness.log.dockRenderKeys.last?.scene == sceneAfterSettings
                && harness.log.dockRenderKeys.last?.backgroundStyle == .dark
        }

        harness.settings.appIconPlacement = .dock
        try await waitUntil { harness.log.events.contains("menu:false") }
        #expect(harness.log.dockRenderKeys.last?.scene == sceneAfterSettings)
        #expect(harness.log.dockRenderKeys.last?.backgroundStyle == .dark)

        harness.controller.stop()
        harness.settings.ringStrokeStyle = .regular
        let sceneWhileStopped = harness.iconPresentation.output.scene
        #expect(sceneWhileStopped != sceneAfterSettings)
        harness.controller.start()
        try await waitUntil {
            harness.log.dockRenderKeys.last?.scene == sceneWhileStopped
                && harness.log.dockRenderKeys.last?.backgroundStyle == .dark
        }
    }

    @Test func mappedSettingsStayInParityAcrossMenuBarAndDock() async throws {
        let harness = try AppIconControllerHarness(
            initialPlacement: .both,
            initialBattery: BatteryStatus(
                rawPercentage: 62,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            initialWiFi: WiFiStatus(state: .noInternet, rssi: nil),
            initialVolume: VolumeStatus(
                scalar: 0.6,
                isMuted: false,
                deviceName: "AirPods",
                currentDevice: PresentationFixtures.bluetoothDevice
            )
        )
        defer { harness.cleanUp() }
        harness.settings.showsBatteryPercentage = true
        try await waitUntil(
            failureMessage: "model did not map the battery percentage accessory",
            diagnostics: { "accessory=\(String(describing: harness.iconPresentation.output.scene.outerRing?.accessory))" }
        ) {
            if case .text = harness.iconPresentation.output.scene.outerRing?.accessory { return true }
            return false
        }
        var menuBarScenes: [IconSceneState] = []
        let menuBar = StatusBarController(
            store: harness.store,
            settings: harness.settings,
            iconPresentation: harness.iconPresentation,
            localization: Localization(preferredLanguages: ["en"]),
            openSettings: {},
            quitAction: {},
            renderMenuBarBase: { scene, _, _, _ in
                menuBarScenes.append(scene)
                return NSImage(size: NSSize(width: 32, height: 32))
            },
            renderMenuBarOverlay: { _, _, _, _, _ in nil }
        )
        defer { menuBar.setVisible(false) }
        harness.controller.start()
        try await waitUntil(
            failureMessage: "initial menu-bar and Dock surface did not render",
            diagnostics: {
                "menuBarScenes=\(menuBarScenes.count), dockRenders=\(harness.log.renderCount), "
                    + "centre=\(describe(harness.iconPresentation.output.scene.center))"
            }
        ) { !menuBarScenes.isEmpty && harness.log.renderCount > 0 }

        try await verifySetting(
            "battery scale",
            { harness.settings.batterySymbolScale = 0.95 },
            matches: { scene in
                guard case let .text(text) = scene.outerRing?.accessory else { return false }
                return text.scale == 0.95 * BatteryIconOptions.defaultTextScale
            },
            latestMenuBarScene: { menuBarScenes.last },
            harness: harness
        )

        try await verifySetting(
            "ring stroke",
            { harness.settings.ringStrokeStyle = .bold },
            matches: { $0.outerRing?.strokeScale == RingStrokeStyle.bold.scale },
            latestMenuBarScene: { menuBarScenes.last },
            harness: harness
        )
        try await verifySetting(
            "Wi-Fi scale",
            { harness.settings.wifiSymbolScale = 1.35 },
            matches: { scene in
                guard case let .symbol(symbol) = scene.center else { return false }
                return symbol.scale == 1.35
            },
            latestMenuBarScene: { menuBarScenes.last },
            harness: harness
        )
        try await verifySetting(
            "volume style",
            { harness.settings.volumeDisplayStyle = .arc },
            matches: { if case .arc = $0.footer { true } else { false } },
            latestMenuBarScene: { menuBarScenes.last },
            harness: harness
        )

        // The V1 global rule is the single network-failure authority now, so the
        // regression is global ON -> OFF for an automaticLegacy centre that also
        // asks Bluetooth to replace the network icon. The legacy per-source
        // priority flag is neutralized on the projection and is no longer the
        // control under test.
        harness.settings.replacesNetworkIconWithBluetoothAudio = true
        harness.settings.updateIconConfiguration {
            $0.composition.centerOverride.networkProblemOverridesPrimary = true
        }
        try await waitUntil(
            failureMessage: "global network rule did not raise the network warning",
            diagnostics: { "centre=\(describe(harness.iconPresentation.output.scene.center))" }
        ) {
            harness.iconPresentation.output.trace.center.reason == .overridden(.networkProblem)
                && harness.iconPresentation.output.trace.center.selectedSourceID == CenterSource.network.rawValue
                && menuBarScenes.last == harness.iconPresentation.output.scene
                && harness.log.lastScene == harness.iconPresentation.output.scene
        }
        let beforePriorityChange = harness.iconPresentation.output.scene
        #expect(beforePriorityChange == menuBarScenes.last)
        #expect(beforePriorityChange == harness.log.lastScene)

        harness.settings.updateIconConfiguration {
            $0.composition.centerOverride.networkProblemOverridesPrimary = false
        }
        try await waitUntil(
            failureMessage: "turning the global rule off did not restore the Bluetooth replacement",
            diagnostics: {
                "centre=\(describe(harness.iconPresentation.output.scene.center)), "
                    + "menu=\(describe(menuBarScenes.last?.center)), dock=\(describe(harness.log.lastScene?.center))"
            }
        ) {
            guard case let .symbol(symbol) = harness.iconPresentation.output.scene.center else { return false }
            return symbol.color == .bluetooth
                && harness.iconPresentation.output.scene != beforePriorityChange
                && menuBarScenes.last == harness.iconPresentation.output.scene
                && harness.log.lastScene == harness.iconPresentation.output.scene
        }
        #expect(menuBarScenes.last == harness.iconPresentation.output.scene)
        #expect(harness.log.lastScene == harness.iconPresentation.output.scene)

        // The earlier Wi-Fi size edit changed shared center Appearance. Bluetooth
        // retains its source control and is rendered through that same slot size.
        let centerAppearance = harness.settings.iconConfiguration.appearance.center
        let expectedBluetoothScale = 1.4 * centerAppearance.symbolScale / CenterAppearance.classic.symbolScale
        try await verifySetting(
            "Bluetooth scale",
            { harness.settings.bluetoothSymbolScale = 1.4 },
            matches: { scene in
                guard case let .symbol(symbol) = scene.center else { return false }
                return abs(symbol.scale - expectedBluetoothScale) < 1e-12
            },
            latestMenuBarScene: { menuBarScenes.last },
            harness: harness
        )
        #expect(harness.settings.bluetoothSymbolScale == 1.4)
        #expect(harness.settings.iconConfiguration.appearance.center == centerAppearance)
        harness.publishBattery(BatteryStatus(
            rawPercentage: 62,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        ))
        try await waitUntil { harness.store.snapshot.battery.isCharging }
        try await waitUntil {
            harness.iconPresentation.output.scene.outerRing?.effect?.pulsesAccessory == true
                && menuBarScenes.last == harness.iconPresentation.output.scene
                && harness.log.lastScene == harness.iconPresentation.output.scene
        }
        try await verifySetting(
            "charging bolt heartbeat",
            { harness.settings.showsChargingBoltHeartbeat = false },
            matches: { $0.outerRing?.effect?.pulsesAccessory == false },
            latestMenuBarScene: { menuBarScenes.last },
            harness: harness,
            expectsDockSceneParity: false
        )
        try await verifySetting(
            "charging effect",
            { harness.settings.showsChargingEffect = false },
            matches: { $0.outerRing?.effect == nil },
            latestMenuBarScene: { menuBarScenes.last },
            harness: harness,
            expectsDockSceneParity: false
        )
    }

    @Test func ssidExactVolumeAndLanguageChangesDoNotRasterizeEitherSurface() async throws {
        let initialWiFi = WiFiStatus(
            state: .connected,
            rssi: -50,
            ssid: "Office",
            nameAccess: .authorized
        )
        let scheduler = ManualIconPresentationScheduler()
        let harness = try AppIconControllerHarness(
            initialPlacement: .both,
            initialWiFi: initialWiFi,
            initialVolume: VolumeStatus(scalar: 0.60, isMuted: false, deviceName: "Speakers"),
            snapshotScheduler: scheduler
        )
        defer { harness.cleanUp() }
        harness.settings.volumeDisplayStyle = .dots
        try await waitUntil {
            if case .dots = harness.iconPresentation.output.scene.footer { return true }
            return false
        }
        var menuBarRenders = 0
        var menuBarKeys: [MenuBarRenderSurfaceKey] = []
        let languageSuite = "IconSurfaceIntegration.\(UUID().uuidString)"
        let languageDefaults = try #require(UserDefaults(suiteName: languageSuite))
        defer { languageDefaults.removePersistentDomain(forName: languageSuite) }
        let localization = Localization(defaults: languageDefaults, preferredLanguages: ["en"])
        var menuBarScenes: [IconSceneState] = []
        var spokenValues: [String] = []
        let menuBar = StatusBarController(
            store: harness.store,
            settings: harness.settings,
            iconPresentation: harness.iconPresentation,
            localization: localization,
            openSettings: {},
            quitAction: {},
            accessibilityValueDidChange: { spokenValues.append($0) },
            renderMenuBarBase: { scene, size, scale, appearance in
                menuBarRenders += 1
                menuBarScenes.append(scene)
                menuBarKeys.append(MenuBarRenderSurfaceKey(
                    scene: scene,
                    size: size,
                    scale: scale,
                    appearanceName: appearance.name.rawValue,
                    phase: nil
                ))
                return NSImage(size: NSSize(width: 32, height: 32))
            },
            renderMenuBarOverlay: { _, _, _, _, _ in nil }
        )
        defer { menuBar.setVisible(false) }
        harness.controller.start()
        try await waitUntil { menuBarRenders > 0 && harness.log.renderCount > 0 }
        try await waitUntil {
            menuBarScenes.last == harness.iconPresentation.output.scene
                && harness.log.lastScene == harness.iconPresentation.output.scene
                && !spokenValues.isEmpty
        }
        let initialMenuBarRenders = menuBarRenders
        let initialDockRenders = harness.log.renderCount
        let initialScene = harness.iconPresentation.output.scene
        let initialMenuBarKey = try #require(menuBarKeys.last)
        let initialDockKey = try #require(harness.log.dockRenderKeys.last)
        #expect(initialMenuBarKey.phase == nil)
        let initialSpokenValue = try #require(spokenValues.last)

        harness.publishWiFi(WiFiStatus(
            state: .connected,
            rssi: -50,
            ssid: "Guest",
            nameAccess: .authorized
        ))
        try await waitUntil { harness.store.snapshot.wifi.ssid == "Guest" }
        try await waitUntil { spokenValues.last?.contains("Guest") == true }
        let ssidSpokenValue = try #require(spokenValues.last)
        #expect(ssidSpokenValue != initialSpokenValue)
        #expect(ssidSpokenValue.contains("Guest"))
        harness.publishVolume(VolumeStatus(scalar: 0.70, isMuted: false, deviceName: "Speakers"))
        try await waitUntil { harness.store.snapshot.volume.scalar == 0.70 }
        try await waitUntil { spokenValues.last != ssidSpokenValue }
        let exactVolumeSpokenValue = try #require(spokenValues.last)
        #expect(exactVolumeSpokenValue != ssidSpokenValue)
        localization.setPreference(.language(.simplifiedChinese))
        try await waitUntil { localization.resolvedLanguage == .simplifiedChinese }
        try await waitUntil { spokenValues.last != exactVolumeSpokenValue }
        let localizedSpokenValue = try #require(spokenValues.last)
        #expect(localizedSpokenValue != exactVolumeSpokenValue)

        scheduler.runScheduled()
        menuBar.flushPendingPresentationForTesting()
        harness.controller.flushPendingPresentationForTesting()

        #expect(harness.iconPresentation.output.scene == initialScene)
        var precedingKey = initialMenuBarKey
        for key in menuBarKeys.dropFirst(initialMenuBarRenders) {
            #expect(key.scene == precedingKey.scene)
            #expect(key.size == precedingKey.size)
            #expect(key.phase == precedingKey.phase)
            #expect(key.appearanceName != precedingKey.appearanceName || key.scale != precedingKey.scale)
            precedingKey = key
        }
        #expect(harness.log.dockRenderKeys.count == initialDockRenders)
        #expect(harness.log.dockRenderKeys.last == initialDockKey)
    }

    @Test func chargingTestProjectionStaysMenuBarOnly() async throws {
        let harness = try AppIconControllerHarness(initialPlacement: .both)
        defer { harness.cleanUp() }
        var menuBarScenes: [IconSceneState] = []
        let menuBar = StatusBarController(
            store: harness.store,
            settings: harness.settings,
            iconPresentation: harness.iconPresentation,
            localization: Localization(preferredLanguages: ["en"]),
            openSettings: {},
            quitAction: {},
            renderMenuBarBase: { scene, _, _, _ in
                menuBarScenes.append(scene)
                return NSImage(size: NSSize(width: 32, height: 32))
            },
            renderMenuBarOverlay: { _, _, _, _, _ in nil }
        )
        defer { menuBar.setVisible(false) }
        harness.controller.start()
        try await waitUntil { !menuBarScenes.isEmpty && harness.log.renderCount > 0 }
        try await waitUntil {
            menuBarScenes.last == harness.iconPresentation.output.scene
                && harness.log.lastScene == harness.iconPresentation.output.scene
        }
        let canonicalScene = harness.iconPresentation.output.scene
        let originalDockImage = harness.application.applicationIconImage
        let dockRenders = harness.log.renderCount

        harness.settings.setChargingEffectTestEnabled(true)
        try await waitUntil {
            guard let testScene = harness.iconPresentation.output.menuBarTestScene else { return false }
            return menuBarScenes.last == testScene
        }

        #expect(harness.iconPresentation.output.scene == canonicalScene)
        #expect(menuBarScenes.last != canonicalScene)
        #expect(harness.log.lastScene == canonicalScene)
        #expect(harness.log.renderCount == dockRenders)
        #expect(harness.application.applicationIconImage === originalDockImage)
    }

    @Test func chargingEffectPreferenceChangesUpdateMenuBarWithoutRerasterizingStaticDock() async throws {
        let harness = try AppIconControllerHarness(
            initialPlacement: .both,
            initialBattery: BatteryStatus(
                rawPercentage: 62,
                isPresent: true,
                isCharging: true,
                isLowPowerMode: false,
                isConnectedToPower: true
            ),
            snapshotScheduler: ManualIconPresentationScheduler()
        )
        defer { harness.cleanUp() }
        var menuBarScenes: [IconSceneState] = []
        let menuBar = StatusBarController(
            store: harness.store,
            settings: harness.settings,
            iconPresentation: harness.iconPresentation,
            localization: Localization(preferredLanguages: ["en"]),
            openSettings: {},
            quitAction: {},
            renderMenuBarBase: { scene, _, _, _ in
                menuBarScenes.append(scene)
                return NSImage(size: NSSize(width: 32, height: 32))
            },
            renderMenuBarOverlay: { _, _, _, _, _ in nil }
        )
        defer { menuBar.setVisible(false) }
        harness.controller.start()
        try await waitUntil {
            harness.log.renderCount > 0
                && menuBarScenes.last == harness.iconPresentation.output.scene
                && harness.iconPresentation.output.scene.outerRing?.effect?.pulsesAccessory == true
        }
        let initialDockRenders = harness.log.renderCount
        let initialDockImage = harness.application.applicationIconImage

        harness.settings.showsChargingBoltHeartbeat = false
        try await waitUntil {
            harness.iconPresentation.output.scene.outerRing?.effect?.pulsesAccessory == false
                && menuBarScenes.last == harness.iconPresentation.output.scene
        }
        harness.controller.flushPendingPresentationForTesting()
        #expect(menuBarScenes.last?.outerRing?.effect?.pulsesAccessory == false)
        #expect(harness.log.renderCount == initialDockRenders)
        #expect(harness.application.applicationIconImage === initialDockImage)

        harness.settings.showsChargingEffect = false
        try await waitUntil {
            harness.iconPresentation.output.scene.outerRing?.effect == nil
                && menuBarScenes.last == harness.iconPresentation.output.scene
        }
        harness.controller.flushPendingPresentationForTesting()
        #expect(menuBarScenes.last?.outerRing?.effect == nil)
        #expect(harness.log.renderCount == initialDockRenders)
        #expect(harness.application.applicationIconImage === initialDockImage)

        harness.settings.ringStrokeStyle = .bold
        try await waitUntil {
            harness.iconPresentation.output.scene.outerRing?.strokeScale == RingStrokeStyle.bold.scale
                && menuBarScenes.last == harness.iconPresentation.output.scene
        }
        harness.controller.flushPendingPresentationForTesting()
        #expect(harness.log.renderCount > initialDockRenders)
        #expect(harness.log.lastScene?.outerRing?.strokeScale == RingStrokeStyle.bold.scale)
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        failureMessage: String = "The surface update did not arrive.",
        diagnostics: @escaping @MainActor () -> String = { "" },
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        let detail = diagnostics()
        Issue.record("\(failureMessage) Timeout: \(timeout).\(detail.isEmpty ? "" : " \(detail)")")
    }

    /// Short, stable description of a centre payload so a timeout record names
    /// what actually rendered instead of only the missing condition.
    private func describe(_ center: CenterState?) -> String {
        switch center {
        case .none: "none"
        case .text(let text): "text(\(text.text))"
        case .symbol(let symbol): "symbol(\(symbol.source))"
        }
    }

    private func verifySetting(
        _ label: String,
        _ update: @escaping @MainActor () -> Void,
        matches: @escaping @MainActor (IconSceneState) -> Bool,
        latestMenuBarScene: @escaping @MainActor () -> IconSceneState?,
        harness: AppIconControllerHarness,
        expectsDockSceneParity: Bool = true
    ) async throws {
        let dockRenderCount = harness.log.renderCount
        update()
        try await waitUntil(failureMessage: "Model did not map \(label).") {
            matches(harness.iconPresentation.output.scene)
        }
        try await waitUntil(failureMessage: "Surface presentation did not update for \(label).") {
            guard let scene = latestMenuBarScene() else { return false }
            guard matches(scene), scene == harness.iconPresentation.output.scene else { return false }
            return !expectsDockSceneParity || scene == harness.log.lastScene
        }
        if expectsDockSceneParity {
            #expect(latestMenuBarScene() == harness.log.lastScene)
        } else {
            #expect(harness.log.renderCount == dockRenderCount)
        }
    }

}

private struct MenuBarRenderSurfaceKey: Equatable {
    let scene: IconSceneState
    let size: Double
    let scale: CGFloat
    let appearanceName: String
    let phase: ChargingEffectPhase?
}

@MainActor
private final class MenuBarRasterSpy {
    var allowSuccess = false
    private(set) var calls = 0
    private(set) var scenes: [IconSceneState] = []
    private(set) var sizes: [Double] = []
    private(set) var successfulImage: NSImage?

    func render(_ scene: IconSceneState, size: Double = 28) -> NSImage? {
        calls += 1
        scenes.append(scene)
        sizes.append(size)
        guard allowSuccess else { return nil }
        let image = NSImage(size: NSSize(width: 32, height: 32))
        successfulImage = image
        return image
    }
}
