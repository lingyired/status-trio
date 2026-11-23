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
/// one of them — but only a connected device is ever given a level. An ambiguous
/// resolution costs only the device it concerns: that device is given no level,
/// while readings that resolve uniquely keep supplying theirs. A missing level is
/// acceptable, a level borrowed from the wrong device is not, and neither one
/// device's ambiguity nor one unreadable source may hide an unrelated device's
/// level.
enum BluetoothBatteryLevelFallback {
    /// How strongly one accessory reading's identity matches a device.
    ///
    /// `nameOnly` is the weak, fallback comparison: at least one side has no
    /// complete vendor/product pair, so a normalized name is all there is.
    /// `exactVendorProduct` is a *model* identity — both sides carry the pair and
    /// the pairs agree — never a physical-device identity. `none` covers both no
    /// relationship at all and a conflict between two complete, different pairs.
    private enum IdentityEvidence: Equatable {
        case none
        case nameOnly
        case exactVendorProduct
        /// `Accessory Identifier` is a six-byte Bluetooth address equal to the
        /// device's own address. This is the only *physical-device* evidence the
        /// accessory sources can carry, so it outranks every model or name fit.
        case exactAddress
    }

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
        let attributed = attributedReadings(accessories: accessories, devices: devices)
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
        guard let readings = attributedReadings(accessories: accessories, devices: devices)[address] else {
            return nil
        }
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
    /// levels for connected devices.
    ///
    /// Ambiguity is scoped to the device it concerns. A group that does not name
    /// exactly one device adds nothing and taints nothing; a device that two
    /// identifiers both name is dropped, but every other device whose reading
    /// resolves uniquely keeps it. One unresolvable accessory therefore can no
    /// longer suppress the levels of unrelated devices.
    ///
    /// Every identifier is resolved before any ownership is decided, so the
    /// result never depends on the order the accessory sources or devices arrive
    /// in. The one relaxation is the keyboard/mouse owner rule in
    /// `resolveKeyboardMouseAccessoryOwner`: it only ever applies after the strict
    /// "exactly one device" rule has failed, and only for a connected keyboard or
    /// mouse whose complete vendor/product pair is otherwise blocked by a stale,
    /// name-only duplicate of the same device.
    private static func attributedReadings(
        accessories: [BluetoothAccessoryBatteryLevel],
        devices: [BluetoothDevice]
    ) -> [String: [BluetoothAccessoryBatteryLevel]] {
        let groups = identifierGroups(accessories)
        guard !groups.isEmpty else { return [:] }

        // First decide, for every identifier, which single device (if any) it
        // names. Nothing is written to the result yet: ownership is finalised
        // only after every group has been resolved.
        var resolutions: [(address: String, readings: [BluetoothAccessoryBatteryLevel])] = []
        for readings in groups {
            guard let device = resolveGroupOwner(readings: readings, devices: devices) else {
                continue
            }
            let address = BluetoothBatteryReader.normalizedAddress(device.id)
            guard !address.isEmpty else { continue }
            resolutions.append((address, readings))
        }

        // A device two identifiers both name owns neither reading: no identifier
        // tells us whose reading it is, so the device gets nothing. Every other
        // device whose identifier resolves uniquely keeps its own reading — one
        // device's ambiguity stays confined to that device.
        var counts: [String: Int] = [:]
        for resolution in resolutions { counts[resolution.address, default: 0] += 1 }

        var attributed: [String: [BluetoothAccessoryBatteryLevel]] = [:]
        for resolution in resolutions where counts[resolution.address] == 1 {
            attributed[resolution.address] = resolution.readings
        }
        return attributed
    }

    /// The one device an identifier's readings name, or `nil` when the group
    /// cannot be resolved safely.
    ///
    /// The strict rule comes first: the whole group must name exactly one device
    /// in the full list and every reading must agree it is that device. A group
    /// that names no device, or that names several, is resolved only by the
    /// keyboard/mouse rule; otherwise it adds nothing.
    private static func resolveGroupOwner(
        readings: [BluetoothAccessoryBatteryLevel],
        devices: [BluetoothDevice]
    ) -> BluetoothDevice? {
        // Collect every device any record could describe. Dropping a record early
        // would hide a second possible owner and make the group look unambiguous.
        let namingDevices = devices.filter { device in
            readings.contains { identityMatches($0, device) }
        }
        if namingDevices.count == 1,
           let device = namingDevices.first,
           readings.allSatisfy({ identityMatches($0, device) }) {
            return device
        }
        return resolveKeyboardMouseAccessoryOwner(readings: readings, devices: devices)
    }

    /// A complete vendor/product pair, kept together so it can be compared as a
    /// unit. A pair is only complete when both halves are present; a partial pair
    /// never forms an identity.
    private struct ModelIdentity: Equatable {
        let vendor: Int
        let product: Int

        init?(_ accessory: BluetoothAccessoryBatteryLevel) {
            guard let vendor = accessory.vendorID, let product = accessory.productID else {
                return nil
            }
            self.vendor = vendor
            self.product = product
        }

        init?(_ device: BluetoothDevice) {
            guard let vendor = device.vendorID, let product = device.productID else {
                return nil
            }
            self.vendor = vendor
            self.product = product
        }
    }

    /// The largest last-byte difference this rule treats as "the same address,
    /// give or take". It is only ever a corroborating limit: the first five bytes
    /// must already agree, and even then two addresses are never treated as one
    /// physical device — only as consistent with a stale record of the same one.
    private static let maximumTrailingAddressByteDelta = 2

    /// Resolves a group of device-level readings to a connected keyboard or mouse
    /// when the only other devices the group could describe are stale, name-only
    /// duplicates of that same device.
    ///
    /// This exists because the power manager (`pmset`) names an accessory by its
    /// own UUID and carries neither a Bluetooth address nor a real sampling time.
    /// The device list can therefore hold two rows with one name: the connected
    /// device with a complete vendor/product pair, and a disconnected historical
    /// record without one. The strict rule rejects the pair as ambiguous, which
    /// costs the connected keyboard or mouse its level even though only one of the
    /// rows could be the live device.
    ///
    /// A vendor/product pair is a *model* identity, not a physical one, so this
    /// can never prove the reading belongs to this exact unit — only that it is a
    /// safe, narrow fit. It is therefore deliberately confined to keyboards and
    /// mice, and every relaxation has a condition that keeps a real second device
    /// from being joined:
    ///
    /// - the reading must be a device-level value (never a bud or case channel);
    /// - the source must carry one complete, self-consistent vendor/product pair;
    /// - that pair must name exactly one device across the whole list, connected
    ///   or not — a same-model twin still carrying the pair blocks the rule;
    /// - the target must be connected and a keyboard or mouse;
    /// - every other device the group could describe must be disconnected, of the
    ///   same class and name, missing its own complete pair, and at an address
    ///   that differs from the target's in at most the trailing byte.
    private static func resolveKeyboardMouseAccessoryOwner(
        readings: [BluetoothAccessoryBatteryLevel],
        devices: [BluetoothDevice]
    ) -> BluetoothDevice? {
        // Only a device-wide level: a Left/Right/Case channel belongs to an earbud
        // or case, never to a keyboard or mouse.
        guard readings.allSatisfy({ $0.part == nil }) else { return nil }

        // An identifier that is a real Bluetooth address is exact physical
        // evidence. When it did not match a device's address, the group must not
        // fall back to model or name guessing — that is exactly how a same-model
        // neighbour would receive another mouse's level.
        guard readings.allSatisfy({ $0.identifier.flatMap(normalizedAddressBytes) == nil }) else {
            return nil
        }

        // The source must carry one complete and self-consistent model identity.
        // A partial pair on any record, or a group whose records disagree, is not
        // a firm enough basis to relax anything.
        guard let source = ModelIdentity(readings[0]),
              readings.allSatisfy({ ModelIdentity($0) == source }) else {
            return nil
        }

        // The complete pair must name exactly one device in the whole list. A
        // second device with the same pair — connected or not — means the pair
        // names a model, not an owner, so the strict answer stands.
        let exactMatches = devices.filter {
            $0.vendorID == source.vendor && $0.productID == source.product
        }
        guard exactMatches.count == 1, let target = exactMatches.first else { return nil }

        guard target.isConnected else { return nil }
        guard isKeyboardOrMouse(target.kind) else { return nil }

        // Any other device the group could describe must be explainable as a
        // stale, same-device record. Anything else is a real conflict.
        let competitors = devices.filter { device in
            device.id != target.id && readings.contains { identityMatches($0, device) }
        }
        for competitor in competitors {
            guard isHistoricalTwin(competitor, of: target) else { return nil }
        }
        return target
    }

    /// Whether `kind` is one of the two peripheral classes the relaxed rule is
    /// allowed to touch. This is the declared device class, never a name.
    private static func isKeyboardOrMouse(_ kind: BluetoothDeviceKind) -> Bool {
        switch kind {
        case .peripheral(.keyboard), .peripheral(.mouse):
            return true
        default:
            return false
        }
    }

    /// Whether a competing device looks like a stale duplicate of `target`: same
    /// class and name, not connected, and carrying no complete model identity of
    /// its own. Its address is a corroborating limit only — two unrelated devices
    /// are never joined by name alone.
    private static func isHistoricalTwin(
        _ candidate: BluetoothDevice,
        of target: BluetoothDevice
    ) -> Bool {
        guard !candidate.isConnected else { return false }
        guard candidate.kind == target.kind else { return false }
        guard normalizedName(candidate.name) == normalizedName(target.name) else { return false }
        // Missing its own complete pair. A complete pair that differs is a
        // different model (a conflicting identity); one that matched would have
        // pushed the exact-match count above one.
        guard candidate.vendorID == nil || candidate.productID == nil else { return false }
        return addressesLookLikeSameDevice(candidate.id, target.id)
    }

    /// Whether two Bluetooth addresses agree on their first five bytes and differ
    /// in the last by only a little. This is evidence of a stale record, never
    /// proof: it must not, and does not, merge two devices.
    private static func addressesLookLikeSameDevice(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = normalizedAddressBytes(lhs),
              let right = normalizedAddressBytes(rhs),
              left.count == 6,
              right.count == 6 else {
            return false
        }
        guard left.prefix(5) == right.prefix(5) else { return false }
        return abs(Int(left[5]) - Int(right[5])) <= maximumTrailingAddressByteDelta
    }

    /// A Bluetooth address reduced to its six bytes. Anything that is not exactly
    /// twelve hex digits after normalization is rejected outright, so a malformed
    /// address can never accidentally match another malformed one.
    private static func normalizedAddressBytes(_ address: String) -> [UInt8]? {
        guard let hex = BluetoothDeviceIdentity.normalizedAddress(from: address) else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    /// A device or accessory name reduced to the form the fallback compares:
    /// trimming surrounding whitespace and ignoring case. It is exact beyond that
    /// — no substring or fuzzy matching.
    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
        identityEvidence(accessory, device) != .none
    }

    /// The identity evidence one reading gives for a device, without the final
    /// boolean.
    ///
    /// A complete vendor/product pair on both sides decides on its own: equal is
    /// an exact model match, unequal is a conflict (`none`) even when the names
    /// agree. A name is consulted only when at least one side has no complete
    /// pair, and the comparison is exact once whitespace and case are ignored.
    /// This mirrors `identityMatches` exactly, so the stronger classification can
    /// never turn two readings that did not match into a match.
    private static func identityEvidence(
        _ accessory: BluetoothAccessoryBatteryLevel,
        _ device: BluetoothDevice
    ) -> IdentityEvidence {
        // A six-byte `Accessory Identifier` is a Bluetooth address. The user's
        // Magic Mouse proves `pmset` can report the address here rather than a
        // UUID, so an exact address is decided first and alone: when the source
        // carries a valid address, a device whose address differs cannot match by
        // model or name, and no weaker guess is ever used.
        if let identifier = accessory.identifier,
           normalizedAddressBytes(identifier) != nil {
            guard let sourceBytes = normalizedAddressBytes(identifier),
                  let deviceBytes = normalizedAddressBytes(device.id),
                  sourceBytes == deviceBytes else {
                return .none
            }
            if let vendor = device.vendorID,
               let product = device.productID,
               let accessoryVendor = accessory.vendorID,
               let accessoryProduct = accessory.productID,
               vendor != accessoryVendor || product != accessoryProduct {
                return .none
            }
            return .exactAddress
        }
        if let vendor = device.vendorID,
           let product = device.productID,
           let accessoryVendor = accessory.vendorID,
           let accessoryProduct = accessory.productID {
            return accessoryVendor == vendor && accessoryProduct == product
                ? .exactVendorProduct
                : .none
        }
        let name = normalizedName(device.name)
        guard !name.isEmpty else { return .none }
        return normalizedName(accessory.name) == name ? .nameOnly : .none
    }
}
