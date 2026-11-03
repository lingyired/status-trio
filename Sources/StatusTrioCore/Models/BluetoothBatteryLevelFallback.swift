/// Whether a device's level has to come from the accessory power sources, and
/// how the two sources are combined when it does.
///
/// The paired-device report is the primary source: it carries the device list
/// and the per-channel levels the list is rendered from. The accessory power
/// sources are the same underlying data seen through the power manager, and they
/// are consulted only for the devices the report carries no level for. A device
/// macOS can already read is therefore never described by the other source, so
/// the app can gain a level and can never change or lose one.
///
/// An accessory reading names the accessory it describes by its
/// `Accessory Identifier`, not by the Bluetooth address: the power manager's
/// identifier is its own UUID, so it cannot be compared to a device directly.
/// The identifier is still the only safe way to tell two sets of one model
/// apart, so a reading is used only when its identifier resolves to *one* device
/// in the paired list and no other identifier names that device. Disconnected
/// paired devices take part in that resolution — a retained reading may belong to
/// one of them — but only a connected device is ever given a level. When the
/// resolution is ambiguous the fallback is dropped for the whole read: a missing
/// level is acceptable, and a level borrowed from the wrong device is not.
enum BluetoothBatteryLevelFallback {
    /// Whether the accessory sources are worth reading at all.
    ///
    /// Only a connected device counts. A disconnected one has no live session to
    /// read a level from — neither source reports one — so counting it here would
    /// make the answer "yes" on every single refresh, and cost a `/usr/bin/pmset`
    /// process each time. The filter lives here rather than at the call site so a
    /// caller cannot pass the whole list and get that for free.
    ///
    /// A report that could not be read is the other case this covers: with no
    /// levels to compare against, the only way to show anything is to ask the
    /// second source.
    static func isNeeded(
        levels: [String: BluetoothBatteryLevel]?,
        devices: [BluetoothDevice]
    ) -> Bool {
        let connected = devices.filter(\.isConnected)
        guard !connected.isEmpty else { return false }
        guard let levels else { return true }
        return connected.contains {
            levels[BluetoothBatteryReader.normalizedAddress($0.id)] == nil
        }
    }

    /// The primary levels, with a level added for every connected device they
    /// carry none for. Entries the report already has are copied through
    /// untouched, so this can only ever add.
    ///
    /// A disconnected device is never given a level here: it has no live session,
    /// so an accessory source that still names it is stale, not a reading.
    static func merged(
        levels: [String: BluetoothBatteryLevel],
        accessories: [BluetoothAccessoryBatteryLevel],
        devices: [BluetoothDevice]
    ) -> [String: BluetoothBatteryLevel] {
        var merged = levels
        guard let attributed = attributedReadings(accessories: accessories, devices: devices) else {
            return merged
        }
        for device in devices where device.isConnected {
            let address = BluetoothBatteryReader.normalizedAddress(device.id)
            guard !address.isEmpty, merged[address] == nil else { continue }
            guard let readings = attributed[address] else { continue }
            guard let level = channelLevel(for: device, readings: readings) else { continue }
            merged[address] = level
        }
        return merged
    }

    /// One device's level, built from the accessory identifier that names it.
    ///
    /// The reading has to survive both halves of the identifier check: exactly
    /// one identifier may name this device, and that identifier may name no other
    /// device in the paired list. A reading that fails either half would either be
    /// guessed onto this device or borrowed from a same-model neighbour, so it is
    /// discarded instead.
    static func level(
        for device: BluetoothDevice,
        accessories: [BluetoothAccessoryBatteryLevel],
        devices: [BluetoothDevice]
    ) -> BluetoothBatteryLevel? {
        guard device.isConnected else { return nil }
        let address = BluetoothBatteryReader.normalizedAddress(device.id)
        guard !address.isEmpty else { return nil }
        guard let attributed = attributedReadings(accessories: accessories, devices: devices),
              let readings = attributed[address] else { return nil }
        return channelLevel(for: device, readings: readings)
    }

    /// The readings each device owns, keyed by normalized address.
    ///
    /// A reading without an `Accessory Identifier` cannot be attributed at all
    /// and is ignored. Readings that share an identifier are one accessory and
    /// are resolved together: the identifier must name exactly one device in the
    /// paired list (by vendor/product pair or name), and no second identifier may
    /// name the same device. Disconnected devices are included in that resolution
    /// so a reading the power manager still holds for a device that left cannot
    /// be handed to its same-model neighbour; the callers still only publish
    /// levels for connected devices. When more than one identifier is present and any of them
    /// cannot be resolved that way, the whole result is `nil` — the caller then
    /// adds nothing. A single unresolvable source is only ever a reading that
    /// matches no device, which adds nothing anyway.
    private static func attributedReadings(
        accessories: [BluetoothAccessoryBatteryLevel],
        devices: [BluetoothDevice]
    ) -> [String: [BluetoothAccessoryBatteryLevel]]? {
        let groups = identifierGroups(accessories)
        guard !groups.isEmpty else { return [:] }

        // Disconnected paired devices still participate in ambiguity checks:
        // a retained pmset reading may belong to one of them.
        var attributed: [String: [BluetoothAccessoryBatteryLevel]] = [:]
        var isAmbiguous = false

        for readings in groups {
            let namingDevices = devices.filter { device in
                readings.contains { identityMatches($0, device) }
            }
            guard namingDevices.count == 1, let device = namingDevices.first else {
                isAmbiguous = true
                continue
            }
            let address = BluetoothBatteryReader.normalizedAddress(device.id)
            guard !address.isEmpty, attributed[address] == nil else {
                // Two identifiers naming one device are as ambiguous as one
                // identifier naming two: neither tells us whose reading this is.
                isAmbiguous = true
                continue
            }
            attributed[address] = readings
        }

        return isAmbiguous && groups.count > 1 ? nil : attributed
    }

    /// The readings grouped by the accessory each one names. Readings with no
    /// identifier are dropped rather than collected under a shared empty key,
    /// which would join distinct accessories into one group.
    private static func identifierGroups(
        _ accessories: [BluetoothAccessoryBatteryLevel]
    ) -> [[BluetoothAccessoryBatteryLevel]] {
        var order: [String] = []
        var groups: [String: [BluetoothAccessoryBatteryLevel]] = [:]
        for accessory in accessories {
            guard let identifier = accessory.identifier?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !identifier.isEmpty else { continue }
            let key = identifier.lowercased()
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(accessory)
        }
        return order.compactMap { groups[$0] }
    }

    /// One accessory's readings turned into one device's channels.
    ///
    /// Each reading lands in the channel its part names, and a reading with no
    /// part — or with a part the app does not know — lands in the device-wide
    /// level. A part is never allowed to write the device-wide level, which is
    /// what stops one bud's charge from being reported as the whole device's.
    /// The first reading for a channel wins, so a second source for the same
    /// channel cannot overwrite the first with a staler number.
    private static func channelLevel(
        for device: BluetoothDevice,
        readings: [BluetoothAccessoryBatteryLevel]
    ) -> BluetoothBatteryLevel? {
        var main: Int?
        var left: Int?
        var right: Int?
        var caseLevel: Int?
        for accessory in readings {
            switch accessory.part {
            case .none: main = main ?? accessory.percentage
            case .left: left = left ?? accessory.percentage
            case .right: right = right ?? accessory.percentage
            case .caseLevel: caseLevel = caseLevel ?? accessory.percentage
            }
        }
        guard main != nil || left != nil || right != nil || caseLevel != nil else { return nil }
        return BluetoothBatteryLevel(
            deviceAddress: device.id,
            main: main,
            left: left,
            right: right,
            caseLevel: caseLevel
        )
    }

    /// Whether an accessory reading describes a device that is currently
    /// connected.
    ///
    /// Connectivity is part of the answer: a disconnected device has no live
    /// session, so no source can describe it, and a stale reading must not be
    /// attributed to a device that already left. The check lives here as well as
    /// in the callers so a new caller cannot borrow a reading for a device whose
    /// session is gone.
    static func matches(_ accessory: BluetoothAccessoryBatteryLevel, _ device: BluetoothDevice) -> Bool {
        device.isConnected && identityMatches(accessory, device)
    }

    /// Whether an accessory reading names this device's model or name, ignoring
    /// connectivity.
    ///
    /// The vendor and product ID pair is the identity: it survives a rename and
    /// names one model. When both sides carry the pair, they decide on their own —
    /// a name is not consulted, because a rename would otherwise re-join a
    /// reading to whichever device now happens to share its wording. A name is
    /// what is left when either side has no pair, and that comparison is exact
    /// once whitespace and case are ignored: a substring match would join an
    /// accessory to any device whose name happens to contain it.
    ///
    /// This deliberately ignores connectivity: working out which device an
    /// accessory identifier belongs to has to consider the devices that left too,
    /// because a reading the power manager still holds may belong to one of them.
    /// Only the final output is restricted to connected devices.
    private static func identityMatches(
        _ accessory: BluetoothAccessoryBatteryLevel,
        _ device: BluetoothDevice
    ) -> Bool {
        if let vendor = device.vendorID,
           let product = device.productID,
           let accessoryVendor = accessory.vendorID,
           let accessoryProduct = accessory.productID {
            return accessoryVendor == vendor && accessoryProduct == product
        }
        let name = device.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return false }
        return accessory.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name
    }
}
