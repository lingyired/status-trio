import XCTest
@testable import StatusTrioCore

final class AirPodsBatterySourceTests: XCTestCase {
    func testAirPodsSelectionUsesExactBluetoothAddressAndNeverDisplayName() throws {
        let airPods = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:01", name: "Renamed headset", kind: .audio, isConnected: true,
            airPodsModel: .airPodsPro
        )
        let levels = [
            "AABBCCDDEE01": BluetoothBatteryLevel(deviceAddress: "AA:BB:CC:DD:EE:01", main: nil, left: 72, right: 68, caseLevel: 90),
            "AABBCCDDEE02": BluetoothBatteryLevel(deviceAddress: "AA:BB:CC:DD:EE:02", main: 10, left: nil, right: nil, caseLevel: nil)
        ]

        let selected = try XCTUnwrap(AirPodsBatteryIconSnapshot.resolve(
            devices: [airPods], levels: levels, selectedAddress: nil,
            observedAt: Date(timeIntervalSince1970: 10)
        ))

        XCTAssertEqual(selected.deviceAddress, "AABBCCDDEE01")
        XCTAssertEqual(selected.left, 72)
        XCTAssertEqual(selected.right, 68)
        XCTAssertEqual(selected.caseLevel, 90)
    }

    func testAmbiguousAirPodsRequireSelectionInsteadOfChoosingFirst() {
        let devices = ["01", "02"].map { address in
            BluetoothDevice(id: address, name: "AirPods", kind: .audio, isConnected: true, airPodsModel: .airPodsPro)
        }
        let levels = Dictionary(uniqueKeysWithValues: devices.map {
            (BluetoothBatteryReader.normalizedAddress($0.id), BluetoothBatteryLevel(deviceAddress: $0.id, main: 50, left: nil, right: nil, caseLevel: nil))
        })

        let result = AirPodsBatteryIconSnapshot.selection(
            devices: devices, levels: levels, selectedAddress: nil
        )

        XCTAssertEqual(result, .needsSelection)
    }

    func testSingleConnectedAirPodsCanBeSelectedWithoutAudioUIDMatching() {
        let device = BluetoothDevice(id: "AA:BB:CC:DD:EE:03", name: "Renamed", kind: .audio, isConnected: true, airPodsModel: .airPodsPro)
        let levels = ["AABBCCDDEE03": BluetoothBatteryLevel(deviceAddress: device.id, main: 40, left: 39, right: 41, caseLevel: nil)]

        let result = AirPodsBatteryIconSnapshot.selection(devices: [device], levels: levels, selectedAddress: nil)

        guard case let .selected(snapshot) = result else { return XCTFail("A sole connected AirPods device should be unambiguous") }
        XCTAssertEqual(snapshot.deviceAddress, "AABBCCDDEE03")
    }

    func testExplicitSelectionWinsWhenSeveralAirPodsAreConnected() throws {
        let devices = ["01", "02"].map { BluetoothDevice(id: $0, name: "AirPods", kind: .audio, isConnected: true, airPodsModel: .airPodsPro) }
        let levels = Dictionary(uniqueKeysWithValues: devices.map {
            (BluetoothBatteryReader.normalizedAddress($0.id), BluetoothBatteryLevel(deviceAddress: $0.id, main: 50, left: nil, right: nil, caseLevel: nil))
        })

        let selected = try XCTUnwrap(AirPodsBatteryIconSnapshot.resolve(
            devices: devices, levels: levels, selectedAddress: "02", observedAt: .distantPast
        ))

        XCTAssertEqual(selected.deviceAddress, "02")
    }
}
