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
    let iconDesignerWindowController: IconDesignerWindowController
    let onboardingWindowController: OnboardingWindowController
    let activationPolicy: AppActivationPolicy
    let appIconController: AppIconController
    let mainMenuController: MainMenuController
    let inputSourceController: InputSourceController
    let chargingEffectClock: ChargingEffectClock
    let chargingEffectMotionMonitor: ChargingEffectMotionMonitor
    let telemetryReporter: any TelemetryReporting
    let bluetoothAudioIconOverrideSynchronizer = BluetoothAudioIconOverrideSynchronizer()
    private let bluetoothNearbyBatteryOptOutSynchronizer = BluetoothNearbyBatteryOptOutSynchronizer()
    private let lowPowerModeControlSynchronizer = LowPowerModeControlSynchronizer()

    private var chargingEffectCancellables = Set<AnyCancellable>()
    private var iconSourceDemandBridge = IconSourceDemandBridge()
    private var realIconOverrideBridge: IconDesignerRealIconOverrideBridge?
    private var inputSourceLifecycleCancellables = Set<AnyCancellable>()

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        localization: Localization,
        iconPresentation: IconPresentationViewModel,
        statusBarController: StatusBarController,
        settingsWindowController: SettingsWindowController,
        iconDesignerWindowController: IconDesignerWindowController,
        onboardingWindowController: OnboardingWindowController,
        activationPolicy: AppActivationPolicy,
        appIconController: AppIconController,
        mainMenuController: MainMenuController,
        inputSourceController: InputSourceController,
        chargingEffectClock: ChargingEffectClock,
        chargingEffectMotionMonitor: ChargingEffectMotionMonitor,
        telemetryReporter: any TelemetryReporting,
        realIconOverrideBridge: IconDesignerRealIconOverrideBridge? = nil
    ) {
        self.store = store
        self.settings = settings
        self.localization = localization
        self.iconPresentation = iconPresentation
        self.statusBarController = statusBarController
        self.settingsWindowController = settingsWindowController
        self.iconDesignerWindowController = iconDesignerWindowController
        self.onboardingWindowController = onboardingWindowController
        self.activationPolicy = activationPolicy
        self.appIconController = appIconController
        self.mainMenuController = mainMenuController
        self.inputSourceController = inputSourceController
        self.chargingEffectClock = chargingEffectClock
        self.chargingEffectMotionMonitor = chargingEffectMotionMonitor
        self.telemetryReporter = telemetryReporter
        self.realIconOverrideBridge = realIconOverrideBridge
    }

    func start() {
        iconPresentation.start()
        realIconOverrideBridge?.start()
        startInputSourceMonitoringIfNeeded()
        onboardingWindowController.showIfNeeded()
        chargingEffectMotionMonitor.onChange = { [weak self] _ in
            self?.updateChargingEffectClock()
        }
        chargingEffectMotionMonitor.start()
        subscribeToChargingEffectInputs()
        mainMenuController.start()
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
        store.bindMobileBatterySettings(settings)
        store.bindLowPowerModeSettings(settings)
        store.start()
        subscribeToIconSourceDemand()
        telemetryReporter.start()
    }

    func stop() {
        realIconOverrideBridge?.stop()
        telemetryReporter.stop()
        chargingEffectClock.stop()
        chargingEffectMotionMonitor.onChange = nil
        chargingEffectMotionMonitor.stop()
        chargingEffectCancellables.removeAll()
        iconSourceDemandBridge.releaseAll(
            releaseActivation: { [bluetoothDevices = store.bluetoothDevices] token in
                bluetoothDevices.releaseActivation(token)
            },
            releaseBatteryLevels: { [bluetoothDevices = store.bluetoothDevices] token in
                bluetoothDevices.releaseBackgroundBatteryLevels(token)
            }
        )
        bluetoothAudioIconOverrideSynchronizer.stop()
        bluetoothNearbyBatteryOptOutSynchronizer.stop()
        lowPowerModeControlSynchronizer.stop()
        inputSourceLifecycleCancellables.removeAll()
        inputSourceController.stop()
        appIconController.stop()
        mainMenuController.stop()
        store.stop()
        iconPresentation.stop()
    }

    private func subscribeToIconSourceDemand() {
        Publishers.CombineLatest4(
            settings.$iconConfiguration.removeDuplicates(),
            settings.$refreshesAirPodsBatteryForIcon.removeDuplicates(),
            settings.$airPodsIconDeviceAddress.removeDuplicates(),
            settings.$connectedBluetoothIconDeviceAddress.removeDuplicates()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _, _ in
            guard let self else { return }
            // Deferred publications invalidate demand; historical tuples must
            // not replay an opt-in that was revoked before the queue drained.
            self.reconcileIconSourceDemand(
                configuration: self.settings.iconConfiguration,
                batteryOptIn: self.settings.refreshesAirPodsBatteryForIcon,
                selectedAirPodsAddress: self.settings.airPodsIconDeviceAddress
            )
            self.iconPresentation.refreshSourceState()
        }
        .store(in: &chargingEffectCancellables)

        Publishers.CombineLatest3(
            store.bluetoothDevices.$devices.removeDuplicates(),
            store.bluetoothDevices.$batteryLevels.removeDuplicates(),
            store.bluetoothDevices.$batteryLevelsUpdatedAt.removeDuplicates()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            guard let self else { return }
            self.reconcileIconSourceDemand(
                configuration: self.settings.iconConfiguration,
                batteryOptIn: self.settings.refreshesAirPodsBatteryForIcon,
                selectedAirPodsAddress: self.settings.airPodsIconDeviceAddress
            )
            self.iconPresentation.refreshSourceState()
        }
        .store(in: &chargingEffectCancellables)

        store.bluetoothDevices.$availability
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.reconcileIconSourceDemand(
                    configuration: self.settings.iconConfiguration,
                    batteryOptIn: self.settings.refreshesAirPodsBatteryForIcon,
                    selectedAirPodsAddress: self.settings.airPodsIconDeviceAddress
                )
                self.iconPresentation.refreshSourceState()
            }
            .store(in: &chargingEffectCancellables)
    }

    private func reconcileIconSourceDemand(
        configuration: IconConfigurationV1,
        batteryOptIn: Bool,
        selectedAirPodsAddress: String?
    ) {
        let bluetoothDevices = store.bluetoothDevices
        iconSourceDemandBridge.reconcile(
            configuration: configuration,
            userOptedInToBackgroundBattery: batteryOptIn,
            bluetoothDevices: bluetoothDevices.devices,
            selectedAirPodsAddress: selectedAirPodsAddress,
            requestActivation: { bluetoothDevices.requestActivation($0) },
            releaseActivation: { bluetoothDevices.releaseActivation($0) },
            requestBatteryLevels: { bluetoothDevices.requestBackgroundBatteryLevels($0) },
            releaseBatteryLevels: { bluetoothDevices.releaseBackgroundBatteryLevels($0) }
        )
    }

    /// Input-source observers exist only while a feature that draws them is
    /// on: the centre-slot source or the panel section. Both off — the shipped
    /// default — means no TIS reads and no distributed observers at all.
    private func startInputSourceMonitoringIfNeeded() {
        guard inputSourceLifecycleCancellables.isEmpty else { return }
        Publishers.CombineLatest(
            settings.$iconConfiguration
                .map { configuration in
                    let selection = configuration.composition.center
                    return selection.primary == .inputSource || selection.fallback == .inputSource
                }
                .removeDuplicates(),
            settings.$enabledPopupSections.removeDuplicates()
        )
        .sink { [weak self] centerSource, enabledSections in
            guard let self else { return }
            let isNeeded = centerSource || enabledSections.contains(.inputSource)
            if isNeeded {
                inputSourceController.start()
            } else {
                inputSourceController.stop()
            }
        }
        .store(in: &inputSourceLifecycleCancellables)
    }

    private func subscribeToChargingEffectInputs() {
        guard chargingEffectCancellables.isEmpty else { return }
        Publishers.CombineLatest4(
            store.$snapshot.map(\.battery).removeDuplicates(),
            settings.$iconConfiguration.map(\.behaviors.systemBatteryRing.showsChargingEffect).removeDuplicates(),
            store.$isDisplayAsleep.removeDuplicates(),
            settings.$testsChargingEffect.removeDuplicates()
        )
        .sink { [weak self] battery, enabled, displayAsleep, testMode in
            guard let self else { return }
            chargingEffectClock.update(
                battery: ChargingEffectTestMode.battery(battery, enabled: testMode),
                enabled: enabled,
                reduceMotion: chargingEffectMotionMonitor.shouldReduceMotion,
                displayAsleep: displayAsleep
            )
        }
        .store(in: &chargingEffectCancellables)
    }

    private func updateChargingEffectClock() {
        chargingEffectClock.update(
            battery: ChargingEffectTestMode.battery(
                store.snapshot.battery,
                enabled: settings.testsChargingEffect
            ),
            enabled: settings.showsChargingEffect,
            reduceMotion: chargingEffectMotionMonitor.shouldReduceMotion,
            displayAsleep: store.isDisplayAsleep
        )
    }

    static func makeStore(
        batteryMonitor: any BatteryMonitoring,
        wifiMonitor: any WiFiMonitoring,
        connectionMonitor: (any NetworkConnectionMonitoring)? = nil,
        vpnMonitor: (any VPNMonitoring)? = nil,
        volumeMonitor: any VolumeMonitoring,
        inputMonitor: (any AudioInputMonitoring)? = nil,
        refreshInterval: Duration = .seconds(15)
    ) -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: batteryMonitor,
            wifiMonitor: wifiMonitor,
            connectionMonitor: connectionMonitor,
            vpnMonitor: vpnMonitor,
            volumeMonitor: volumeMonitor,
            inputMonitor: inputMonitor,
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
            )
        )
    }

    static func live() -> AppEnvironment {
        let settings = SettingsStore()
        let store = makeStore(
            batteryMonitor: BatteryMonitor(),
            wifiMonitor: WiFiMonitor(),
            connectionMonitor: NetworkConnectionMonitor(),
            vpnMonitor: VPNMonitor(),
            volumeMonitor: VolumeMonitor(outputController: CoreAudioOutputController()),
            inputMonitor: AudioInputMonitor(hardware: CoreAudioInputHardware()),
            refreshInterval: settings.refreshInterval
        )
        let localization = Localization()
        let inputSourceController = InputSourceController()
        let appearance = StatusIconAppearance(settings: settings)
        let iconPresentation = IconPresentationViewModel(
            snapshot: store.snapshot,
            settings: IconPresentationSettings(
                configuration: settings.iconPresentationConfiguration,
                menuBarSize: appearance.iconSize,
                testsChargingEffect: settings.testsChargingEffect,
                designerConfiguration: settings.iconConfiguration,
                runtimeOptions: settings.iconRuntimePresentationOptions
            ),
            snapshots: store.$snapshot.eraseToAnyPublisher(),
            preferences: settings.iconPresentationPublisher,
            inputSources: inputSourceController.$state
                .map(\.selectedDescriptor)
                .removeDuplicates()
                .eraseToAnyPublisher(),
            resolveInputs: { snapshot in
                IconPresentationResourceResolver.inputs(snapshot: snapshot)
            },
            mapResolution: { inputs, configuration, sources in
                IconCompositionResolver.resolve(
                    inputs: IconResolutionInputs(system: inputs, sources: sources),
                    configuration: configuration
                )
            },
            resolveSourceSnapshot: { snapshot in
                IconPresentationResourceResolver.sourceSnapshot(
                    snapshot: snapshot,
                    bluetoothDevices: store.bluetoothDevices.devices,
                    batteryLevels: store.bluetoothDevices.batteryLevels,
                    batteryLevelsUpdatedAt: store.bluetoothDevices.batteryLevelsUpdatedAt,
                    selectedAirPodsAddress: settings.airPodsIconDeviceAddress,
                    selectedConnectedDeviceAddress: settings.connectedBluetoothIconDeviceAddress,
                    bluetoothAvailability: store.bluetoothDevices.availability
                )
            }
        )
        let chargingEffectClock = ChargingEffectClock()
        let chargingEffectMotionMonitor = ChargingEffectMotionMonitor()
        let activationPolicy = AppActivationPolicy()
        let onboardingWindowController = OnboardingWindowController(
            settings: settings,
            localization: localization,
            activationPolicy: activationPolicy
        )
        let iconDesignerPreviewSession = IconDesignerPreviewSession()
        let realIconOverrideBridge = IconDesignerRealIconOverrideBridge(
            session: iconDesignerPreviewSession,
            settings: settings,
            iconPresentation: iconPresentation
        )
        let iconDesignerWindowController = IconDesignerWindowController(
            store: settings,
            statusStore: store,
            localization: localization,
            activationPolicy: activationPolicy,
            chargingEffectClock: chargingEffectClock,
            previewSession: iconDesignerPreviewSession,
            inputSourceController: inputSourceController
        )
        let settingsWindowController = SettingsWindowController(
            store: settings,
            statusStore: store,
            localization: localization,
            activationPolicy: activationPolicy,
            showIconGuide: { [weak onboardingWindowController] in
                onboardingWindowController?.show()
            },
            openIconDesigner: { [weak iconDesignerWindowController] slot in
                iconDesignerWindowController?.show(slot: slot)
            },
            chargingEffectClock: chargingEffectClock,
            previewSession: iconDesignerPreviewSession,
            inputSourceController: inputSourceController
        )
        onboardingWindowController.openSettings = { [weak settingsWindowController] in
            settingsWindowController?.show()
        }
        let controller = StatusBarController(
            store: store,
            settings: settings,
            iconPresentation: iconPresentation,
            localization: localization,
            isVisible: settings.appIconPlacement.showsMenuBarIcon,
            openSettings: { settingsWindowController.show() },
            quitAction: { NSApplication.shared.terminate(nil) },
            chargingEffectClock: chargingEffectClock,
            inputSourceController: inputSourceController
        )
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
            openSettings: { settingsWindowController.show() }
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
            settingsWindowController: settingsWindowController,
            iconDesignerWindowController: iconDesignerWindowController,
            onboardingWindowController: onboardingWindowController,
            activationPolicy: activationPolicy,
            appIconController: appIconController,
            mainMenuController: mainMenuController,
            inputSourceController: inputSourceController,
            chargingEffectClock: chargingEffectClock,
            chargingEffectMotionMonitor: chargingEffectMotionMonitor,
            telemetryReporter: telemetryReporter,
            realIconOverrideBridge: realIconOverrideBridge
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
