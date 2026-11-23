import Foundation
import Testing
@testable import StatusTrioCore

/// The accessory power sources are the second battery source, and they describe
/// a *part* of an accessory rather than a device. These pin what the parser
/// keeps, what it ignores, and which channel a part lands in.
struct BluetoothAccessoryBatteryTests {
    // MARK: - Parsing

    /// `pmset -g accps -xml` prints one property list per power source,
    /// concatenated. The Mac's own battery is one of them and is not an
    /// accessory, so its type is what keeps it out of the list.
    @Test("Every accessory document is read and the Mac's own battery is not")
    func readsAccessoriesAndIgnoresTheInternalBattery() {
        let levels = BluetoothAccessoryBatteryReader.parse(xml: report)

        #expect(levels.count == 2)
        let keyboard = levels.first { $0.name == "MX Keys" }
        #expect(keyboard?.percentage == 100)
        #expect(keyboard?.vendorID == 1133)
        #expect(keyboard?.productID == 45915)
        #expect(keyboard?.part == nil)
        #expect(keyboard?.identifier == "63F146B5-8E90-CDEB-598D-C2E98CBB8779")

        let earbuds = levels.first { $0.name == "机灵的耳机" }
        #expect(earbuds?.percentage == 93)
        #expect(earbuds?.part == .left)
        #expect(earbuds?.identifier == "E0CA918B-FC5E-C942-B6C3-23F27810A34F")
    }

    /// The identifier is what keeps two sets of one model apart, so a source
    /// that omits it must read as unidentifiable rather than borrowing an empty
    /// string that would group unrelated accessories together.
    @Test("An accessory without an Accessory Identifier reads as unidentified")
    func keepsAMissingIdentifierAsNil() {
        let levels = BluetoothAccessoryBatteryReader.parse(xml: document(
            type: "Accessory Source",
            current: 80,
            maximum: 100
        ))

        #expect(levels.count == 1)
        #expect(levels.first?.identifier == nil)
        #expect(BluetoothAccessoryBatteryReader.parse(xml: document(
            type: "Accessory Source",
            current: 80,
            maximum: 100,
            identifier: "   "
        )).first?.identifier == nil)
    }

    /// Two sets of one model share every other field, so the identifier is the
    /// only value that tells their readings apart after parsing.
    @Test("Two same-model accessories keep distinct identifiers")
    func keepsDistinctIdentifiersForSameModelAccessories() {
        let levels = BluetoothAccessoryBatteryReader.parse(xml:
            document(type: "Accessory Source", current: 93, maximum: 100,
                     name: "AirPods Pro", identifier: "AAAAAAAA-0000-0000-0000-000000000001")
            + document(type: "Accessory Source", current: 12, maximum: 100,
                       name: "AirPods Pro", identifier: "BBBBBBBB-0000-0000-0000-000000000002")
        )

        #expect(levels.count == 2)
        #expect(Set(levels.compactMap(\.identifier)).count == 2)
    }

    /// A part is what decides the channel, and wording the app does not know has
    /// to stay device-wide rather than being guessed into a bud.
    @Test("A part identifier maps to its channel and unknown wording maps to none")
    func mapsPartIdentifiers() {
        #expect(BluetoothAccessoryPart(identifier: "Left") == .left)
        #expect(BluetoothAccessoryPart(identifier: " right ") == .right)
        #expect(BluetoothAccessoryPart(identifier: "Case") == .caseLevel)
        #expect(BluetoothAccessoryPart(identifier: "Primary") == nil)
        #expect(BluetoothAccessoryPart(identifier: nil) == nil)
        #expect(BluetoothAccessoryPart(identifier: "") == nil)
    }

    /// `Current Capacity` is the charge left and `Max Capacity` the full charge,
    /// both in the source's own units, so the two have to be divided rather than
    /// assumed to be a percentage already.
    @Test("Capacity is normalized against the source's own maximum")
    func normalizesCapacity() {
        let levels = BluetoothAccessoryBatteryReader.parse(xml: document(
            type: "Accessory Source",
            current: 1860,
            maximum: 2000
        ))

        #expect(levels.first?.percentage == 93)
    }

    /// A capacity that is missing or out of range is not a level, and the
    /// document is dropped rather than guessed at.
    @Test("A capacity that cannot be a percentage is dropped")
    func dropsUnusableCapacities() {
        #expect(BluetoothAccessoryBatteryReader.parse(xml: document(
            type: "Accessory Source", current: 250, maximum: 100
        )).isEmpty)
        #expect(BluetoothAccessoryBatteryReader.parse(xml: document(
            type: "Accessory Source", current: -1, maximum: 100
        )).isEmpty)
        #expect(BluetoothAccessoryBatteryReader.parse(xml: """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
          <key>Name</key><string>No Capacity</string>
          <key>Type</key><string>Accessory Source</string>
        </dict>
        </plist>
        """).isEmpty)
    }

    /// One document that does not decode must not cost the readings that do:
    /// this source is a refinement, so a partial read is still worth having.
    @Test("An undecodable document does not take the readable ones with it")
    func dropsAnUndecodableDocumentOnly() {
        let levels = BluetoothAccessoryBatteryReader.parse(xml: report + """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict><key>Name</key><string>Truncated</string>
        """)

        #expect(levels.count == 2)
    }

    @Test("An empty or unreported answer reads as no accessory")
    func emptyReportReadsAsNoAccessory() {
        #expect(BluetoothAccessoryBatteryReader.parse(xml: "").isEmpty)
        #expect(BluetoothAccessoryBatteryReader.parse(xml: "no plist here").isEmpty)
    }

    // MARK: - The worker

    /// A spawn that fails is not an empty report: the read answers with nothing,
    /// so the controller can tell "could not read" from "no accessory has a
    /// level".
    @Test("A failed spawn answers with nothing")
    func failedSpawnAnswersWithNothing() async {
        let worker = PmsetAccessoryBatteryWorker(outputProvider: { nil })

        let result = AccessoryLevelBox()
        worker.read { result.set($0) }
        await waitUntil { result.hasAnswered }

        #expect(result.value == nil)
    }

    @Test("The worker parses the output it fetched")
    func workerParsesItsOwnOutput() async {
        let worker = PmsetAccessoryBatteryWorker(outputProvider: { [report] in report })

        let result = AccessoryLevelBox()
        worker.read { result.set($0) }
        await waitUntil { result.hasAnswered }

        #expect(result.value?.count == 2)
    }

    // MARK: - Bounded subprocess

    /// The reader must not inherit the raw `readDataToEndOfFile()` +
    /// `waitUntilExit()` hang: a child that never exits has to be killed near the
    /// deadline and read as "no accessory", not block the serial queue for good.
    @Test("The pmset read is bounded: a hung child times out and answers nil")
    func hungChildTimesOut() {
        let started = Date()
        let output = PmsetAccessoryBatteryWorker.readAccessoryPowerSources(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["30"],
            timeout: .milliseconds(300)
        )
        let elapsed = Date().timeIntervalSince(started)

        #expect(output == nil)
        #expect(elapsed < 10, "a hung child must be killed near the deadline, not block for good")
    }

    @Test("A non-zero exit answers nil, not an empty report")
    func nonZeroExitAnswersNil() {
        let output = PmsetAccessoryBatteryWorker.readAccessoryPowerSources(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "exit 3"],
            timeout: .seconds(4)
        )

        #expect(output == nil)
    }

    @Test("The bounded read returns what the child wrote on success")
    func boundedReadReturnsStdout() {
        let output = PmsetAccessoryBatteryWorker.readAccessoryPowerSources(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'hello'"],
            timeout: .seconds(4)
        )

        #expect(output == "hello")
    }

    // MARK: - Fixtures

    /// Three documents in the shape the system prints them: the Mac's own
    /// battery, a keyboard with no part, and earbuds reporting their left part.
    private var report: String {
        document(type: "InternalBattery", current: 80, maximum: 100, name: "InternalBattery-0")
            + document(
                type: "Accessory Source",
                current: 100,
                maximum: 100,
                name: "MX Keys",
                vendorID: 1133,
                productID: 45915,
                identifier: "63F146B5-8E90-CDEB-598D-C2E98CBB8779",
                extra: ["Accessory Category": "Mouse", "Transport Type": "Bluetooth LE"]
            )
            + document(
                type: "Accessory Source",
                current: 93,
                maximum: 100,
                name: "机灵的耳机",
                vendorID: 76,
                productID: 8207,
                identifier: "E0CA918B-FC5E-C942-B6C3-23F27810A34F",
                extra: [
                    "Accessory Category": "Headset",
                    "Part Identifier": "Left",
                    "Group Identifier": "9CF8643F-CD3D-45F4-39CE-54867521EC20"
                ]
            )
    }

    private func document(
        type: String,
        current: Int,
        maximum: Int,
        name: String = "Accessory",
        vendorID: Int? = nil,
        productID: Int? = nil,
        identifier: String? = nil,
        extra: [String: String] = [:]
    ) -> String {
        var entries: [(String, String)] = [
            ("Current Capacity", "<integer>\(current)</integer>"),
            ("Max Capacity", "<integer>\(maximum)</integer>"),
            ("Name", "<string>\(name)</string>"),
            ("Type", "<string>\(type)</string>")
        ]
        if let vendorID {
            entries.append(("Vendor ID", "<integer>\(vendorID)</integer>"))
        }
        if let productID {
            entries.append(("Product ID", "<integer>\(productID)</integer>"))
        }
        if let identifier {
            entries.append(("Accessory Identifier", "<string>\(identifier)</string>"))
        }
        for (key, value) in extra.sorted(by: { $0.key < $1.key }) {
            entries.append((key, "<string>\(value)</string>"))
        }

        let body = entries
            .sorted { $0.0 < $1.0 }
            .map { "  <key>\($0.0)</key>\n  \($0.1)" }
            .joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
        \(body)
        </dict>
        </plist>

        """
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Timed out waiting for the accessory read")
    }
}

/// The worker answers on its own serial queue, so the test collects the result
/// and the answered flag behind a lock.
private final class AccessoryLevelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [BluetoothAccessoryBatteryLevel]?
    private var answered = false

    var value: [BluetoothAccessoryBatteryLevel]? { lock.withLock { stored } }
    /// A read that answered with nothing still answered, so waiting on
    /// `value != nil` would never finish for a failed read.
    var hasAnswered: Bool { lock.withLock { answered } }

    func set(_ levels: [BluetoothAccessoryBatteryLevel]?) {
        lock.withLock {
            stored = levels
            answered = true
        }
    }
}
