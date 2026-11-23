import Testing
@testable import StatusTrioCore

/// The accessory sources may only ever add a level. These pin the two rules that
/// make that true: when the second source is worth reading at all, and which
/// channel a reading is allowed to write.
struct BluetoothBatteryLevelFallbackTests {
    private func device(
        address: String = "AC:90:85:C2:9C:1F",
        name: String = "AirPods Pro",
        kind: BluetoothDeviceKind = .audio,
        isConnected: Bool = true,
        vendorID: Int? = nil,
        productID: Int? = nil
    ) -> BluetoothDevice {
        BluetoothDevice(
            id: address,
            name: name,
            kind: kind,
            isConnected: isConnected,
            vendorID: vendorID,
            productID: productID
        )
    }

    private func accessory(
        identifier: String? = "E0CA918B-FC5E-C942-B6C3-23F27810A34F",
        name: String = "AirPods Pro",
        vendorID: Int? = nil,
        productID: Int? = nil,
        part: BluetoothAccessoryPart? = nil,
        percentage: Int = 93
    ) -> BluetoothAccessoryBatteryLevel {
        BluetoothAccessoryBatteryLevel(
            identifier: identifier,
            name: name,
            vendorID: vendorID,
            productID: productID,
            part: part,
            percentage: percentage
        )
    }

    private func level(main: Int? = nil, left: Int? = nil) -> BluetoothBatteryLevel {
        BluetoothBatteryLevel(
            deviceAddress: "AC:90:85:C2:9C:1F",
            main: main,
            left: left,
            right: nil,
            caseLevel: nil
        )
    }

    // MARK: - When the second source is read

    /// A read that could not answer is the one case where the second source is
    /// the only way to show anything.
    @Test("A failed primary read is worth asking the second source about")
    func aFailedPrimaryReadNeedsTheSecondSource() {
        #expect(BluetoothBatteryLevelFallback.isNeeded(levels: nil, devices: [device()]))
    }

    /// The whole point of the second source: a connected device the report
    /// carries no level for.
    @Test("A connected device with no level is worth asking about")
    func aConnectedDeviceWithoutALevelNeedsTheSecondSource() {
        let devices = [device(address: "AC:90:85:C2:9C:1F"), device(address: "D3:6D:6C:40:A3:2E", name: "MX Keys")]

        #expect(BluetoothBatteryLevelFallback.isNeeded(
            levels: [BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F"): level(main: 100)],
            devices: devices
        ))
    }

    /// The common case must not cost a second subprocess.
    @Test("A report that covers every connected device needs nothing more")
    func aCompleteReportNeedsNothingMore() {
        #expect(!BluetoothBatteryLevelFallback.isNeeded(
            levels: [BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F"): level(main: 100)],
            devices: [device()]
        ))
    }

    /// The panel lists paired devices too, but only a connected one is worth a
    /// read. Counting a disconnected one would answer "yes" on every refresh, and
    /// cost a `pmset` process each time, because neither source ever reports a
    /// level for it.
    @Test("A disconnected device without a level does not trigger the read")
    func aDisconnectedDeviceDoesNotTriggerTheRead() {
        #expect(!BluetoothBatteryLevelFallback.isNeeded(
            levels: [:],
            devices: [device(isConnected: false)]
        ))
        #expect(!BluetoothBatteryLevelFallback.isNeeded(
            levels: nil,
            devices: [device(isConnected: false)]
        ))
        #expect(BluetoothBatteryLevelFallback.isNeeded(
            levels: [:],
            devices: [device(isConnected: false), device(address: "D3:6D:6C:40:A3:2E", name: "MX Keys")]
        ))
    }

    // MARK: - Merging

    /// This is the guarantee the whole fallback rests on: a level the report
    /// already carries is copied through untouched.
    @Test("A level the report carries is never changed by the second source")
    func thePrimarySourceAlwaysWins() {
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F"): level(main: 88)],
            accessories: [accessory(percentage: 12)],
            devices: [device()]
        )

        #expect(merged[BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F")]?.main == 88)
    }

    @Test("A device the report has no level for takes the accessory's")
    func aMissingDeviceTakesTheAccessoryLevel() {
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:],
            accessories: [accessory(percentage: 93)],
            devices: [device()]
        )

        #expect(merged[BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F")]?.main == 93)
    }

    @Test("An accessory that matches no device adds nothing")
    func anUnmatchedAccessoryAddsNothing() {
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:],
            accessories: [accessory(name: "Some Other Headset")],
            devices: [device()]
        )

        #expect(merged.isEmpty)
    }

    // MARK: - Which channel a reading may write

    /// A bud is not the device, and the distinction is the whole reason the part
    /// is carried through the parse.
    @Test("A part writes its own channel and never the device-wide level")
    func aPartNeverWritesTheDeviceWideLevel() {
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:],
            accessories: [accessory(part: .left, percentage: 93)],
            devices: [device()]
        )

        let level = merged[BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F")]
        #expect(level?.left == 93)
        #expect(level?.main == nil)
        #expect(level?.summary == "L 93%")
    }

    /// A reading with no part is the only kind allowed to describe the device as
    /// a whole.
    @Test("A reading with no part supplies the device-wide level")
    func aReadingWithNoPartSuppliesTheDeviceWideLevel() {
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:],
            accessories: [accessory(part: nil, percentage: 64)],
            devices: [device()]
        )

        #expect(merged[BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F")]?.summary == "64%")
    }

    /// A set of earbuds publishes one source per part, so both buds and the case
    /// arrive as separate readings and have to land in one device's channels.
    @Test("Separate readings for one device fill their own channels")
    func separateReadingsFillTheirOwnChannels() {
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:],
            accessories: [
                accessory(part: .left, percentage: 93),
                accessory(part: .right, percentage: 91),
                accessory(part: .caseLevel, percentage: 60)
            ],
            devices: [device()]
        )

        #expect(
            merged[BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F")]?.summary
                == "L 93% · R 91% · Case 60%"
        )
    }

    @Test("Two connected sets of the same model cannot borrow one reading")
    func sameModelDevicesAreAmbiguous() {
        let devices = [device(vendorID: 76, productID: 8207),
                       device(address: "11:22:33:44:55:66", vendorID: 76, productID: 8207)]
        let readings = [accessory(vendorID: 76, productID: 8207)]
        #expect(BluetoothBatteryLevelFallback.merged(levels: [:], accessories: readings, devices: devices).isEmpty)
        #expect(BluetoothBatteryLevelFallback.level(for: devices[0], accessories: readings, devices: devices) == nil)
    }

    @Test("A disconnected same-model neighbour still makes ownership ambiguous")
    func disconnectedNeighbourCannotLendItsReading() {
        let devices = [device(vendorID: 76, productID: 8207),
                       device(address: "11:22:33:44:55:66", isConnected: false, vendorID: 76, productID: 8207)]
        #expect(BluetoothBatteryLevelFallback.merged(
            levels: [:], accessories: [accessory(vendorID: 76, productID: 8207)], devices: devices
        ).isEmpty)
    }

    @Test("Distinct identifiers never combine parts or choose the first set")
    func multipleIdentifiersForOneDeviceAreRejected() {
        let target = device()
        let readings = [accessory(identifier: "first", part: .left, percentage: 93),
                        accessory(identifier: "second", part: .right, percentage: 12)]
        #expect(BluetoothBatteryLevelFallback.merged(levels: [:], accessories: readings, devices: [target]).isEmpty)
        #expect(BluetoothBatteryLevelFallback.level(for: target, accessories: readings, devices: [target]) == nil)
    }

    @Test("Uniquely attributable identifiers can describe distinct devices")
    func distinctDevicesKeepTheirOwnReadings() {
        let first = device()
        let second = device(address: "11:22:33:44:55:66", name: "MX Keys")
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:], accessories: [accessory(identifier: "first", percentage: 93),
                                      accessory(identifier: "second", name: "MX Keys", percentage: 12)],
            devices: [first, second]
        )
        #expect(merged[BluetoothBatteryReader.normalizedAddress(first.id)]?.main == 93)
        #expect(merged[BluetoothBatteryReader.normalizedAddress(second.id)]?.main == 12)
    }

    @Test("Disconnected devices and unidentified readings supply no fallback")
    func disconnectedAndUnidentifiedReadingsAreRejected() {
        let disconnected = device(isConnected: false)
        #expect(!BluetoothBatteryLevelFallback.matches(accessory(), disconnected))
        #expect(BluetoothBatteryLevelFallback.level(for: disconnected, accessories: [accessory()], devices: [disconnected]) == nil)
        #expect(BluetoothBatteryLevelFallback.merged(levels: [:], accessories: [accessory()], devices: [disconnected]).isEmpty)
        #expect(BluetoothBatteryLevelFallback.merged(levels: [:], accessories: [accessory(identifier: nil)], devices: [device()]).isEmpty)
        #expect(BluetoothBatteryLevelFallback.merged(levels: [:], accessories: [], devices: [device()]).isEmpty)
        #expect(!BluetoothBatteryLevelFallback.isNeeded(levels: nil, devices: []))
    }

    @Test("UUID casing does not split a single accessory's channels")
    func identifierCaseDoesNotSplitChannels() {
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:], accessories: [accessory(identifier: "ABCD", part: .left, percentage: 93),
                                      accessory(identifier: "abcd", part: .right, percentage: 91)], devices: [device()]
        )
        #expect(merged.values.first?.summary == "L 93% · R 91%")
    }

    @Test("An accessory that matches no device cannot suppress a readable one")
    func unresolvableAccessoryDoesNotSuppressAnotherDevice() {
        // The second accessory names no device; it adds nothing, but it also
        // gives no reason to withhold the level the first one resolves to.
        let target = device()
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:], accessories: [accessory(identifier: "first"),
                                      accessory(identifier: "second", name: "Unknown")], devices: [target]
        )
        #expect(merged[BluetoothBatteryReader.normalizedAddress(target.id)]?.main == 93)
    }

    @Test("A shared identifier cannot lend one matching part's identity to a conflicting part")
    func conflictingPartsRejectTheWholeIdentifierGroup() {
        let target = device(vendorID: 76, productID: 8207)
        let readings = [
            accessory(vendorID: 76, productID: 8207, part: .left, percentage: 93),
            accessory(vendorID: 1133, productID: 45915, part: .right, percentage: 12)
        ]
        #expect(BluetoothBatteryLevelFallback.merged(levels: [:], accessories: readings, devices: [target]).isEmpty)
        #expect(BluetoothBatteryLevelFallback.level(for: target, accessories: readings, devices: [target]) == nil)
        let primary = [BluetoothBatteryReader.normalizedAddress(target.id): level(main: 88)]
        #expect(BluetoothBatteryLevelFallback.merged(levels: primary, accessories: readings, devices: [target]) == primary)
    }

    @Test("All-parts agreement must not shrink away a cross-device ambiguity")
    func aPartMatchingAnotherDeviceKeepsTheGroupAmbiguous() {
        let target = device(vendorID: 76, productID: 8207)
        // The unnamed-ID part matches both devices by name. The other part
        // matches only target by model; filtering with allSatisfy first would
        // conceal the second possible owner of the first part.
        let neighbour = device(address: "11:22:33:44:55:66", vendorID: 1133, productID: 45915)
        let readings = [accessory(part: .left), accessory(vendorID: 76, productID: 8207, part: .right)]
        #expect(BluetoothBatteryLevelFallback.merged(levels: [:], accessories: readings, devices: [target, neighbour]).isEmpty)
    }

    @Test("An ambiguous accessory costs only its own device, not unrelated devices")
    func ambiguityIsScopedToTheAffectedDevice() {
        // Issue #328: a set of AirPods reports its case and combined level under
        // two identifiers, both naming the same (here disconnected) AirPods. That
        // ambiguity must not hide a mouse and keyboard whose readings resolve
        // uniquely — the regression that dropped the whole fallback round.
        let airPods = device(address: "AA:BB:CC:DD:EE:01", name: "AirPods",
                             isConnected: false, vendorID: 76, productID: 8231)
        let mouse = device(address: "AA:BB:CC:DD:EE:02", name: "Rapoo BT Mouse",
                           vendorID: 9390, productID: 13330)
        let keyboard = device(address: "AA:BB:CC:DD:EE:03", name: "Keychron K10 Max",
                              vendorID: 13364, productID: 2720)
        let readings = [
            accessory(identifier: "case", name: "AirPods", vendorID: 76, productID: 8231,
                      part: .caseLevel, percentage: 69),
            accessory(identifier: "headset", name: "AirPods", vendorID: 76, productID: 8231,
                      percentage: 80),
            accessory(identifier: "mouse", name: "Rapoo BT Mouse", vendorID: 9390, productID: 13330,
                      percentage: 81),
            accessory(identifier: "keyboard", name: "Keychron K10 Max", vendorID: 13364, productID: 2720,
                      percentage: 65)
        ]
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:], accessories: readings, devices: [airPods, mouse, keyboard]
        )
        #expect(merged[BluetoothBatteryReader.normalizedAddress(mouse.id)]?.main == 81)
        #expect(merged[BluetoothBatteryReader.normalizedAddress(keyboard.id)]?.main == 65)
        // The ambiguous AirPods are left without a level, never given a guess.
        #expect(merged[BluetoothBatteryReader.normalizedAddress(airPods.id)] == nil)
    }

    @Test("A device named by two identifiers is dropped while a neighbour keeps its own")
    func twoIdentifiersDropOnlyTheirDevice() {
        let target = device(vendorID: 76, productID: 8207)
        let neighbour = device(address: "11:22:33:44:55:66", name: "MX Keys", vendorID: 1133, productID: 45915)
        let readings = [
            accessory(identifier: "a", vendorID: 76, productID: 8207, part: .left, percentage: 93),
            accessory(identifier: "b", vendorID: 76, productID: 8207, part: .right, percentage: 91),
            accessory(identifier: "c", name: "MX Keys", vendorID: 1133, productID: 45915, percentage: 42)
        ]
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:], accessories: readings, devices: [target, neighbour]
        )
        #expect(merged[BluetoothBatteryReader.normalizedAddress(target.id)] == nil)
        #expect(merged[BluetoothBatteryReader.normalizedAddress(neighbour.id)]?.main == 42)
    }

    // MARK: - Matching

    /// The pair identifies one model, and it is what survives a rename. When both
    /// sides carry it, it decides on its own — including when the pair says the
    /// two are the same device under different names.
    @Test("A matching vendor and product pair identifies the device")
    func theIdentifierPairIdentifiesTheDevice() {
        #expect(BluetoothBatteryLevelFallback.matches(
            accessory(name: "Renamed Since", vendorID: 76, productID: 8207),
            device(name: "AirPods Pro", vendorID: 76, productID: 8207)
        ))
    }

    /// A pair that disagrees is a different model, and the name must not
    /// re-join it: two accessories can share a default name while being
    /// different hardware.
    @Test("A disagreeing identifier pair is not rescued by a matching name")
    func aDisagreeingPairIsNotRescuedByTheName() {
        #expect(!BluetoothBatteryLevelFallback.matches(
            accessory(name: "AirPods Pro", vendorID: 1133, productID: 45915),
            device(name: "AirPods Pro", vendorID: 76, productID: 8207)
        ))
    }

    /// The name is what is left when a source carries no pair at all.
    @Test("The name matches when either side carries no identifier pair")
    func theNameMatchesWhenAPairIsMissing() {
        #expect(BluetoothBatteryLevelFallback.matches(
            accessory(name: "MX Keys"),
            device(name: "mx keys")
        ))
        #expect(BluetoothBatteryLevelFallback.matches(
            accessory(name: "MX Keys"),
            device(name: "MX Keys", vendorID: 1133, productID: 45915)
        ))
    }

    /// A substring match would join an accessory to any device whose name
    /// happens to contain it, so the comparison is exact.
    @Test("A name that merely contains another does not match")
    func aNameThatMerelyContainsAnotherDoesNotMatch() {
        #expect(!BluetoothBatteryLevelFallback.matches(
            accessory(name: "MX Keys"),
            device(name: "MX Keys for Mac")
        ))
    }

    /// An accessory the power manager could not name can still be identified by
    /// its pair, but must never match a device by an empty name.
    @Test("An unnamed accessory never matches by name")
    func anUnnamedAccessoryNeverMatchesByName() {
        #expect(!BluetoothBatteryLevelFallback.matches(accessory(name: ""), device(name: "")))
        #expect(!BluetoothBatteryLevelFallback.matches(
            accessory(name: " "),
            device(name: "AirPods Pro")
        ))
    }

    // MARK: - Keyboard / mouse owner rule (MX Anywhere 3S)

    /// The real snapshot that motivated the rule: a connected MX Anywhere 3S
    /// with a complete vendor/product pair, plus a disconnected historical record
    /// of the same mouse with no pair, sharing the full device list with a Magic
    /// Keyboard and AirPods. The connected mouse must get the 25% `pmset` carries;
    /// the stale record must get nothing and must stay disconnected.
    @Test("MX Anywhere 3S: a stale name-only twin does not block the connected mouse")
    func mxAnywhereConnectedMouseKeepsItsLevel() {
        let mouse = device(
            address: "D0:B1:B1:15:D7:F7",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: true,
            vendorID: 1133,
            productID: 45111
        )
        let staleMouse = device(
            address: "D0:B1:B1:15:D7:F5",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: false
        )
        let magicKeyboard = device(
            address: "AA:BB:CC:DD:EE:10",
            name: "Magic Keyboard",
            kind: .peripheral(.keyboard),
            isConnected: true,
            vendorID: 76,
            productID: 615
        )
        let airpods = device(
            address: "11:22:33:44:55:01",
            name: "AirPods Pro",
            kind: .audio,
            isConnected: true,
            vendorID: 76,
            productID: 8207
        )
        let airpodsCase = device(
            address: "11:22:33:44:55:02",
            name: "AirPods Pro Case",
            kind: .audio,
            isConnected: false
        )
        let accessories = [
            accessory(
                identifier: "6F1D4C6A-2B7E-4C0D-9A3E-2C1B0A9D8E71",
                name: "MX Anywhere 3S",
                vendorID: 1133,
                productID: 45111,
                percentage: 25
            )
        ]
        let devices = [mouse, staleMouse, magicKeyboard, airpods, airpodsCase]

        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:],
            accessories: accessories,
            devices: devices
        )

        #expect(merged[BluetoothBatteryReader.normalizedAddress(mouse.id)]?.main == 25)
        #expect(merged[BluetoothBatteryReader.normalizedAddress(mouse.id)]?.summary == "25%")
        #expect(merged[BluetoothBatteryReader.normalizedAddress(staleMouse.id)] == nil)
        #expect(merged.count == 1)
        // The device list itself is untouched: a battery rule never reconnects.
        #expect(staleMouse.isConnected == false)
    }

    /// The same rule for a keyboard, using an address pair that differs only in
    /// the last byte.
    @Test("A connected keyboard with a stale name-only twin gets its level")
    func connectedKeyboardWithStaleTwinGetsItsLevel() {
        let keyboard = device(
            address: "AA:BB:CC:DD:EE:10",
            name: "MX Keys",
            kind: .peripheral(.keyboard),
            isConnected: true,
            vendorID: 1133,
            productID: 45915
        )
        let staleKeyboard = device(
            address: "AA:BB:CC:DD:EE:12",
            name: "MX Keys",
            kind: .peripheral(.keyboard),
            isConnected: false
        )
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:],
            accessories: [
                accessory(
                    identifier: "0B2B5A4E-8D7C-4B1A-9F3E-5A6C7D8E9F01",
                    name: "MX Keys",
                    vendorID: 1133,
                    productID: 45915,
                    percentage: 71
                )
            ],
            devices: [keyboard, staleKeyboard]
        )

        #expect(merged[BluetoothBatteryReader.normalizedAddress(keyboard.id)]?.main == 71)
        #expect(merged[BluetoothBatteryReader.normalizedAddress(staleKeyboard.id)] == nil)
    }

    /// Two records of the same name whose addresses are visibly unrelated are not
    /// the same device. The rule refuses rather than guessing by name alone.
    @Test("Same name but unrelated addresses stay conservative")
    func sameNameButUnrelatedAddressesStayConservative() {
        let mouse = device(
            address: "AA:BB:CC:DD:EE:10",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: true,
            vendorID: 1133,
            productID: 45111
        )
        let unrelated = device(
            address: "11:22:33:44:55:66",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: false
        )
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:],
            accessories: [accessory(name: "MX Anywhere 3S", vendorID: 1133, productID: 45111)],
            devices: [mouse, unrelated]
        )

        #expect(merged.isEmpty)
    }

    /// Two connected mice of the same model cannot share one reading, even with
    /// the relaxed rule available.
    @Test("Two connected mice with the same pair are rejected")
    func twoConnectedMiceWithSamePairAreRejected() {
        let first = device(
            address: "AA:BB:CC:DD:EE:10",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: true,
            vendorID: 1133,
            productID: 45111
        )
        let second = device(
            address: "AA:BB:CC:DD:EE:12",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: true,
            vendorID: 1133,
            productID: 45111
        )
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:],
            accessories: [accessory(name: "MX Anywhere 3S", vendorID: 1133, productID: 45111)],
            devices: [first, second]
        )

        #expect(merged.isEmpty)
    }

    /// A disconnected twin that still carries the complete pair is a second real
    /// device of the model, so the pair no longer names one owner.
    @Test("A disconnected twin with the same complete pair blocks the rule")
    func aDisconnectedTwinWithTheSamePairBlocksTheRule() {
        let mouse = device(
            address: "AA:BB:CC:DD:EE:10",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: true,
            vendorID: 1133,
            productID: 45111
        )
        let twin = device(
            address: "AA:BB:CC:DD:EE:12",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: false,
            vendorID: 1133,
            productID: 45111
        )
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:],
            accessories: [accessory(name: "MX Anywhere 3S", vendorID: 1133, productID: 45111)],
            devices: [mouse, twin]
        )

        #expect(merged.isEmpty)
    }

    /// Without a complete pair on the source there is no safe strong match, so the
    /// relaxed rule must not run at all.
    @Test("A pmset reading without a full pair never triggers the relaxed rule")
    func aReadingWithoutAFullPairNeverTriggersTheRelaxedRule() {
        let mouse = device(
            address: "AA:BB:CC:DD:EE:10",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: true,
            vendorID: 1133,
            productID: 45111
        )
        let stale = device(
            address: "AA:BB:CC:DD:EE:12",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: false
        )
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:],
            accessories: [accessory(name: "MX Anywhere 3S", percentage: 25)],
            devices: [mouse, stale]
        )

        #expect(merged.isEmpty)
    }

    /// Two independent identifiers that both name the one mouse make ownership
    /// ambiguous: a higher evidence level must not pick one of them.
    @Test("Two identifiers naming one mouse are still rejected")
    func twoIdentifiersNamingOneMouseAreRejected() {
        let mouse = device(
            address: "AA:BB:CC:DD:EE:10",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: true,
            vendorID: 1133,
            productID: 45111
        )
        let stale = device(
            address: "AA:BB:CC:DD:EE:12",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: false
        )
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:],
            accessories: [
                accessory(identifier: "AAAA", name: "MX Anywhere 3S", vendorID: 1133, productID: 45111, percentage: 25),
                accessory(identifier: "BBBB", name: "MX Anywhere 3S", vendorID: 1133, productID: 45111, percentage: 30)
            ],
            devices: [mouse, stale]
        )

        #expect(merged.isEmpty)
    }

    /// A complete, different pair on the same-named device is a conflict, not a
    /// stale copy, so the reading is withheld.
    @Test("A conflicting complete pair on a same-named device is rejected")
    func aConflictingCompletePairOnASameNamedDeviceIsRejected() {
        let mouse = device(
            address: "AA:BB:CC:DD:EE:10",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: true,
            vendorID: 1133,
            productID: 12345
        )
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:],
            accessories: [accessory(name: "MX Anywhere 3S", vendorID: 1133, productID: 45111)],
            devices: [mouse]
        )

        #expect(merged.isEmpty)
    }

    /// A level the profiler already carries is never replaced by `pmset`, even
    /// when the relaxed rule would otherwise apply.
    @Test("A profiler level survives the relaxed rule untouched")
    func aProfilerLevelSurvivesTheRelaxedRule() {
        let mouse = device(
            address: "AA:BB:CC:DD:EE:10",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: true,
            vendorID: 1133,
            productID: 45111
        )
        let stale = device(
            address: "AA:BB:CC:DD:EE:12",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: false
        )
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [BluetoothBatteryReader.normalizedAddress(mouse.id): level(main: 80)],
            accessories: [accessory(name: "MX Anywhere 3S", vendorID: 1133, productID: 45111, percentage: 25)],
            devices: [mouse, stale]
        )

        #expect(merged[BluetoothBatteryReader.normalizedAddress(mouse.id)]?.main == 80)
    }

    /// The relaxed rule is confined to keyboards and mice. AirPods of the same
    /// name keep the strict behavior, so the twin still blocks.
    @Test("AirPods never enter the keyboard/mouse relaxed rule")
    func airPodsNeverEnterTheRelaxedRule() {
        let connected = device(
            address: "AA:BB:CC:DD:EE:10",
            name: "AirPods Pro",
            kind: .audio,
            isConnected: true,
            vendorID: 76,
            productID: 8207
        )
        let stale = device(
            address: "AA:BB:CC:DD:EE:12",
            name: "AirPods Pro",
            kind: .audio,
            isConnected: false
        )
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:],
            accessories: [accessory(name: "AirPods Pro", vendorID: 76, productID: 8207, percentage: 55)],
            devices: [connected, stale]
        )

        #expect(merged.isEmpty)
    }

    /// A trackpad is a peripheral but not a keyboard or mouse: the relaxed rule
    /// must not apply to it.
    @Test("A trackpad stays on the strict rule")
    func aTrackpadStaysOnTheStrictRule() {
        let trackpad = device(
            address: "AA:BB:CC:DD:EE:10",
            name: "Magic Trackpad",
            kind: .peripheral(.trackpad),
            isConnected: true,
            vendorID: 76,
            productID: 613
        )
        let stale = device(
            address: "AA:BB:CC:DD:EE:12",
            name: "Magic Trackpad",
            kind: .peripheral(.trackpad),
            isConnected: false
        )
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:],
            accessories: [accessory(name: "Magic Trackpad", vendorID: 76, productID: 613, percentage: 40)],
            devices: [trackpad, stale]
        )

        #expect(merged.isEmpty)
    }

    /// A part-channel reading is never device-wide, so it must not be handed to a
    /// keyboard or mouse by the relaxed rule either.
    @Test("A part reading never feeds the relaxed rule")
    func aPartReadingNeverFeedsTheRelaxedRule() {
        let mouse = device(
            address: "AA:BB:CC:DD:EE:10",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: true,
            vendorID: 1133,
            productID: 45111
        )
        let stale = device(
            address: "AA:BB:CC:DD:EE:12",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: false
        )
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:],
            accessories: [accessory(name: "MX Anywhere 3S", vendorID: 1133, productID: 45111, part: .left, percentage: 25)],
            devices: [mouse, stale]
        )

        #expect(merged.isEmpty)
    }

    /// Resolving every identifier before assigning ownership makes the result
    /// independent of both accessory and device order.
    @Test("The relaxed rule is order independent")
    func theRelaxedRuleIsOrderIndependent() {
        let mouse = device(
            address: "AA:BB:CC:DD:EE:10",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: true,
            vendorID: 1133,
            productID: 45111
        )
        let stale = device(
            address: "AA:BB:CC:DD:EE:12",
            name: "MX Anywhere 3S",
            kind: .peripheral(.mouse),
            isConnected: false
        )
        let other = device(
            address: "11:22:33:44:55:66",
            name: "Magic Keyboard",
            kind: .peripheral(.keyboard),
            isConnected: true,
            vendorID: 76,
            productID: 615
        )
        let accessories = [
            accessory(identifier: "AAAA", name: "MX Anywhere 3S", vendorID: 1133, productID: 45111, percentage: 25),
            accessory(identifier: "BBBB", name: "Magic Keyboard", vendorID: 76, productID: 615, percentage: 90)
        ]

        let forward = BluetoothBatteryLevelFallback.merged(
            levels: [:], accessories: accessories, devices: [mouse, stale, other]
        )
        let reversed = BluetoothBatteryLevelFallback.merged(
            levels: [:], accessories: Array(accessories.reversed()), devices: [stale, other, mouse]
        )

        #expect(forward == reversed)
        #expect(forward[BluetoothBatteryReader.normalizedAddress(mouse.id)]?.main == 25)
        #expect(forward[BluetoothBatteryReader.normalizedAddress(other.id)]?.main == 90)
    }
}
