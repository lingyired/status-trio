import AppKit
import Foundation

@MainActor
enum IconPresentationResourceResolver {
    static func sourceSnapshot(
        snapshot: StatusSnapshot,
        bluetoothDevices: [BluetoothDevice] = [],
        batteryLevels: [String: BluetoothBatteryLevel] = [:],
        batteryLevelsUpdatedAt: Date? = nil,
        selectedAirPodsAddress: String? = nil,
        selectedConnectedDeviceAddress: String? = nil,
        now: Date = .now
    ) -> IconSourceSnapshot {
        let networkAvailability: IconSourceAvailability
        if snapshot.connection == .ethernet {
            networkAvailability = .available
        } else {
            networkAvailability = switch snapshot.wifi.state {
            case .connected, .noInternet, .hotspot, .temporary, .shared:
                .available
            case .notAssociated, .off:
                .unavailable(.disconnected)
            case .unavailable:
                .unavailable(.unknown)
            }
        }
        let bluetoothAvailability: IconSourceAvailability =
            snapshot.volume.currentDevice?.isBluetoothAudio == true
                ? .available
                : .unavailable(.disconnected)
        let volumeAvailability: IconSourceAvailability = snapshot.volume.scalar != nil
            ? .available
            : .unavailable(.unknown)
        let batteryAvailability: IconSourceAvailability = snapshot.battery.isPresent
            ? .available
            : .unavailable(.disconnected)

        let airPodsSelection = AirPodsBatteryIconSnapshot.selection(
            devices: bluetoothDevices,
            levels: batteryLevels,
            selectedAddress: selectedAirPodsAddress,
            observedAt: batteryLevelsUpdatedAt ?? .distantPast
        )
        let airPodsBattery: AirPodsBatteryIconSnapshot?
        let airPodsAvailability: IconSourceAvailability
        switch airPodsSelection {
        case let .selected(value):
            let age = now.timeIntervalSince(value.observedAt)
            let isFresh = (0...AirPodsBatteryIconSnapshot.freshnessInterval).contains(age)
            airPodsBattery = isFresh ? value : nil
            airPodsAvailability = isFresh ? .available : .unavailable(.temporarilyStale)
        case .needsSelection:
            airPodsBattery = nil
            airPodsAvailability = .unavailable(.unknown)
        case let .unavailable(reason):
            airPodsBattery = nil
            airPodsAvailability = .unavailable(reason)
        }

        let selectedConnectedKey = selectedConnectedDeviceAddress.map { BluetoothBatteryReader.normalizedAddress($0) }
        let connectedDevice = selectedConnectedKey.flatMap { selectedKey in
            bluetoothDevices.first {
                BluetoothBatteryReader.normalizedAddress($0.id) == selectedKey && $0.isConnected
            }
        }
        let connectedDeviceSymbol = connectedDevice.map { BluetoothDeviceRowIcon.symbolName(for: $0) }
        let connectedDeviceAvailability: IconSourceAvailability = connectedDevice == nil
            ? .unavailable(selectedConnectedDeviceAddress == nil ? .unknown : .disconnected)
            : .available

        return IconSourceSnapshot(availability: [
            CenterSource.network.rawValue: networkAvailability,
            CenterSource.bluetoothAudioOutput.rawValue: bluetoothAvailability,
            CenterSource.systemBatteryPercentage.rawValue: batteryAvailability,
            CenterSource.connectedBluetoothDevice.rawValue: connectedDeviceAvailability,
            RingSource.systemBattery.rawValue: batteryAvailability,
            RingSource.airPodsBattery.rawValue: airPodsAvailability,
            FooterSource.systemVolume.rawValue: volumeAvailability
        ], airPodsBattery: airPodsBattery, connectedBluetoothDeviceSymbol: connectedDeviceSymbol)
    }

    static func inputs(
        snapshot: StatusSnapshot,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        isSymbolAvailable: (String) -> Bool = { symbol in
            NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
        }
    ) -> IconPresentationInputs {
        guard let device = snapshot.volume.currentDevice else {
            return IconPresentationInputs(snapshot: snapshot, audioIcon: nil)
        }

        let source: IconSymbolSource
        if let iconURL = device.iconURL, fileExists(iconURL) {
            source = .image(url: iconURL, fallbackSymbol: "headphones")
        } else {
            let kind = AudioOutputDeviceIcon.kind(for: device)
            let host = HostMacKind(deviceName: device.name)
            let symbol = AudioOutputDeviceIcon.symbolName(for: kind, host: host, isSymbolAvailable: isSymbolAvailable)
            source = .symbol(name: symbol, variableValue: nil, fallback: "headphones")
        }
        return IconPresentationInputs(snapshot: snapshot, audioIcon: source)
    }
}
