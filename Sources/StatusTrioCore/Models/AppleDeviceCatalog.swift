import Foundation

struct AppleDevicePanelRow: Identifiable, Equatable, Sendable {
    let id: AppleDeviceID
    let device: BluetoothDevice
    let batteryLevel: Int?
    let status: NearbyBLEPanelRowStatus
}

enum AppleDeviceCatalog {
    struct Projection: Equatable, Sendable {
        let rows: [AppleDevicePanelRow]
        let batteryLevels: [String: BluetoothBatteryLevel]
        let mobileMetadataByDeviceID: [String: MobileBatterySnapshot]
    }

    static func readAuthorizedIDs(
        visibleIDs: Set<AppleDeviceID>,
        currentCandidates: [AppleDeviceCandidate]
    ) -> Set<AppleDeviceID> {
        let eligible = Set(currentCandidates.filter(\.isVerifiedTrustedAppleDevice).map(\.id))
        return visibleIDs.intersection(eligible)
    }

    static func candidates(
        trusted: [AppleDeviceCandidate]
    ) -> [AppleDeviceCandidate] {
        var values: [AppleDeviceID: AppleDeviceCandidate] = [:]
        for candidate in trusted where candidate.isVerifiedTrustedAppleDevice {
            if let existing = values[candidate.id] {
                let transports = ([MobileBatteryTransport.usb, .network] as [MobileBatteryTransport]).filter {
                    existing.transports.contains($0) || candidate.transports.contains($0)
                }
                values[candidate.id] = AppleDeviceCandidate(
                    id: candidate.id,
                    name: candidate.name,
                    model: candidate.model ?? existing.model,
                    transports: transports,
                    trustRequired: false,
                    evidence: candidate.evidence
                )
            } else {
                values[candidate.id] = candidate
            }
        }
        return values.values.sorted { $0.id.rowID < $1.id.rowID }
    }

    /// The identities that may take part in the current display projection.
    ///
    /// Stored metadata is a user-facing history and is never deleted here. But a
    /// history entry with no current discovery result and no fresh snapshot may
    /// not fabricate a live row: a trusted ID that is no longer discovered does
    /// not keep a device on screen forever. `lastSuccessfulIDs == nil` means no
    /// discovery cycle has completed (initial load, failure, permissions), so an
    /// empty result is not treated as proof the device is gone.
    static func currentCandidates(
        history: [AppleDeviceCandidate],
        discovered: [AppleDeviceCandidate],
        lastSuccessfulIDs: Set<AppleDeviceID>?,
        trustedSnapshots: [MobileBatterySnapshot],
        now: Date
    ) -> [AppleDeviceCandidate] {
        let verifiedHistory = history.filter(\.isVerifiedTrustedAppleDevice)
        guard let lastSuccessfulIDs else { return history }
        let freshSnapshotIDs = Set(
            MobileBatteryDeviceMerge.deduplicatedSnapshots(trustedSnapshots)
                .filter { now.timeIntervalSince($0.observedAt) < mobileSnapshotLifetime }
                .map(id(for:))
        )
        let discoveredIDs = Set(discovered.map(\.id))
        var seen = Set<AppleDeviceID>()
        var result: [AppleDeviceCandidate] = []
        for candidate in discovered + verifiedHistory {
            guard candidate.isVerifiedTrustedAppleDevice else { continue }
            guard seen.insert(candidate.id).inserted else { continue }
            if discoveredIDs.contains(candidate.id)
                || lastSuccessfulIDs.contains(candidate.id)
                || freshSnapshotIDs.contains(candidate.id) {
                result.append(candidate)
            }
        }
        // Non-trusted history is preserved verbatim for later migration or a
        // future successful cycle; it never produced a live row in the first place.
        return result + history.filter { !$0.isVerifiedTrustedAppleDevice }
    }

    /// Matches `MobileBatteryController.cacheLifetime`; the projection must not
    /// outlive the snapshot source it reads.
    static let mobileSnapshotLifetime: TimeInterval = 1_200

    static func projection(
        candidates: [AppleDeviceCandidate],
        trustedSnapshots: [MobileBatterySnapshot],
        failures: Set<AppleDeviceID> = [],
        options: BluetoothDeviceListOptions
    ) -> Projection {
        let trustedCandidates = Self.candidates(trusted: candidates)
        let snapshots = MobileBatteryDeviceMerge.deduplicatedSnapshots(trustedSnapshots)
        let snapshotsByID = Dictionary(snapshots.map { (id(for: $0), $0) }, uniquingKeysWith: { old, new in
            new.observedAt >= old.observedAt ? new : old
        })
        let failuresByID = failures
        var levels: [String: BluetoothBatteryLevel] = [:]
        var metadata: [String: MobileBatterySnapshot] = [:]
        let rows = trustedCandidates.compactMap { candidate -> AppleDevicePanelRow? in
            guard candidate.isVerifiedTrustedAppleDevice else { return nil }
            let snapshot = snapshotsByID[candidate.id]
            let name = snapshot?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (name?.isEmpty == false ? name : nil) ?? candidate.name
            let model = snapshot?.model ?? candidate.model
            let device = BluetoothDevice(
                id: candidate.id.rowID,
                name: displayName,
                kind: BluetoothMobileDeviceModel.kind(forModel: model) ?? .unknown,
                isConnected: false,
                appleMobileModel: model,
                isReadOverTheAir: true
            )
            guard !BluetoothDeviceListPresentation.isDeviceHidden(device, options: options) else { return nil }

            if let snapshot {
                levels[BluetoothBatteryReader.normalizedAddress(device.id)] = BluetoothBatteryLevel(
                    deviceAddress: device.id,
                    main: snapshot.batteryLevel,
                    left: nil,
                    right: nil,
                    caseLevel: nil
                )
                metadata[device.id] = snapshot
            }
            let status: NearbyBLEPanelRowStatus
            if let snapshot { status = .battery(snapshot.batteryLevel) }
            else { status = failuresByID.contains(candidate.id) ? .unavailable : .pending }
            return AppleDevicePanelRow(
                id: candidate.id,
                device: device,
                batteryLevel: snapshot?.batteryLevel,
                status: status
            )
        }
        let orderedRows = BluetoothDeviceListPresentation.orderedDevices(rows.map(\.device), using: options.order)
        let rowByID = Dictionary(rows.map { ($0.device.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = orderedRows.compactMap { rowByID[$0.id] }
        return Projection(rows: ordered, batteryLevels: levels, mobileMetadataByDeviceID: metadata)
    }

    static func rowIdentityMap(_ rows: [AppleDevicePanelRow]) -> [String: AppleDeviceID] {
        Dictionary(rows.map { ($0.device.id, $0.id) }, uniquingKeysWith: { first, _ in first })
    }

    private static func id(for snapshot: MobileBatterySnapshot) -> AppleDeviceID {
        if let parentID = snapshot.parentID { .trustedWatch(parentID: parentID, id: snapshot.id) }
        else { .trustedDevice(snapshot.id) }
    }
}
