import Foundation

/// How one source's row id resolves to a canonical identity.
///
/// Only evidence that names the *same source identity* collapses rows. Nothing
/// here merges a BLE UUID with a system address or a trusted Apple ID: without a
/// verified cross-source mapping those are different devices as far as this app
/// can prove, and guessing by name, model or battery would be the exact bug this
/// resolver exists to prevent.
enum BluetoothSourceIdentity: Equatable, Sendable {
    case systemAddress(String)
    case bluetoothUUID(String)
    case trustedAppleDevice(String)

    var key: String {
        switch self {
        case let .systemAddress(address): "mac:\(address)"
        case let .bluetoothUUID(id): "ble:\(id)"
        case let .trustedAppleDevice(id): "trusted:\(id)"
        }
    }
}

struct BluetoothResolvedIdentity: Equatable, Sendable {
    let device: BluetoothDevice
    /// Every row id that resolved to this identity, representative first.
    let sourceIDs: [String]
    let identity: BluetoothSourceIdentity
}

enum BluetoothDeviceIdentityResolver {
    /// The stable source identity of one row, or `nil` when the row carries no
    /// usable identity. A row without one is left on its own rather than joined
    /// to anything.
    static func identity(of device: BluetoothDevice) -> BluetoothSourceIdentity? {
        if let uuid = BluetoothDeviceIdentity.bleUUID(from: device.id) {
            return .bluetoothUUID(uuid.uuidString.lowercased())
        }
        let normalized = BluetoothDeviceIdentity.normalizedAddress(from: device.id)
        if let normalized {
            return .systemAddress(normalized)
        }
        if device.id.hasPrefix("mobile-") || device.id.hasPrefix("trusted") {
            return .trustedAppleDevice(device.id)
        }
        return nil
    }

    /// Collapse rows that share one source identity.
    ///
    /// The representative is chosen by content, not position, so the result is
    /// independent of the order the sources arrive in: a real system row wins
    /// over a ghost, a paired row over a read-over-the-air alias, and a connected
    /// row over a disconnected one. Rows with no identity keep their own group.
    static func resolve(_ devices: [BluetoothDevice]) -> [BluetoothResolvedIdentity] {
        var order: [String] = []
        var grouped: [String: [BluetoothDevice]] = [:]
        for device in devices {
            let key = identity(of: device)?.key ?? "row:\(device.id)"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(device)
        }
        return order.compactMap { key in
            guard let members = grouped[key], let representative = members.min(by: prefer) else { return nil }
            let aliases = [representative.id]
                + members.map(\.id).filter { $0 != representative.id }.sorted()
            return BluetoothResolvedIdentity(
                device: representative,
                sourceIDs: aliases,
                identity: identity(of: representative) ?? .systemAddress(representative.id)
            )
        }
    }

    private static func prefer(_ lhs: BluetoothDevice, _ rhs: BluetoothDevice) -> Bool {
        if priority(lhs) != priority(rhs) { return priority(lhs) < priority(rhs) }
        return lhs.id < rhs.id
    }

    private static func priority(_ device: BluetoothDevice) -> Int {
        let base: Int
        if device.isUnpairedGhost { base = 2 }
        else if device.isReadOverTheAir { base = 1 }
        else { base = 0 }
        return base * 2 + (device.isConnected ? 0 : 1)
    }
}
