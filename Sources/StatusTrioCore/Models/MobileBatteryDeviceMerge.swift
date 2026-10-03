import Foundation
import CryptoKit

/// Combines macOS's paired-device report with the two read-only mobile battery
/// sources. Names only bridge sources when a single compatible candidate exists
/// on each side; ambiguous names stay as separate rows.
enum MobileBatteryDeviceMerge {
    struct Result: Equatable {
        let devices: [BluetoothDevice]
        let batteryLevels: [String: BluetoothBatteryLevel]
        let remainingNearby: [NearbyBluetoothBatteryDevice]
        /// Rows identified by a mobile read even when an existing paired
        /// battery value remains authoritative and mobile metadata is hidden.
        let mobileDeviceIDs: Set<String>
        let mobileMetadataByDeviceID: [String: MobileBatterySnapshot]
    }

    static func merged(
        devices: [BluetoothDevice],
        batteryLevels: [String: BluetoothBatteryLevel],
        nearbyDevices: [NearbyBluetoothBatteryDevice],
        mobileSnapshots: [MobileBatterySnapshot],
        fallbackWatchName: String
    ) -> Result {
        var mergedDevices = devices
        var mergedLevels = batteryLevels
        var remainingNearby: [NearbyBluetoothBatteryDevice] = []
        var metadata: [String: MobileBatterySnapshot] = [:]
        var mobileDeviceIDs = Set<String>()
        var consumedNearby = Set<UUID>()
        let snapshots = deduplicated(mobileSnapshots)

        // Reserve every exact identity match before considering any names. A
        // different snapshot with a matching name must never take a row that a
        // stable identity identifies later in the same merge.
        let identityMatches = Dictionary(uniqueKeysWithValues: snapshots.compactMap { snapshot -> (String, Int)? in
            let matches = devices.indices.filter { devices[$0].id == snapshot.identity }
            guard matches.count == 1, let index = matches.first else { return nil }
            return (snapshot.identity, index)
        })
        var reservedPairedIndices = Set(identityMatches.values)
        var consumedMobileIdentities = Set<String>()

        for snapshot in snapshots {
            guard let index = identityMatches[snapshot.identity],
                  let mobileKind = BluetoothMobileDeviceModel.kind(forModel: snapshot.model) else { continue }
            let device = mergedDevices[index]
            if device.kind == .unknown {
                mergedDevices[index] = device.replacingKind(with: mobileKind)
            }
            mobileDeviceIDs.insert(device.id)
            if addMobileLevel(snapshot, to: device.id, levels: &mergedLevels) {
                metadata[device.id] = snapshot
            }
            consumedMobileIdentities.insert(snapshot.identity)
        }

        for snapshot in snapshots {
            guard !consumedMobileIdentities.contains(snapshot.identity) else { continue }
            guard let mobileKind = BluetoothMobileDeviceModel.kind(forModel: snapshot.model) else { continue }
            let stableID = externalDeviceID(for: snapshot.identity)

            let normalizedName = normalized(snapshot.name)
            let sameFamilySnapshots = snapshots.filter {
                BluetoothMobileDeviceModel.kind(forModel: $0.model) == mobileKind
                    && normalized($0.name) == normalizedName
                    && !normalizedName.isEmpty
            }
            let pairedCandidates = devices.indices.filter {
                normalized(devices[$0].name) == normalizedName
                    && isCompatible(devices[$0].kind, with: mobileKind)
                    && !reservedPairedIndices.contains($0)
                    && !normalizedName.isEmpty
            }
            let nearbyCandidates = nearbyDevices.filter {
                !consumedNearby.contains($0.id)
                    && normalized($0.name) == normalizedName
                    && BluetoothMobileDeviceModel.kind(forModel: $0.model) == mobileKind
                    && !normalizedName.isEmpty
            }

            if sameFamilySnapshots.count == 1,
               pairedCandidates.count + nearbyCandidates.count == 1 {
                if let index = pairedCandidates.first {
                    let device = mergedDevices[index]
                    if device.kind == .unknown {
                        mergedDevices[index] = device.replacingKind(with: mobileKind)
                    }
                    mobileDeviceIDs.insert(device.id)
                    if addMobileLevel(snapshot, to: device.id, levels: &mergedLevels) {
                        metadata[device.id] = snapshot
                    }
                    reservedPairedIndices.insert(index)
                } else if let nearby = nearbyCandidates.first {
                    consumedNearby.insert(nearby.id)
                    let device = nearbyDeviceRow(nearby, kind: mobileKind)
                    mergedDevices.append(device)
                    mobileDeviceIDs.insert(device.id)
                    // A trusted phone read carries the fresher, authoritative
                    // value, so it wins when the BLE scan saw the same device.
                    if addMobileLevel(snapshot, to: device.id, levels: &mergedLevels) {
                        metadata[device.id] = snapshot
                    }
                }
                continue
            }

            let observedName = snapshot.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = observedName.isEmpty
                ? (mobileKind == .mobile(.watch) ? fallbackWatchName : fallbackPhoneName)
                : observedName
            let device = BluetoothDevice(
                id: stableID,
                name: name,
                kind: mobileKind,
                isConnected: false,
                isReadOverTheAir: true
            )
            mergedDevices.append(device)
            mobileDeviceIDs.insert(device.id)
            if addMobileLevel(snapshot, to: device.id, levels: &mergedLevels) {
                metadata[device.id] = snapshot
            }
        }

        for nearby in nearbyDevices where !consumedNearby.contains(nearby.id) {
            guard let kind = BluetoothMobileDeviceModel.kind(forModel: nearby.model),
                  !normalized(nearby.name).isEmpty else {
                remainingNearby.append(nearby)
                continue
            }

            let name = normalized(nearby.name)
            let pairedCandidates = devices.indices.filter {
                normalized(devices[$0].name) == name
                    && isNearbyCompatible(devices[$0].kind, with: kind)
            }
            let matchingSnapshots = snapshots.filter {
                BluetoothMobileDeviceModel.kind(forModel: $0.model) == kind
                    && normalized($0.name) == name
            }
            let matchingNearby = nearbyDevices.filter {
                BluetoothMobileDeviceModel.kind(forModel: $0.model) == kind
                    && normalized($0.name) == name
            }

            guard pairedCandidates.count == 1,
                  matchingSnapshots.isEmpty,
                  matchingNearby.count == 1,
                  let index = pairedCandidates.first else {
                remainingNearby.append(nearby)
                continue
            }

            let device = mergedDevices[index]
            if device.kind == .unknown {
                mergedDevices[index] = device.identifiedByModel(kind)
            }
            addNearbyLevel(nearby, to: device.id, levels: &mergedLevels)
        }

        return Result(
            devices: mergedDevices,
            batteryLevels: mergedLevels,
            remainingNearby: remainingNearby,
            mobileDeviceIDs: mobileDeviceIDs,
            mobileMetadataByDeviceID: metadata
        )
    }

    /// The namespace is visibly prefixed and the identity is hashed to fixed
    /// hex. The global Bluetooth key normalizer keeps the hex namespace and
    /// digest, avoiding collisions between provider IDs that filter to the same
    /// text without embedding a reversible device identifier in the row ID.
    static func externalDeviceID(for identity: String) -> String {
        let digest = SHA256.hash(data: Data(identity.utf8))
        let hexDigest = digest.map { String(format: "%02X", $0) }.joined()
        return "mobile-\(hexDigest)"
    }

    private static let fallbackPhoneName = "iPhone"

    private static func deduplicated(_ snapshots: [MobileBatterySnapshot]) -> [MobileBatterySnapshot] {
        var latestByIdentity: [String: MobileBatterySnapshot] = [:]
        for snapshot in snapshots {
            guard let existing = latestByIdentity[snapshot.identity] else {
                latestByIdentity[snapshot.identity] = snapshot
                continue
            }
            if snapshot.observedAt > existing.observedAt
                || (snapshot.observedAt == existing.observedAt && snapshot.transport == .usb && existing.transport == .network) {
                latestByIdentity[snapshot.identity] = snapshot
            }
        }
        return latestByIdentity.values.sorted { $0.identity < $1.identity }
    }

    private static func isCompatible(_ kind: BluetoothDeviceKind, with mobileKind: BluetoothDeviceKind) -> Bool {
        kind == mobileKind
    }

    /// A BLE Device Information read itself supplies the missing family, so it
    /// may refine a uniquely named unclassified paired row as the existing BLE
    /// path did. A phone snapshot alone does not prove an unknown row's family.
    private static func isNearbyCompatible(_ kind: BluetoothDeviceKind, with mobileKind: BluetoothDeviceKind) -> Bool {
        kind == mobileKind || kind == .unknown
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func addMobileLevel(
        _ snapshot: MobileBatterySnapshot,
        to deviceID: String,
        levels: inout [String: BluetoothBatteryLevel]
    ) -> Bool {
        let key = BluetoothBatteryReader.normalizedAddress(deviceID)
        guard !key.isEmpty, levels[key] == nil else { return false }
        levels[key] = BluetoothBatteryLevel(
            deviceAddress: deviceID,
            main: snapshot.batteryLevel,
            left: nil,
            right: nil,
            caseLevel: nil
        )
        return true
    }

    private static func addNearbyLevel(
        _ nearby: NearbyBluetoothBatteryDevice,
        to deviceID: String,
        levels: inout [String: BluetoothBatteryLevel]
    ) {
        let key = BluetoothBatteryReader.normalizedAddress(deviceID)
        guard !key.isEmpty, levels[key] == nil else { return }
        levels[key] = BluetoothBatteryLevel(
            deviceAddress: deviceID,
            main: nearby.batteryLevel,
            left: nil,
            right: nil,
            caseLevel: nil
        )
    }

    private static func nearbyDeviceRow(
        _ nearby: NearbyBluetoothBatteryDevice,
        kind: BluetoothDeviceKind
    ) -> BluetoothDevice {
        BluetoothDevice(
            id: nearby.id.uuidString,
            name: nearby.displayName(fallback: fallbackPhoneName),
            kind: kind,
            isConnected: false,
            isReadOverTheAir: true
        )
    }
}
