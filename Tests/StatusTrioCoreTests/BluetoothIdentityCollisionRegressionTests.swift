import Foundation
import Testing
@testable import StatusTrioCore

/// Synthetic identifiers reproduce the supplied case without asserting that
/// same-named Apple sources necessarily describe one physical device.
struct BluetoothIdentityCollisionRegressionTests {
    private func mouse(_ address: String, connected: Bool = true, product: Int = 0x030d) -> BluetoothDevice {
        BluetoothDevice(id: address, name: "Magic Mouse", kind: .peripheral(.mouse),
                        isConnected: connected, vendorID: 0x004c, productID: product)
    }

    @Test func hidingOneAddressAliasExpandsToTheWholeMergedRow() {
        let colon = mouse("02:00:00:00:00:01")
        let dash = mouse("02-00-00-00-00-01")
        let hidden = BluetoothDeviceListPresentation.expandedAliasIDs(
            forHiddenIDs: [BluetoothDeviceIdentity.preferenceKey(dash.id)], among: [colon, dash])
        #expect(Set([colon.id, dash.id]).isSubset(of: hidden))
    }

    @Test func renamingOneRecordDoesNotSplitAConfirmedAddress() {
        let original = mouse("02:00:00:00:00:01")
        let renamed = BluetoothDevice(
            id: "02-00-00-00-00-01", name: "My Mouse", kind: .peripheral(.mouse),
            isConnected: true, vendorID: 0x004c, productID: 0x030d)
        let rows = BluetoothDeviceListPresentation.sharedDisplayRows([original, renamed])
        #expect(rows.count == 1)
        #expect(rows.first?.sourceIDs.count == 2)
    }

    @Test func savedOrderOfEitherAliasRanksTheMergedRow() {
        let first = mouse("02:00:00:00:00:01")
        let second = mouse("02:00:00:00:00:02")
        let rows = BluetoothDeviceListPresentation.sharedDisplayRows([first, second])
        let ordered = BluetoothDeviceListPresentation.orderedDisplayRows(
            rows, using: [BluetoothDeviceIdentity.preferenceKey(second.id)])
        #expect(ordered.first?.device.id == second.id)
    }

    @Test func inputOrderDoesNotChangeRepresentativeOrIdentity() {
        let colon = mouse("02:00:00:00:00:01")
        let dash = BluetoothDevice(id: "02-00-00-00-00-01", name: "Magic Mouse",
                                   kind: .peripheral(.mouse), isConnected: true,
                                   vendorID: 0x004c, productID: 0x030d)
        let forward = BluetoothDeviceListPresentation.sharedDisplayRows([colon, dash])
        let reverse = BluetoothDeviceListPresentation.sharedDisplayRows([dash, colon])
        #expect(forward.map(\.device.id) == reverse.map(\.device.id))
        #expect(forward.map(\.sourceIDs) == reverse.map(\.sourceIDs))
    }

    @Test func nonAddressTextCannotBecomeAnAddressByDroppingCharacters() {
        let address = mouse("02:00:00:00:00:01")
        let invalid = mouse("xyz02:00:00:00:00:01")
        #expect(BluetoothDeviceListPresentation.sharedDisplayRows([address, invalid]).count == 2)
    }

    @Test func sameMACFormattingProducesOneDisplayIdentity() {
        let rows = BluetoothDeviceListPresentation.sharedDisplayRows([
            mouse("02:00:00:00:00:01"), mouse("02-00-00-00-00-01")])
        #expect(rows.count == 1)
        #expect(Set(rows.flatMap(\.sourceIDs)).count == 2)
    }

    @Test func identicalNamesModelsAndBatteryAreNotIdentity() {
        let rows = BluetoothDeviceListPresentation.sharedDisplayRows([
            mouse("02:00:00:00:00:01"), mouse("02:00:00:00:00:02")])
        #expect(rows.count == 2)
    }

    @Test func threeRecordsOfOneAddressCollapseToOneDisplayRow() {
        let rows = BluetoothDeviceListPresentation.sharedDisplayRows([
            mouse("02:00:00:00:00:01"), mouse("02-00-00-00-00-01", connected: false),
            mouse("020000000001")])
        #expect(rows.count == 1)
        #expect(rows.first?.sourceIDs.count == 3)
    }

    @Test func threeUnverifiedPhoneSourcesKeepSystemAddressSeparate() {
        let ble = BluetoothDevice(
            id: "ble:00000000-0000-0000-0000-000000000001", name: "Phone", kind: .mobile(.phone),
            isConnected: false, appleMobileModel: "iPhone18,1", isReadOverTheAir: true)
        let trusted = BluetoothDevice(
            id: AppleDeviceID.trustedDevice("phone-a").rowID, name: "Phone", kind: .mobile(.phone),
            isConnected: false, appleMobileModel: "iPhone18,1", isReadOverTheAir: true)
        let system = BluetoothDevice(
            id: "02:00:00:00:00:03", name: "Phone", kind: .mobile(.phone),
            isConnected: true, appleMobileModel: "iPhone18,1", isReadOverTheAir: false)
        let rows = BluetoothDeviceListPresentation.sharedDisplayRows([system, ble, trusted])
        // The legacy pair fold may combine the BLE and trusted row for display,
        // but the system address is never absorbed without a verified mapping.
        #expect(rows.contains { $0.sourceIDs == [system.id] })
        #expect(rows.allSatisfy { !$0.sourceIDs.contains(system.id) || $0.sourceIDs.count == 1 })
    }

    @Test func watchRowsCollapseOnlyOnParentAndWatchIdentity() {
        let sameIdentity = [0, 1].map { _ in
            BluetoothDevice(id: AppleDeviceID.trustedWatch(parentID: "parent", id: "watch").rowID,
                            name: "Watch", kind: .mobile(.watch), isConnected: false,
                            appleMobileModel: "Watch7,1", isReadOverTheAir: true) }
        #expect(BluetoothDeviceListPresentation.sharedDisplayRows(sameIdentity).count == 1)
    }

    @Test func sameWatchNameUnderDifferentParentsIsNotMerged() {
        let rows = BluetoothDeviceListPresentation.sharedDisplayRows(["parent-a", "parent-b"].map {
            BluetoothDevice(id: AppleDeviceID.trustedWatch(parentID: $0, id: "watch").rowID,
                            name: "Watch", kind: .mobile(.watch), isConnected: false,
                            appleMobileModel: "Watch7,1", isReadOverTheAir: true) })
        #expect(rows.count == 2)
    }

    @Test func twoTrustedPhonesWithSameNameRemainIndependent() {
        let devices = ["phone-a", "phone-b"].map {
            BluetoothDevice(id: AppleDeviceID.trustedDevice($0).rowID, name: "Phone", kind: .mobile(.phone),
                            isConnected: false, appleMobileModel: "iPhone18,1", isReadOverTheAir: true)
        }
        #expect(BluetoothDeviceListPresentation.sharedDisplayRows(devices).count == 2)
    }
}
