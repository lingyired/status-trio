import Foundation
import Testing
@testable import StatusTrioCore

struct MobileBatteryDeviceMergeTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(
        id: String,
        parentID: String? = nil,
        name: String? = nil,
        model: String = "iPhone14,3",
        level: Int = 61,
        charging: Bool? = false,
        transport: MobileBatteryTransport = .usb,
        observedAt: Date? = nil
    ) -> MobileBatterySnapshot {
        MobileBatterySnapshot(
            id: id,
            parentID: parentID,
            name: name,
            model: model,
            batteryLevel: level,
            isCharging: charging,
            transport: transport,
            observedAt: observedAt ?? now
        )
    }

    private func paired(
        id: String,
        name: String,
        kind: BluetoothDeviceKind = .unknown
    ) -> BluetoothDevice {
        BluetoothDevice(id: id, name: name, kind: kind, isConnected: true)
    }

    private func nearby(name: String, model: String, level: Int) -> NearbyBluetoothBatteryDevice {
        NearbyBluetoothBatteryDevice(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            name: name,
            batteryLevel: level,
            model: model,
            manufacturer: "Apple Inc.",
            lastUpdated: now
        )
    }

    @Test func addsUnnamedWatchWithFallbackAndReadOnlyExternalIdentity() {
        let watch = snapshot(id: "watch-1", parentID: "phone-1", model: "Watch7,1")
        let result = MobileBatteryDeviceMerge.merged(
            devices: [], batteryLevels: [:], nearbyDevices: [],
            mobileSnapshots: [watch], fallbackWatchName: "Apple Watch"
        )

        #expect(result.devices.count == 1)
        #expect(result.devices[0].kind == .mobile(.watch))
        #expect(result.devices[0].name == "Apple Watch")
        #expect(result.devices[0].id.hasPrefix("mobile-"))
        #expect(!result.devices[0].isConnected)
        #expect(result.devices[0].isReadOverTheAir)
        #expect(result.mobileMetadataByDeviceID[result.devices[0].id] == watch)
        #expect(result.batteryLevels[BluetoothBatteryReader.normalizedAddress(result.devices[0].id)]?.main == 61)
    }

    @Test func pairedBatteryWinnerKeepsItsValueWithoutMobileMetadata() {
        let phone = paired(id: "AA-BB", name: "Lina’s iPhone", kind: .mobile(.phone))
        let pairedLevel = BluetoothBatteryLevel(deviceAddress: phone.id, main: 88, left: nil, right: nil, caseLevel: nil)
        let watchWithSameName = snapshot(id: "phone-1", name: "Lina’s iPhone", level: 31)
        let result = MobileBatteryDeviceMerge.merged(
            devices: [phone], batteryLevels: ["AABB": pairedLevel], nearbyDevices: [],
            mobileSnapshots: [watchWithSameName], fallbackWatchName: "Apple Watch"
        )

        #expect(result.devices.count == 1)
        #expect(result.batteryLevels["AABB"] == pairedLevel)
        #expect(result.devices[0].kind == .mobile(.phone))
        #expect(result.mobileMetadataByDeviceID[phone.id] == nil)
        #expect(result.mobileDeviceIDs.contains(phone.id))
    }

    @Test func exactStableIdentityWinsWhenTheNameIsAmbiguous() {
        let snapshot = snapshot(id: "phone-1", name: "Same phone")
        let identityMatch = paired(id: "phone:phone-1", name: "Same phone", kind: .mobile(.phone))
        let otherSameName = paired(id: "AA-BB", name: "Same phone", kind: .mobile(.phone))
        let result = MobileBatteryDeviceMerge.merged(
            devices: [identityMatch, otherSameName], batteryLevels: [:], nearbyDevices: [],
            mobileSnapshots: [snapshot], fallbackWatchName: "Apple Watch"
        )

        #expect(result.devices.count == 2)
        #expect(result.mobileMetadataByDeviceID[identityMatch.id] == snapshot)
        #expect(result.mobileMetadataByDeviceID[otherSameName.id] == nil)
        #expect(result.batteryLevels["EE1"]?.main == 61)
    }

    @Test func stableIdentityReservesItsRowBeforeNameMatchingInEitherInputOrder() {
        for stableDeviceID in ["phone:a", "phone:z"] {
            let exactID = stableDeviceID.replacingOccurrences(of: "phone:", with: "")
            let nameMatchedSnapshot = snapshot(id: exactID == "a" ? "z" : "a", name: "Shared phone", level: 22)
            let identitySnapshot = snapshot(id: exactID, name: nil, level: 88)
            let identityRow = paired(id: stableDeviceID, name: "Shared phone", kind: .mobile(.phone))

            for snapshots in [[nameMatchedSnapshot, identitySnapshot], [identitySnapshot, nameMatchedSnapshot]] {
                let result = MobileBatteryDeviceMerge.merged(
                    devices: [identityRow], batteryLevels: [:], nearbyDevices: [],
                    mobileSnapshots: snapshots, fallbackWatchName: "Apple Watch"
                )

                #expect(result.devices.count == 2)
                #expect(result.devices[0].id == stableDeviceID)
                #expect(result.batteryLevels[BluetoothBatteryReader.normalizedAddress(stableDeviceID)]?.main == 88)
                let competingID = MobileBatteryDeviceMerge.externalDeviceID(for: nameMatchedSnapshot.identity)
                #expect(result.devices.contains { $0.id == competingID })
                #expect(result.batteryLevels[BluetoothBatteryReader.normalizedAddress(competingID)]?.main == 22)
            }
        }
    }

    @Test func pairedBatteryWinnerDoesNotShowMobileObservationMetadata() {
        let phone = paired(id: "phone:phone-1", name: "Lina’s iPhone", kind: .mobile(.phone))
        let pairedLevel = BluetoothBatteryLevel(deviceAddress: phone.id, main: 88, left: nil, right: nil, caseLevel: nil)
        let observation = snapshot(
            id: "phone-1", name: "Lina’s iPhone", level: 31, charging: true,
            observedAt: now.addingTimeInterval(900)
        )
        let result = MobileBatteryDeviceMerge.merged(
            devices: [phone], batteryLevels: [BluetoothBatteryReader.normalizedAddress(phone.id): pairedLevel],
            nearbyDevices: [], mobileSnapshots: [observation], fallbackWatchName: "Apple Watch"
        )

        #expect(result.batteryLevels[BluetoothBatteryReader.normalizedAddress(phone.id)] == pairedLevel)
        #expect(result.mobileMetadataByDeviceID[phone.id] == nil)
        #expect(result.mobileDeviceIDs.contains(phone.id))
    }

    @Test func uniqueBluetoothPhoneMatchUsesTrustedMobileLevelAndMetadata() {
        let blePhone = nearby(name: "Ling's iPhone", model: "iPhone14,3", level: 20)
        let snapshot = snapshot(id: "phone-1", name: "Ling's iPhone", level: 84)
        let result = MobileBatteryDeviceMerge.merged(
            devices: [], batteryLevels: [:], nearbyDevices: [blePhone],
            mobileSnapshots: [snapshot], fallbackWatchName: "Apple Watch"
        )

        #expect(result.devices.count == 1)
        #expect(result.devices[0].id == blePhone.id.uuidString)
        #expect(result.devices[0].isReadOverTheAir)
        #expect(result.batteryLevels.values.first?.main == 84)
        #expect(result.mobileMetadataByDeviceID[blePhone.id.uuidString] == snapshot)
        #expect(result.remainingNearby.isEmpty)
    }

    @Test func sameNameAcrossPhoneAndWatchFamiliesDoesNotMerge() {
        let watch = paired(id: "11-22", name: "Shared name", kind: .mobile(.watch))
        let phone = snapshot(id: "phone-1", name: "Shared name", model: "iPhone14,3")
        let result = MobileBatteryDeviceMerge.merged(
            devices: [watch], batteryLevels: [:], nearbyDevices: [],
            mobileSnapshots: [phone], fallbackWatchName: "Apple Watch"
        )

        #expect(result.devices.count == 2)
        #expect(result.devices[0].id == watch.id)
        #expect(result.devices[1].id.hasPrefix("mobile-"))
        #expect(result.mobileMetadataByDeviceID[watch.id] == nil)
        #expect(result.batteryLevels["1122"] == nil)
    }

    @Test func unknownBluetoothFamilyDoesNotAbsorbMobileReadingByName() {
        let unknown = paired(id: "11-22", name: "Ling's Watch")
        let watch = snapshot(
            id: "watch-1", parentID: "phone-1", name: "Ling's Watch", model: "Watch7,1", level: 42
        )
        let result = MobileBatteryDeviceMerge.merged(
            devices: [unknown], batteryLevels: [:], nearbyDevices: [],
            mobileSnapshots: [watch], fallbackWatchName: "Apple Watch"
        )

        #expect(result.devices.count == 2)
        #expect(result.devices[0].kind == .unknown)
        #expect(result.devices.dropFirst().contains { $0.isReadOverTheAir })
        #expect(result.mobileMetadataByDeviceID[unknown.id] == nil)
        #expect(result.batteryLevels["1122"] == nil)
    }

    @Test func namedWatchKeepsItsObservedName() {
        let watch = snapshot(id: "watch-1", parentID: "phone-1", name: "Office Watch", model: "Watch7,1")
        let result = MobileBatteryDeviceMerge.merged(
            devices: [], batteryLevels: [:], nearbyDevices: [],
            mobileSnapshots: [watch], fallbackWatchName: "Apple Watch"
        )

        #expect(result.devices.count == 1)
        #expect(result.devices[0].name == "Office Watch")
    }

    @Test func preservesAmbiguousSameNameWatchesAndBluetoothRowsSeparately() {
        let firstWatch = snapshot(id: "watch-1", parentID: "phone-1", name: "Watch", model: "Watch7,1", level: 42)
        let secondWatch = snapshot(id: "watch-1", parentID: "phone-2", name: "Watch", model: "Watch7,1", level: 73)
        let firstBluetooth = paired(id: "11-22", name: "Watch")
        let secondBluetooth = paired(id: "33-44", name: "Watch")
        let result = MobileBatteryDeviceMerge.merged(
            devices: [firstBluetooth, secondBluetooth], batteryLevels: [:], nearbyDevices: [],
            mobileSnapshots: [firstWatch, secondWatch], fallbackWatchName: "Apple Watch"
        )

        #expect(result.devices.count == 4)
        #expect(result.devices.filter { $0.isReadOverTheAir }.count == 2)
        #expect(result.mobileMetadataByDeviceID.count == 2)
        #expect(result.batteryLevels["1122"] == nil)
        #expect(result.batteryLevels["3344"] == nil)
    }

    @Test func deduplicatesTransportCopiesByIdentityUsingLatestObservation() {
        let wired = snapshot(id: "phone-1", name: "Phone", level: 30, transport: .usb, observedAt: now)
        let wireless = snapshot(
            id: "phone-1", name: "Phone", level: 47, transport: .network,
            observedAt: now.addingTimeInterval(5)
        )
        let result = MobileBatteryDeviceMerge.merged(
            devices: [], batteryLevels: [:], nearbyDevices: [],
            mobileSnapshots: [wired, wireless], fallbackWatchName: "Apple Watch"
        )

        #expect(result.devices.count == 1)
        #expect(result.mobileMetadataByDeviceID.count == 1)
        #expect(result.mobileMetadataByDeviceID.values.first == wireless)
        #expect(result.batteryLevels.values.first?.main == 47)
    }

    @Test func externalIdentifiersRemainDistinctAfterHexNormalization() {
        let first = snapshot(id: "watch-a", parentID: "phone-1", model: "Watch7,1")
        let second = snapshot(id: "watcg-a", parentID: "phone-1", model: "Watch7,1")
        #expect(BluetoothBatteryReader.normalizedAddress(first.identity) == BluetoothBatteryReader.normalizedAddress(second.identity))

        let result = MobileBatteryDeviceMerge.merged(
            devices: [], batteryLevels: [:], nearbyDevices: [],
            mobileSnapshots: [first, second], fallbackWatchName: "Apple Watch"
        )

        #expect(result.devices.count == 2)
        let keys = result.devices.map { BluetoothBatteryReader.normalizedAddress($0.id) }
        #expect(Set(keys).count == 2)
        #expect(result.batteryLevels[keys[0]]?.main == 61)
        #expect(result.batteryLevels[keys[1]]?.main == 61)

        let repeated = MobileBatteryDeviceMerge.merged(
            devices: [], batteryLevels: [:], nearbyDevices: [],
            mobileSnapshots: [first, second], fallbackWatchName: "Apple Watch"
        )
        #expect(repeated.devices.map(\.id) == result.devices.map(\.id))
    }

    @Test func bluetoothListOptionsStillFilterAndLimitExternalRows() {
        let snapshots = (1...3).map {
            snapshot(id: "phone-\($0)", name: "Phone \($0)", level: $0 * 10)
        }
        let result = MobileBatteryDeviceMerge.merged(
            devices: [], batteryLevels: [:], nearbyDevices: [],
            mobileSnapshots: snapshots, fallbackWatchName: "Apple Watch"
        )
        let hidden = BluetoothBatteryReader.normalizedAddress(result.devices[0].id)
        let options = BluetoothDeviceListOptions(
            showsList: true,
            maxVisibleDevices: 1,
            order: [],
            hidesGhostDevices: false,
            hiddenDeviceAddresses: [hidden],
            revealedGhostDeviceAddresses: []
        )
        let model = BluetoothDeviceListModel.make(
            devices: result.devices, order: [], limit: 1, isExpanded: false, options: options
        )

        #expect(model.orderedDevices.count == 2)
        #expect(model.visibleDevices.count == 1)
        #expect(model.canToggleExpansion)
    }
}
