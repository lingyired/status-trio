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
    let chargingEffectClock: ChargingEffectClock
    let chargingEffectMotionMonitor: ChargingEffectMotionMonitor
    let telemetryReporter: any TelemetryReporting
    let bluetoothAudioIconOverrideSynchronizer = BluetoothAudioIconOverrideSynchronizer()
    private let bluetoothNearbyBatteryOptOutSynchronizer = BluetoothNearbyBatteryOptOutSynchronizer()

    private var chargingEffectCancellables = Set<AnyCancellable>()

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
        chargingEffectClock: ChargingEffectClock,
        chargingEffectMotionMonitor: ChargingEffectMotionMonitor,
        telemetryReporter: any TelemetryReporting
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
        self.chargingEffectClock = chargingEffectClock
        self.chargingEffectMotionMonitor = chargingEffectMotionMonitor
        self.telemetryReporter = telemetryReporter
    }

    func start() {
        iconPresentation.start()
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
        store.bindInputSettings(settings)
        store.bindMobileBatterySettings(settings)
        store.start()
        telemetryReporter.start()
    }

    func stop() {
        telemetryReporter.stop()
        chargingEffectClock.stop()
        chargingEffectMotionMonitor.onChange = nil
        chargingEffectMotionMonitor.stop()
        chargingEffectCancellables.removeAll()
        bluetoothAudioIconOverrideSynchronizer.stop()
        bluetoothNearbyBatteryOptOutSynchronizer.stop()
        appIconController.stop()
        mainMenuController.stop()
        store.stop()
        iconPresentation.stop()
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
        let appearance = StatusIconAppearance(settings: settings)
        let iconPresentation = IconPresentationViewModel(
            snapshot: store.snapshot,
            settings: IconPresentationSettings(
                configuration: settings.iconConfiguration.legacyPresentationConfiguration,
                menuBarSize: appearance.iconSize,
                testsChargingEffect: settings.testsChargingEffect,
                designerConfiguration: settings.iconConfiguration
            ),
            snapshots: store.$snapshot.eraseToAnyPublisher(),
            preferences: settings.iconPresentationPublisher,
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
                IconPresentationResourceResolver.sourceSnapshot(snapshot: snapshot)
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
        let settingsWindowController = SettingsWindowController(
            store: settings,
            statusStore: store,
            localization: localization,
            activationPolicy: activationPolicy,
            showIconGuide: { [weak onboardingWindowController] in
                onboardingWindowController?.show()
            },
            chargingEffectClock: chargingEffectClock
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
            chargingEffectClock: chargingEffectClock
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
            onboardingWindowController: onboardingWindowController,
            activationPolicy: activationPolicy,
            appIconController: appIconController,
            mainMenuController: mainMenuController,
            chargingEffectClock: chargingEffectClock,
            chargingEffectMotionMonitor: chargingEffectMotionMonitor,
            telemetryReporter: telemetryReporter
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
