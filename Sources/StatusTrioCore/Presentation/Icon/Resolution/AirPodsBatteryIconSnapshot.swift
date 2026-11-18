import Foundation

/// The accessory battery payload selected for the icon. Its address is kept
/// only in memory and is never included in a resolution trace or localization.
struct AirPodsBatteryIconSnapshot: Equatable, Sendable {
    /// Two paired-device safety-net poll intervals; older reports are treated
    /// as stale instead of displaying a frozen accessory level indefinitely.
    static let freshnessInterval: TimeInterval = 60
    let deviceAddress: String
    let model: AirPodsModel
    let main: Int?
    let left: Int?
    let right: Int?
    let caseLevel: Int?
    let observedAt: Date

    enum Selection: Equatable, Sendable {
        case selected(AirPodsBatteryIconSnapshot)
        case needsSelection
        case unavailable(IconSourceUnavailableReason)
    }

    static func hasConnectedSelection(devices: [BluetoothDevice], selectedAddress: String?) -> Bool {
        let candidates = devices.filter { $0.isConnected && $0.airPodsModel != nil }
        guard !candidates.isEmpty else { return false }
        guard let selectedKey = normalizedAddress(selectedAddress) else { return candidates.count == 1 }
        return candidates.contains { normalizedAddress($0.id) == selectedKey }
    }

    static func resolve(
        devices: [BluetoothDevice],
        levels: [String: BluetoothBatteryLevel],
        selectedAddress: String?,
        observedAt: Date
    ) -> Self? {
        guard case let .selected(snapshot) = selection(
            devices: devices,
            levels: levels,
            selectedAddress: selectedAddress,
            observedAt: observedAt
        ) else { return nil }
        return snapshot
    }

    static func selection(
        devices: [BluetoothDevice],
        levels: [String: BluetoothBatteryLevel],
        selectedAddress: String?,
        observedAt: Date = .now
    ) -> Selection {
        let candidates = devices.filter { $0.isConnected && $0.airPodsModel != nil }
        guard !candidates.isEmpty else { return .unavailable(.disconnected) }

        let selectedKey = normalizedAddress(selectedAddress)
        let device: BluetoothDevice?
        if let selectedKey {
            device = candidates.first { normalizedAddress($0.id) == selectedKey }
            guard device != nil else { return .unavailable(.disconnected) }
        } else if candidates.count == 1 {
            device = candidates[0]
        } else {
            return .needsSelection
        }

        guard let device,
              let address = normalizedAddress(device.id),
              let level = levels[address],
              let model = device.airPodsModel else {
            return .unavailable(.temporarilyStale)
        }
        return .selected(Self(
            deviceAddress: address,
            model: model,
            main: level.main,
            left: level.left,
            right: level.right,
            caseLevel: level.caseLevel,
            observedAt: observedAt
        ))
    }

    private static func normalizedAddress(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = BluetoothBatteryReader.normalizedAddress(value)
        return normalized.isEmpty ? nil : normalized
    }
}
