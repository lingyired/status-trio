import Combine
import Foundation

enum BluetoothAudioIconOverrideUpdate: Equatable {
    case unchanged
    case clear
    case set(String)
}

@MainActor
final class BluetoothAudioIconOverrideSynchronizer {
    private var cancellables = Set<AnyCancellable>()

    func start(devices: BluetoothDeviceController, settings: SettingsStore) {
        guard cancellables.isEmpty else { return }
        Publishers.CombineLatest3(
            devices.$devices,
            devices.$availability,
            settings.$bluetoothNetworkIconDeviceAddress
        )
        .sink { [weak self, weak settings] listedDevices, availability, selectedAddress in
            guard let self, let settings else { return }
            self.synchronize(
                devices: listedDevices,
                availability: availability,
                selectedAddress: selectedAddress,
                settings: settings
            )
        }
        .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
    }

    private func synchronize(
        devices: [BluetoothDevice],
        availability: BluetoothAvailability,
        selectedAddress: String?,
        settings: SettingsStore
    ) {
        switch Self.update(
            currentSymbol: settings.bluetoothNetworkIconSymbolName,
            selectedAddress: selectedAddress,
            devices: devices,
            availability: availability
        ) {
        case .unchanged:
            break
        case .clear:
            settings.bluetoothNetworkIconSymbolName = nil
        case let .set(symbolName):
            settings.bluetoothNetworkIconSymbolName = symbolName
        }
    }

    static func update(
        currentSymbol: String?,
        selectedAddress: String?,
        devices: [BluetoothDevice],
        availability: BluetoothAvailability
    ) -> BluetoothAudioIconOverrideUpdate {
        guard let selectedAddress else {
            return currentSymbol == nil ? .unchanged : .clear
        }
        guard availability == .available else { return .unchanged }

        let normalizedSelectedAddress = BluetoothBatteryReader.normalizedAddress(selectedAddress)
        guard !normalizedSelectedAddress.isEmpty,
              let device = devices.first(where: { device in
                  !device.isUnpairedGhost
                      && BluetoothBatteryReader.normalizedAddress(device.id) == normalizedSelectedAddress
              }) else {
            return .unchanged
        }

        let symbolName = BluetoothDeviceRowIcon.symbolName(for: device)
        return currentSymbol == symbolName ? .unchanged : .set(symbolName)
    }
}
