import AppKit
import Foundation

@MainActor
extension AppEnvironment {
    static func live() -> AppEnvironment {
        let settings = SettingsStore(
            chargeLimitProvider: UnavailableSystemChargeLimitProvider(),
            legacyInstallationMarker: { _ in false }
        )
        let store = makeStore(
            batteryMonitor: BatteryMonitor(),
            wifiMonitor: WiFiMonitor(
                statusReader: CoreWLANStatusReader(sharingDetector: nil)
            ),
            connectionMonitor: NetworkConnectionMonitor(),
            vpnMonitor: VPNMonitor(),
            volumeMonitor: VolumeMonitor(
                outputController: CoreAudioOutputController(),
                ddcCoordinatorFactory: { onUpdate, configuration in
                    StoreDDCFactory.makeCoordinator(
                        onUpdate: onUpdate,
                        configuration: configuration
                    )
                }
            ),
            inputMonitor: AudioInputMonitor(
                hardware: CoreAudioInputHardware()
            ),
            refreshInterval: settings.refreshInterval
        )
        return makeLive(
            settings: settings,
            store: store,
            makeUpdater: { _ in
                UpdateStateFacade(service: SystemManagedUpdateService())
            },
            privilegedHelper: PrivilegedHelperFacade(
                service: UnsupportedPrivilegedHelperService()
            ),
            platformCapabilities: PlatformCapabilities.appStore,
            distributionChannel: .appStore
        )
    }

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
            batteryDetails: batteryDetails ?? BatteryDetailsController(
                systemPowerReader: UnavailableSystemPowerReader()
            ),
            wifiNetworks: wifiNetworks ?? WiFiNetworkController(
                scanWorker: CoreWLANNetworkWorker(
                    knownNetworkProvider: CoreWLANKnownNetworkProvider()
                )
            ),
            bluetoothDevices: bluetoothDevices ?? storeBluetoothDeviceController(),
            bluetoothPower: bluetoothPower ?? BluetoothRadioPowerController(
                backend: UnavailableBluetoothRadioPowerBackend()
            ),
            mobileBattery: mobileBattery ?? MobileBatteryController(
                reader: UnavailableMobileBatteryReader()
            ),
            bluetoothListeningModes: bluetoothListeningModes ?? storeListeningModeController(),
            lowPowerMode: lowPowerMode ?? LowPowerModeController(
                client: UnavailableLowPowerModeClient()
            )
        )
    }

    private static func storeBluetoothDeviceController() -> BluetoothDeviceController {
        BluetoothDeviceController(
            worker: PublicBluetoothPairedDeviceReader(),
            stateMonitor: CoreBluetoothStateMonitor(),
            batteryReader: UnavailableBluetoothBatteryReader(),
            accessoryBatteryReader: PublicAccessoryBatteryReader(),
            connectionEvents: IOBluetoothConnectionEventMonitor(),
            accessoryBatteryEvents: nil,
            nearbyBatteryScanner: CoreBluetoothLEBatteryScanner()
        )
    }

    private static func storeListeningModeController() -> BluetoothListeningModeController {
        BluetoothListeningModeController(
            hal: BluetoothListeningModeHAL(
                backend: UnavailableBluetoothListeningModeBackend()
            ),
            endpointProvider: nil,
            listenerBackend: nil
        )
    }
}
