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
        IconContentDependencyResolver.dependencies(configuration: configuration, targetIsAudio: false).requiresAirPodsBattery
    }

    static func requiresBluetoothMonitor(in configuration: IconConfigurationV1) -> Bool {
        IconContentDependencyResolver.dependencies(configuration: configuration, targetIsAudio: false).requiresBluetoothMonitor
    }

    struct HardwareRingDemands: Equatable {
        var menuBar: Set<HardwareMetricID>?
        var dock: Set<HardwareMetricID>?

        static let none = HardwareRingDemands(menuBar: nil, dock: nil)
    }

    /// Which hardware-metric demands the System Monitoring ring needs on each
    /// surface. `nil` means "release that surface's demand". Driven purely by the
    /// composition, the fallback source, and the icon placement.
    static func hardwareRingDemands(configuration: IconConfigurationV1,
                                    placement: AppIconPlacement) -> HardwareRingDemands {
        let composition = configuration.composition.outerRing
        let usesHardware = composition.primary == .hardwareMonitor || composition.fallback == .hardwareMonitor
        guard usesHardware else { return .none }
        let metricIDs = Set(configuration.behaviors.hardwareRing.referencedMetrics.map(\.metricID))
        return HardwareRingDemands(
            menuBar: placement.showsMenuBarIcon ? metricIDs : nil,
            dock: placement.showsDockIcon ? metricIDs : nil
        )
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
