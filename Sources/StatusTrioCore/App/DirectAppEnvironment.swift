import AppKit
import Combine

@MainActor
extension AppEnvironment {
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
            volumeFeedback: VolumeFeedbackPlayer(),
            refreshInterval: refreshInterval,
            bluetoothDevices: BluetoothDeviceController(
                // The accessory power sources are the second battery source, read
                // only for the devices the paired-device report carries no level
                // for; accessory notifications are what make a level refresh
                // between the safety-net polls.
                accessoryBatteryReader: PmsetAccessoryBatteryWorker(),
                connectionEvents: IOBluetoothConnectionEventMonitor(),
                accessoryBatteryEvents: AccessoryPowerNotifyEventMonitor(),
                // Constructing the adapter is inert; its CBCentralManager is
                // created only when the user has enabled Nearby results and the
                // authorized Bluetooth popover is visible.
                nearbyBatteryScanner: CoreBluetoothLEBatteryScanner()
            ),
            lowPowerMode: LowPowerModeController(client: XPCPrivilegedHelperClient()),
            highPowerMode: HighPowerModeController(client: XPCPrivilegedHighPowerClient()),
            sleepControl: SleepControlController(client: XPCPrivilegedHighPowerClient())
        )
    }

    static func live(
        backgroundUITesting: BackgroundUITestingConfiguration = .disabled
    ) -> AppEnvironment {
        SystemChargeLimitReader.installDirectDefaults()
        SystemVolumeFeedbackPreference.installDirectDefaults()
        let settings = SettingsStore(
            backgroundUITestingForcesHardwareMonitor:
                backgroundUITesting.isEnabled && backgroundUITesting.opensHardwareDetailRaw != nil
        )
        // A measurement launch can force the synthetic charging input so the
        // animation can be compared on and off on a machine that is not charging.
        if ChargingEffectTestMode.shouldForceChargingInput() {
            settings.setChargingEffectTestInputEnabled(true)
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
                    selectedConnectedDeviceAddress: settings.bluetoothNetworkIconDeviceAddress
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
            localIconPluginRuntime: localIconPluginRuntime,
            privilegedHelper: PrivilegedHelperManager.shared
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
