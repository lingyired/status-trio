import XCTest
@testable import StatusTrioCore

final class BluetoothDeviceListPresentationTests: XCTestCase {
    func testSharedProjectionDeduplicatesOnlyOneUnambiguousCompatibleCrossSourcePair() {
        let bleID = UUID(uuidString: "00000000-0000-0000-0000-000000000091")!
        let ble = BluetoothDevice(
            id: BluetoothDeviceIdentity.bleRowID(bleID), name: "Phone", kind: .mobile(.phone),
            isConnected: false, appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )
        let trusted = BluetoothDevice(
            id: "trusted:phone", name: " phone ", kind: .mobile(.phone),
            isConnected: false, appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )

        let projection = BluetoothDeviceListPresentation.sharedDisplayRows([ble, trusted])

        XCTAssertEqual(projection.map(\.device.id), [ble.id])
        XCTAssertEqual(projection.first?.sourceIDs.sorted(), [ble.id, trusted.id].sorted())
    }

    func testSharedProjectionMergesPairRegardlessOfInputOrderAndUsesEitherAliasRank() {
        let bleID = UUID(uuidString: "00000000-0000-0000-0000-000000000095")!
        let ble = BluetoothDevice(
            id: BluetoothDeviceIdentity.bleRowID(bleID), name: "Phone", kind: .mobile(.phone),
            isConnected: false, appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )
        let trusted = BluetoothDevice(
            id: AppleDeviceID.trustedDevice("phone").rowID,
            name: "Phone", kind: .mobile(.phone), isConnected: false,
            appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )
        let forward = BluetoothDeviceListPresentation.sharedDisplayRows([ble, trusted])
        let reverse = BluetoothDeviceListPresentation.sharedDisplayRows([trusted, ble])

        XCTAssertEqual(forward.count, 1)
        XCTAssertEqual(reverse.count, 1)
        XCTAssertEqual(forward.first?.sourceIDs.sorted(), reverse.first?.sourceIDs.sorted())
        XCTAssertEqual(reverse.first?.device.id, ble.id)
        let ordered = BluetoothDeviceListPresentation.orderedDisplayRows(
            reverse,
            using: [trusted.id, ble.id]
        )
        XCTAssertEqual(ordered.first?.device.id, ble.id)
    }

    func testSharedProjectionChoosesNewestValidReadingWithoutUsingBatteryEqualityAsIdentity() {
        let bleID = UUID(uuidString: "00000000-0000-0000-0000-000000000098")!
        let ble = BluetoothDevice(
            id: BluetoothDeviceIdentity.bleRowID(bleID), name: "Phone", kind: .mobile(.phone),
            isConnected: false, appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )
        let trusted = BluetoothDevice(
            id: AppleDeviceID.trustedDevice("phone").rowID,
            name: "Phone", kind: .mobile(.phone), isConnected: false,
            appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )
        let oldBLE = NearbyBluetoothBatteryDevice(id: bleID, name: "Phone", batteryLevel: 18,
                                                  model: "iPhone18,1", manufacturer: nil,
                                                  lastUpdated: Date(timeIntervalSince1970: 100))
        let newerTrusted = MobileBatterySnapshot(
            id: "phone", parentID: nil, name: "Phone", model: "iPhone18,1",
            batteryLevel: 20, isCharging: false, transport: .usb,
            observedAt: Date(timeIntervalSince1970: 200)
        )
        let displayPair = BluetoothDeviceListPresentation.sharedDisplayRows([trusted, ble]).first!
        let bleRow = NearbyBLEPanelRow(id: bleID, device: ble, batteryLevel: 18,
                                       wasSeenRecently: false, readFailed: false,
                                       observedAt: Date(timeIntervalSince1970: 100))

        let newerBLE = NearbyBluetoothBatteryDevice(id: bleID, name: "Phone", batteryLevel: 18,
                                                    model: "iPhone18,1", manufacturer: nil,
                                                    lastUpdated: Date(timeIntervalSince1970: 250))
        let olderTrusted = MobileBatterySnapshot(
            id: "phone", parentID: nil, name: "Phone", model: "iPhone18,1",
            batteryLevel: 20, isCharging: false, transport: .usb,
            observedAt: Date(timeIntervalSince1970: 200)
        )
        XCTAssertEqual(BluetoothDeviceListPresentation.newestValidReading(
            for: displayPair, nearbyReadings: [newerBLE], nearbyRows: [bleRow],
            trustedSnapshots: [olderTrusted], now: Date(timeIntervalSince1970: 300)
        )?.level, 18, "live BLE lastUpdated must outrank the panel row's older timestamp")
        XCTAssertEqual(BluetoothDeviceListPresentation.newestValidReading(
            for: displayPair, nearbyReadings: [oldBLE], nearbyRows: [bleRow],
            trustedSnapshots: [newerTrusted], now: Date(timeIntervalSince1970: 300)
        )?.level, 20, "a genuinely newer trusted snapshot must outrank older BLE data")
        XCTAssertEqual(BluetoothDeviceListPresentation.newestValidReading(
            for: displayPair, nearbyReadings: [], nearbyRows: [
                NearbyBLEPanelRow(id: bleID, device: ble, batteryLevel: 17, wasSeenRecently: false,
                                  readFailed: false, observedAt: Date(timeIntervalSince1970: 250))
            ], trustedSnapshots: [olderTrusted], now: Date(timeIntervalSince1970: 300)
        )?.level, 17, "a fresh retained panel reading remains usable when no live cache exists")
        XCTAssertNil(BluetoothDeviceListPresentation.newestValidReading(
            for: displayPair,
            nearbyReadings: [NearbyBluetoothBatteryDevice(id: bleID, name: "Phone", batteryLevel: 18,
                                                          model: "iPhone18,1", manufacturer: nil,
                                                          lastUpdated: Date(timeIntervalSince1970: 301))],
            nearbyRows: [], trustedSnapshots: [], now: Date(timeIntervalSince1970: 300)
        ), "future timestamps are not fresh")
        XCTAssertNil(BluetoothDeviceListPresentation.newestValidReading(
            for: displayPair,
            nearbyReadings: [NearbyBluetoothBatteryDevice(id: bleID, name: "Phone", batteryLevel: 150,
                                                          model: "iPhone18,1", manufacturer: nil,
                                                          lastUpdated: Date(timeIntervalSince1970: 290))],
            nearbyRows: [],
            trustedSnapshots: []
        ))
        let unrelated = BluetoothDisplayRow(device: ble, sourceIDs: [ble.id])
        XCTAssertNil(BluetoothDeviceListPresentation.newestValidReading(
            for: unrelated,
            nearbyReadings: [],
            nearbyRows: [],
            trustedSnapshots: [newerTrusted]
        ))
    }

    func testRowStatusUsesCanonicalReadingBeforeSourceFallback() {
        let device = BluetoothDevice(
            id: "ble:00000000-0000-0000-0000-000000000098", name: "Phone", kind: .mobile(.phone),
            isConnected: false, appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )

        XCTAssertEqual(BluetoothDeviceListPresentation.externalBatteryStatus(
            for: device, canonicalStatus: .battery(20), nearbyStatus: .battery(18), appleStatus: nil
        ), .battery(20))
        XCTAssertEqual(BluetoothDeviceListPresentation.externalBatteryStatus(
            for: device, canonicalStatus: .battery(18), nearbyStatus: .battery(20), appleStatus: nil
        ), .battery(18))
        XCTAssertEqual(BluetoothDeviceListPresentation.externalBatteryStatus(
            for: device, canonicalStatus: nil, nearbyStatus: .pending, appleStatus: nil
        ), .pending)
        XCTAssertNil(BluetoothDeviceListPresentation.externalBatteryStatus(
            for: device, canonicalStatus: nil, nearbyStatus: .unavailable, appleStatus: nil
        ))
        XCTAssertNil(BluetoothDeviceListPresentation.externalBatteryStatus(
            for: device, canonicalStatus: nil, nearbyStatus: .notNearby, appleStatus: nil
        ))
    }

    func testSettingsProjectionUsesSharedPairingAndAliasAwareOrdering() {
        let bleID = UUID(uuidString: "00000000-0000-0000-0000-000000000096")!
        let ble = BluetoothDevice(
            id: BluetoothDeviceIdentity.bleRowID(bleID), name: "Phone", kind: .mobile(.phone),
            isConnected: false, appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )
        let trusted = BluetoothDevice(
            id: "trusted:phone", name: "Phone", kind: .mobile(.phone), isConnected: false,
            appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )
        let rows = BluetoothDeviceListPresentation.settingsDisplayRows(
            [trusted, ble], order: [trusted.id, ble.id], options: .standard
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.device.id, ble.id)
        XCTAssertEqual(rows.first?.sourceIDs.sorted(), [ble.id, trusted.id].sorted())
    }

    func testSettingsProjectionHidesAndRestoresBothPairAliases() {
        let bleID = UUID(uuidString: "00000000-0000-0000-0000-000000000097")!
        let ble = BluetoothDevice(
            id: BluetoothDeviceIdentity.bleRowID(bleID), name: "Phone", kind: .mobile(.phone),
            isConnected: false, appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )
        let trusted = BluetoothDevice(
            id: "trusted:phone", name: "Phone", kind: .mobile(.phone), isConnected: false,
            appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )
        let pair = try! XCTUnwrap(BluetoothDeviceListPresentation.settingsDisplayRows(
            [trusted, ble], order: [], options: .standard
        ).first)
        let hidden = BluetoothDeviceListPresentation.expandedAliasIDs(
            forHiddenIDs: [trusted.id], among: [trusted, ble]
        )
        XCTAssertEqual(Set(pair.sourceIDs).subtracting(hidden).count, 0)
        XCTAssertEqual(BluetoothDeviceListPresentation.settingsDisplayRows(
            [trusted, ble], order: [], options: .standard
        ).count, 1, "removing the hide restores the same canonical row")
    }

    func testSharedProjectionKeepsAmbiguousOrBatteryOnlyNameMatchesSeparate() {
        let bleID = UUID(uuidString: "00000000-0000-0000-0000-000000000092")!
        let ble = BluetoothDevice(
            id: BluetoothDeviceIdentity.bleRowID(bleID), name: "Phone", kind: .unknown,
            isConnected: false, isReadOverTheAir: true
        )
        let first = BluetoothDevice(
            id: "trusted:phone-a", name: "Phone", kind: .mobile(.phone), isConnected: false,
            appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )
        let second = BluetoothDevice(
            id: "trusted:phone-b", name: "phone", kind: .mobile(.phone), isConnected: false,
            appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )

        XCTAssertEqual(BluetoothDeviceListPresentation.sharedDisplayRows([ble, first, second]).count, 3)
        XCTAssertEqual(BluetoothDeviceListPresentation.sharedDisplayRows([ble, first]).count, 2)
    }

    func testSharedProjectionPreservesBothAliasIDsAndHonorsHideFromEitherSource() {
        let bleID = UUID(uuidString: "00000000-0000-0000-0000-000000000093")!
        let ble = BluetoothDevice(
            id: BluetoothDeviceIdentity.bleRowID(bleID), name: "Phone", kind: .mobile(.phone),
            isConnected: false, appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )
        let trusted = BluetoothDevice(
            id: "trusted:phone", name: "Phone", kind: .mobile(.phone), isConnected: false,
            appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )
        let pair = BluetoothDeviceListPresentation.sharedDisplayRows([ble, trusted]).first
        XCTAssertEqual(pair?.sourceIDs.sorted(), [ble.id, trusted.id].sorted())

        XCTAssertEqual(BluetoothDeviceListPresentation.expandedAliasIDs(
            forHiddenIDs: [trusted.id], among: [ble, trusted]
        ), Set([ble.id, trusted.id]))
    }

    func testSourceCatalogsHideBothCompatibleAliasesBeforeSharedRowsMerge() {
        let bleID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let now = Date()
        let ble = BluetoothDevice(
            id: BluetoothDeviceIdentity.bleRowID(bleID), name: "Phone", kind: .mobile(.phone),
            isConnected: false, appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )
        let trustedCandidate = AppleDeviceCandidate(
            id: .trustedDevice("phone-b"), name: "Phone", model: "iPhone18,1",
            transports: [.usb], trustRequired: false, evidence: .verifiedAppleModel
        )
        let trusted = BluetoothDevice(
            id: trustedCandidate.id.rowID, name: trustedCandidate.name, kind: .mobile(.phone),
            isConnected: false, appleMobileModel: trustedCandidate.model, isReadOverTheAir: true
        )
        let selection = NearbyBLEDeviceSelection(
            id: bleID, name: "Phone", vendor: .apple, model: "iPhone18,1",
            batteryLevel: 50, batteryLastUpdated: now
        )

        for hiddenID in [ble.id, trustedCandidate.id.rowID] {
            let options = BluetoothDeviceListOptions(
                showsList: true, maxVisibleDevices: 5, order: [],
                hiddenDeviceAddresses: [hiddenID]
            )
            let sourceOptions = BluetoothDeviceListPresentation.expandingHiddenAliases(
                in: options, among: [ble, trusted]
            )
            let appleRows = AppleDeviceCatalog.projection(
                candidates: [trustedCandidate], trustedSnapshots: [], options: sourceOptions
            ).rows
            let nearbyRows = NearbyBLEDeviceCatalog.panelRows(
                selections: [selection], readings: [], failures: [], options: sourceOptions, now: now
            )

            XCTAssertTrue(appleRows.isEmpty, "hiding either alias must suppress the trusted source row")
            XCTAssertTrue(nearbyRows.isEmpty, "hiding either alias must suppress the BLE source row")
        }
    }

    func testSharedProjectionRetainsUniqueSelectedBLEGhostShadowRule() {
        let bleID = UUID(uuidString: "00000000-0000-0000-0000-000000000094")!
        let ble = BluetoothDevice(
            id: BluetoothDeviceIdentity.bleRowID(bleID), name: "Phone", kind: .mobile(.phone),
            isConnected: false, appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )
        let uniqueGhost = BluetoothDevice(
            id: "AA:00:00:00:00:91", name: "Phone", kind: .unknown,
            isConnected: false, isUnpairedGhost: true
        )
        let pairedPeer = BluetoothDevice(
            id: "AA:00:00:00:00:92", name: "Phone", kind: .mobile(.phone),
            isConnected: true, appleMobileModel: "iPhone18,1"
        )

        let projected = BluetoothDeviceListModel.make(
            devices: [uniqueGhost, pairedPeer], nearbyRows: [nearbyRow(id: bleID, name: "Phone")],
            order: [], limit: 10, isExpanded: true, options: .standard
        )
        XCTAssertTrue(projected.orderedDevices.contains { $0.id == pairedPeer.id })
        XCTAssertTrue(projected.orderedDevices.contains { $0.id == ble.id })
        XCTAssertFalse(projected.orderedDevices.contains { $0.id == uniqueGhost.id })
    }

    func testGhostExclusionDoesNotMergeSameNamedClassicAndBLERows() {
        let id = UUID()
        let classic = BluetoothDevice(id: "AA:00:00:00:00:01", name: "Phone", kind: .unknown,
                                      isConnected: false, isUnpairedGhost: true)
        let ble = BluetoothDevice(id: BluetoothDeviceIdentity.bleRowID(id), name: "Phone", kind: .unknown,
                                  isConnected: false, isReadOverTheAir: true)
        XCTAssertTrue(BluetoothDeviceListPresentation.systemDevicesExcludingGhosts([classic]).isEmpty)
        XCTAssertNotEqual(classic.id, ble.id)
    }
    func testUnifiedListSharesOrderHideLimitExpansionAndVisibleBLESelection() {
        let firstBLEID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let secondBLEID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        let hiddenBLEID = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
        let connected = makeDevice(address: "AA:00:00:00:00:01", name: "Connected", isConnected: true)
        let system = makeDevice(address: "AA:00:00:00:00:02", name: "System", isConnected: false)
        let nearbyRows = [
            nearbyRow(id: secondBLEID, name: "Second BLE"),
            nearbyRow(id: hiddenBLEID, name: "Hidden BLE"),
            nearbyRow(id: firstBLEID, name: "First BLE")
        ]
        let options = BluetoothDeviceListOptions(
            showsList: true,
            maxVisibleDevices: 2,
            order: [
                BluetoothDeviceIdentity.bleRowID(firstBLEID),
                BluetoothDeviceIdentity.bleRowID(secondBLEID),
                system.id
            ],
            hiddenDeviceAddresses: [BluetoothDeviceIdentity.bleRowID(hiddenBLEID)]
        )

        let collapsed = BluetoothDeviceListModel.make(
            devices: [system, connected],
            nearbyRows: nearbyRows,
            order: options.order,
            limit: options.maxVisibleDevices,
            isExpanded: false,
            options: options
        )

        XCTAssertEqual(collapsed.orderedDevices.map(\.name), ["Connected", "First BLE", "Second BLE", "System"])
        XCTAssertEqual(collapsed.visibleDevices.map(\.name), ["Connected", "First BLE"])
        XCTAssertTrue(collapsed.canToggleExpansion)
        XCTAssertEqual(
            NearbyBLEPanelVisibility.visibleSelectedIDs(
                in: collapsed.visibleDevices,
                frames: [
                    firstBLEID: CGRect(x: 0, y: 0, width: 200, height: 24),
                    secondBLEID: CGRect(x: 0, y: 32, width: 200, height: 24)
                ],
                viewport: CGRect(x: 0, y: 0, width: 200, height: 168)
            ),
            [firstBLEID]
        )

        let expanded = BluetoothDeviceListModel.make(
            devices: [system, connected],
            nearbyRows: nearbyRows,
            order: options.order,
            limit: options.maxVisibleDevices,
            isExpanded: true,
            options: options
        )
        XCTAssertEqual(expanded.visibleDevices.map(\.name), ["Connected", "First BLE", "Second BLE", "System"])
        XCTAssertEqual(
            NearbyBLEPanelVisibility.visibleSelectedIDs(
                in: expanded.visibleDevices,
                frames: [
                    firstBLEID: CGRect(x: 0, y: -40, width: 200, height: 24),
                    secondBLEID: CGRect(x: 0, y: 32, width: 200, height: 24)
                ],
                viewport: CGRect(x: 0, y: 0, width: 200, height: 168)
            ),
            [secondBLEID]
        )
    }

    private func nearbyRow(id: UUID, name: String) -> NearbyBLEPanelRow {
        NearbyBLEPanelRow(
            id: id,
            device: BluetoothDevice(
                id: BluetoothDeviceIdentity.bleRowID(id),
                name: name,
                kind: .unknown,
                isConnected: false,
                isReadOverTheAir: true
            ),
            batteryLevel: 84,
            wasSeenRecently: true,
            readFailed: false
        )
    }

    func testUnifiedModelExcludesEveryUnpairedGhostAndKeepsIndependentPairedAndBLERows() {
        let selectedID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let selectedRow = nearbyRow(id: selectedID, name: "Ling's iPhone")
        let ghost = makeDevice(
            address: "AA:00:00:00:00:99", name: "Ling's iPhone", isConnected: false, isUnpairedGhost: true
        )
        let paired = BluetoothDevice(
            id: "paired-exact", name: "Ling's iPhone", kind: .mobile(.phone), isConnected: true
        )
        let duplicatePresentation = BluetoothDevice(
            id: paired.id, name: "stale duplicate", kind: .unknown, isConnected: false, isReadOverTheAir: true
        )
        let distinctSameNamePaired = BluetoothDevice(
            id: "paired-other", name: "Ling's iPhone", kind: .mobile(.phone), isConnected: true
        )
        let options = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 20, order: [], hidesGhostDevices: false)

        let model = BluetoothDeviceListModel.make(
            devices: [ghost, paired, distinctSameNamePaired, duplicatePresentation],
            nearbyRows: [selectedRow],
            order: [], limit: 20, isExpanded: true, options: options
        )

        XCTAssertEqual(model.orderedDevices.filter { $0.name == "Ling's iPhone" }.count, 3)
        XCTAssertEqual(model.orderedDevices.filter { $0.id == paired.id }.count, 1)
        XCTAssertFalse(model.orderedDevices.contains { $0.id == ghost.id })
        XCTAssertTrue(model.orderedDevices.contains { $0.id == distinctSameNamePaired.id })
        XCTAssertTrue(model.orderedDevices.contains { $0.id == selectedRow.device.id })
        XCTAssertEqual(model.orderedDevices.first { $0.id == paired.id }, paired)
    }

    func testUnifiedModelExcludesGhostEvenWhenItHasSavedBLESelectionAndThatRowIsHidden() {
        let selected = makeSelectedBLERow(name: "Ling's iPhone")
        let ghost = makeDevice(
            address: "AA:00:00:00:00:98", name: "Ling's iPhone", isConnected: false, isUnpairedGhost: true
        )
        let options = BluetoothDeviceListOptions(
            showsList: true, maxVisibleDevices: 20, order: [], hidesGhostDevices: false,
            hiddenDeviceAddresses: [selected.id]
        )

        let model = BluetoothDeviceListModel.make(
            devices: [ghost], order: [], limit: 20,
            isExpanded: true, options: options
        )

        XCTAssertFalse(model.orderedDevices.contains { $0.id == ghost.id })
        XCTAssertTrue(model.orderedDevices.isEmpty)
    }

    func testTrustedAppleRowsShareSettingsOrderAndHiddenDeviceFiltering() {
        let phoneID = AppleDeviceID.trustedDevice("phone-123")
        let phone = BluetoothDevice(
            id: phoneID.rowID, name: "Renamed iPhone", kind: .mobile(.phone),
            isConnected: false, appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )
        let ordinary = makeDevice(address: "AA:00:00:00:00:44", name: "Keyboard", isConnected: false)
        let options = BluetoothDeviceListOptions(
            showsList: true, maxVisibleDevices: 5,
            order: [ordinary.id, phone.id], hidesGhostDevices: false,
            hiddenDeviceAddresses: [BluetoothDeviceIdentity.preferenceKey(phone.id)]
        )

        let model = BluetoothDeviceListModel.make(
            devices: [phone, ordinary], order: options.order, limit: 5,
            isExpanded: true, options: options
        )

        XCTAssertEqual(model.orderedDevices.map(\.id), [ordinary.id])
    }

    func testTrustedAppleRowsRespectTheSameUnifiedOrderAsOrdinaryDevices() {
        let phoneID = AppleDeviceID.trustedDevice("phone-123")
        let phone = BluetoothDevice(
            id: phoneID.rowID, name: "iPhone", kind: .mobile(.phone),
            isConnected: false, isReadOverTheAir: true
        )
        let ordinary = makeDevice(address: "AA:00:00:00:00:45", name: "Keyboard", isConnected: false)

        let ordered = BluetoothDeviceListPresentation.orderedDevices(
            [phone, ordinary], using: [phone.id, ordinary.id]
        )

        XCTAssertEqual(ordered.map(\.id), [phone.id, ordinary.id])
    }

    func testBLERowsUseExplicitPreferenceKeysForOrderingAndHiding() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let first = BluetoothDevice(
            id: BluetoothDeviceIdentity.bleRowID(firstID), name: "First", kind: .unknown,
            isConnected: false, isReadOverTheAir: true
        )
        let second = BluetoothDevice(
            id: BluetoothDeviceIdentity.bleRowID(secondID), name: "Second", kind: .unknown,
            isConnected: false, isReadOverTheAir: true
        )
        let options = BluetoothDeviceListOptions(
            showsList: true, maxVisibleDevices: 5,
            order: [BluetoothDeviceIdentity.bleRowID(secondID), BluetoothDeviceIdentity.bleRowID(firstID)],
            hidesGhostDevices: true, hiddenDeviceAddresses: []
        )

        XCTAssertEqual(BluetoothDeviceListPresentation.orderedDevices([first, second], using: options.order).map(\.id), [second.id, first.id])
        XCTAssertEqual(BluetoothDeviceListPresentation.filteredDevices(
            [first, second],
            options: BluetoothDeviceListOptions(
                showsList: true, maxVisibleDevices: 5, order: [], hidesGhostDevices: true,
                hiddenDeviceAddresses: [BluetoothDeviceIdentity.bleRowID(firstID)]
            )
        ).map(\.id), [second.id])
    }

    func testNearbyReadRowsFollowSharedSavedOrder() {
        let bleID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let classicRead = BluetoothDevice(
            id: "AA:00:00:00:00:01", name: "Classic read", kind: .unknown,
            isConnected: false, isReadOverTheAir: true
        )
        let ble = BluetoothDevice(
            id: BluetoothDeviceIdentity.bleRowID(bleID), name: "Selected BLE", kind: .unknown,
            isConnected: false, isReadOverTheAir: true
        )

        XCTAssertEqual(
            BluetoothDeviceListPresentation.orderedDevices(
                [ble, classicRead], using: [BluetoothDeviceIdentity.bleRowID(bleID)]
            ).map(\.id),
            [ble.id, classicRead.id]
        )
    }

    func testConnectedDevicesLeadAndOrderOnlyAppliesWithinAGroup() {
        let devices = [
            makeDevice(address: "AA:00:00:00:00:01", name: "Mouse", isConnected: false),
            makeDevice(address: "AA:00:00:00:00:02", name: "Keyboard", isConnected: false),
            makeDevice(address: "AA:00:00:00:00:03", name: "AirPods", isConnected: true)
        ]

        // The saved order ranks a disconnected device first, but the group rule
        // wins: a drag can never lift it above a connected device. The stale
        // address matches no device and changes nothing.
        let ordered = BluetoothDeviceListPresentation.orderedDevices(
            devices,
            using: ["AA0000000001", "STALE-ADDRESS", "AA0000000003", "AA0000000002"]
        )

        XCTAssertEqual(ordered.map(\.name), ["AirPods", "Mouse", "Keyboard"])
    }

    func testUnlistedDevicesKeepIncomingOrderAfterRankedOnes() {
        let devices = [
            makeDevice(address: "AA:00:00:00:00:01", name: "First", isConnected: true),
            makeDevice(address: "AA:00:00:00:00:02", name: "Second", isConnected: true),
            makeDevice(address: "AA:00:00:00:00:03", name: "Third", isConnected: true)
        ]

        let ordered = BluetoothDeviceListPresentation.orderedDevices(
            devices,
            using: ["AA0000000002"]
        )

        XCTAssertEqual(ordered.map(\.name), ["Second", "First", "Third"])
    }

    func testOrderEntriesAreNormalizedBeforeTheyRankDevices() {
        // A saved entry written with separators or in lowercase has to rank the
        // device it names. Before the order side was normalized too, these
        // entries silently ranked nothing and the list kept the system order.
        let devices = [
            makeDevice(address: "AA:00:00:00:00:01", name: "First", isConnected: true),
            makeDevice(address: "AA:00:00:00:00:02", name: "Second", isConnected: true),
            makeDevice(address: "AA:00:00:00:00:03", name: "Third", isConnected: true)
        ]

        XCTAssertEqual(
            BluetoothDeviceListPresentation.orderedDevices(
                devices,
                using: ["aa:00:00:00:00:03", "AA-00-00-00-00-01"]
            ).map(\.name),
            ["Third", "First", "Second"]
        )
    }

    func testEmptyOrderKeepsGroupingOrder() {
        let devices = [
            makeDevice(address: "AA:00:00:00:00:01", name: "Idle", isConnected: false),
            makeDevice(address: "AA:00:00:00:00:02", name: "Live", isConnected: true)
        ]

        XCTAssertEqual(
            BluetoothDeviceListPresentation.orderedDevices(devices, using: []).map(\.name),
            ["Live", "Idle"]
        )
    }

    func testConnectedDevicesFillTheLimitFirst() {
        // The disconnected device leads the fixture, so the expected result can
        // only come from the connected-first rule rather than from the incoming
        // order happening to already match it.
        let devices = [
            makeDevice(address: "AA:00:00:00:00:02", name: "Idle", isConnected: false),
            makeDevice(address: "AA:00:00:00:00:01", name: "Live", isConnected: true),
            makeDevice(address: "AA:00:00:00:00:03", name: "Idle2", isConnected: false)
        ]

        let model = BluetoothDeviceListModel.make(
            devices: devices,
            order: [],
            limit: 2,
            isExpanded: false,
            options: .standard
        )

        XCTAssertEqual(model.visibleDevices.map(\.name), ["Live", "Idle"])
        XCTAssertTrue(model.canToggleExpansion)
    }

    func testExpansionShowsEveryDeviceAndDisappearsWhenEverythingFits() {
        let devices = (1...3).map {
            makeDevice(address: "AA:00:00:00:00:0\($0)", name: "Device \($0)", isConnected: true)
        }

        XCTAssertEqual(
            BluetoothDeviceListPresentation.visibleDevices(from: devices, limit: 1, isExpanded: true)
                .map(\.name),
            ["Device 1", "Device 2", "Device 3"]
        )
        XCTAssertFalse(
            BluetoothDeviceListPresentation.canToggleExpansion(for: devices, limit: 3)
        )
        XCTAssertTrue(
            BluetoothDeviceListPresentation.canToggleExpansion(for: devices, limit: 2)
        )
        XCTAssertEqual(
            BluetoothDeviceListPresentation.visibleDevices(from: [], limit: 5, isExpanded: false),
            []
        )
    }

    func testListVisibilityFollowsAvailabilityAndEmptyState() {
        let devices = [
            makeDevice(address: "AA:00:00:00:00:01", name: "Idle", isConnected: false)
        ]
        let options = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 5, order: [])

        XCTAssertTrue(
            BluetoothPanelListVisibility.showsList(
                availability: .available,
                devices: devices,
                options: options
            )
        )
        XCTAssertFalse(
            BluetoothPanelListVisibility.showsList(
                availability: .poweredOff,
                devices: devices,
                options: options
            )
        )
        XCTAssertFalse(
            BluetoothPanelListVisibility.showsList(
                availability: .available,
                devices: [],
                options: options
            )
        )
        XCTAssertFalse(
            BluetoothPanelListVisibility.showsList(
                availability: .available,
                devices: devices,
                options: BluetoothDeviceListOptions(showsList: false, maxVisibleDevices: 5, order: [])
            )
        )
    }

    func testSubtitleIsReplacedOnlyWhenTheListCarriesConnectedNames() {
        let options = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 5, order: [])
        let connected = [makeDevice(address: "AA:00:00:00:00:01", name: "Live", isConnected: true)]
        let idle = [makeDevice(address: "AA:00:00:00:00:02", name: "Idle", isConnected: false)]

        XCTAssertTrue(
            BluetoothPanelListVisibility.hidesRowSubtitle(
                availability: .available,
                devices: connected,
                options: options
            )
        )
        // Nothing connected: the row keeps saying so, and the list still shows
        // the paired devices underneath.
        XCTAssertFalse(
            BluetoothPanelListVisibility.hidesRowSubtitle(
                availability: .available,
                devices: idle,
                options: options
            )
        )
        XCTAssertFalse(
            BluetoothPanelListVisibility.hidesRowSubtitle(
                availability: .available,
                devices: connected,
                options: BluetoothDeviceListOptions(showsList: false, maxVisibleDevices: 5, order: [])
            )
        )
    }

    func testFilteredDevicesAlwaysDropsSystemGhostsRegardlessOfLegacyOption() {
        let ghost = makeDevice(address: "AA:00:00:00:00:01", name: "Ghost", isConnected: false, isUnpairedGhost: true)
        let paired = makeDevice(address: "AA:00:00:00:00:02", name: "Paired", isConnected: true)

        let hiding = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 5, order: [], hidesGhostDevices: true)
        XCTAssertEqual(
            BluetoothDeviceListPresentation.filteredDevices([ghost, paired], options: hiding).map(\.id),
            [paired.id]
        )

        let showing = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 5, order: [], hidesGhostDevices: false)
        XCTAssertEqual(BluetoothDeviceListPresentation.filteredDevices([ghost, paired], options: showing).map(\.id), [paired.id])
    }

    func testFilteredDevicesDropsManuallyHiddenDevicesByNormalizedAddress() {
        let first = makeDevice(address: "AA:00:00:00:00:01", name: "First", isConnected: false)
        let second = makeDevice(address: "AA:00:00:00:00:02", name: "Second", isConnected: true)

        let options = BluetoothDeviceListOptions(
            showsList: true,
            maxVisibleDevices: 5,
            order: [],
            hiddenDeviceAddresses: ["AA0000000001"]
        )
        XCTAssertEqual(
            BluetoothDeviceListPresentation.filteredDevices([first, second], options: options).map(\.id),
            [second.id]
        )
    }

    func testFilteredDevicesHidesGhostAndManualHidesIndependently() {
        let ghost = makeDevice(address: "AA:00:00:00:00:01", name: "Ghost", isConnected: false, isUnpairedGhost: true)
        let hidden = makeDevice(address: "AA:00:00:00:00:02", name: "Hidden", isConnected: true)
        let visible = makeDevice(address: "AA:00:00:00:00:03", name: "Visible", isConnected: true)

        let options = BluetoothDeviceListOptions(
            showsList: true,
            maxVisibleDevices: 5,
            order: [],
            hidesGhostDevices: true,
            hiddenDeviceAddresses: ["AA0000000002"]
        )
        XCTAssertEqual(
            BluetoothDeviceListPresentation.filteredDevices([ghost, hidden, visible], options: options).map(\.id),
            [visible.id]
        )
    }

    func testLegacyGhostRevealPreferencesCannotShowSystemGhosts() {
        let ghostA = makeDevice(address: "AA:00:00:00:00:01", name: "Ghost A", isConnected: false, isUnpairedGhost: true)
        let ghostB = makeDevice(address: "AA:00:00:00:00:02", name: "Ghost B", isConnected: false, isUnpairedGhost: true)
        let paired = makeDevice(address: "AA:00:00:00:00:03", name: "Paired", isConnected: true)

        let options = BluetoothDeviceListOptions(
            showsList: true,
            maxVisibleDevices: 5,
            order: [],
            hidesGhostDevices: true,
            revealedGhostDeviceAddresses: ["AA0000000001"]
        )
        XCTAssertEqual(BluetoothDeviceListPresentation.filteredDevices([ghostA, ghostB, paired], options: options).map(\.id), [paired.id])

        // With the filter off, the reveal set is irrelevant: everything shows.
        let off = BluetoothDeviceListOptions(
            showsList: true,
            maxVisibleDevices: 5,
            order: [],
            hidesGhostDevices: false,
            revealedGhostDeviceAddresses: ["AA0000000001"]
        )
        XCTAssertEqual(BluetoothDeviceListPresentation.filteredDevices([ghostA, ghostB, paired], options: off).map(\.id), [paired.id])
    }

    func testSettingsExcludesSystemGhostsButPreservesPairedAndBLERows() {
        let selected = makeSelectedBLERow(name: " Ling's iPhone ")
        let shadow = makeDevice(
            address: "AA:00:00:00:00:01",
            name: "LING'S IPHONE",
            isConnected: false,
            isUnpairedGhost: true
        )
        let pairedPeer = makeDevice(
            address: "AA:00:00:00:00:02",
            name: "Ling's iPhone",
            isConnected: true
        )
        let unrelatedGhost = makeDevice(
            address: "AA:00:00:00:00:03",
            name: "Other ghost",
            isConnected: false,
            isUnpairedGhost: true
        )
        let settingsRows = BluetoothDeviceListPresentation.systemDevicesExcludingGhosts([shadow, pairedPeer, unrelatedGhost, selected])

        XCTAssertEqual(Set(settingsRows.map(\.id)), Set([pairedPeer.id, selected.id]))
        XCTAssertTrue(settingsRows.contains { $0.id == pairedPeer.id }, "a truly paired peer must remain")
        XCTAssertTrue(settingsRows.contains { $0.id == selected.id }, "the selected BLE row keeps its own identity")
        XCTAssertFalse(settingsRows.contains { $0.id == shadow.id })
        XCTAssertFalse(settingsRows.contains { $0.id == unrelatedGhost.id })
    }

    func testPanelNeverShowsGhostsWhenSelectedBLERowIsHidden() {
        let selectedID = UUID()
        let selected = makeSelectedBLERow(name: "Ling's iPhone", id: selectedID)
        let shadow = makeDevice(
            address: "AA:00:00:00:00:11",
            name: "Ling's iPhone",
            isConnected: false,
            isUnpairedGhost: true
        )
        let revealedGhost = makeDevice(
            address: "AA:00:00:00:00:12",
            name: "Unrelated ghost",
            isConnected: false,
            isUnpairedGhost: true
        )
        let pairedPeer = makeDevice(
            address: "AA:00:00:00:00:13",
            name: "Ling's iPhone",
            isConnected: true
        )
        let options = BluetoothDeviceListOptions(
            showsList: true,
            maxVisibleDevices: 5,
            order: [],
            hidesGhostDevices: true,
            revealedGhostDeviceAddresses: [BluetoothBatteryReader.normalizedAddress(revealedGhost.id)]
        )

        let panelRows = BluetoothDeviceListPresentation.systemDevicesExcludingGhosts([shadow, revealedGhost, pairedPeer])
        XCTAssertEqual(BluetoothDeviceListPresentation.filteredDevices(panelRows, options: options).map(\.id), [pairedPeer.id])

        // The actual panel catalog omits a manually hidden selected UUID. Its
        // former name therefore must not continue suppressing a separately
        // revealed system ghost.
        let selection = NearbyBLEDeviceSelection(
            id: selectedID,
            name: selected.name,
            vendor: .unknown,
            model: nil,
            batteryLevel: 50,
            batteryLastUpdated: .now
        )
        let hiddenOptions = BluetoothDeviceListOptions(
            showsList: true,
            maxVisibleDevices: 5,
            order: [],
            hiddenDeviceAddresses: [BluetoothDeviceIdentity.bleRowID(selectedID)]
        )
        let hiddenNearbyRows = NearbyBLEDeviceCatalog.panelRows(
            selections: [selection],
            readings: [],
            failures: [],
            options: hiddenOptions,
            now: Date()
        )
        XCTAssertTrue(hiddenNearbyRows.isEmpty)
        let revealShadow = BluetoothDeviceListOptions(
            showsList: true,
            maxVisibleDevices: 5,
            order: [],
            hidesGhostDevices: true,
            hiddenDeviceAddresses: [BluetoothDeviceIdentity.bleRowID(selectedID)],
            revealedGhostDeviceAddresses: [BluetoothBatteryReader.normalizedAddress(shadow.id)]
        )
        let panelSystemRows = BluetoothDeviceListPresentation.systemDevicesExcludingGhosts([shadow, pairedPeer])
        XCTAssertEqual(BluetoothDeviceListPresentation.filteredDevices(panelSystemRows, options: revealShadow).map(\.id), [pairedPeer.id])
        XCTAssertEqual(
            BluetoothDeviceListPresentation.systemDevicesExcludingGhosts([shadow]).map(\.id),
            [],
            "Profiler ghosts are excluded regardless of nearby battery rows"
        )
    }

    func testSystemGhostsAreExcludedWithoutNameBasedMerging() {
        let selectedA = makeSelectedBLERow(name: "Shared phone")
        let selectedB = makeSelectedBLERow(name: "Shared phone")
        let ghost = makeDevice(
            address: "AA:00:00:00:00:21",
            name: "Shared phone",
            isConnected: false,
            isUnpairedGhost: true
        )
        let ambiguousSelection = BluetoothDeviceListPresentation.systemDevicesExcludingGhosts([ghost, selectedA, selectedB])
        XCTAssertFalse(ambiguousSelection.contains { $0.id == ghost.id })

        let nonBLEReading = makeReadingDevice(address: "CB-1", name: "Shared phone")
        let nonSelectedSource = BluetoothDeviceListPresentation.systemDevicesExcludingGhosts([ghost, nonBLEReading])
        XCTAssertFalse(nonSelectedSource.contains { $0.id == ghost.id })

        let ghostA = makeDevice(
            address: "AA:00:00:00:00:22",
            name: "Shared phone",
            isConnected: false,
            isUnpairedGhost: true
        )
        let ghostB = makeDevice(
            address: "AA:00:00:00:00:23",
            name: "Shared phone",
            isConnected: false,
            isUnpairedGhost: true
        )
        let ambiguousGhosts = BluetoothDeviceListPresentation.systemDevicesExcludingGhosts([ghostA, ghostB, selectedA])
        XCTAssertFalse(ambiguousGhosts.contains { $0.id == ghostA.id })
        XCTAssertFalse(ambiguousGhosts.contains { $0.id == ghostB.id })
    }

    func testTrustedRowsFollowSavedOrderWithinTheirConnectionGroup() {
        let devices = [
            makeDevice(address: "AA:00:00:00:00:01", name: "AirPods", isConnected: false),
            makeReadingDevice(address: "CB-1", name: "Ling's iPhone"),
            makeDevice(address: "AA:00:00:00:00:02", name: "MX Keys", isConnected: false),
            makeReadingDevice(address: "CB-2", name: "Lingsipad")
        ]

        let ordered = BluetoothDeviceListPresentation.orderedDevices(
            devices,
            using: ["AA0000000001", "CB-1", "AA0000000002", "CB-2"]
        )

        XCTAssertEqual(ordered.map(\.name), ["AirPods", "Ling's iPhone", "MX Keys", "Lingsipad"])
    }

    func testSavedOrderCanPositionATrustedReadingWithinItsGroup() {
        let devices = [
            makeDevice(address: "AA:00:00:00:00:01", name: "Mouse", isConnected: false),
            makeReadingDevice(address: "CB-1", name: "Ling's iPhone")
        ]

        XCTAssertEqual(
            BluetoothDeviceListPresentation.orderedDevices(
                devices,
                using: ["AA0000000001", "CB-1"]
            ).map(\.name),
            ["Mouse", "Ling's iPhone"]
        )
    }

    /// A reading leads its own group and no further: a device the report has
    /// connected is still connected, and still first.
    /// Within the connected group, devices whose battery the row can draw lead
    /// the devices macOS reports no level for; the AirPods rule still wins among
    /// rows that both carry a level.
    func testConnectedDevicesWithBatteryLeadWithinTheirGroup() {
        let keyboard = BluetoothDevice(
            id: "AA:00:00:00:00:01", name: "Keyboard", kind: .audio, isConnected: true
        )
        let mouse = BluetoothDevice(
            id: "AA:00:00:00:00:02", name: "Mouse", kind: .audio, isConnected: true
        )
        let trackpad = BluetoothDevice(
            id: "AA:00:00:00:00:03", name: "Trackpad", kind: .audio, isConnected: true
        )
        let idle = makeDevice(address: "AA:00:00:00:00:04", name: "Idle", isConnected: false)
        let levels = [BluetoothBatteryReader.normalizedAddress(mouse.id): BluetoothBatteryLevel(
            deviceAddress: mouse.id, main: 80, left: nil, right: nil, caseLevel: nil
        )]

        XCTAssertEqual(
            BluetoothDeviceListPresentation.orderedDevices(
                [keyboard, idle, trackpad, mouse], using: [], batteryLevels: levels
            ).map(\.name),
            ["Mouse", "Keyboard", "Trackpad", "Idle"]
        )
    }

    func testAirPodsWithBatteryStillLeadOtherBatteryRows() {
        let airpods = BluetoothDevice(
            id: "AA:00:00:00:00:01", name: "AirPods Pro", kind: .audio, isConnected: true,
            airPodsModel: AirPodsModel.airPodsPro
        )
        let keyboard = BluetoothDevice(
            id: "AA:00:00:00:00:02", name: "Keyboard", kind: .audio, isConnected: true
        )
        let levels = [
            BluetoothBatteryReader.normalizedAddress(airpods.id): BluetoothBatteryLevel(
                deviceAddress: airpods.id, main: nil, left: 90, right: 80, caseLevel: 70
            ),
            BluetoothBatteryReader.normalizedAddress(keyboard.id): BluetoothBatteryLevel(
                deviceAddress: keyboard.id, main: 50, left: nil, right: nil, caseLevel: nil
            )
        ]

        XCTAssertEqual(
            BluetoothDeviceListPresentation.orderedDevices(
                [keyboard, airpods], using: [], batteryLevels: levels
            ).map(\.name),
            ["AirPods Pro", "Keyboard"]
        )
    }

    func testDisconnectedDevicesWithBatteryLeadDisconnectedGroup() {
        let phone = makeReadingDevice(address: "CB-1", name: "Phone")
        let mouse = makeDevice(address: "AA:00:00:00:00:02", name: "Mouse", isConnected: false)
        let levels = [BluetoothBatteryReader.normalizedAddress(phone.id): BluetoothBatteryLevel(
            deviceAddress: phone.id, main: 65, left: nil, right: nil, caseLevel: nil
        )]

        XCTAssertEqual(
            BluetoothDeviceListPresentation.orderedDevices(
                [mouse, phone], using: [], batteryLevels: levels
            ).map(\.name),
            ["Phone", "Mouse"]
        )
    }

    func testCrossSourceRowBatteryAliasCountsForOrdering() {
        let bleID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let ble = BluetoothDevice(
            id: BluetoothDeviceIdentity.bleRowID(bleID), name: "Phone", kind: .mobile(.phone),
            isConnected: false, appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )
        let system = makeDevice(address: "AA:00:00:00:00:05", name: "Phone", isConnected: false)
        let rows = BluetoothDeviceListPresentation.sharedDisplayRows([system, ble])
        XCTAssertEqual(rows.count, 2, "same name alone never merges; keep both rows")
        let keyboardRow = BluetoothDisplayRow(
            device: makeDevice(address: "AA:00:00:00:00:06", name: "Keyboard", isConnected: false),
            sourceIDs: ["AA:00:00:00:00:06"]
        )
        let levels = [BluetoothBatteryReader.normalizedAddress(ble.id): BluetoothBatteryLevel(
            deviceAddress: ble.id, main: 60, left: nil, right: nil, caseLevel: nil
        )]
        let batteryRow = rows.first { $0.device.id == ble.id }!
        let ordered = BluetoothDeviceListPresentation.orderedDisplayRows(
            [keyboardRow, batteryRow], using: [], batteryLevels: levels
        )
        XCTAssertEqual(ordered.first?.device.id, batteryRow.device.id)
    }

    /// Regression: the popover builds nearby rows from persisted selections, and
    /// those rows carry their level on the row itself rather than in the system
    /// report's dictionary. When the row level was not folded into the ordering
    /// dictionary, a disconnected phone with a charge sorted behind every
    /// battery-less accessory macOS reported.
    func testNearbyRowBatteryLevelsLeadTheDisconnectedGroup() {
        let iPhoneID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let iPadID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
        let headset = makeDevice(address: "AA:00:00:00:00:0A", name: "EDIFIER LolliPods", isConnected: false)
        let mouse = makeDevice(address: "AA:00:00:00:00:0B", name: "M585/M590", isConnected: false)
        let iPhone = makeSelectedBLERow(name: "Ling's iPhone", id: iPhoneID)
        let iPad = makeSelectedBLERow(name: "Lingsipad", id: iPadID)
        let nearbyRows = [
            NearbyBLEPanelRow(id: iPhoneID, device: iPhone, batteryLevel: 36,
                              wasSeenRecently: false, readFailed: false),
            NearbyBLEPanelRow(id: iPadID, device: iPad, batteryLevel: 35,
                              wasSeenRecently: false, readFailed: false)
        ]

        let model = BluetoothDeviceListModel.make(
            devices: [headset, mouse], nearbyRows: nearbyRows,
            order: [], limit: 10, isExpanded: true, options: .standard
        )

        XCTAssertEqual(
            model.orderedDevices.map(\.name),
            ["Ling's iPhone", "Lingsipad", "EDIFIER LolliPods", "M585/M590"]
        )
    }

    /// The row level only ranks while the row actually draws it: with battery
    /// presentation off the row must not claim a slot it does not explain.
    func testNearbyRowWithoutVisibleBatteryDoesNotLeadTheDisconnectedGroup() {
        let iPhoneID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!
        let headset = makeDevice(address: "AA:00:00:00:00:0A", name: "EDIFIER LolliPods", isConnected: false)
        let iPhone = makeSelectedBLERow(name: "Ling's iPhone", id: iPhoneID)
        let nearbyRows = [
            NearbyBLEPanelRow(id: iPhoneID, device: iPhone, batteryLevel: 36,
                              wasSeenRecently: false, readFailed: false,
                              batteryLevelsEnabled: false)
        ]

        let model = BluetoothDeviceListModel.make(
            devices: [headset], nearbyRows: nearbyRows,
            order: [], limit: 10, isExpanded: true, options: .standard
        )

        XCTAssertEqual(model.orderedDevices.map(\.name), ["EDIFIER LolliPods", "Ling's iPhone"])
    }

    /// Regression: the final display pass ranked by the saved order before it
    /// looked at the level, so a battery-less device with an earlier saved
    /// position pushed a charged device back to the bottom of its group.
    func testDisplayRowsRankBatteryAheadOfTheSavedOrder() {
        let headset = BluetoothDisplayRow(
            device: makeDevice(address: "AA:00:00:00:00:0C", name: "EDIFIER LolliPods", isConnected: false),
            sourceIDs: ["AA:00:00:00:00:0C"]
        )
        let iPhoneID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A4")!
        let iPhone = BluetoothDisplayRow(
            device: makeSelectedBLERow(name: "Ling's iPhone", id: iPhoneID),
            sourceIDs: [BluetoothDeviceIdentity.bleRowID(iPhoneID)]
        )
        let levels = [BluetoothBatteryReader.normalizedAddress(iPhone.device.id): BluetoothBatteryLevel(
            deviceAddress: iPhone.device.id, main: 36, left: nil, right: nil, caseLevel: nil
        )]

        XCTAssertEqual(
            BluetoothDeviceListPresentation.orderedDisplayRows(
                [headset, iPhone],
                using: [headset.device.id, iPhone.device.id],
                batteryLevels: levels
            ).map(\.device.name),
            ["Ling's iPhone", "EDIFIER LolliPods"]
        )
    }

    /// The reported state, run through the same three steps the popover runs:
    /// the unified model order, the shared cross-source rows, then the
    /// per-group display pass. The fix first landed in the model alone and the
    /// display pass put the charged rows back at the bottom.
    func testPopoverPipelineKeepsChargedNearbyRowsAtTheTopOfTheDisconnectedGroup() {
        let headset = makeDevice(address: "AA:00:00:00:00:0D", name: "EDIFIER LolliPods", isConnected: false)
        let mouse = makeDevice(address: "AA:00:00:00:00:0E", name: "M585/M590", isConnected: false)
        let iPhoneID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A5")!
        let iPadID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A6")!
        let iPhone = makeSelectedBLERow(name: "Ling's iPhone", id: iPhoneID)
        let iPad = makeSelectedBLERow(name: "Lingsipad", id: iPadID)
        let nearbyRows = [
            NearbyBLEPanelRow(id: iPhoneID, device: iPhone, batteryLevel: 36,
                              wasSeenRecently: false, readFailed: false),
            NearbyBLEPanelRow(id: iPadID, device: iPad, batteryLevel: 35,
                              wasSeenRecently: false, readFailed: false)
        ]
        // Both charged rows were appended to the saved order after the
        // accessories, so a saved-order-first pass buries them.
        let order = [headset.id, mouse.id, iPhone.id, iPad.id]

        let model = BluetoothDeviceListModel.make(
            devices: [headset, mouse], nearbyRows: nearbyRows,
            order: order, limit: 10, isExpanded: true, options: .standard
        )
        let levels = BluetoothDeviceListPresentation.includingRowBatteryLevels([:], nearbyRows: nearbyRows)
        let rows = BluetoothDeviceListPresentation.sharedDisplayRows(model.orderedDevices)
        let disconnected = rows.filter { !$0.device.isConnected }
        let finalRows = BluetoothDeviceListPresentation.orderedDisplayRows(
            disconnected, using: order, batteryLevels: levels
        )

        XCTAssertEqual(
            finalRows.map(\.device.name),
            ["Ling's iPhone", "Lingsipad", "EDIFIER LolliPods", "M585/M590"]
        )
    }

    func testAConnectedDeviceStillLeadsAReading() {
        let devices = [
            makeReadingDevice(address: "CB-1", name: "Ling's iPhone"),
            makeDevice(address: "AA:00:00:00:00:01", name: "MX Keys", isConnected: true)
        ]

        XCTAssertEqual(
            BluetoothDeviceListPresentation.orderedDevices(devices, using: []).map(\.name),
            ["MX Keys", "Ling's iPhone"]
        )
    }

    private func makeSelectedBLERow(name: String, id: UUID = UUID()) -> BluetoothDevice {
        BluetoothDevice(
            id: BluetoothDeviceIdentity.bleRowID(id),
            name: name,
            kind: .unknown,
            isConnected: false,
            isReadOverTheAir: true
        )
    }

    /// A row a reading created, in the shape the merge builds it.
    // MARK: - Issue #330: cached rows must not outlive a failed read

    func testCachedDevicesAreShownWhileAReadCanStillLand() {
        let cached = [makeDevice(address: "AA:BB:CC:DD:EE:01", name: "Old", isConnected: true)]
        for availability in [BluetoothAvailability.idle, .initializing, .available] {
            XCTAssertTrue(
                BluetoothDeviceListPresentation.showsCachedDevices(
                    availability: availability,
                    isRadioOff: false,
                    showsList: true,
                    hasLoadedDevices: false,
                    devices: [],
                    cachedDevices: cached
                ),
                "a pending read may stand in cached rows for \(availability)"
            )
        }
    }

    func testCachedDevicesAreHiddenAfterAFailedRead() {
        let cached = [makeDevice(address: "AA:BB:CC:DD:EE:02", name: "Removed", isConnected: true)]
        // A device removed in System Settings must not keep rendering from the
        // reopen cache once the replacing read failed: nothing will overwrite it.
        for availability in [
            BluetoothAvailability.failed, .poweredOff, .unavailable,
            .authorizationNotDetermined, .authorizationDenied, .authorizationRestricted
        ] {
            XCTAssertFalse(
                BluetoothDeviceListPresentation.showsCachedDevices(
                    availability: availability,
                    isRadioOff: false,
                    showsList: true,
                    hasLoadedDevices: false,
                    devices: [],
                    cachedDevices: cached
                ),
                "no cached row may stand in for \(availability)"
            )
        }
    }

    func testCachedDevicesRequireAnEmptyLiveListAndAnUnloadedRead() {
        let cached = [makeDevice(address: "AA:BB:CC:DD:EE:03", name: "Old", isConnected: true)]
        let fresh = [makeDevice(address: "AA:BB:CC:DD:EE:04", name: "New", isConnected: true)]

        func shows(
            isRadioOff: Bool = false,
            showsList: Bool = true,
            hasLoadedDevices: Bool = false,
            devices: [BluetoothDevice] = [],
            cachedDevices: [BluetoothDevice]
        ) -> Bool {
            BluetoothDeviceListPresentation.showsCachedDevices(
                availability: .available,
                isRadioOff: isRadioOff,
                showsList: showsList,
                hasLoadedDevices: hasLoadedDevices,
                devices: devices,
                cachedDevices: cachedDevices
            )
        }

        XCTAssertFalse(shows(isRadioOff: true, cachedDevices: cached))
        XCTAssertFalse(shows(showsList: false, cachedDevices: cached))
        XCTAssertFalse(shows(hasLoadedDevices: true, cachedDevices: cached))
        XCTAssertFalse(shows(devices: fresh, cachedDevices: cached))
        XCTAssertFalse(shows(cachedDevices: []))
    }

    /// On `.failed` the panel hides the list and reports the read failure, even
    /// if a stale device list is still held in memory — the deleted device must
    /// never be painted as a live connected row.
    func testAFailedReadHidesTheListAndReportsTheFailure() {
        let stale = [makeDevice(address: "AA:BB:CC:DD:EE:05", name: "Removed", isConnected: true)]
        XCTAssertFalse(
            BluetoothPanelListVisibility.showsList(
                availability: .failed,
                devices: stale,
                options: .standard
            )
        )
        XCTAssertEqual(
            BluetoothSummary.presentation(availability: .failed, devices: stale, batteryLevels: [:]),
            .readFailed
        )
    }

    private func makeReadingDevice(address: String, name: String) -> BluetoothDevice {
        BluetoothDevice(
            id: address,
            name: name,
            kind: .mobile(.phone),
            isConnected: false,
            isReadOverTheAir: true
        )
    }

    private func makeDevice(
        address: String,
        name: String,
        isConnected: Bool,
        isUnpairedGhost: Bool = false
    ) -> BluetoothDevice {
        BluetoothDevice(
            id: address,
            name: name,
            kind: .audio,
            isConnected: isConnected,
            isUnpairedGhost: isUnpairedGhost
        )
    }
}
