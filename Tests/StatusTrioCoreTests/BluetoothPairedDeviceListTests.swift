import Foundation
import Testing
@testable import StatusTrioCore

/// `IOBluetoothDevice.nameOrAddress` returns a cached name that never picks up
/// a rename, so the paired list is read from the system profiler instead: the
/// same source the battery levels already come from.
struct BluetoothPairedDeviceListTests {
    private let connectedAndPaired = """
    {
      "SPBluetoothDataType": [
          {
            "device_connected": [
              {
                "机灵的AirPods": {
                  "device_address": "AC:90:85:C2:9C:1F",
                  "device_minorType": "Headphones",
                  "device_productID": "0x200F",
                  "device_vendorID": "0x004C"
                }
              }
            ],
            "device_not_connected": [
              {
                "MX Keys": {
                  "device_address": "D3:6D:6C:40:A3:2E",
                  "device_minorType": "Mouse"
                }
              }
            ]
          }
        ]
    }
    """

    /// The regression: a renamed device has to report its current name, which
    /// the IOBluetooth cache did not.
    @Test func reportsTheNameTheSystemCurrentlyUses() throws {
        let devices = try #require(
            BluetoothPairedDeviceReader.parse(json: Data(connectedAndPaired.utf8))
        )

        #expect(devices.count == 2)
        let airPods = try #require(devices.first { $0.id == "AC:90:85:C2:9C:1F" })
        #expect(airPods.name == "机灵的AirPods")
        #expect(airPods.isConnected)
        #expect(airPods.kind == .audio)
    }

    /// The profiler reports the paired device's product ID, which is what
    /// identifies the model when the name does not spell "AirPods". AirPods
    /// (2nd generation, A2031/A2032) is product `0x200F` from Apple.
    @Test func readsTheProductIDThatIdentifiesTheModel() throws {
        let devices = try #require(
            BluetoothPairedDeviceReader.parse(json: Data(connectedAndPaired.utf8))
        )

        let airPods = try #require(devices.first { $0.id == "AC:90:85:C2:9C:1F" })
        #expect(airPods.airPodsModel == .airPods)
        // The keyboard entry carries no product ID.
        let keyboard = try #require(devices.first { $0.id == "D3:6D:6C:40:A3:2E" })
        #expect(keyboard.airPodsModel == nil)
    }

    /// The paired list draws the AirPods glyph macOS declares for the model
    /// instead of the generic headphone glyph it drew for every audio device.
    @Test func airPodsRowDrawsTheDeclaredAirPodsGlyph() throws {
        let devices = try #require(
            BluetoothPairedDeviceReader.parse(json: Data(connectedAndPaired.utf8))
        )
        let airPods = try #require(devices.first { $0.id == "AC:90:85:C2:9C:1F" })

        #expect(BluetoothDeviceRowIcon.symbolName(for: airPods) == "airpods")
    }

    /// A user can rename their AirPods, so the row has to keep the AirPods
    /// glyph from the product ID rather than falling back to headphones.
    @Test func renamedAirPodsRowKeepsTheAirPodsGlyph() {
        let renamed = BluetoothDevice(
            id: "AC:90:85:C2:9C:1F",
            name: "小王的耳机",
            kind: .audio,
            isConnected: true,
            airPodsModel: .airPods
        )

        #expect(BluetoothDeviceRowIcon.symbolName(for: renamed) == "airpods")
    }

    /// Audio devices that are not AirPods keep the generic headphone glyph, a
    /// peripheral is drawn as the form it declares, and a class the report did
    /// not describe draws the generic radio rather than a question mark.
    @Test func otherRowsDrawTheGlyphTheirClassCallsFor() {
        #expect(
            BluetoothDeviceRowIcon.symbolName(
                for: BluetoothDevice(
                    id: "0C:AE:BD:FE:D7:C3",
                    name: "EDIFIER LolliPods 2022版",
                    kind: .audio,
                    isConnected: false
                )
            ) == "headphones"
        )
        #expect(
            BluetoothDeviceRowIcon.symbolName(
                for: BluetoothDevice(id: "D3:6D:6C:40:A3:2E", name: "MX Keys", kind: .peripheral(.keyboard), isConnected: true)
            ) == "keyboard"
        )
        #expect(
            BluetoothDeviceRowIcon.symbolName(
                for: BluetoothDevice(id: "AA:BB:CC:DD:EE:FF", name: "Mystery Device", kind: .unknown, isConnected: false)
            ) == BluetoothDeviceRowIcon.genericSymbol
        )
    }

    /// Paired devices keep the profiler's declared minor type regardless of
    /// connection state, even when the manufacturer mislabels them.
    @Test func keepsPairedButDisconnectedDevices() throws {
        let devices = try #require(
            BluetoothPairedDeviceReader.parse(json: Data(connectedAndPaired.utf8))
        )

        let keyboard = try #require(devices.first { $0.id == "D3:6D:6C:40:A3:2E" })
        #expect(keyboard.name == "MX Keys")
        #expect(keyboard.isConnected == false)
        #expect(keyboard.kind == .peripheral(.mouse))
    }

    @Test func normalizesTheAddressToMatchTheBatteryReader() throws {
        let devices = try #require(
            BluetoothPairedDeviceReader.parse(json: Data(connectedAndPaired.utf8))
        )

        let airPods = try #require(devices.first { $0.name == "机灵的AirPods" })
        #expect(BluetoothBatteryReader.normalizedAddress(airPods.id) == "AC9085C29C1F")
    }

    /// An unsupported minor type stays generic rather than being guessed as
    /// audio, which would make it eligible for a battery level.
    @Test func unknownMinorTypesStayGeneric() throws {
        let json = """
        {"SPBluetoothDataType": [{"device_connected": [
          {"Mystery Device": {"device_address": "AA:BB:CC:DD:EE:FF", "device_minorType": "Unknown"}}
        ]}]}
        """
        let devices = try #require(BluetoothPairedDeviceReader.parse(json: Data(json.utf8)))

        #expect(devices.first?.kind == .unknown)
        #expect(devices.first?.airPodsModel == nil)
    }

    @Test func majorTypeDrivesTheKindWhenTheMinorTypeIsMissing() throws {
        let json = """
        {"SPBluetoothDataType": [{"device_connected": [
          {"Generic Peripheral": {"device_address": "AA:BB:CC:DD:EE:FF", "device_majorType": "Peripheral"}}
        ]}]}
        """
        let devices = try #require(BluetoothPairedDeviceReader.parse(json: Data(json.utf8)))

        #expect(devices.first?.kind == .peripheral(.unclassified))
    }

    /// The regression: a report that carries one address twice drew the device
    /// twice, handed `ForEach` a duplicate id and shared one set of action state
    /// between the two rows. The connected entry is the one that survives —
    /// the collections are read connected-first, and it is the entry that
    /// matches the state the device is actually in. The address is compared
    /// normalized, so the two spellings in this report are still one device.
    @Test func aDeviceListedInBothCollectionsIsListedOnce() throws {
        let json = """
        {"SPBluetoothDataType": [{
          "device_connected": [
            {"机灵的AirPods": {"device_address": "AC:90:85:C2:9C:1F", "device_minorType": "Headphones"}}
          ],
          "device_not_connected": [
            {"小王的耳机": {"device_address": "ac:90:85:c2:9c:1f", "device_minorType": "Headphones"}}
          ]
        }]}
        """
        let devices = try #require(BluetoothPairedDeviceReader.parse(json: Data(json.utf8)))

        #expect(devices.count == 1)
        #expect(devices.first?.name == "机灵的AirPods")
        #expect(devices.first?.isConnected == true)
    }

    /// A Mac with more than one Bluetooth controller makes the profiler report a
    /// section per controller, and the parse reads every section: the same
    /// device would otherwise be listed once per controller.
    @Test func aDeviceReportedInTwoSectionsIsListedOnce() throws {
        let json = """
        {"SPBluetoothDataType": [
          {"device_connected": [
            {"MX Keys": {"device_address": "D3:6D:6C:40:A3:2E", "device_minorType": "Keyboard"}}
          ]},
          {"device_not_connected": [
            {"MX Keys": {"device_address": "D3:6D:6C:40:A3:2E", "device_minorType": "Keyboard"}}
          ]}
        ]}
        """
        let devices = try #require(BluetoothPairedDeviceReader.parse(json: Data(json.utf8)))

        #expect(devices.count == 1)
        #expect(devices.first?.isConnected == true)
    }

    /// Two addresses the normalizer cannot reduce are not necessarily one device,
    /// so they all stay listed rather than collapsing into each other.
    @Test func addressesWithoutAnIdentityAreAllKept() throws {
        let json = """
        {"SPBluetoothDataType": [{"device_connected": [
          {"One": {"device_address": "--", "device_minorType": "Keyboard"}},
          {"Two": {"device_address": "--", "device_minorType": "Keyboard"}}
        ]}]}
        """
        let devices = try #require(BluetoothPairedDeviceReader.parse(json: Data(json.utf8)))

        #expect(devices.count == 2)
    }

    /// No readable device database is a read failure, not "no paired devices".
    @Test func malformedOutputIsAReadFailure() {
        #expect(BluetoothPairedDeviceReader.parse(json: Data("not json".utf8)) == nil)
    }

    /// A machine that genuinely has no paired devices reports an empty list.
    @Test func emptyDatabaseIsAnEmptyList() throws {
        let json = """
        {"SPBluetoothDataType": [{"device_connected": [], "device_not_connected": []}]}
        """
        let devices = try #require(BluetoothPairedDeviceReader.parse(json: Data(json.utf8)))

        #expect(devices.isEmpty)
    }

    @Test func readerSurfacesProfilerOutput() async {
        let worker = SystemProfilerBluetoothPairedDeviceWorker {
            Data(self.connectedAndPaired.utf8)
        }
        let box = ResultBox()

        worker.read { box.set($0) }
        await waitUntil { box.value != nil }

        guard case .success(let devices) = box.value else {
            Issue.record("expected a successful read, got \(String(describing: box.value))")
            return
        }
        #expect(devices.contains { $0.name == "机灵的AirPods" })
    }

    @Test func readerReportsFailureWithoutProfilerOutput() async {
        let worker = SystemProfilerBluetoothPairedDeviceWorker { nil }
        let box = ResultBox()

        worker.read { box.set($0) }
        await waitUntil { box.value != nil }

        guard case .failed = box.value else {
            Issue.record("expected a read failure, got \(String(describing: box.value))")
            return
        }
    }

    /// The reader answers on its own serial queue.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Timed out waiting for the profiler read")
    }
}

/// The reader delivers on its own queue, so the test needs somewhere
/// thread-safe to collect the result.
private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: BluetoothWorkerResult?

    var value: BluetoothWorkerResult? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ result: BluetoothWorkerResult) {
        lock.lock()
        stored = result
        lock.unlock()
    }
}
