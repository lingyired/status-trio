import Combine

@MainActor
final class BluetoothNearbyBatteryOptOutSynchronizer {
    private var cancellables = Set<AnyCancellable>()

    func start(settings: SettingsStore, actions: StatusPanelActions) {
        guard cancellables.isEmpty else { return }
        Publishers.CombineLatest(
            settings.$showsBluetoothBatteryLevels,
            settings.$showsNearbyBluetoothBatteryDevices
        )
        .map { $0 && $1 }
        .removeDuplicates()
        .sink { isEnabled in
            guard !isEnabled else { return }
            actions.updateBluetoothNearbyBatteryClaim(enabled: false)
        }
        .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
    }
}
