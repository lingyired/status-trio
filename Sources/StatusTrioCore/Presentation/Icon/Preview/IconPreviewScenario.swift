import Foundation

/// Deterministic, value-only status samples for the icon designer preview.
/// These scenarios never retain or mutate monitoring controllers.
enum IconPreviewScenario: String, CaseIterable, Hashable, Sendable {
    case live
    case networkHealthy
    case networkNoInternet
    case wifiOffEthernetConnected
    case batteryCharging
    case batteryCriticallyLow
    case volumeMuted
    case airPodsConnected
    case airPodsDisconnected

    func makeInputs(basedOn liveInputs: IconResolutionInputs, now: Date = .now) -> IconResolutionInputs {
        guard self != .live else { return liveInputs }

        let current = liveInputs.system.snapshot
        let battery: BatteryStatus
        let wifi: WiFiStatus
        let connection: NetworkConnection
        let volume: VolumeStatus

        switch self {
        case .live:
            return liveInputs
        case .networkHealthy:
            battery = current.battery
            wifi = WiFiStatus(state: .connected, rssi: -48, nameAccess: .notDetermined)
            connection = .wifi
            volume = current.volume
        case .networkNoInternet:
            battery = current.battery
            wifi = WiFiStatus(state: .noInternet, rssi: -48, nameAccess: .notDetermined)
            connection = .wifi
            volume = current.volume
        case .wifiOffEthernetConnected:
            battery = current.battery
            wifi = WiFiStatus(state: .off, rssi: nil)
            connection = .ethernet
            volume = current.volume
        case .batteryCharging:
            battery = BatteryStatus(rawPercentage: 72, isPresent: true, isCharging: true,
                                    isLowPowerMode: false, isConnectedToPower: true)
            wifi = current.wifi
            connection = current.connection
            volume = current.volume
        case .batteryCriticallyLow:
            battery = BatteryStatus(rawPercentage: 8, isPresent: true, isCharging: false,
                                    isLowPowerMode: false, isConnectedToPower: false)
            wifi = current.wifi
            connection = current.connection
            volume = current.volume
        case .volumeMuted:
            battery = current.battery
            wifi = current.wifi
            connection = current.connection
            volume = VolumeStatus(
                scalar: 0,
                isMuted: true,
                deviceName: current.volume.deviceName,
                currentDevice: current.volume.currentDevice,
                outputDevices: current.volume.outputDevices,
                canSetVolume: current.volume.canSetVolume,
                canMute: current.volume.canMute
            )
        case .airPodsConnected, .airPodsDisconnected:
            battery = current.battery
            wifi = current.wifi
            connection = current.connection
            volume = current.volume
        }

        let snapshot = StatusSnapshot(battery: battery, wifi: wifi, connection: connection, volume: volume)
        var availability = liveInputs.sources.availability
        availability[RingSource.systemBattery.rawValue] = snapshot.battery.isPresent
            ? .available
            : .unavailable(.disconnected)
        availability[CenterSource.systemBatteryPercentage.rawValue] = snapshot.battery.isPresent
            ? .available
            : .unavailable(.disconnected)
        availability[CenterSource.network.rawValue] = networkAvailability(for: snapshot)
        availability[CenterSource.bluetoothAudioOutput.rawValue] = snapshot.volume.currentDevice?.isBluetoothAudio == true
            ? .available
            : .unavailable(.disconnected)
        availability[FooterSource.systemVolume.rawValue] = snapshot.volume.scalar != nil
            ? .available
            : .unavailable(.unknown)

        var airPodsBattery = liveInputs.sources.airPodsBattery
        switch self {
        case .airPodsConnected:
            airPodsBattery = AirPodsBatteryIconSnapshot(
                deviceAddress: "PREVIEW-AIRPODS",
                model: .airPodsPro,
                main: nil,
                left: 73,
                right: 68,
                caseLevel: 81,
                observedAt: now
            )
            availability[RingSource.airPodsBattery.rawValue] = .available
        case .airPodsDisconnected:
            airPodsBattery = nil
            availability[RingSource.airPodsBattery.rawValue] = .unavailable(.disconnected)
        case .live, .networkHealthy, .networkNoInternet, .wifiOffEthernetConnected,
             .batteryCharging, .batteryCriticallyLow, .volumeMuted:
            break
        }

        return IconResolutionInputs(
            system: IconPresentationInputs(snapshot: snapshot, audioIcon: liveInputs.system.audioIcon),
            sources: IconSourceSnapshot(
                availability: availability,
                airPodsBattery: airPodsBattery,
                connectedBluetoothDeviceSymbol: liveInputs.sources.connectedBluetoothDeviceSymbol
            )
        )
    }

    private func networkAvailability(for snapshot: StatusSnapshot) -> IconSourceAvailability {
        if snapshot.connection == .ethernet { return .available }
        switch snapshot.wifi.state {
        case .connected, .noInternet, .hotspot, .temporary, .shared:
            return .available
        case .notAssociated, .off:
            return .unavailable(.disconnected)
        case .unavailable:
            return .unavailable(.unknown)
        }
    }
}
