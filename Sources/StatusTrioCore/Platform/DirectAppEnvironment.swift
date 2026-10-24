import AppKit
import Foundation

@MainActor
extension AppEnvironment {
    static func live() -> AppEnvironment {
        let settings = DirectPlatformFactory.settings()
        // A measurement launch can force the synthetic charging input so the
        // animation can be compared on and off on a machine that is not charging.
        if ChargingEffectTestMode.shouldForceChargingInput() {
            settings.setChargingEffectTestInputEnabled(true)
        }
        let store = makeStore(
            batteryMonitor: BatteryMonitor(),
            wifiMonitor: WiFiMonitor(statusReader: DirectPlatformFactory.wifiStatusReader()),
            connectionMonitor: NetworkConnectionMonitor(),
            vpnMonitor: VPNMonitor(),
            volumeMonitor: VolumeMonitor(
                outputController: CoreAudioOutputController()
            ),
            inputMonitor: AudioInputMonitor(
                hardware: CoreAudioInputHardware()
            ),
            refreshInterval: settings.refreshInterval
        )
        let privilegedHelper = DirectPlatformFactory.privilegedHelper()
        return makeLive(
            settings: settings,
            store: store,
            makeUpdater: { activationPolicy in
                DirectPlatformFactory.makeUpdater(
                    activationPolicy: activationPolicy
                )
            },
            privilegedHelper: privilegedHelper,
            platformCapabilities: PlatformCapabilities.direct
        )
    }

    /// Direct factories retain every production source. Store composition uses
    /// its own factory and never falls through to these concrete implementations.
    static func makeStore(
        batteryMonitor: any BatteryMonitoring,
        wifiMonitor: any WiFiMonitoring,
        connectionMonitor: (any NetworkConnectionMonitoring)? = nil,
        vpnMonitor: (any VPNMonitoring)? = nil,
        volumeMonitor: any VolumeMonitoring,
        inputMonitor: (any AudioInputMonitoring)? = nil,
        refreshInterval: Duration = .seconds(15),
        batteryDetails: BatteryDetailsController? = nil,
        wifiNetworks: WiFiNetworkController? = nil,
        bluetoothDevices: BluetoothDeviceController? = nil,
        bluetoothPower: BluetoothRadioPowerController? = nil,
        mobileBattery: MobileBatteryController? = nil,
        appleDeviceDiscovery: AppleDeviceDiscoveryController? = nil,
        bluetoothListeningModes: BluetoothListeningModeController? = nil,
        lowPowerMode: LowPowerModeController? = nil
    ) -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: batteryMonitor,
            wifiMonitor: wifiMonitor,
            connectionMonitor: connectionMonitor,
            vpnMonitor: vpnMonitor,
            volumeMonitor: volumeMonitor,
            inputMonitor: inputMonitor,
            refreshInterval: refreshInterval,
            batteryDetails: batteryDetails ?? DirectPlatformFactory.batteryDetailsController(),
            wifiNetworks: wifiNetworks ?? DirectPlatformFactory.wifiNetworkController(),
            bluetoothDevices: bluetoothDevices ?? DirectPlatformFactory.bluetoothDeviceController(),
            bluetoothPower: bluetoothPower ?? DirectPlatformFactory.bluetoothRadioPowerController(),
            mobileBattery: mobileBattery ?? DirectPlatformFactory.mobileBatteryController(),
            appleDeviceDiscovery: appleDeviceDiscovery
                ?? DirectPlatformFactory.appleDeviceDiscoveryController(),
            bluetoothListeningModes: bluetoothListeningModes ?? DirectPlatformFactory.listeningModeController(),
            lowPowerMode: lowPowerMode ?? DirectPlatformFactory.lowPowerModeController()
        )
    }
}

@MainActor
enum DirectPlatformFactory {
    static func settings() -> SettingsStore {
        SettingsStore(chargeLimitProvider: SystemChargeLimitReader())
    }

    static func chargeLimitProvider() -> any SystemChargeLimitProviding {
        SystemChargeLimitReader()
    }

    static func wifiStatusReader() -> CoreWLANStatusReader {
        CoreWLANStatusReader(
            sharingDetector: SystemInternetSharingDetector()
        )
    }

    static func wifiKnownNetworkProvider() -> any WiFiKnownNetworkProviding {
        NetworksetupWiFiKnownNetworkProvider()
    }

    static func bluetoothPairedDeviceReader() -> any BluetoothPairedDeviceReading {
        SystemProfilerBluetoothPairedDeviceWorker()
    }

    static func bluetoothBatteryReader() -> any BluetoothBatteryReading {
        SystemProfilerBluetoothBatteryWorker()
    }

    static func accessoryBatteryReader() -> any BluetoothAccessoryBatteryReading {
        PmsetAccessoryBatteryWorker()
    }

    static func systemPowerReader() -> any SystemPowerReading {
        SystemPowerReader()
    }

    static func mobileBatteryReader() -> any MobileBatteryReading {
        MobileBatteryHelperReader()
    }

    static func appleDeviceDiscoveryController() -> AppleDeviceDiscoveryController {
        AppleDeviceDiscoveryController(reader: mobileBatteryReader())
    }

    static func bluetoothRadioBackend() -> any BluetoothRadioPowerBacking {
        IOBluetoothRadioPowerBackend()
    }

    static func listeningModeBackend() -> any BluetoothListeningModePropertyReading {
        CoreAudioBluetoothListeningModeBackend()
    }

    static func listeningModeEndpointProvider() -> any CoreAudioBluetoothEndpointProviding {
        CoreAudioBluetoothListeningModeEndpointProvider()
    }

    static func listeningModeListenerBackend() -> any BluetoothListeningModePropertyListening {
        CoreAudioBluetoothListeningModeListenerBackend()
    }

    static func lowPowerModeClient() -> any LowPowerModeClienting {
        XPCPrivilegedHelperClient()
    }

    static func batteryDetailsController() -> BatteryDetailsController {
        BatteryDetailsController(systemPowerReader: systemPowerReader())
    }

    static func wifiNetworkController() -> WiFiNetworkController {
        WiFiNetworkController(
            scanWorker: CoreWLANNetworkWorker(
                knownNetworkProvider: wifiKnownNetworkProvider()
            )
        )
    }

    static func bluetoothDeviceController() -> BluetoothDeviceController {
        BluetoothDeviceController(
            worker: bluetoothPairedDeviceReader(),
            batteryReader: bluetoothBatteryReader(),
            accessoryBatteryReader: accessoryBatteryReader(),
            connectionEvents: IOBluetoothConnectionEventMonitor(),
            accessoryBatteryEvents: AccessoryPowerNotifyEventMonitor(),
            nearbyBatteryScanner: CoreBluetoothLEBatteryScanner()
        )
    }

    static func bluetoothRadioPowerController() -> BluetoothRadioPowerController {
        BluetoothRadioPowerController(backend: bluetoothRadioBackend())
    }

    static func mobileBatteryController() -> MobileBatteryController {
        MobileBatteryController(reader: mobileBatteryReader())
    }

    static func listeningModeController() -> BluetoothListeningModeController {
        BluetoothListeningModeController(
            hal: BluetoothListeningModeHAL(
                backend: listeningModeBackend()
            ),
            endpointProvider: listeningModeEndpointProvider(),
            listenerBackend: listeningModeListenerBackend()
        )
    }

    static func lowPowerModeController() -> LowPowerModeController {
        LowPowerModeController(client: lowPowerModeClient())
    }

    static func makeUpdater(activationPolicy: AppActivationPolicy) -> UpdateStateFacade {
        UpdaterManager.shared.configure(activationPolicy: activationPolicy)
        return UpdateStateFacade(service: UpdaterManager.shared)
    }

    static func privilegedHelper() -> PrivilegedHelperFacade {
        PrivilegedHelperFacade(service: PrivilegedHelperManager.shared)
    }
}
