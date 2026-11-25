import Foundation
import Testing
@testable import StatusTrioCore

/// Charging state is a second field the accessory sources add to a level the
/// primary report already carries. These pin the parser (real booleans only,
/// nested parts, charging without capacity), the merge (bolt without a level
/// change), and the drawn segments (bolt beside the percentage, silent text).
struct BluetoothBatteryChargingTests {
    // MARK: - Parsing

    private func source(_ overrides: [String: Any]) -> [String: Any] {
        var document: [String: Any] = [
            "Type": "Accessory Source",
            "Name": "AirPods Pro"
        ]
        for (key, value) in overrides { document[key] = value }
        return document
    }

    @Test("A real Is Charging boolean is read; a missing field is unknown")
    func parsesBoolAndMissing() {
        let charged = BluetoothAccessoryBatteryReader.parse(documents: [
            source(["Current Capacity": 82, "Max Capacity": 100, "Is Charging": true])
        ])
        #expect(charged.first?.isCharging == true)

        let notCharging = BluetoothAccessoryBatteryReader.parse(documents: [
            source(["Current Capacity": 82, "Max Capacity": 100, "Is Charging": false])
        ])
        #expect(notCharging.first?.isCharging == false)

        let unknown = BluetoothAccessoryBatteryReader.parse(documents: [
            source(["Current Capacity": 82, "Max Capacity": 100])
        ])
        #expect(unknown.first?.isCharging == nil)
    }

    /// A number or a string is not a boolean: reading `<integer>1</integer>` as
    /// "charging" would invent a state the source never reported.
    @Test("A non-boolean Is Charging value is unknown, not false")
    func rejectsNonBooleanCharging() {
        let integer = BluetoothAccessoryBatteryReader.parse(documents: [
            source(["Current Capacity": 82, "Max Capacity": 100, "Is Charging": 1])
        ])
        #expect(integer.first?.isCharging == nil)

        let string = BluetoothAccessoryBatteryReader.parse(documents: [
            source(["Current Capacity": 82, "Max Capacity": 100, "Is Charging": "true"])
        ])
        #expect(string.first?.isCharging == nil)
    }

    /// The plist path must read `<true/>`/`<false/>` and still ignore `<integer>`.
    @Test("The XML path reads the boolean element and ignores an integer one")
    func parsesBooleanFromXML() {
        let xml = plist([
            ("Type", "<string>Accessory Source</string>"),
            ("Name", "<string>Magic Keyboard</string>"),
            ("Current Capacity", "<integer>82</integer>"),
            ("Max Capacity", "<integer>100</integer>"),
            ("Is Charging", "<true/>")
        ])
        #expect(BluetoothAccessoryBatteryReader.parse(xml: xml).first?.isCharging == true)

        let integerXML = plist([
            ("Type", "<string>Accessory Source</string>"),
            ("Name", "<string>Magic Keyboard</string>"),
            ("Current Capacity", "<integer>82</integer>"),
            ("Is Charging", "<integer>1</integer>")
        ])
        #expect(BluetoothAccessoryBatteryReader.parse(xml: integerXML).first?.isCharging == nil)
    }

    /// An explicit state with no readable capacity is still worth keeping: it can
    /// add the bolt to a level the primary report already has.
    @Test("A charging-only record is kept with no percentage")
    func keepsChargingWithoutCapacity() {
        let levels = BluetoothAccessoryBatteryReader.parse(documents: [
            source(["Is Charging": true])
        ])
        #expect(levels.count == 1)
        #expect(levels.first?.percentage == nil)
        #expect(levels.first?.isCharging == true)
    }

    @Test("Capacity normalises at 0% and 100%")
    func capacityBoundaries() {
        let empty = BluetoothAccessoryBatteryReader.parse(documents: [
            source(["Current Capacity": 0, "Max Capacity": 100])
        ])
        #expect(empty.first?.percentage == 0)

        let full = BluetoothAccessoryBatteryReader.parse(documents: [
            source(["Current Capacity": 100, "Max Capacity": 100])
        ])
        #expect(full.first?.percentage == 100)
    }

    /// Nested parts inherit the parent's identity but never its capacity or its
    /// charging state: one bud's state must not become another's.
    @Test("Combined Parts are parsed individually and inherit only identity")
    func parsesCombinedParts() {
        let parent = source([
            "Accessory Identifier": "PARENT-ID",
            "Vendor ID": 76,
            "Product ID": 8207,
            "Current Capacity": 50,
            "Is Charging": true,
            "Combined Parts": [
                ["Part Identifier": "Left", "Current Capacity": 72, "Is Charging": true],
                ["Part Identifier": "Right", "Current Capacity": 93, "Is Charging": false]
            ]
        ])
        let levels = BluetoothAccessoryBatteryReader.parse(documents: [parent])

        #expect(levels.count == 2)
        let left = levels.first { $0.part == .left }
        #expect(left?.percentage == 72)
        #expect(left?.isCharging == true)
        #expect(left?.identifier == "PARENT-ID")
        #expect(left?.vendorID == 76)

        let right = levels.first { $0.part == .right }
        #expect(right?.percentage == 93)
        #expect(right?.isCharging == false)
        #expect(right?.identifier == "PARENT-ID")
    }

    @Test("A missing Accessory Identifier falls back to the Group Identifier")
    func groupIdentifierIsFallbackIdentity() {
        let levels = BluetoothAccessoryBatteryReader.parse(documents: [
            source(["Group Identifier": "GROUP-ID", "Current Capacity": 80])
        ])
        #expect(levels.first?.identifier == "GROUP-ID")
    }

    // MARK: - Merging

    private func device(address: String = "AA:BB:CC:DD:EE:FF", connected: Bool = true) -> BluetoothDevice {
        BluetoothDevice(id: address, name: "AirPods Pro", kind: .audio, isConnected: connected)
    }

    private func accessory(
        part: BluetoothAccessoryPart? = nil,
        percentage: Int? = nil,
        isCharging: Bool? = nil,
        identifier: String = "ID"
    ) -> BluetoothAccessoryBatteryLevel {
        BluetoothAccessoryBatteryLevel(
            identifier: identifier,
            name: "AirPods Pro",
            vendorID: nil,
            productID: nil,
            part: part,
            percentage: percentage,
            isCharging: isCharging
        )
    }

    private func level(
        main: Int? = nil,
        left: Int? = nil,
        caseLevel: Int? = nil,
        mainIsCharging: Bool? = nil,
        leftIsCharging: Bool? = nil,
        caseIsCharging: Bool? = nil
    ) -> BluetoothBatteryLevel {
        BluetoothBatteryLevel(
            deviceAddress: "AA:BB:CC:DD:EE:FF",
            main: main,
            left: left,
            right: nil,
            caseLevel: caseLevel,
            mainIsCharging: mainIsCharging,
            leftIsCharging: leftIsCharging,
            caseIsCharging: caseIsCharging
        )
    }

    /// The primary percentage is never replaced by the accessory's; the accessory
    /// only adds the bolt.
    @Test("Existing level keeps its percentage and gains the charging state")
    func mergedKeepsLevelAddsCharging() {
        let address = "AA:BB:CC:DD:EE:FF"
        let key = BluetoothBatteryReader.normalizedAddress(address)
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [key: level(main: 80)],
            accessories: [accessory(percentage: 82, isCharging: true)],
            devices: [device()]
        )
        #expect(merged[key]?.main == 80)
        #expect(merged[key]?.mainIsCharging == true)
    }

    @Test("An explicit not-charging state is kept, an unknown one is not invented")
    func mergedRespectsFalseAndUnknown() {
        let address = "AA:BB:CC:DD:EE:FF"
        let key = BluetoothBatteryReader.normalizedAddress(address)
        let notCharging = BluetoothBatteryLevelFallback.merged(
            levels: [key: level(main: 80)],
            accessories: [accessory(isCharging: false)],
            devices: [device()]
        )
        #expect(notCharging[key]?.mainIsCharging == false)

        let unknown = BluetoothBatteryLevelFallback.merged(
            levels: [key: level(main: 80)],
            accessories: [accessory()],
            devices: [device()]
        )
        #expect(unknown[key]?.mainIsCharging == nil)
    }

    @Test("A device missing a level gains both the level and its charging state")
    func mergedAddsLevelAndCharging() {
        let address = "AA:BB:CC:DD:EE:FF"
        let key = BluetoothBatteryReader.normalizedAddress(address)
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:],
            accessories: [accessory(percentage: 82, isCharging: true)],
            devices: [device()]
        )
        #expect(merged[key]?.main == 82)
        #expect(merged[key]?.mainIsCharging == true)
    }

    /// A charging flag for a channel the row has no percentage for is not stored:
    /// the row would have no place to draw the bolt.
    @Test("A channel without a level does not gain a charging flag")
    func mergedSkipsChargingForMissingChannel() {
        let address = "AA:BB:CC:DD:EE:FF"
        let key = BluetoothBatteryReader.normalizedAddress(address)
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [key: level(main: 80)],
            accessories: [accessory(part: .left, percentage: nil, isCharging: true)],
            devices: [device()]
        )
        #expect(merged[key]?.left == nil)
        #expect(merged[key]?.leftIsCharging == nil)
        #expect(merged[key]?.main == 80)
    }

    @Test("A disconnected device is never given charging state")
    func mergedSkipsDisconnected() {
        let address = "AA:BB:CC:DD:EE:FF"
        let key = BluetoothBatteryReader.normalizedAddress(address)
        let merged = BluetoothBatteryLevelFallback.merged(
            levels: [:],
            accessories: [accessory(percentage: 82, isCharging: true)],
            devices: [device(connected: false)]
        )
        #expect(merged[key] == nil)
    }

    // MARK: - Triggering

    @Test("Charging demand reads even when every device already has a level")
    func needsChargingForcesRead() {
        let key = BluetoothBatteryReader.normalizedAddress("AA:BB:CC:DD:EE:FF")
        #expect(BluetoothBatteryLevelFallback.isNeeded(
            levels: [key: level(main: 80)],
            devices: [device()],
            needsChargingState: true
        ))
        #expect(!BluetoothBatteryLevelFallback.isNeeded(
            levels: [key: level(main: 80)],
            devices: [device()],
            needsChargingState: false
        ))
        #expect(!BluetoothBatteryLevelFallback.isNeeded(
            levels: [key: level(main: 80)],
            devices: [device(connected: false)],
            needsChargingState: true
        ))
    }

    // MARK: - Segments

    private func boltCount(_ segments: [BluetoothBatterySegment]) -> Int {
        segments.filter { segment in
            if case .symbol(let name, _) = segment { return name == "bolt.fill" }
            return false
        }.count
    }

    @Test("A charging main channel draws a bolt and keeps its text")
    func mainBolt() {
        let segments = level(main: 82, mainIsCharging: true).segments
        #expect(segments != nil)
        #expect(boltCount(segments ?? []) == 1)
        #expect(segments?.plainText == "82%")
    }

    @Test("Charging is drawn per channel, case included, without changing the text")
    func perChannelBolts() {
        let segments = level(left: 72, caseLevel: 56,
                             leftIsCharging: true, caseIsCharging: true).segments ?? []
        #expect(boltCount(segments) == 2)
        #expect(segments.plainText == "L 72% · Case 56%")
    }

    @Test("An unknown or false state draws no bolt")
    func noBoltWhenNotCharging() {
        #expect(boltCount(level(main: 82, mainIsCharging: false).segments ?? []) == 0)
        #expect(boltCount(level(main: 82).segments ?? []) == 0)
    }

    @Test("hasVisibleCharging only counts channels that are drawn")
    func hasVisibleChargingGuard() {
        #expect(level(main: 82, mainIsCharging: true).hasVisibleCharging)
        // A charging flag on a channel with no level is not "visible".
        #expect(!level(main: 82, leftIsCharging: true).hasVisibleCharging)
        #expect(!level(main: 82, mainIsCharging: false).hasVisibleCharging)
    }

    // MARK: - Fixtures

    private func plist(_ entries: [(String, String)]) -> String {
        let body = entries.map { "  <key>\($0.0)</key>\n  \($0.1)" }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
        \(body)
        </dict>
        </plist>

        """
    }
}
