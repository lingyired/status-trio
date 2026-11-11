import Foundation

/// The list the status panel renders, derived once per body evaluation so the
/// view never re-derives the order or the limit itself.
struct BluetoothDeviceListModel: Equatable {
    let orderedDevices: [BluetoothDevice]
    let visibleDevices: [BluetoothDevice]
    let canToggleExpansion: Bool

    static func make(
        devices: [BluetoothDevice],
        nearbyRows: [NearbyBLEPanelRow] = [],
        appleRows: [AppleDevicePanelRow] = [],
        batteryLevels: [String: BluetoothBatteryLevel] = [:],
        order: [String],
        limit: Int,
        isExpanded: Bool,
        options: BluetoothDeviceListOptions
    ) -> BluetoothDeviceListModel {
        let shadowRows = nearbyRows.map(\.device) + appleRows.compactMap { row in
            if case .ble = row.id { row.device } else { nil }
        }
        let systemRows = BluetoothDeviceListPresentation.panelSystemRows(
            from: devices,
            selectedNearbyBLERows: shadowRows,
            showsNearbyBatteryLevels: !shadowRows.isEmpty,
            listOptions: options
        )
        let rawDevices = BluetoothDeviceListPresentation.uniquelyIdentifiedDevices(
            (systemRows + nearbyRows.map(\.device) + appleRows.map(\.device)).filter { !$0.isUnpairedGhost }
        )
        let unifiedDevices = rawDevices
        let filteredDevices = BluetoothDeviceListPresentation.filteredDevices(unifiedDevices, options: options)
        let orderedDevices = BluetoothDeviceListPresentation.orderedDevices(
            filteredDevices,
            using: order,
            batteryLevels: BluetoothDeviceListPresentation.includingRowBatteryLevels(
                batteryLevels,
                nearbyRows: nearbyRows,
                appleRows: appleRows
            )
        )
        return BluetoothDeviceListModel(
            orderedDevices: orderedDevices,
            visibleDevices: BluetoothDeviceListPresentation.visibleDevices(
                from: orderedDevices,
                limit: limit,
                isExpanded: isExpanded
            ),
            canToggleExpansion: BluetoothDeviceListPresentation.canToggleExpansion(
                for: orderedDevices,
                limit: limit
            )
        )
    }
}

struct BluetoothDisplayRow: Equatable {
    let device: BluetoothDevice
    let sourceIDs: [String]
}

struct BluetoothDisplayBatteryReading: Equatable {
    let level: Int
    let observedAt: Date
    let sourceID: String
}

enum BluetoothDeviceListPresentation {
    static func expandingHiddenAliases(
        in options: BluetoothDeviceListOptions,
        among devices: [BluetoothDevice]
    ) -> BluetoothDeviceListOptions {
        let hiddenIDs = expandedAliasIDs(forHiddenIDs: options.hiddenDeviceAddresses, among: devices)
        return BluetoothDeviceListOptions(
            showsList: options.showsList,
            maxVisibleDevices: options.maxVisibleDevices,
            order: options.order,
            hidesGhostDevices: options.hidesGhostDevices,
            hiddenDeviceAddresses: Set(hiddenIDs.map { BluetoothDeviceIdentity.preferenceKey($0) }),
            revealedGhostDeviceAddresses: options.revealedGhostDeviceAddresses
        )
    }

    static func panelSystemRows(
        from devices: [BluetoothDevice],
        selectedNearbyBLERows: [BluetoothDevice],
        showsNearbyBatteryLevels: Bool,
        listOptions: BluetoothDeviceListOptions
    ) -> [BluetoothDevice] {
        let rows = systemDevicesExcludingGhosts(devices)
        guard showsNearbyBatteryLevels, listOptions.showsList, listOptions.maxVisibleDevices > 0 else { return rows }
        var selectedNames: [String: Int] = [:]
        for row in selectedNearbyBLERows where row.isReadOverTheAir && BluetoothDeviceIdentity.bleUUID(from: row.id) != nil {
            let name = normalizedMeaningfulName(row.name)
            if !name.isEmpty { selectedNames[name, default: 0] += 1 }
        }
        return rows.filter { row in
            guard row.isUnpairedGhost, !row.isConnected else { return true }
            let name = normalizedMeaningfulName(row.name)
            return name.isEmpty || selectedNames[name] != 1
        }
    }

    static func sharedDisplayRows(
        _ devices: [BluetoothDevice],
        options: BluetoothDeviceListOptions = .standard
    ) -> [BluetoothDisplayRow] {
        let names = Dictionary(grouping: devices.filter { !normalizedMeaningfulName($0.name).isEmpty }) {
            normalizedMeaningfulName($0.name)
        }
        let bleByName = Dictionary(grouping: devices.compactMap { device -> (String, BluetoothDevice)? in
            guard BluetoothDeviceIdentity.bleUUID(from: device.id) != nil,
                  isSpecificPhoneOrTablet(device.appleMobileModel ?? "") else { return nil }
            let name = normalizedMeaningfulName(device.name)
            return name.isEmpty ? nil : (name, device)
        }, by: \.0)
        let trustedByName = Dictionary(grouping: devices.compactMap { device -> (String, BluetoothDevice)? in
            guard device.isReadOverTheAir,
                  BluetoothDeviceIdentity.bleUUID(from: device.id) == nil,
                  isSpecificPhoneOrTablet(device.appleMobileModel ?? "") else { return nil }
            let name = normalizedMeaningfulName(device.name)
            return name.isEmpty ? nil : (name, device)
        }, by: \.0)
        var trustedForBLE: [String: BluetoothDevice] = [:]
        var consumedPairs = Set<String>()
        for (name, bleRows) in bleByName where names[name]?.count == 2 && bleRows.count == 1 {
            guard let trustedRows = trustedByName[name], trustedRows.count == 1,
                  let ble = bleRows.first?.1, let trusted = trustedRows.first?.1,
                  compatibleMobileModels(ble.appleMobileModel ?? "", trusted.appleMobileModel) else { continue }
            trustedForBLE[ble.id] = trusted
            consumedPairs.insert(trusted.id)
        }
        var consumed = Set<String>()
        var rows: [BluetoothDisplayRow] = []
        for device in devices where !consumed.contains(device.id) && !consumedPairs.contains(device.id) {
            if let trusted = trustedForBLE[device.id] {
                consumed.insert(device.id)
                rows.append(BluetoothDisplayRow(device: device, sourceIDs: [device.id, trusted.id]))
            } else {
                consumed.insert(device.id)
                rows.append(BluetoothDisplayRow(device: device, sourceIDs: [device.id]))
            }
        }
        return rows
    }

    static func settingsDisplayRows(
        _ devices: [BluetoothDevice],
        order: [String],
        options: BluetoothDeviceListOptions
    ) -> [BluetoothDisplayRow] {
        let rows = sharedDisplayRows(uniquelyIdentifiedDevices(devices))
        let connected = rows.filter { $0.device.isConnected }
        let disconnected = rows.filter { !$0.device.isConnected }
        return orderedDisplayRows(connected, using: order) + orderedDisplayRows(disconnected, using: order)
    }

    static func expandedAliasIDs(
        forHiddenIDs hiddenIDs: Set<String>,
        among devices: [BluetoothDevice]
    ) -> Set<String> {
        let hiddenKeys = Set(hiddenIDs.map { BluetoothDeviceIdentity.preferenceKey($0) })
        var result = hiddenIDs
        for row in sharedDisplayRows(devices) {
            let aliases = Set(row.sourceIDs)
            if aliases.contains(where: { hiddenKeys.contains(BluetoothDeviceIdentity.preferenceKey($0)) }) {
                result.formUnion(aliases)
            }
        }
        return result
    }

    static func newestValidReading(
        for row: BluetoothDisplayRow,
        nearbyReadings: [NearbyBluetoothBatteryDevice],
        nearbyRows: [NearbyBLEPanelRow],
        trustedSnapshots: [MobileBatterySnapshot],
        now: Date = Date()
    ) -> BluetoothDisplayBatteryReading? {
        let nearbyByID = Dictionary(nearbyReadings.map { ($0.id, $0) }, uniquingKeysWith: { old, new in
            new.lastUpdated >= old.lastUpdated ? new : old
        })
        var readings: [BluetoothDisplayBatteryReading] = []
        for sourceID in row.sourceIDs {
            if let uuid = BluetoothDeviceIdentity.bleUUID(from: sourceID) {
                let nearby = nearbyByID[uuid]
                if let nearby,
                   (0...100).contains(nearby.batteryLevel),
                   isFresh(nearby.lastUpdated, now: now) {
                    readings.append(BluetoothDisplayBatteryReading(
                        level: nearby.batteryLevel,
                        observedAt: nearby.lastUpdated,
                        sourceID: sourceID
                    ))
                } else if nearby == nil,
                          let nearbyRow = nearbyRows.first(where: { $0.id == uuid }),
                          let observedAt = nearbyRow.observedAt,
                          let level = nearbyRow.batteryLevel,
                          (0...100).contains(level),
                          isFresh(observedAt, now: now) {
                    readings.append(BluetoothDisplayBatteryReading(
                        level: level,
                        observedAt: observedAt,
                        sourceID: sourceID
                    ))
                }
            }
            if let snapshot = trustedSnapshots.first(where: { snapshot in
                if let parentID = snapshot.parentID { return sourceID == AppleDeviceID.trustedWatch(parentID: parentID, id: snapshot.id).rowID }
                return sourceID == AppleDeviceID.trustedDevice(snapshot.id).rowID
            }), (0...100).contains(snapshot.batteryLevel), isFresh(snapshot.observedAt, now: now) {
                readings.append(BluetoothDisplayBatteryReading(
                    level: snapshot.batteryLevel,
                    observedAt: snapshot.observedAt,
                    sourceID: sourceID
                ))
            }
        }
        return readings.max { $0.observedAt < $1.observedAt }
    }

    static func externalBatteryStatus(
        for device: BluetoothDevice,
        canonicalStatus: NearbyBLEPanelRowStatus?,
        nearbyStatus: NearbyBLEPanelRowStatus?,
        appleStatus: NearbyBLEPanelRowStatus?
    ) -> NearbyBLEPanelRowStatus? {
        if let canonicalStatus { return canonicalStatus }
        if device.isReadOverTheAir, device.id.hasPrefix("ble:") {
            switch nearbyStatus {
            case let .battery(level)?: return .battery(level)
            case .pending?: return .pending
            case .unavailable?, .notNearby?, nil: return nil
            }
        }
        return nearbyStatus ?? appleStatus
    }

    private static func isFresh(_ timestamp: Date, now: Date) -> Bool {
        (0...BluetoothLEBatteryScanPolicy.resultLifetime).contains(now.timeIntervalSince(timestamp))
    }

    private static func normalizedMeaningfulName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func isSpecificPhoneOrTablet(_ model: String) -> Bool {
        let value = model.lowercased()
        return (value.hasPrefix("iphone") || value.hasPrefix("ipad"))
            && value.contains(where: \.isNumber)
    }

    private static func compatibleMobileModels(_ lhs: String, _ rhs: String?) -> Bool {
        guard let rhs, isSpecificPhoneOrTablet(rhs) else { return false }
        return lhs.lowercased().hasPrefix("iphone") == rhs.lowercased().hasPrefix("iphone")
            && lhs.lowercased().hasPrefix("ipad") == rhs.lowercased().hasPrefix("ipad")
    }

    /// Excludes profiler-only ghosts before list ordering and manual hides.
    static func systemDevicesExcludingGhosts(_ devices: [BluetoothDevice]) -> [BluetoothDevice] {
        devices.filter { !$0.isUnpairedGhost }
    }

    /// Exact IDs may recur when a trusted paired row and a battery projection
    /// represent the same underlying device. Prefer the real system row so its
    /// connection state and actions survive. Never merge by display name.
    static func uniquelyIdentifiedDevices(_ devices: [BluetoothDevice]) -> [BluetoothDevice] {
        var result: [BluetoothDevice] = []
        var indexByID: [String: Int] = [:]
        for device in devices {
            guard let existingIndex = indexByID[device.id] else {
                indexByID[device.id] = result.count
                result.append(device)
                continue
            }
            let existing = result[existingIndex]
            if identityPriority(device) < identityPriority(existing) {
                result[existingIndex] = device
            }
        }
        return result
    }

    private static func identityPriority(_ device: BluetoothDevice) -> Int {
        if !device.isUnpairedGhost && !device.isReadOverTheAir { return 0 }
        if !device.isUnpairedGhost { return 1 }
        return 2
    }

    /// Connected devices always lead; the saved order only reorders devices
    /// **within** their own group, so a drag can never lift a disconnected
    /// device above a connected one. Devices with no saved rank keep the
    /// group's own order and land after the ranked ones.
    ///
    /// Every row in a group follows the same saved identity order, regardless
    /// of which provider supplied its metadata or battery value.
    ///
    /// Within each group a device the list can draw a battery level for leads
    /// the devices without one: the level is the row's reason to exist for the
    /// reader, so a phone with a live reading outranks a headset macOS reports
    /// no charge for. The saved order still ranks inside this battery group.
    ///
    /// Read-over-the-air rows carry their level on the row itself rather than in
    /// the system report's dictionary. Fold those levels in before ordering so a
    /// row the list draws a charge for ranks where that charge says it should.
    static func includingRowBatteryLevels(
        _ batteryLevels: [String: BluetoothBatteryLevel],
        nearbyRows: [NearbyBLEPanelRow] = [],
        appleRows: [AppleDevicePanelRow] = []
    ) -> [String: BluetoothBatteryLevel] {
        var merged = batteryLevels
        func add(deviceID: String, level: Int?) {
            guard let level, (0...100).contains(level) else { return }
            let key = BluetoothBatteryReader.normalizedAddress(deviceID)
            guard !key.isEmpty, merged[key] == nil else { return }
            merged[key] = BluetoothBatteryLevel(
                deviceAddress: deviceID, main: level, left: nil, right: nil, caseLevel: nil
            )
        }
        for row in nearbyRows where row.batteryLevelsEnabled {
            add(deviceID: row.device.id, level: row.batteryLevel)
        }
        for row in appleRows {
            add(deviceID: row.device.id, level: row.batteryLevel)
        }
        return merged
    }

    static func orderedDevices(
        _ devices: [BluetoothDevice],
        using order: [String],
        batteryLevels: [String: BluetoothBatteryLevel] = [:]
    ) -> [BluetoothDevice] {
        let groups = BluetoothDevicePresentation.grouped(devices)
        return batteryRankedList(groups.connected, using: order, batteryLevels: batteryLevels)
            + batteryRankedList(groups.disconnected, using: order, batteryLevels: batteryLevels)
    }

    private static func batteryRankedList(
        _ devices: [BluetoothDevice],
        using order: [String],
        batteryLevels: [String: BluetoothBatteryLevel]
    ) -> [BluetoothDevice] {
        let withLevels = devices.filter { hasReportedBatteryLevel($0, batteryLevels: batteryLevels) }
        let withoutLevels = devices.filter { !hasReportedBatteryLevel($0, batteryLevels: batteryLevels) }
        return ranked(withLevels, using: order) + ranked(withoutLevels, using: order)
    }

    /// Whether the row can draw any battery reading at all: a device with no
    /// channel the report or a fallback carries is the one that loses the
    /// battery-first ordering inside its connection group.
    private static func hasReportedBatteryLevel(
        _ device: BluetoothDevice,
        batteryLevels: [String: BluetoothBatteryLevel]
    ) -> Bool {
        guard let level = batteryLevels[BluetoothBatteryReader.normalizedAddress(device.id)] else { return false }
        return level.main != nil || level.left != nil || level.right != nil || level.caseLevel != nil
    }

    /// The same two rules `orderedDevices` applies, in the same order: within
    /// the group the rows the list can draw a level for lead the rows it cannot,
    /// and the saved order ranks inside each half. A saved position must not
    /// lift a battery-less row over a row with a reading — otherwise the model's
    /// order and this final pass disagree, and this one wins.
    static func orderedDisplayRows(
        _ rows: [BluetoothDisplayRow],
        using order: [String],
        batteryLevels: [String: BluetoothBatteryLevel] = [:]
    ) -> [BluetoothDisplayRow] {
        let withLevels = rows.filter { hasReportedBatteryLevel($0, batteryLevels: batteryLevels) }
        let withoutLevels = rows.filter { !hasReportedBatteryLevel($0, batteryLevels: batteryLevels) }
        return rankedDisplayRows(withLevels, using: order) + rankedDisplayRows(withoutLevels, using: order)
    }

    private static func rankedDisplayRows(
        _ rows: [BluetoothDisplayRow],
        using order: [String]
    ) -> [BluetoothDisplayRow] {
        guard !order.isEmpty else { return rows }
        let rankByKey = Dictionary(order.enumerated().map {
            (BluetoothDeviceIdentity.preferenceKey($0.element), $0.offset)
        }, uniquingKeysWith: { first, _ in first })
        return rows.enumerated().sorted { lhs, rhs in
            let left = lhs.element.sourceIDs.compactMap { rankByKey[BluetoothDeviceIdentity.preferenceKey($0)] }.min() ?? Int.max
            let right = rhs.element.sourceIDs.compactMap { rankByKey[BluetoothDeviceIdentity.preferenceKey($0)] }.min() ?? Int.max
            if left != right { return left < right }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func hasReportedBatteryLevel(
        _ row: BluetoothDisplayRow,
        batteryLevels: [String: BluetoothBatteryLevel]
    ) -> Bool {
        row.sourceIDs.contains { sourceID in
            guard let level = batteryLevels[BluetoothBatteryReader.normalizedAddress(sourceID)] else { return false }
            return level.main != nil || level.left != nil || level.right != nil || level.caseLevel != nil
        }
    }

    /// Drops manually hidden devices. Profiler ghosts are excluded before this
    /// stage in both Settings and the status panel.
    static func filteredDevices(
        _ devices: [BluetoothDevice],
        options: BluetoothDeviceListOptions
    ) -> [BluetoothDevice] {
        devices.filter { !$0.isUnpairedGhost && !isDeviceHidden($0, options: options) }
    }

    /// Whether the panel should paint the last successful read's rows as a
    /// placeholder while a fresh one is still in flight.
    ///
    /// The placeholder exists so reopening the panel shows last-known names
    /// instantly instead of waiting on the OS read (PR #232's height stability).
    /// It may only stand in for a read that can still land: once the read has
    /// failed, last-known rows must not keep rendering as if the radio were
    /// available — that is how a device removed in System Settings lingered
    /// (#330). Power-off, denied permission and an already-loaded read are
    /// excluded the same way.
    static func showsCachedDevices(
        availability: BluetoothAvailability,
        isRadioOff: Bool,
        showsList: Bool,
        hasLoadedDevices: Bool,
        devices: [BluetoothDevice],
        cachedDevices: [BluetoothDevice]
    ) -> Bool {
        guard !isRadioOff,
              showsList,
              !hasLoadedDevices,
              devices.isEmpty,
              !cachedDevices.isEmpty else {
            return false
        }
        switch availability {
        case .idle, .initializing, .available:
            // A read is still expected to overwrite these rows.
            return true
        case .authorizationNotDetermined, .authorizationDenied, .authorizationRestricted,
             .poweredOff, .unavailable, .failed:
            // No read will replace the placeholder, so it would be stale live data.
            return false
        }
    }

    /// Whether the panel drops `device` under the user's manual-hide setting.
    static func isDeviceHidden(
        _ device: BluetoothDevice,
        options: BluetoothDeviceListOptions
    ) -> Bool {
        if device.isUnpairedGhost { return true }
        let key = BluetoothDeviceIdentity.preferenceKey(device.id)
        if !key.isEmpty, options.hiddenDeviceAddresses.contains(key) {
            return true
        }
        return false
    }

    static func visibleDevices(
        from devices: [BluetoothDevice],
        limit: Int,
        isExpanded: Bool
    ) -> [BluetoothDevice] {
        guard !isExpanded else { return devices }
        return Array(devices.prefix(max(0, limit)))
    }

    static func canToggleExpansion(for devices: [BluetoothDevice], limit: Int) -> Bool {
        devices.count > max(0, limit)
    }

    private static func ranked(
        _ devices: [BluetoothDevice],
        using order: [String]
    ) -> [BluetoothDevice] {
        guard !order.isEmpty else { return devices }

        // Both sides are normalized: a saved entry written with separators or in
        // lowercase has to rank the device it names, or the order silently
        // applies to nothing while the list looks shuffled.
        var ranks: [String: Int] = [:]
        for (index, address) in order.enumerated() {
            let key = BluetoothDeviceIdentity.preferenceKey(address)
            guard !key.isEmpty, ranks[key] == nil else { continue }
            ranks[key] = index
        }

        return devices.enumerated()
            .sorted { lhs, rhs in
                let leftRank = ranks[BluetoothDeviceIdentity.preferenceKey(lhs.element.id)] ?? Int.max
                let rightRank = ranks[BluetoothDeviceIdentity.preferenceKey(rhs.element.id)] ?? Int.max
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

/// Whether the panel's Bluetooth section shows the list at all, and whether the
/// row's own subtitle gives way to it. Both rules live here so the view body
/// stays a straight rendering of decisions that are unit-tested.
enum BluetoothPanelListVisibility {
    static func showsList(
        availability: BluetoothAvailability,
        devices: [BluetoothDevice],
        options: BluetoothDeviceListOptions
    ) -> Bool {
        guard options.showsList, availability == .available else { return false }
        return !BluetoothDeviceListPresentation.filteredDevices(devices, options: options).isEmpty
    }

    /// The list carries the connected names, so the subtitle that would repeat
    /// them is dropped. States only the row can explain — nothing connected, no
    /// permission, powered off, read failure — keep it.
    static func hidesRowSubtitle(
        availability: BluetoothAvailability,
        devices: [BluetoothDevice],
        options: BluetoothDeviceListOptions
    ) -> Bool {
        guard showsList(availability: availability, devices: devices, options: options) else {
            return false
        }
        let visible = BluetoothDeviceListPresentation.filteredDevices(devices, options: options)
        return !BluetoothDevicePresentation.grouped(visible).connected.isEmpty
    }
}

/// Mobile helper readings are independently available while Bluetooth is off
/// or denied, but they still obey the user's device-list setting and filters.
enum BluetoothMobileBatteryPanelVisibility {
    static func shouldClaim(
        showsBatteryLevels: Bool,
        showsMobileBatteryLevels: Bool,
        options: BluetoothDeviceListOptions
    ) -> Bool {
        showsBatteryLevels && showsMobileBatteryLevels && options.showsList
    }

    static func showsList(
        availability: BluetoothAvailability,
        devices: [BluetoothDevice],
        pairedDevices: [BluetoothDevice],
        mobileDeviceIDs: Set<String>,
        showsMobileBatteryLevels: Bool,
        options: BluetoothDeviceListOptions
    ) -> Bool {
        guard options.showsList else { return false }
        if BluetoothPanelListVisibility.showsList(
            availability: availability,
            devices: pairedDevices,
            options: options
        ) {
            return true
        }
        guard showsMobileBatteryLevels else { return false }
        return BluetoothDeviceListPresentation.filteredDevices(devices, options: options)
            .contains { mobileDeviceIDs.contains($0.id) }
    }
}

enum BluetoothDeviceListHeading {
    static func title(
        hasNearbyDevices: Bool,
        hasExternalMobileDevices: Bool
    ) -> LocalizationKey? {
        guard hasNearbyDevices else { return nil }
        return hasExternalMobileDevices ? .bluetoothDevicesTitle : .bluetoothPairedDevicesTitle
    }
}

/// USB/Wi-Fi helper failures are independent of nearby BLE readings: a BLE
/// success must never hide a real helper failure, and an empty helper result
/// without failures is not itself an error.
enum MobileBatteryFailurePresentation {
    static func message(
        isEnabled: Bool,
        snapshots: [MobileBatterySnapshot],
        failures: [MobileBatteryReadFailure],
        isRefreshing: Bool
    ) -> LocalizationKey? {
        guard isEnabled, !isRefreshing, snapshots.isEmpty, !failures.isEmpty else { return nil }
        return failures.contains { $0.category == "trust-required" }
            ? .mobileBatteryTrustRequired
            : .mobileBatteryUnavailable
    }
}
