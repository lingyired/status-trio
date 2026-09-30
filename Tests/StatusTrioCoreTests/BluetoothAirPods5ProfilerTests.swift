import Foundation
import Testing
@testable import StatusTrioCore

struct BluetoothAirPods5ProfilerTests {
    @Test("system_profiler product IDs identify renamed AirPods 5 devices")
    func parsesRenamedAirPodsFive() throws {
        let json = #"""
        {
          "SPBluetoothDataType": [
            {
              "device_connected": [
                {
                  "My Earbuds": {
                    "device_address": "AA:BB:CC:DD:EE:FF",
                    "device_minorType": "Headphones",
                    "device_productID": "0x2030",
                    "device_vendorID": "0x004C"
                  }
                }
              ]
            }
          ]
        }
        """#

        let devices = try #require(BluetoothPairedDeviceReader.parse(json: Data(json.utf8)))
        let device = try #require(devices.first)

        #expect(device.name == "My Earbuds")
        #expect(device.kind == .audio)
        #expect(device.isConnected)
        #expect(device.airPodsModel == .airPodsGen5)
        #expect(device.productID == 0x2030)
        #expect(device.vendorID == 0x004C)
        #expect(device.appleBluetoothAudioDiagnostic == nil)
        #expect(BluetoothDeviceRowIcon.symbolName(for: device).isEmpty == false)
    }

    @Test("Unknown Apple audio product IDs retain structured profiler metadata")
    func retainsUnknownAppleAudioMetadata() throws {
        let json = #"""
        {
          "SPBluetoothDataType": [{
            "device_connected": [{
              "Renamed Headphones": {
                "device_address": "AA:BB:CC:DD:EE:FF",
                "device_majorType": "Audio",
                "device_minorType": "Headphones",
                "device_productID": "0x2042",
                "device_vendorID": "0x004C"
              }
            }]
          }]
        }
        """#

        let device = try #require(BluetoothPairedDeviceReader.parse(json: Data(json.utf8))?.first)
        let record = try #require(device.appleBluetoothAudioDiagnostic)

        #expect(record.source == .bluetooth)
        #expect(record.name == "Renamed Headphones")
        #expect(record.address == "AA:BB:CC:DD:EE:FF")
        #expect(record.vendorID == 0x004C)
        #expect(record.productID == 0x2042)
        #expect(record.minorType == "Headphones")
    }

    @Test("CoreAudio model UIDs share the resolver for AirPods 5")
    func coreAudioModelUIDResolvesAirPodsFive() {
        let identity = AudioDeviceIdentity(
            coreAudio: "My Earbuds",
            transport: .bluetooth,
            dataSource: nil,
            modelUID: "2036 4c"
        )

        #expect(identity.airPodsModel == .airPodsGen5)
        #expect(AudioOutputDeviceIcon.kind(for: identity) == .airPodsGen5)
    }
}
