import Combine
import Foundation
import SwiftUI

@MainActor
final class IconDesignerEditorModel: ObservableObject {
    @Published private(set) var canUndo = false
    @Published private(set) var hasExternalChangeNotice = false

    private let store: SettingsStore
    private var history = IconDesignerEditHistory()
    private var isPerformingTransaction = false
    private var activeCoalescingKey: String?
    private var lastCoalescingKey: String?
    private var cancellable: AnyCancellable?

    init(store: SettingsStore) {
        self.store = store
        // Phase-1 bridge: iconConfigurationPublisher is derived from the whole
        // settings surface, so it already covers every relevant change.
        let relevantChanges = store.iconConfigurationPublisher
            .map { _ in () }
            .eraseToAnyPublisher()
        cancellable = relevantChanges.dropFirst().sink { [weak self] _ in
            guard let self, !self.isPerformingTransaction else { return }
            let hadHistory = self.history.count > 0
            self.history.invalidateForExternalChange()
            self.canUndo = false
            self.hasExternalChangeNotice = hadHistory
            self.lastCoalescingKey = nil
        }
    }

    func beginCoalescingGroup(_ key: String) {
        activeCoalescingKey = key
    }

    func endCoalescingGroup(_ key: String) {
        guard activeCoalescingKey == key else { return }
        activeCoalescingKey = nil
        lastCoalescingKey = nil
    }

    func perform(coalescingKey: String? = nil, _ mutation: () -> Void) {
        let group = coalescingKey ?? activeCoalescingKey
        let before = snapshot
        isPerformingTransaction = true
        mutation()
        isPerformingTransaction = false
        let after = snapshot
        if let group, group == lastCoalescingKey, history.coalesceLast(after: after) {
            // One explicit control gesture updates the same undo entry.
        } else {
            history.record(before: before, after: after)
            lastCoalescingKey = group
        }
        canUndo = history.count > 0
        hasExternalChangeNotice = false
    }

    func updateIconConfiguration(
        coalescingKey: String? = nil,
        _ edit: (inout IconConfigurationV1) -> Void
    ) {
        perform(coalescingKey: coalescingKey) {
            store.updateIconConfiguration(edit)
        }
    }

    func undo() {
        let current = snapshot
        guard let restored = history.undo(current: current) else {
            canUndo = false
            hasExternalChangeNotice = true
            return
        }
        isPerformingTransaction = true
        store.updateIconConfiguration { $0 = restored.configuration }
        store.airPodsIconDeviceAddress = restored.airPodsAddress
        store.connectedBluetoothIconDeviceAddress = restored.connectedBluetoothAddress
        store.bluetoothNetworkIconDeviceAddress = restored.bluetoothNetworkAddress
        store.refreshesAirPodsBatteryForIcon = restored.refreshesAirPodsBatteryForIcon
        store.bluetoothAudioIconChoice = restored.bluetoothAudioIconChoice
        isPerformingTransaction = false
        lastCoalescingKey = nil
        activeCoalescingKey = nil
        canUndo = history.count > 0
    }

    func reset(_ slot: IconSlot) {
        perform {
            store.updateIconConfiguration { $0 = IconDesignerDefaults.resetting(slot, in: $0) }
            switch slot {
            case .outerRing:
                store.airPodsIconDeviceAddress = nil
                store.refreshesAirPodsBatteryForIcon = false
            case .center:
                store.connectedBluetoothIconDeviceAddress = nil
                store.bluetoothNetworkIconDeviceAddress = nil
                store.bluetoothAudioIconChoice = .automatic
            case .footer:
                break
            }
        }
    }

    func resetAll() {
        perform {
            store.resetIconConfiguration(to: IconDesignerDefaults.configuration())
            store.airPodsIconDeviceAddress = nil
            store.connectedBluetoothIconDeviceAddress = nil
            store.bluetoothNetworkIconDeviceAddress = nil
            store.refreshesAirPodsBatteryForIcon = false
            store.bluetoothAudioIconChoice = .automatic
        }
    }

    var historyCountForTesting: Int { history.count }

    func dismissExternalChangeNotice() {
        hasExternalChangeNotice = false
    }

    private var snapshot: IconDesignerEditSnapshot {
        IconDesignerEditSnapshot(
            configuration: store.iconConfiguration,
            airPodsAddress: store.airPodsIconDeviceAddress,
            connectedBluetoothAddress: store.connectedBluetoothIconDeviceAddress,
            bluetoothNetworkAddress: store.bluetoothNetworkIconDeviceAddress,
            refreshesAirPodsBatteryForIcon: store.refreshesAirPodsBatteryForIcon,
            bluetoothAudioIconChoice: store.bluetoothAudioIconChoice
        )
    }
}
