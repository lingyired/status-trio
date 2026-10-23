import Foundation

enum BluetoothLEReadDemand {
    static func permittedIDs(
        visibleIDs: Set<UUID>,
        initialCandidateIDs: Set<UUID>,
        allowsInitialReads: Bool,
        hiddenIDs: Set<UUID>
    ) -> Set<UUID> {
        let initialIDs = allowsInitialReads ? initialCandidateIDs : []
        return visibleIDs.union(initialIDs).subtracting(hiddenIDs)
    }
}

enum BluetoothLEInitialReadPolicy {
    static let retryCooldown: TimeInterval = 60

    static func permittedCandidateIDs(
        enabled: Bool,
        batteryLevelsEnabled: Bool,
        hasActiveDiscoverySurface: Bool,
        showsDeviceList: Bool,
        candidateIDs: Set<UUID>,
        hiddenIDs: Set<UUID>
    ) -> Set<UUID> {
        guard enabled, batteryLevelsEnabled, hasActiveDiscoverySurface, showsDeviceList else { return [] }
        return candidateIDs.subtracting(hiddenIDs)
    }

    static func freshVerifiedIDs(_ selections: [NearbyBLEDeviceSelection], now: Date) -> Set<UUID> {
        Set(selections.compactMap { selection in
            guard let level = selection.batteryLevel,
                  (0...100).contains(level),
                  let updatedAt = selection.batteryLastUpdated else { return nil }
            let age = now.timeIntervalSince(updatedAt)
            return (0...BluetoothLEBatteryScanPolicy.resultLifetime).contains(age) ? selection.id : nil
        })
    }

    static func attemptSuppressionExpiry(
        attemptedAt: Date,
        succeeded: Bool,
        verifiedAt: Date?
    ) -> Date {
        if succeeded, let verifiedAt {
            return verifiedAt.addingTimeInterval(BluetoothLEBatteryScanPolicy.resultLifetime)
        }
        return attemptedAt.addingTimeInterval(retryCooldown)
    }

    static func shouldSuppressInitialRead(until deadline: Date, now: Date) -> Bool {
        deadline > now
    }
}

/// A read token becomes stale whenever its UUID is removed from the allowlist.
/// Re-adding the UUID does not revive a pending read from the previous grant.
struct NearbyBLEReadAuthorization {
    private(set) var allowedIDs: Set<UUID> = []
    private var tokens: [UUID: DeviceOperationToken] = [:]

    var grantCount: Int { tokens.count }

    var currentTokens: [UUID: DeviceOperationToken] { tokens }

    mutating func update(_ ids: Set<UUID>) -> Set<UUID> {
        let removedIDs = allowedIDs.subtracting(ids)
        for id in removedIDs {
            tokens.removeValue(forKey: id)
        }
        for id in ids where tokens[id] == nil {
            tokens[id] = DeviceOperationToken()
        }
        allowedIDs = ids
        return removedIDs
    }

    func token(for id: UUID) -> DeviceOperationToken? {
        tokens[id]
    }

    func accepts(_ id: UUID, token: DeviceOperationToken) -> Bool {
        allowedIDs.contains(id) && tokens[id] == token
    }

    func permits(_ id: UUID, token: DeviceOperationToken?) -> Bool {
        guard let token else { return false }
        return accepts(id, token: token)
    }
}

extension NearbyBLEReadAuthorization {
    /// Moves current grants into a new authorization set while preserving their
    /// identity. This is used only when the same physical read demand changes
    /// source; removing an ID still retires its token.
    mutating func migrate(
        to ids: Set<UUID>,
        preserving preserved: [UUID: DeviceOperationToken]
    ) -> Set<UUID> {
        let removedIDs = allowedIDs.subtracting(ids)
        for id in removedIDs {
            tokens.removeValue(forKey: id)
        }
        for id in ids where tokens[id] == nil {
            tokens[id] = preserved[id] ?? DeviceOperationToken()
        }
        allowedIDs = ids
        return removedIDs
    }
}
