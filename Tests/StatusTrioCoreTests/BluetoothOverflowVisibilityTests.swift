import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct BluetoothOverflowVisibilityTests {
    @Test func overflowKeepsMainLimitAndStableRemainder() {
        let devices = (1...5).map(device)
        let partition = BluetoothDeviceList.partition(devices, limit: 2)

        #expect(partition.main.map(\.id) == devices.prefix(2).map(\.id))
        #expect(partition.overflow.map(\.id) == devices.dropFirst(2).map(\.id))
        #expect(BluetoothDeviceList.partition(devices, limit: 0).overflow == devices)
        #expect(BluetoothDeviceList.partition([], limit: 2).main.isEmpty)
    }

    @Test func onlyClippedVisibleCanonicalRowsAuthorizeTheirSourceAliases() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let clippedID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let appleID = AppleDeviceID.trustedDevice("phone")
        let rows = [
            BluetoothDisplayRow(device: device(1), sourceIDs: [BluetoothDeviceIdentity.bleRowID(firstID), appleID.rowID]),
            BluetoothDisplayRow(device: device(2), sourceIDs: [BluetoothDeviceIdentity.bleRowID(clippedID)])
        ]
        let demand = BluetoothDeviceList.VisibilityDemand.visible(
            rows: rows,
            frames: [rows[0].device.id: CGRect(x: 0, y: 0, width: 200, height: 24),
                     rows[1].device.id: CGRect(x: 0, y: 60, width: 200, height: 24)],
            viewport: CGRect(x: 0, y: 0, width: 200, height: 40),
            appleRowIDs: [appleID.rowID: appleID]
        )

        #expect(demand.nearbyIDs == [firstID])
        #expect(demand.appleIDs == [appleID])
        #expect(BluetoothDeviceList.VisibilityDemand.visible(
            rows: rows, frames: [:], viewport: .zero, appleRowIDs: [appleID.rowID: appleID]
        ) == .init())
    }

    @Test func closingOverflowRestoresOnlyMainDemandAndIgnoresLateChildReports() {
        let mainID = UUID()
        let childID = UUID()
        let mainApple = AppleDeviceID.trustedDevice("main")
        let childApple = AppleDeviceID.trustedDevice("child")
        let main = BluetoothDeviceList.VisibilityDemand(nearbyIDs: [mainID], appleIDs: [mainApple])
        let child = BluetoothDeviceList.VisibilityDemand(nearbyIDs: [childID], appleIDs: [childApple])

        #expect(BluetoothDeviceList.VisibilityDemand.combining(
            main: main, overflow: child, isOverflowPresented: false
        ) == main)
        #expect(BluetoothDeviceList.VisibilityDemand.combining(
            main: main, overflow: child, isOverflowPresented: true
        ) == .init(nearbyIDs: [mainID, childID], appleIDs: [mainApple, childApple]))
        #expect(BluetoothDeviceList.VisibilityDemand.combining(
            main: .init(), overflow: .init(), isOverflowPresented: false
        ) == .init())
    }

    private func device(_ index: Int) -> BluetoothDevice {
        BluetoothDevice(id: "AA:00:00:00:00:0\(index)", name: "Device \(index)", kind: .unknown, isConnected: false)
    }
}
