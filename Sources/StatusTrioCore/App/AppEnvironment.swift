import AppKit
import Combine

@MainActor
final class AppEnvironment {
    let store: SystemStatusStore
    let settings: SettingsStore
    let localization: Localization
    let iconPresentation: IconPresentationViewModel
    let localIconPluginRuntime: LocalIconPluginRuntime
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
    let bluetoothAudioIconOverrideSynchronizer = BluetoothAudioIconOverrideSynchronizer()
    private let bluetoothProfilerCache: BluetoothProfilerReportCache
    private let bluetoothNearbyBatteryOptOutSynchronizer = BluetoothNearbyBatteryOptOutSynchronizer()
    private let lowPowerModeControlSynchronizer = LowPowerModeControlSynchronizer()
    private let memoryPressureMonitor: MemoryPressureMonitor
    private let previewResourceLifecycle: PreviewResourceLifecycle
    let backgroundUITesting: BackgroundUITestingConfiguration

    private var chargingEffectCancellables = Set<AnyCancellable>()
    private var inputSourceLifecycleCancellables = Set<AnyCancellable>()
    private var hardwareRingDemandWiring: IconHardwareDemandWiring?
    private var hardwareSamplingSettingsCancellables = Set<AnyCancellable>()
    private var localIconDemandWiring: IconLiveDemandWiring?
    private var localIconPluginCancellables = Set<AnyCancellable>()
    private let localIconRefreshCoalescer = IconLiveResolutionCoalescer(
        minimumInterval: 0.25,
        timing: .live()
    )
    private let hardwareBackgroundDemandController: HardwareBackgroundDemandController
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
        memoryPressureMonitor: MemoryPressureMonitor? = nil,
        bluetoothProfilerCache: BluetoothProfilerReportCache = .shared,
        previewResourceLifecycle: PreviewResourceLifecycle? = nil,
        backgroundUITesting: BackgroundUITestingConfiguration = .disabled,
        localIconPluginRuntime: LocalIconPluginRuntime = LocalIconPluginRuntime(directories: { [] })
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
        self.memoryPressureMonitor = memoryPressureMonitor ?? MemoryPressureMonitor()
        self.bluetoothProfilerCache = bluetoothProfilerCache
        self.previewResourceLifecycle = previewResourceLifecycle ?? PreviewResourceLifecycle()
        self.backgroundUITesting = backgroundUITesting
        self.localIconPluginRuntime = localIconPluginRuntime
        self.menuBarChargingEffectEnabled = settings.showsMenuBarChargingEffect
        self.dockChargingEffectEnabled = settings.showsDockChargingEffect
        self.hardwareBackgroundDemandController = HardwareBackgroundDemandController(store: store, settings: settings)
    }

    func start() {
        startPreviewResourceLifecycleIfNeeded()
        memoryPressureMonitor.onPressure = { [weak self] in
            self?.releaseRebuildableResources()
        }
        memoryPressureMonitor.start()
        iconPresentation.start()
        startHardwareRingDemand()
        startHardwareSamplingSettings()
        startLocalIconPluginRuntime()
        hardwareBackgroundDemandController.start()
        startInputSourceMonitoringIfNeeded()
        // A panel test must not be blocked by first-run onboarding. The
        // Settings background route keeps its existing onboarding policy.
        let presentedOnboarding =
            backgroundUITesting.isEnabled && backgroundUITesting.opensStatusPanel
            ? false
            : onboardingWindowController.showIfNeeded()
        if backgroundUITesting.isEnabled, !presentedOnboarding {
            if backgroundUITesting.opensStatusPanel {
                statusBarController.presentStatusPanelForBackgroundTesting()
                if let raw = backgroundUITesting.opensHardwareDetailRaw,
                   let detail = HardwareDetailKind(rawValue: raw) {
                    // Present first, then route on the next main turn so the
                    // panel's own prepare/reset cannot overwrite the page.
                    DispatchQueue.main.async { [weak self] in
                        self?.statusBarController.panelForTesting.showHardwareDetail(detail)
                    }
                }
            } else {
                settingsWindowController.show()
            }
        }
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
            actions: StatusPanelActions(store: store, settings: settings)
        )
        lowPowerModeControlSynchronizer.start(
            settings: settings,
            helper: PrivilegedHelperManager.shared
        )
        store.bindInputSettings(settings)
        store.bindLocalIPSettings(settings)
        store.bindApplicationEnergySettings(settings)
        store.bindMobileBatterySettings(settings)
        store.bindLowPowerModeSettings(settings)
        store.bindBluetoothSettings(settings)
        store.bindExternalVolumeSettings(settings)
        store.bindExternalBrightnessSettings(settings)
        store.start()
        telemetryReporter.start()
    }

    func stop() {
        settings.flushPendingPersists()
        memoryPressureMonitor.stop()
        memoryPressureMonitor.onPressure = nil
        telemetryReporter.stop()
        globalShortcutController?.stop()
        chargingEffectClock.stop()
        statusBarController.visibilityDidChange = nil
        stopPreviewResourceLifecycle()
        appIconController.dockChargingAnimationEligibilityDidChange = nil
        appIconController.dockContentDidChange = nil
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
        hardwareBackgroundDemandController.stop()
        hardwareRingDemandWiring?.stop()
        hardwareRingDemandWiring = nil
        hardwareSamplingSettingsCancellables.removeAll()
        localIconDemandWiring?.stop()
        localIconDemandWiring = nil
        localIconPluginRuntime.stop()
        localIconPluginCancellables.removeAll()
        localIconRefreshCoalescer.cancel()
        store.hardwareMetrics.end(.menuBarArc)
        store.hardwareMetrics.end(.dock)
        // Both profiler consumers belong to the stopped store. A pressure
        // warning alone must not invalidate a report another reader is using.
        bluetoothProfilerCache.resetIfUnused()
        iconPresentation.stop()
        releaseRebuildableResources()
    }

    /// Starts the local package runtime and keeps it in step with the resolved
    /// icon demand and the enabled directory list. A package update only
    /// re-resolves the scene; it never rewrites the saved slot bindings.
    private func startLocalIconPluginRuntime() {
        guard settings.isLocalIconPluginEntryAvailable else { return }
        localIconPluginCancellables.removeAll()
        localIconDemandWiring?.stop()
        localIconDemandWiring = nil
        localIconPluginRuntime.start()
        localIconPluginRuntime.changes
            .sink { [weak self] in
                guard let self else { return }
                // External readings can arrive in bursts; keep the first value
                // immediate and coalesce the rest to at most four parses/second.
                self.localIconRefreshCoalescer.request { [weak self] in
                    self?.iconPresentation.refresh()
                }
            }
            .store(in: &localIconPluginCancellables)
        let demandWiring = IconLiveDemandWiring(
            demand: iconPresentation.demand,
            placement: settings.appIconPlacement,
            apply: { [weak self] bindings in
                self?.localIconPluginRuntime.updateDemand(bindings)
            }
        )
        localIconDemandWiring = demandWiring
        demandWiring.start(
            demands: iconPresentation.$demand.eraseToAnyPublisher(),
            placements: settings.$appIconPlacement.eraseToAnyPublisher()
        )
        settings.$localIconPluginDirectories
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.localIconPluginRuntime.reloadCatalog() }
            }
            .store(in: &localIconPluginCancellables)
    }

    /// Demand the hardware metrics only while the System Monitoring ring is the
    /// selected outer-ring source. This keeps the low-power contract: battery /
    /// AirPods users never start the metric sampling loop.
    private func startHardwareRingDemand() {
        let wiring = IconHardwareDemandWiring(
            demand: iconPresentation.demand,
            placement: settings.appIconPlacement,
            apply: { [weak self] demands in
                guard let self else { return }
                if let menuBar = demands.menuBar {
                    self.store.hardwareMetrics.begin(.menuBarArc, metrics: menuBar)
                } else {
                    self.store.hardwareMetrics.end(.menuBarArc)
                }
                if let dock = demands.dock {
                    self.store.hardwareMetrics.begin(.dock, metrics: dock)
                } else {
                    self.store.hardwareMetrics.end(.dock)
                }
            }
        )
        hardwareRingDemandWiring = wiring
        wiring.start(
            demands: iconPresentation.$demand.eraseToAnyPublisher(),
            placements: settings.$appIconPlacement.eraseToAnyPublisher()
        )
    }

    /// Applies the temperature-monitoring switch to the shared sampler. Keeping
    /// it here covers the background and menu-bar demands even while the panel is
    /// closed; the panel view model only mirrors the setting for rendering.
    private func startHardwareSamplingSettings() {
        applyHardwareSamplingSettings(
            temperatureEnabled: settings.hardwareTemperatureMonitoringEnabled,
            cpuRingCenterContent: settings.cpuRingCenterContent)
        // Published emits in willSet, so the sink must use the delivered values;
        // reading the stored properties here would apply the previous toggle
        // (off-to-on would leave sampling disabled).
        Publishers.CombineLatest(
            settings.$hardwareTemperatureMonitoringEnabled,
            settings.$cpuRingCenterContent
        )
        .removeDuplicates { lhs, rhs in
            lhs.0 == rhs.0 && lhs.1 == rhs.1
        }
        .sink { [weak self] enabled, content in
            self?.applyHardwareSamplingSettings(
                temperatureEnabled: enabled,
                cpuRingCenterContent: content)
        }
        .store(in: &hardwareSamplingSettingsCancellables)
    }

    private func applyHardwareSamplingSettings(
        temperatureEnabled: Bool,
        cpuRingCenterContent: HardwareRingCenterContent
    ) {
        store.hardwareMetrics.temperatureMonitoringEnabled = temperatureEnabled
        store.hardwareMetrics.wantsRingCPUFrequency =
            !temperatureEnabled || cpuRingCenterContent == .frequency
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
        ApplicationEnergyIconCache.shared.reset()
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

}
