import Foundation

enum IconPreviewDataLiveStatus {
    static func airPodsBattery(from sources: IconSourceSnapshot) -> AirPodsBatteryIconSnapshot? {
        guard case .available? = sources.availability[RingSource.airPodsBattery.rawValue] else { return nil }
        return sources.airPodsBattery
    }

    static func bluetoothDeviceName(
        selectedAddress: String?,
        devices: [BluetoothDevice],
        bluetoothAvailability: BluetoothAvailability,
        audioOutputAvailability: IconSourceAvailability?,
        currentOutput: AudioOutputDevice?
    ) -> String? {
        guard bluetoothAvailability == .available else { return nil }

        if let selectedAddress {
            let selectedAddress = BluetoothBatteryReader.normalizedAddress(selectedAddress)
            guard !selectedAddress.isEmpty else { return nil }
            return devices.first(where: {
                BluetoothBatteryReader.normalizedAddress($0.id) == selectedAddress
                    && $0.isConnected
                    && !$0.isUnpairedGhost
                    && !$0.isReadOverTheAir
            })?.name
        }

        guard case .available? = audioOutputAvailability,
              let currentOutput,
              currentOutput.isBluetoothAudio else { return nil }
        return currentOutput.name
    }
}
