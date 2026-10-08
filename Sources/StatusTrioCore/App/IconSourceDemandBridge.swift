import Foundation

/// Reconciles icon composition with Bluetooth's owner-token API. It never
/// starts BLE discovery and battery reads require a separate explicit opt-in.
struct IconSourceDemandBridge {
    static let batteryLevelsToken = "icon.outerRing.airPodsBattery"
    private(set) var activationClaimed = false
    private(set) var batteryLevelsClaimed = false

    mutating func reconcile(
        configuration: IconConfigurationV1,
        userOptedInToBackgroundBattery: Bool,
        bluetoothDevices: [BluetoothDevice],
        selectedAirPodsAddress: String?,
        requestActivation: (String) -> Bool,
        releaseActivation: (String) -> Void,
        requestBatteryLevels: (String) -> Void,
        releaseBatteryLevels: (String) -> Void
    ) {
        let needsMonitor = IconSourceDemandPolicy.requiresBluetoothMonitor(in: configuration)
        if needsMonitor && !activationClaimed {
            activationClaimed = requestActivation(Self.batteryLevelsToken)
        } else if !needsMonitor && activationClaimed {
            activationClaimed = false
            releaseActivation(Self.batteryLevelsToken)
        }

        let needsBatteryLevels = IconSourceDemandPolicy.shouldReadAirPodsBattery(
            configuration: configuration,
            userOptedIn: userOptedInToBackgroundBattery,
            bluetoothDevices: bluetoothDevices,
            selectedAddress: selectedAirPodsAddress
        )
        if needsBatteryLevels && !batteryLevelsClaimed {
            batteryLevelsClaimed = true
            requestBatteryLevels(Self.batteryLevelsToken)
        } else if !needsBatteryLevels && batteryLevelsClaimed {
            batteryLevelsClaimed = false
            releaseBatteryLevels(Self.batteryLevelsToken)
        }
    }

    mutating func releaseAll(
        releaseActivation: (String) -> Void,
        releaseBatteryLevels: (String) -> Void
    ) {
        if activationClaimed { releaseActivation(Self.batteryLevelsToken) }
        if batteryLevelsClaimed { releaseBatteryLevels(Self.batteryLevelsToken) }
        activationClaimed = false
        batteryLevelsClaimed = false
    }
}

enum IconSourceDemandPolicy {
    static func requiresAirPodsBattery(in configuration: IconConfigurationV1) -> Bool {
        let ring = configuration.composition.outerRing
        return ring.primary == .airPodsBattery || ring.fallback == .airPodsBattery
    }

    static func requiresBluetoothMonitor(in configuration: IconConfigurationV1) -> Bool {
        requiresAirPodsBattery(in: configuration)
            || configuration.composition.center.primary == .connectedBluetoothDevice
            || configuration.composition.center.fallback == .connectedBluetoothDevice
    }

    static func shouldReadAirPodsBattery(
        configuration: IconConfigurationV1,
        userOptedIn: Bool,
        bluetoothDevices: [BluetoothDevice],
        selectedAddress: String?
    ) -> Bool {
        userOptedIn
            && requiresAirPodsBattery(in: configuration)
            && AirPodsBatteryIconSnapshot.hasConnectedSelection(
                devices: bluetoothDevices,
                selectedAddress: selectedAddress
            )
    }
}
