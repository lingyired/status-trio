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
    private var airPodsDemandWiring: IconAirPodsDemandWiring?
    private var hardwareSamplingSettingsCancellables = Set<AnyCancellable>()
    private var menuBarInstancesRuntime: MenuBarInstancesRuntime?
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
        startAirPodsDemand()
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
        let menuBarRuntime = MenuBarInstancesRuntime(
            store: store,
            settings: settings,
            statusBarController: statusBarController,
            localization: localization,
            openSettings: { [weak self] in
                self?.settingsWindowController.show(section: .menuBarInstances)
            }
        )
        menuBarRuntime.start()
        menuBarInstancesRuntime = menuBarRuntime
        telemetryReporter.start()
    }

    func stop() {
        menuBarInstancesRuntime?.stop()
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
        airPodsDemandWiring?.stop()
        airPodsDemandWiring = nil
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

    /// Keeps the AirPods battery ring fed while it is the outer-ring source.
    /// The claim is driven by the live icon configuration, and every battery
    /// update triggers a repaint so the menu bar and Dock show the new level.
    private func startAirPodsDemand() {
        let wiring = IconAirPodsDemandWiring(
            settings: settings,
            bluetooth: store.bluetoothDevices,
            onBluetoothDemandChange: { [weak self] active in
                self?.store.setIconBluetoothDemand(active)
            },
            onRefresh: { [weak self] in
                self?.iconPresentation.refresh()
            }
        )
        airPodsDemandWiring = wiring
        wiring.start()
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

    static func makeStore(
        batteryMonitor: any BatteryMonitoring,
        wifiMonitor: any WiFiMonitoring,
        connectionMonitor: (any NetworkConnectionMonitoring)? = nil,
        vpnMonitor: (any VPNMonitoring)? = nil,
        volumeMonitor: any VolumeMonitoring,
        brightnessMonitor: any BrightnessMonitoring = BrightnessMonitor(defaultExternalBackend: .automatic),
        inputMonitor: (any AudioInputMonitoring)? = nil,
        refreshInterval: Duration = .seconds(15)
    ) -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: batteryMonitor,
            wifiMonitor: wifiMonitor,
            connectionMonitor: connectionMonitor,
            vpnMonitor: vpnMonitor,
            volumeMonitor: volumeMonitor,
            brightnessMonitor: brightnessMonitor,
            inputMonitor: inputMonitor,
            refreshInterval: refreshInterval,
            bluetoothDevices: BluetoothDeviceController(
                // The accessory power sources are the second battery source, read
                // only for a level the paired-device report cannot supply and for
                // the charging state the summary rows draw. IOKit is the cheap
                // path; `pmset` stays as the fallback when the private symbol or
                // its coverage is not there. Accessory notifications are what
                // make a refresh happen between the safety-net polls.
                accessoryBatteryReader: SystemAccessoryBatteryWorker(),
                connectionEvents: IOBluetoothConnectionEventMonitor(),
                accessoryBatteryEvents: AccessoryPowerNotifyEventMonitor(),
                // Constructing the adapter is inert; its CBCentralManager is
                // created only when the user has enabled Nearby results and the
                // authorized Bluetooth popover is visible.
                nearbyBatteryScanner: CoreBluetoothLEBatteryScanner()
            )
        )
    }

    static func live(
        backgroundUITesting: BackgroundUITestingConfiguration = .disabled
    ) -> AppEnvironment {
        let settings = SettingsStore(
            backgroundUITestingForcesHardwareMonitor:
                backgroundUITesting.isEnabled && backgroundUITesting.opensHardwareDetailRaw != nil
        )
        // A measurement launch can force the synthetic charging input so the
        // animation can be compared on and off on a machine that is not charging.
        if ChargingEffectTestMode.shouldForceChargingInput() {
            settings.setChargingEffectTestInputEnabled(true)
        }
        // Apply a per-worktree development test profile after settings migration
        // and before controllers/monitoring start, so a dev build boots already in
        // the state the task needs. Release/App Store builds never load one.
        if DevelopmentProfileLoader.isDevelopmentBuild() {
            let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            let profileService = SettingsServiceFactory.make(for: settings, appVersion: appVersion)
            let run = DevelopmentProfileBootstrap.runAtLaunch(service: profileService)
            NSLog("StatusTrio development profile: %@", run.log.joined(separator: " | "))
        }
        let store = makeStore(
            batteryMonitor: BatteryMonitor(),
            wifiMonitor: WiFiMonitor(),
            connectionMonitor: NetworkConnectionMonitor(),
            vpnMonitor: VPNMonitor(),
            volumeMonitor: VolumeMonitor(outputController: CoreAudioOutputController()),
            inputMonitor: AudioInputMonitor(hardware: CoreAudioInputHardware()),
            // #255 production propagation only uses the per-power-source
            // values. The store starts on a battery-present, unplugged
            // placeholder snapshot, so seed the initial wait with the battery
            // cadence; StatusBarController's subscription corrects it as soon
            // as the first real power snapshot arrives.
            refreshInterval: settings.refreshInterval(forPluggedIn: false)
        )
        let localization = Localization()
        let inputSourceController = InputSourceController()
        let appearance = StatusIconAppearance(settings: settings)
        // Dev-only no-battery preview (#309): feed the shared icon view model a
        // battery-absent snapshot so the real menu-bar and Dock icons draw the
        // battery-less look too. The real store snapshot and battery automation
        // stay untouched; turning the toggle off restores the live battery.
        let noBatteryPreview = settings.isNoBatterySimulationActive
        let isDevelopmentBuild = settings.isDevelopmentBuild
        let hardwareRingTracker = HardwareRingStatusTracker()
        let localIconPluginRuntime = LocalIconPluginRuntime(
            directories: { [weak settings] in
                settings?.resolvedLocalIconPluginDirectories() ?? []
            }
        )
        let iconPresentation = IconPresentationViewModel(
            snapshot: noBatteryPreview
                ? store.snapshot.replacingBattery(
                    .absent(lowPowerMode: store.snapshot.battery.isLowPowerMode))
                : store.snapshot,
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
            snapshots: store.$snapshot
                .combineLatest(settings.$simulatesNoBattery)
                .map { snapshot, simulatesNoBattery in
                    isDevelopmentBuild && simulatesNoBattery
                        ? snapshot.replacingBattery(
                            .absent(lowPowerMode: snapshot.battery.isLowPowerMode))
                        : snapshot
                }
                .eraseToAnyPublisher(),
            preferences: settings.iconPresentationPublisher,
            inputSources: inputSourceController.$state
                .combineLatest(settings.$inputSourceMarkerStyle)
                .map { state, markerStyle in state.iconDescriptor(markerStyle: markerStyle) }
                .removeDuplicates()
                .eraseToAnyPublisher(),
            systemPowers: store.powerSampling.$systemPower
                .removeDuplicates()
                .eraseToAnyPublisher(),
            highPowerModes: store.highPowerMode.$isHighPowerMode
                .removeDuplicates()
                .eraseToAnyPublisher(),
            hardwareMetrics: store.hardwareMetrics.observable.snapshotPublisher,
            resolveInputs: { [store, settings, hardwareRingTracker] snapshot in
                var inputs = IconPresentationResourceResolver.inputs(
                    snapshot: snapshot,
                    runtimeOptions: settings.iconRuntimePresentationOptions
                )
                inputs.sources = IconPresentationResourceResolver.sourceSnapshot(
                    snapshot: snapshot,
                    bluetoothDevices: store.bluetoothDevices.devices,
                    batteryLevels: store.bluetoothDevices.batteryLevels,
                    batteryLevelsUpdatedAt: store.bluetoothDevices.batteryLevelsUpdatedAt,
                    selectedAirPodsAddress: settings.airPodsIconDeviceAddress,
                    selectedConnectedDeviceAddress: settings.bluetoothNetworkIconDeviceAddress,
                    holdsAirPodsBattery: settings.outerRingContent == .airPodsBattery
                )
                let hardwareSnapshot = store.hardwareMetrics.observable.snapshot
                inputs.sources.hardwareMetrics = hardwareSnapshot
                inputs.sources.hardwareMetricColors = settings.hardwareMonitorMetricColors
                inputs.sources.hardwareSpeedCapsMbps = [
                    .downloadSpeed: settings.hardwareDownloadCapMbps,
                    .uploadSpeed: settings.hardwareUploadCapMbps
                ]
                inputs.sources.hardwareRingLevels = hardwareRingTracker.levels(
                    snapshot: hardwareSnapshot,
                    configuration: settings.hardwareRingConfiguration,
                    now: .now
                )
                return inputs
            },
            mapScene: { inputs, _, iconConfiguration, slotBindings in
                let resolution = IconCompositionResolver.resolve(
                    inputs: IconResolutionInputs(system: inputs, sources: inputs.sources),
                    configuration: iconConfiguration,
                    bindings: slotBindings,
                    registry: localIconPluginRuntime.registry
                )
                return IconSceneMapping(scene: resolution.scene, demand: resolution.demand)
            }
        )
        let chargingEffectClock = ChargingEffectClock()
        let chargingEffectMotionMonitor = ChargingEffectMotionMonitor()
        let chargeToFullNow = ChargeToFullNowController(
            backend: PowerUIChargeController(),
            sessionStore: UserDefaultsChargeToFullNowSessionStore(
                defaults: .standard
            ),
            restoreLimit: {
                Int(settings.chargeToFullRestoreLimit.rounded())
            }
        )
        let dockChargingAnimationPresenter: any DockChargingAnimationPresenting =
            DockChargingAnimationRendererMode.usesApplicationIconFrames()
                ? DockApplicationIconChargingPresenter()
                : DockChargingAnimationPresenter()
        let dockVisibilityMonitor = DockVisibilityMonitor()
        let activationPolicy = AppActivationPolicy()
        let onboardingWindowController = OnboardingWindowController(
            settings: settings,
            localization: localization,
            activationPolicy: activationPolicy,
            backgroundUITesting: backgroundUITesting
        )
        var settingsWindowController: SettingsWindowController?
        let controller = StatusBarController(
            store: store,
            settings: settings,
            iconPresentation: iconPresentation,
            localization: localization,
            isVisible: settings.appIconPlacement.showsMenuBarIcon,
            openSettings: { settingsWindowController?.show() },
            openAppBatterySettings: {
                settingsWindowController?.show(section: .battery)
            },
            quitAction: { NSApplication.shared.terminate(nil) },
            chargingEffectClock: chargingEffectClock,
            backgroundUITesting: backgroundUITesting,
            inputSourceController: inputSourceController,
            chargeToFullNow: chargeToFullNow
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
            chargeToFullNow: chargeToFullNow,
            backgroundUITesting: backgroundUITesting
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
                isDebugBuild: Self.isDebugBuild
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
            backgroundUITesting: backgroundUITesting,
            localIconPluginRuntime: localIconPluginRuntime
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
