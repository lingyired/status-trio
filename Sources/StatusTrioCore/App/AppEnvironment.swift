import AppKit
import Combine

@MainActor
final class AppEnvironment {
    let store: SystemStatusStore
    let settings: SettingsStore
    let localization: Localization
    let iconPresentation: IconPresentationViewModel
    let statusBarController: StatusBarController
    let settingsWindowController: SettingsWindowController
    let onboardingWindowController: OnboardingWindowController
    let activationPolicy: AppActivationPolicy
    let appIconController: AppIconController
    let mainMenuController: MainMenuController
    let inputSourceController: InputSourceController
    let chargingEffectClock: ChargingEffectClock
    let chargingEffectMotionMonitor: ChargingEffectMotionMonitor
    let globalShortcutController: GlobalShortcutController?
    let dockChargingAnimationPresenter: (any DockChargingAnimationPresenting)?
    let dockVisibilityMonitor: (any DockVisibilityMonitoring)?
    let telemetryReporter: any TelemetryReporting
    let updater: UpdateStateFacade
    let privilegedHelper: PrivilegedHelperFacade
    let capabilityPolicy: DistributionCapabilityPolicy
    let bluetoothAudioIconOverrideSynchronizer = BluetoothAudioIconOverrideSynchronizer()
    private let bluetoothProfilerCache: BluetoothProfilerReportCache
    private let bluetoothNearbyBatteryOptOutSynchronizer = BluetoothNearbyBatteryOptOutSynchronizer()
    private let lowPowerModeControlSynchronizer = LowPowerModeControlSynchronizer()
    private let memoryPressureMonitor: MemoryPressureMonitor
    private let previewResourceLifecycle: PreviewResourceLifecycle

    private var chargingEffectCancellables = Set<AnyCancellable>()
    private var inputSourceLifecycleCancellables = Set<AnyCancellable>()
    private var previewResourceLifecycleCancellables = Set<AnyCancellable>()
    private var hasSubscribedToChargingEffectInputs = false
    private var isPreviewResourceLifecycleStarted = false
    private var menuBarChargingEffectEnabled: Bool
    private var dockChargingEffectEnabled: Bool
    private var dockChargingAnimationShouldRun = false
    private var isDockVisibilityMonitoring = false

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        localization: Localization,
        iconPresentation: IconPresentationViewModel,
        statusBarController: StatusBarController,
        settingsWindowController: SettingsWindowController,
        onboardingWindowController: OnboardingWindowController,
        activationPolicy: AppActivationPolicy,
        appIconController: AppIconController,
        mainMenuController: MainMenuController,
        inputSourceController: InputSourceController,
        chargingEffectClock: ChargingEffectClock,
        chargingEffectMotionMonitor: ChargingEffectMotionMonitor,
        globalShortcutController: GlobalShortcutController? = nil,
        dockChargingAnimationPresenter: (any DockChargingAnimationPresenting)? = nil,
        dockVisibilityMonitor: (any DockVisibilityMonitoring)? = nil,
        telemetryReporter: any TelemetryReporting,
        updater: UpdateStateFacade? = nil,
        privilegedHelper: PrivilegedHelperFacade? = nil,
        platformCapabilities: [PlatformCapabilityRecord]? = nil,
        distributionChannel: DistributionChannel = .current,
        memoryPressureMonitor: MemoryPressureMonitor? = nil,
        bluetoothProfilerCache: BluetoothProfilerReportCache = .shared,
        previewResourceLifecycle: PreviewResourceLifecycle? = nil
    ) {
        self.store = store
        self.settings = settings
        self.localization = localization
        self.iconPresentation = iconPresentation
        self.statusBarController = statusBarController
        self.settingsWindowController = settingsWindowController
        self.onboardingWindowController = onboardingWindowController
        self.activationPolicy = activationPolicy
        self.appIconController = appIconController
        self.mainMenuController = mainMenuController
        self.inputSourceController = inputSourceController
        self.chargingEffectClock = chargingEffectClock
        self.chargingEffectMotionMonitor = chargingEffectMotionMonitor
        self.globalShortcutController = globalShortcutController
        self.dockChargingAnimationPresenter = dockChargingAnimationPresenter
        self.dockVisibilityMonitor = dockVisibilityMonitor
        self.telemetryReporter = telemetryReporter
        self.updater = updater ?? UpdateStateFacade(service: SystemManagedUpdateService())
        self.privilegedHelper = privilegedHelper
            ?? PrivilegedHelperFacade(service: UnsupportedPrivilegedHelperService())
        self.capabilityPolicy = DistributionCapabilityPolicy(
            channel: distributionChannel,
            records: platformCapabilities
        )
        self.memoryPressureMonitor = memoryPressureMonitor ?? MemoryPressureMonitor()
        self.bluetoothProfilerCache = bluetoothProfilerCache
        self.previewResourceLifecycle = previewResourceLifecycle ?? PreviewResourceLifecycle()
        self.menuBarChargingEffectEnabled = settings.showsMenuBarChargingEffect
        self.dockChargingEffectEnabled = settings.showsDockChargingEffect
    }

    func start() {
        startPreviewResourceLifecycleIfNeeded()
        memoryPressureMonitor.onPressure = { [weak self] in
            self?.releaseRebuildableResources()
        }
        memoryPressureMonitor.start()
        iconPresentation.start()
        startInputSourceMonitoringIfNeeded()
        onboardingWindowController.showIfNeeded()
        statusBarController.visibilityDidChange = { [weak self] in
            self?.updateChargingEffectClock()
        }
        appIconController.dockChargingAnimationEligibilityDidChange = { [weak self] in
            self?.updateChargingEffectClock()
        }
        appIconController.dockContentDidChange = { [weak self] in
            self?.updateDockChargingAnimation()
        }
        dockVisibilityMonitor?.onChange = { [weak self] _ in
            self?.updateDockChargingAnimationOwnership()
        }
        appIconController.systemPollDidFire = { [weak self] in
            guard let self, isDockVisibilityMonitoring else { return }
            dockVisibilityMonitor?.refresh()
        }
        chargingEffectMotionMonitor.onChange = { [weak self] _ in
            self?.updateChargingEffectClock()
        }
        chargingEffectMotionMonitor.start()
        subscribeToChargingEffectInputs()
        mainMenuController.start()
        globalShortcutController?.start()
        appIconController.start()
        bluetoothAudioIconOverrideSynchronizer.start(
            devices: store.bluetoothDevices,
            settings: settings
        )
        bluetoothNearbyBatteryOptOutSynchronizer.start(
            settings: settings,
            actions: StatusPanelActions(
                store: store,
                settings: settings,
                capabilityPolicy: capabilityPolicy
            )
        )
        lowPowerModeControlSynchronizer.start(
            settings: settings,
            helper: privilegedHelper
        )
        updater.start()
        store.bindInputSettings(settings)
        store.bindLocalIPSettings(settings)
        store.bindMobileBatterySettings(settings)
        store.bindLowPowerModeSettings(settings)
        store.bindBluetoothSettings(settings)
        store.start()
        telemetryReporter.start()
    }

    func stop() {
        memoryPressureMonitor.stop()
        memoryPressureMonitor.onPressure = nil
        telemetryReporter.stop()
        globalShortcutController?.stop()
        chargingEffectClock.stop()
        statusBarController.visibilityDidChange = nil
        stopPreviewResourceLifecycle()
        appIconController.dockChargingAnimationEligibilityDidChange = nil
        appIconController.dockContentDidChange = nil
        appIconController.systemPollDidFire = nil
        dockVisibilityMonitor?.onChange = nil
        if isDockVisibilityMonitoring {
            dockVisibilityMonitor?.stop()
            isDockVisibilityMonitoring = false
        }
        dockChargingAnimationPresenter?.clear()
        chargingEffectMotionMonitor.onChange = nil
        chargingEffectMotionMonitor.stop()
        chargingEffectCancellables.removeAll()
        bluetoothAudioIconOverrideSynchronizer.stop()
        bluetoothNearbyBatteryOptOutSynchronizer.stop()
        lowPowerModeControlSynchronizer.stop()
        inputSourceLifecycleCancellables.removeAll()
        inputSourceController.stop()
        appIconController.stop()
        mainMenuController.stop()
        store.stop()
        // Both profiler consumers belong to the stopped store. A pressure
        // warning alone must not invalidate a report another reader is using.
        bluetoothProfilerCache.resetIfUnused()
        iconPresentation.stop()
        releaseRebuildableResources()
    }

    private func startPreviewResourceLifecycleIfNeeded() {
        guard !isPreviewResourceLifecycleStarted else { return }
        isPreviewResourceLifecycleStarted = true
        previewResourceLifecycle.start()
        settingsWindowController.startPreviewResourceObservation { [weak self] visible in
            self?.previewResourceLifecycle.setPreviewOwner(.settings, visible: visible)
        }
        onboardingWindowController.startPreviewResourceObservation { [weak self] visible in
            self?.previewResourceLifecycle.setPreviewOwner(.onboarding, visible: visible)
        }
        store.$isPopoverVisible
            .removeDuplicates()
            .sink { [weak self] visible in
                guard let self, visible else { return }
                previewResourceLifecycle.setPopoverContentOwned(true)
            }
            .store(in: &previewResourceLifecycleCancellables)
        statusBarController.onPopoverContentReleased = { [weak self] in
            self?.previewResourceLifecycle.setPopoverContentOwned(false)
        }
    }

    private func stopPreviewResourceLifecycle() {
        guard isPreviewResourceLifecycleStarted else { return }
        isPreviewResourceLifecycleStarted = false
        previewResourceLifecycleCancellables.removeAll()
        statusBarController.onPopoverContentReleased = nil
        settingsWindowController.stopPreviewResourceObservation()
        onboardingWindowController.stopPreviewResourceObservation()
        previewResourceLifecycle.stop()
    }

    private func releaseRebuildableResources() {
        appIconController.releaseCachedImages()
        statusBarController.trimForMemoryPressure()
        dockChargingAnimationPresenter?.trimForMemoryPressure()
        previewResourceLifecycle.releaseIfIdle()
        IconImageDecodeCache.shared.reset()
        DockIconRenderer.resetScratchContexts()
        StatusIconRenderer.resetInkOffsetCaches()
    }

    /// Input-source observers exist only while a feature that draws them is
    /// on: the centre-slot source or the panel section. Both off — the shipped
    /// default — means no TIS reads and no distributed observers at all.
    private func startInputSourceMonitoringIfNeeded() {
        guard inputSourceLifecycleCancellables.isEmpty else { return }
        Publishers.CombineLatest(
            settings.$connectionCenterSource.removeDuplicates(),
            settings.$enabledPopupSections.removeDuplicates()
        )
        .sink { [weak self] centerSource, enabledSections in
            guard let self else { return }
            let isNeeded = centerSource == .inputSource || enabledSections.contains(.inputSource)
            if isNeeded {
                inputSourceController.start()
            } else {
                inputSourceController.stop()
            }
        }
        .store(in: &inputSourceLifecycleCancellables)
    }

    private func subscribeToChargingEffectInputs() {
        guard !hasSubscribedToChargingEffectInputs else { return }
        hasSubscribedToChargingEffectInputs = true
        chargingEffectClock.$phase
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateDockChargingAnimation()
            }
            .store(in: &chargingEffectCancellables)
        Publishers.CombineLatest4(
            store.$snapshot.map(\.battery).removeDuplicates(),
            settings.$showsMenuBarChargingEffect.removeDuplicates(),
            settings.$showsDockChargingEffect.removeDuplicates(),
            store.$isDisplayAsleep.removeDuplicates()
        )
        .combineLatest(settings.$testsChargingEffect.removeDuplicates())
        .sink { [weak self] values, testMode in
            // The Dock claim is part of the clock's surface set, so every input
            // that can change it goes through the one entry point. Use the
            // delivered values: `@Published` emits before the store's stored
            // value changes.
            self?.updateChargingEffectClock(
                battery: values.0,
                menuBarEffect: values.1,
                dockEffect: values.2,
                displayAsleep: values.3,
                testMode: testMode
            )
        }
        .store(in: &chargingEffectCancellables)
    }

    private func updateChargingEffectClock(
        battery: BatteryStatus? = nil,
        menuBarEffect: Bool? = nil,
        dockEffect: Bool? = nil,
        displayAsleep: Bool? = nil,
        testMode: Bool? = nil
    ) {
        let menuBarEffect = menuBarEffect ?? menuBarChargingEffectEnabled
        let dockEffect = dockEffect ?? dockChargingEffectEnabled
        self.menuBarChargingEffectEnabled = menuBarEffect
        self.dockChargingEffectEnabled = dockEffect

        let battery = ChargingEffectTestMode.battery(
            battery ?? store.snapshot.battery,
            enabled: testMode ?? settings.testsChargingEffect
        )
        let reduceMotion = chargingEffectMotionMonitor.shouldReduceMotion
        let displayAsleep = displayAsleep ?? store.isDisplayAsleep
        let shouldAnimate = ChargingEffectPolicy.shouldAnimate(
            battery: battery,
            enabled: menuBarEffect || dockEffect,
            reduceMotion: reduceMotion,
            displayAsleep: displayAsleep
        )
        dockChargingAnimationShouldRun = dockEffect && shouldAnimate
        updateDockVisibilityMonitoring()
        updateDockChargingAnimationOwnership()
        chargingEffectClock.update(
            battery: battery,
            enabled: menuBarEffect || dockEffect,
            reduceMotion: reduceMotion,
            displayAsleep: displayAsleep,
            menuBarVisible: statusBarController.isMenuBarVisible && menuBarEffect
        )
        updateDockChargingAnimationOwnership()
    }

    private func updateDockVisibilityMonitoring() {
        guard let dockVisibilityMonitor else { return }
        let shouldMonitor =
            dockChargingAnimationShouldRun && appIconController.isDockChargingAnimationEligible
        guard shouldMonitor != isDockVisibilityMonitoring else { return }
        isDockVisibilityMonitoring = shouldMonitor
        if shouldMonitor {
            dockVisibilityMonitor.start()
        } else {
            dockVisibilityMonitor.stop()
        }
    }

    /// The Dock claims the same clock whenever the user's placement really has
    /// a Dock tile and the Dock effect is enabled. A temporary regular
    /// activation has no placement, so it never claims the animation.
    private func updateDockChargingAnimationOwnership() {
        guard let presenter = dockChargingAnimationPresenter else {
            chargingEffectClock.setDockAnimationActive(false)
            return
        }
        let isDockEligible =
            dockChargingEffectEnabled
            && appIconController.isDockChargingAnimationEligible
            && (dockVisibilityMonitor?.isDockVisible ?? true)

        chargingEffectClock.setDockAnimationActive(isDockEligible)
        appIconController.setDockChargingAnimationActive(isDockEligible)
        guard isDockEligible else {
            presenter.clear()
            return
        }
        updateDockChargingAnimation()
    }

    /// Draws the phase the shared clock just published.
    private func updateDockChargingAnimation() {
        guard let presenter = dockChargingAnimationPresenter,
              dockChargingEffectEnabled,
              appIconController.isDockChargingAnimationEligible,
              (dockVisibilityMonitor?.isDockVisible ?? true)
        else { return }
        guard chargingEffectClock.isRunning, let phase = chargingEffectClock.phase else {
            appIconController.setDockChargingAnimationActive(false)
            presenter.clear()
            return
        }
        guard presenter.present(
            phase: phase,
            scene: appIconController.latestAnimationScene,
            backgroundStyle: appIconController.currentDockBackgroundStyle,
            pixelLength: DockIconRenderer.pixelSize
        ) else {
            appIconController.setDockChargingAnimationActive(false)
            presenter.restoreStaticIcon()
            return
        }
        appIconController.setDockChargingAnimationActive(true)
    }

    static func makeLive(
        settings: SettingsStore,
        store: SystemStatusStore,
        makeUpdater: @MainActor (AppActivationPolicy) -> UpdateStateFacade,
        privilegedHelper: PrivilegedHelperFacade,
        platformCapabilities: [PlatformCapabilityRecord]? = nil,
        distributionChannel: DistributionChannel = .current
    ) -> AppEnvironment {
        let localization = Localization()
        let inputSourceController = InputSourceController()
        let appearance = StatusIconAppearance(settings: settings)
        let iconPresentation = IconPresentationViewModel(
            snapshot: store.snapshot,
            settings: IconPresentationSettings(
                configuration: IconPresentationConfiguration(
                    battery: appearance.batteryOptions,
                    connection: appearance.connectionOptions,
                    volume: appearance.volumeOptions,
                    bluetooth: appearance.bluetoothAudioOptions
                ),
                menuBarSize: appearance.iconSize,
                testsChargingEffect: settings.testsChargingEffect
            ),
            snapshots: store.$snapshot.eraseToAnyPublisher(),
            preferences: settings.iconPresentationPublisher,
            inputSources: inputSourceController.$state
                .map(\.selectedDescriptor)
                .removeDuplicates()
                .eraseToAnyPublisher(),
            resolveInputs: { snapshot in
                IconPresentationResourceResolver.inputs(snapshot: snapshot)
            }
        )
        let chargingEffectClock = ChargingEffectClock()
        let chargingEffectMotionMonitor = ChargingEffectMotionMonitor()
        let dockChargingAnimationPresenter: any DockChargingAnimationPresenting =
            DockChargingAnimationRendererMode.usesApplicationIconFrames()
                ? DockApplicationIconChargingPresenter()
                : DockChargingAnimationPresenter()
        let dockVisibilityMonitor = DockVisibilityMonitor()
        let activationPolicy = AppActivationPolicy()
        let capabilityPolicy = DistributionCapabilityPolicy(
            channel: distributionChannel,
            records: platformCapabilities
        )
        let updater = makeUpdater(activationPolicy)
        let onboardingWindowController = OnboardingWindowController(
            settings: settings,
            localization: localization,
            activationPolicy: activationPolicy
        )
        var settingsWindowController: SettingsWindowController?
        let controller = StatusBarController(
            store: store,
            settings: settings,
            iconPresentation: iconPresentation,
            localization: localization,
            isVisible: settings.appIconPlacement.showsMenuBarIcon,
            openSettings: { settingsWindowController?.show() },
            quitAction: { NSApplication.shared.terminate(nil) },
            chargingEffectClock: chargingEffectClock,
            inputSourceController: inputSourceController,
            updaterManager: updater,
            helper: privilegedHelper,
            capabilityPolicy: capabilityPolicy
        )
        let globalShortcutController = GlobalShortcutController(
            settings: settings,
            backend: CarbonHotKeyBackend(),
            action: { [weak controller] in
                controller?.openPopoverFromShortcut()
            }
        )
        let resolvedSettingsWindowController = SettingsWindowController(
            store: settings,
            statusStore: store,
            localization: localization,
            activationPolicy: activationPolicy,
            showIconGuide: { [weak onboardingWindowController] in
                onboardingWindowController?.show()
            },
            chargingEffectClock: chargingEffectClock,
            inputSourceController: inputSourceController,
            globalShortcutController: globalShortcutController,
            helper: privilegedHelper,
            updaterManager: updater,
            capabilityPolicy: capabilityPolicy
        )
        settingsWindowController = resolvedSettingsWindowController
        onboardingWindowController.openSettings = { [weak resolvedSettingsWindowController] in
            resolvedSettingsWindowController?.show()
        }
        let appIconController = AppIconController(
            settings: settings,
            iconPresentation: iconPresentation,
            activationPolicy: activationPolicy,
            setMenuBarVisible: { isVisible in
                controller.setVisible(isVisible)
            },
            renderDockIcon: {
                scene,
                backgroundStyle,
                pixelLength in
                DockIconRenderer.image(
                    scene: scene,
                    backgroundStyle: backgroundStyle,
                    pixelLength: pixelLength
                )
            }
        )
        let mainMenuController = MainMenuController(
            activationPolicy: activationPolicy,
            localization: localization,
            openSettings: { resolvedSettingsWindowController.show() }
        )
        let telemetryConfiguration = TelemetryConfiguration()
        let telemetryTransport = URLSessionTelemetryTransport(configuration: telemetryConfiguration)
        let telemetryClient = TelemetryClient(
            transport: telemetryTransport,
            configuration: telemetryConfiguration
        )
        let telemetryReporter = TelemetryReporter(
            settings: settings,
            localization: localization,
            client: telemetryClient,
            eligibilityContext: TelemetryEligibilityContext(
                bundleIdentifier: Bundle.main.bundleIdentifier,
                productionMarker: Bundle.main.object(forInfoDictionaryKey: "STTelemetryProduction") as? Bool ?? false,
                isDebugBuild: Self.isDebugBuild,
                channel: distributionChannel
            ),
            configuration: telemetryConfiguration,
            snapshotContext: { language, placement in
                TelemetryAppMetadata.snapshot(
                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                    build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                    osVersion: TelemetryAppMetadata.currentOSVersion,
                    preferredLanguages: Locale.preferredLanguages,
                    appLanguage: language,
                    appIconPlacement: placement
                )
            }
        )
        return AppEnvironment(
            store: store,
            settings: settings,
            localization: localization,
            iconPresentation: iconPresentation,
            statusBarController: controller,
            settingsWindowController: resolvedSettingsWindowController,
            onboardingWindowController: onboardingWindowController,
            activationPolicy: activationPolicy,
            appIconController: appIconController,
            mainMenuController: mainMenuController,
            inputSourceController: inputSourceController,
            chargingEffectClock: chargingEffectClock,
            chargingEffectMotionMonitor: chargingEffectMotionMonitor,
            globalShortcutController: globalShortcutController,
            dockChargingAnimationPresenter: dockChargingAnimationPresenter,
            dockVisibilityMonitor: dockVisibilityMonitor,
            telemetryReporter: telemetryReporter,
            updater: updater,
            privilegedHelper: privilegedHelper,
            platformCapabilities: platformCapabilities,
            distributionChannel: distributionChannel
        )
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
