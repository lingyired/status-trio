import Testing
@testable import StatusTrioCore

/// The accessory sources may only ever add a level. These pin the two rules that
/// make that true: when the second source is worth reading at all, and which
/// channel a reading is allowed to write.
struct BluetoothBatteryLevelFallbackTests {
    private func device(
        address: String = "AC:90:85:C2:9C:1F",
        name: String = "AirPods Pro",
        isConnected: Bool = true,
        vendorID: Int? = nil,
        productID: Int? = nil
    ) -> BluetoothDevice {
        BluetoothDevice(
            id: address,
            name: name,
            kind: .audio,
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
}
