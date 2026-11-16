import Foundation
import Testing
@testable import StatusTrioCore

/// `pmset` can name a Magic Mouse by Bluetooth address, not only by UUID.
struct BluetoothAccessoryBatteryIdentityTests {
    private func mouse(_ address: String, connected: Bool = true, product: Int = 0x030d) -> BluetoothDevice {
        BluetoothDevice(id: address, name: "Magic Mouse", kind: .peripheral(.mouse),
                        isConnected: connected, vendorID: 0x004c, productID: product)
    }

    private func reading(_ identifier: String, product: Int = 0x030d) -> BluetoothAccessoryBatteryLevel {
        BluetoothAccessoryBatteryLevel(identifier: identifier, name: "Magic Mouse",
                                       vendorID: 0x004c, productID: product, part: nil, percentage: 98)
    }

    @Test func exactMACResolvesConnectedMouseDespiteSameModelNeighbour() {
        let connected = mouse("02:00:00:00:00:01")
        let disconnected = mouse("02:00:00:00:00:02", connected: false)
        let levels = BluetoothBatteryLevelFallback.merged(
            levels: [:], accessories: [reading("02-00-00-00-00-01")], devices: [connected, disconnected])
        #expect(levels[BluetoothBatteryReader.normalizedAddress(connected.id)]?.main == 98)
        #expect(levels[BluetoothBatteryReader.normalizedAddress(disconnected.id)] == nil)
    }

    @Test func explicitUnmatchedMACNeverFallsBackToSingleSameModelMouse() {
        let connected = mouse("02:00:00:00:00:01")
        let levels = BluetoothBatteryLevelFallback.merged(
            levels: [:], accessories: [reading("02:00:00:00:00:02")], devices: [connected])
        #expect(levels.isEmpty)
    }

    @Test func disconnectedExactMACCannotDonateBattery() {
        let connected = mouse("02:00:00:00:00:01")
        let disconnected = mouse("02:00:00:00:00:02", connected: false)
        let levels = BluetoothBatteryLevelFallback.merged(
            levels: [:], accessories: [reading(disconnected.id)], devices: [connected, disconnected])
        #expect(levels.isEmpty)
    }

    @Test func conflictingModelRefusesExactMAC() {
        let connected = mouse("02:00:00:00:00:01")
        let levels = BluetoothBatteryLevelFallback.merged(
            levels: [:], accessories: [reading(connected.id, product: 999)], devices: [connected])
        #expect(levels.isEmpty)
    }
}
