import AppKit

@MainActor
final class AppEnvironment {
    let store: SystemStatusStore
    let settings: SettingsStore
    let localization: Localization
    let statusBarController: StatusBarController
    let settingsWindowController: SettingsWindowController
    let onboardingWindowController: OnboardingWindowController
    let activationPolicy: AppActivationPolicy
    let appIconController: AppIconController
    let mainMenuController: MainMenuController

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        localization: Localization,
        statusBarController: StatusBarController,
        settingsWindowController: SettingsWindowController,
        onboardingWindowController: OnboardingWindowController,
        activationPolicy: AppActivationPolicy,
        appIconController: AppIconController,
        mainMenuController: MainMenuController
    ) {
        self.store = store
        self.settings = settings
        self.localization = localization
        self.statusBarController = statusBarController
        self.settingsWindowController = settingsWindowController
        self.onboardingWindowController = onboardingWindowController
        self.activationPolicy = activationPolicy
        self.appIconController = appIconController
        self.mainMenuController = mainMenuController
    }

    func start() {
        onboardingWindowController.showIfNeeded()
        mainMenuController.start()
        appIconController.start()
        store.start()
    }

    func stop() {
        appIconController.stop()
        mainMenuController.stop()
        store.stop()
    }

    static func makeStore(
        batteryMonitor: any BatteryMonitoring,
        wifiMonitor: any WiFiMonitoring,
        connectionMonitor: (any NetworkConnectionMonitoring)? = nil,
        volumeMonitor: any VolumeMonitoring,
        refreshInterval: Duration = .seconds(5)
    ) -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: batteryMonitor,
            wifiMonitor: wifiMonitor,
            connectionMonitor: connectionMonitor,
            volumeMonitor: volumeMonitor,
            refreshInterval: refreshInterval
        )
    }

    static func live() -> AppEnvironment {
        let settings = SettingsStore()
        let store = makeStore(
            batteryMonitor: BatteryMonitor(),
            wifiMonitor: WiFiMonitor(),
            connectionMonitor: NetworkConnectionMonitor(),
            volumeMonitor: VolumeMonitor(outputController: CoreAudioOutputController()),
            refreshInterval: settings.refreshInterval
        )
        let localization = Localization()
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
            }
        )
        onboardingWindowController.openSettings = { [weak settingsWindowController] in
            settingsWindowController?.show()
        }
        let controller = StatusBarController(
            store: store,
            settings: settings,
            localization: localization,
            isVisible: settings.appIconPlacement.showsMenuBarIcon,
            openSettings: { settingsWindowController.show() },
            quitAction: { NSApplication.shared.terminate(nil) }
        )
        let appIconController = AppIconController(
            store: store,
            settings: settings,
            activationPolicy: activationPolicy,
            setMenuBarVisible: { isVisible in
                controller.setVisible(isVisible)
            },
            renderDockIcon: { status, options, connectionOptions, volumeOptions, backgroundStyle in
                DockIconRenderer.image(
                    status: status,
                    options: options,
                    connectionOptions: connectionOptions,
                    volumeOptions: volumeOptions,
                    backgroundStyle: backgroundStyle
                )
            }
        )
        let mainMenuController = MainMenuController(
            activationPolicy: activationPolicy,
            localization: localization,
            openSettings: { settingsWindowController.show() }
        )
        return AppEnvironment(
            store: store,
            settings: settings,
            localization: localization,
            statusBarController: controller,
            settingsWindowController: settingsWindowController,
            onboardingWindowController: onboardingWindowController,
            activationPolicy: activationPolicy,
            appIconController: appIconController,
            mainMenuController: mainMenuController
        )
    }
}
