import AppKit
import Combine
import CoreAudio
import XCTest
@testable import StatusTrioCore

@MainActor
final class SystemStatusStoreTests: XCTestCase {
    func testStoreMergesIndependentMonitorUpdates() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60)
        )

        let updatesApplied = expectation(description: "independent monitor updates applied")
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                guard snapshot.battery.percentage == 42,
                      snapshot.wifi.state == .connected,
                      snapshot.volume.scalar == 0.6 else { return }
                updatesApplied.fulfill()
            }
            .store(in: &cancellables)

        store.start()
        battery.send(makeBattery(percentage: 42))
        wifi.send(WiFiStatus(state: .connected, rssi: -60))
        volume.send(VolumeStatus(scalar: 0.6, isMuted: false, deviceName: "Speaker"))
        await fulfillment(of: [updatesApplied], timeout: 1)

        XCTAssertEqual(store.snapshot.battery.percentage, 42)
        XCTAssertEqual(store.snapshot.wifi.state, .connected)
        XCTAssertEqual(store.snapshot.volume.scalar, 0.6)
        cancellables.removeAll()
        store.stop()
    }

    func testVPNMonitoringFollowsPopoverLifetime() async {
        let vpn = FakeVPNMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            vpnMonitor: vpn,
            volumeMonitor: FakeVolumeMonitor(),
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() }
        )

        store.start()
        XCTAssertEqual(vpn.startCount, 0)
        for tick in 1...4 {
            await sleeper.waitForCallCount(tick)
            sleeper.releaseNext()
            await sleeper.waitForCompletionCount(tick)
        }
        XCTAssertEqual(vpn.refreshCount, 0)

        store.setPopoverVisible(true)
        XCTAssertEqual(vpn.startCount, 1)
        XCTAssertEqual(vpn.refreshCount, 1)

        store.setPopoverVisible(true)
        XCTAssertEqual(vpn.startCount, 1)

        store.setPopoverVisible(false)
        XCTAssertEqual(vpn.stopCount, 1)

        store.setPopoverVisible(true)
        XCTAssertEqual(vpn.startCount, 2)
        XCTAssertEqual(vpn.refreshCount, 2)

        store.stop()
        XCTAssertEqual(vpn.stopCount, 2)
    }

    func testPopoverCloseCancelsMobileBatteryReadWhileViewIsRetained() async {
        let reader = ControlledMobileBatteryReader()
        let mobile = MobileBatteryController(reader: reader)
        mobile.setAuthorizedDeviceIDs([.trustedDevice("phone-1")])
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            mobileBattery: mobile
        )
        mobile.request("summary")
        store.setPopoverVisible(true)
        await waitForMobileReader { await reader.readCount == 1 }

        store.setPopoverVisible(false)
        await waitForMobileReader { await reader.cancellationCount == 1 }
        store.stop()
        await reader.finishAll()
    }

    func testSettingsMasterToggleDoesNotStartAppleDiscoveryOrBatteryReads() async {
        let reader = ControlledMobileBatteryReader()
        let discovery = AppleDeviceDiscoveryController(reader: reader)
        let mobile = MobileBatteryController(reader: reader)
        let suite = makeSuite()
        defer { suite.defaults.removeTestSuite(named: suite.name) }
        let settings = SettingsStore(defaults: suite.defaults)
        settings.showsAppleDevicesAndBattery = true
        settings.showsBluetoothBatteryLevels = true
        settings.showsBluetoothDeviceList = true
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            mobileBattery: mobile,
            appleDeviceDiscovery: discovery
        )

        store.bindMobileBatterySettings(settings)
        XCTAssertFalse(discovery.isDiscovering)
        for _ in 0..<12 { await Task.yield() }

        let discoveryCount = await reader.discoveryCount
        let readCount = await reader.readCount
        XCTAssertEqual(discoveryCount, 0)
        XCTAssertEqual(readCount, 0)
        store.stop()
        await reader.finishAll()
    }

    func testBackgroundPreferenceOwnsClosedPanelDiscoveryOnlyWhenAllGatesAreOn() async {
        let reader = ControlledMobileBatteryReader()
        let discovery = AppleDeviceDiscoveryController(reader: reader)
        let mobile = MobileBatteryController(reader: reader)
        let suite = makeSuite()
        defer { suite.defaults.removeTestSuite(named: suite.name) }
        let settings = SettingsStore(defaults: suite.defaults)
        settings.showsAppleDevicesAndBattery = true
        settings.showsBluetoothBatteryLevels = true
        settings.showsBluetoothDeviceList = true
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            mobileBattery: mobile,
            appleDeviceDiscovery: discovery
        )
        store.bindMobileBatterySettings(settings)
        for _ in 0..<12 { await Task.yield() }
        XCTAssertFalse(discovery.isDiscovering)

        settings.refreshesAppleBatteriesInBackground = true
        for _ in 0..<50 where !discovery.isDiscovering { await Task.yield() }
        await waitForMobileReader { await reader.discoveryCount == 1 }
        let isDiscoveringAfterEnable = discovery.isDiscovering
        let discoveryCountAfterEnable = await reader.discoveryCount
        XCTAssertTrue(isDiscoveringAfterEnable, "background preference must own discovery while closed")
        XCTAssertEqual(discoveryCountAfterEnable, 1)
        for _ in 0..<12 { await Task.yield() }
        let batteryReadCountWithoutSelection = await reader.readCount
        XCTAssertEqual(batteryReadCountWithoutSelection, 0)
        mobile.setBackgroundAuthorizedDeviceIDs([.trustedDevice("phone-1")])
        await waitForMobileReader { await reader.readCount == 1 }
        settings.showsBluetoothBatteryLevels = false
        for _ in 0..<50 where discovery.isDiscovering { await Task.yield() }
        XCTAssertFalse(discovery.isDiscovering)

        store.stop()
        await reader.finishAll()
    }

    func testStoreExpandsHiddenAliasAcrossTrustedAndBLEBackgroundTargets() async throws {
        let reader = ControlledMobileBatteryReader()
        let discovery = AppleDeviceDiscoveryController(reader: reader)
        let mobile = MobileBatteryController(reader: reader)
        let suite = makeSuite()
        defer { suite.defaults.removeTestSuite(named: suite.name) }
        let bleID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
        let bleSelection = NearbyBLEDeviceSelection(
            id: bleID, name: "Phone", vendor: .apple, model: "iPhone18,1",
            batteryLevel: 51, batteryLastUpdated: Date()
        )
        let trusted = AppleDeviceCandidate(
            id: .trustedDevice("phone-a"), name: "Phone", model: "iPhone18,1",
            transports: [.usb], trustRequired: false, evidence: .verifiedAppleModel
        )
        suite.defaults.set(try JSONEncoder().encode([bleSelection]), forKey: SettingsStore.nearbyBLEConsentDefaultsKey)
        suite.defaults.set(try JSONEncoder().encode([trusted]), forKey: SettingsStore.trustedAppleDeviceMetadataDefaultsKey)
        let settings = SettingsStore(defaults: suite.defaults)
        settings.showsAppleDevicesAndBattery = true
        settings.showsBluetoothBatteryLevels = true
        settings.showsBluetoothDeviceList = true
        settings.refreshesAppleBatteriesInBackground = true
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(), wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(), mobileBattery: mobile,
            appleDeviceDiscovery: discovery
        )
        store.bindMobileBatterySettings(settings)
        await waitForMobileReader { mobile.backgroundReadDeviceIDs == [.trustedDevice("phone-a")] }

        settings.setBluetoothDeviceHidden(BluetoothDeviceIdentity.bleRowID(bleID), hidden: true)
        await waitForMobileReader { mobile.backgroundReadDeviceIDs.isEmpty }
        XCTAssertTrue(mobile.backgroundReadDeviceIDs.isEmpty)

        settings.setBluetoothDeviceHidden(BluetoothDeviceIdentity.bleRowID(bleID), hidden: false)
        await waitForMobileReader { mobile.backgroundReadDeviceIDs == [.trustedDevice("phone-a")] }
        XCTAssertEqual(mobile.backgroundReadDeviceIDs, [.trustedDevice("phone-a")])
        store.stop()
        await reader.finishAll()
    }

    func testBackgroundIntervalReachesBLEScannerAndClearsWhenDisabled() async {
        let scanner = StoreIntervalScannerSpy()
        let bluetooth = BluetoothDeviceController(
            stateMonitor: DeniedBluetoothStateMonitor(),
            nearbyBatteryScanner: scanner
        )
        let suite = makeSuite()
        defer { suite.defaults.removeTestSuite(named: suite.name) }
        let settings = SettingsStore(defaults: suite.defaults)
        settings.showsAppleDevicesAndBattery = true
        settings.showsBluetoothBatteryLevels = true
        settings.showsBluetoothDeviceList = true
        settings.appleBatteryRefreshIntervalMinutes = 3
        settings.refreshesAppleBatteriesInBackground = true
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            bluetoothDevices: bluetooth
        )

        store.bindMobileBatterySettings(settings)
        await waitUntil { !scanner.backgroundRefreshIntervals.isEmpty }
        XCTAssertEqual(scanner.backgroundRefreshIntervals, [.seconds(180)])
        XCTAssertEqual(scanner.backgroundRefreshIntervals.last!, .seconds(180))

        settings.appleBatteryRefreshIntervalMinutes = 4
        await waitUntil { scanner.backgroundRefreshIntervals.contains(.seconds(240)) }
        XCTAssertEqual(scanner.backgroundRefreshIntervals.last!, .seconds(240))

        settings.refreshesAppleBatteriesInBackground = false
        await waitUntil { !scanner.backgroundRefreshIntervals.isEmpty && scanner.backgroundRefreshIntervals[scanner.backgroundRefreshIntervals.count - 1] == nil }
        XCTAssertNil(scanner.backgroundRefreshIntervals[scanner.backgroundRefreshIntervals.count - 1])
        store.stop()
    }

    func testHiddenAliasRevokesBothBackgroundReadRoutesAndRestoreReenablesThem() async throws {
        let trustedReader = ControlledMobileBatteryReader()
        let discoveryReader = ControlledMobileBatteryReader()
        let discovery = AppleDeviceDiscoveryController(reader: discoveryReader)
        let mobile = MobileBatteryController(reader: trustedReader)
        let suite = makeSuite()
        defer { suite.defaults.removeTestSuite(named: suite.name) }
        let settings = SettingsStore(defaults: suite.defaults)
        settings.showsAppleDevicesAndBattery = true
        settings.showsBluetoothBatteryLevels = true
        settings.showsBluetoothDeviceList = true
        settings.refreshesAppleBatteriesInBackground = true
        let bleID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let bleSelection = NearbyBLEDeviceSelection(
            id: bleID, name: "Phone", vendor: .apple, model: "iPhone18,1",
            batteryLevel: 50, batteryLastUpdated: Date()
        )
        suite.defaults.set(try JSONEncoder().encode([bleSelection]), forKey: SettingsStore.nearbyBLEConsentDefaultsKey)
        let trustedCandidate = AppleDeviceCandidate(
            id: .trustedDevice("phone-a"), name: "Phone", model: "iPhone18,1",
            transports: [.usb], trustRequired: false, evidence: .verifiedAppleModel
        )
        suite.defaults.set(try JSONEncoder().encode([trustedCandidate]), forKey: SettingsStore.trustedAppleDeviceMetadataDefaultsKey)
        let reloaded = SettingsStore(defaults: suite.defaults)
        reloaded.refreshesAppleBatteriesInBackground = true
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(), wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(), mobileBattery: mobile,
            appleDeviceDiscovery: discovery
        )
        let bleController = store.bluetoothDevices
        store.bindMobileBatterySettings(reloaded)
        await waitForMobileReader { await discoveryReader.discoveryCount == 1 }
        await waitForMobileReader { mobile.backgroundReadDeviceIDs == [.trustedDevice("phone-a")] }
        XCTAssertEqual(bleController.backgroundReadNearbyBLEDeviceIDs, [bleID])
        await waitForMobileReader { await trustedReader.readCount == 1 }

        reloaded.setBluetoothDeviceHidden(BluetoothDeviceIdentity.bleRowID(bleID), hidden: true)
        await waitForMobileReader { mobile.backgroundReadDeviceIDs.isEmpty }
        let idsWhileBLEAliasHidden = await trustedReader.selectedIDHistory.last
        XCTAssertEqual(idsWhileBLEAliasHidden, [.trustedDevice("phone-a")])
        XCTAssertTrue(mobile.backgroundReadDeviceIDs.isEmpty)
        XCTAssertTrue(bleController.backgroundReadNearbyBLEDeviceIDs.isEmpty)

        reloaded.setBluetoothDeviceHidden(BluetoothDeviceIdentity.bleRowID(bleID), hidden: false)
        await waitForMobileReader { mobile.backgroundReadDeviceIDs == [.trustedDevice("phone-a")] }
        XCTAssertEqual(mobile.backgroundReadDeviceIDs, [.trustedDevice("phone-a")])
        XCTAssertEqual(bleController.backgroundReadNearbyBLEDeviceIDs, [bleID])

        reloaded.setBluetoothDeviceHidden(trustedCandidate.id.rowID, hidden: true)
        await waitForMobileReader { mobile.backgroundReadDeviceIDs.isEmpty }
        XCTAssertTrue(mobile.backgroundReadDeviceIDs.isEmpty)
        XCTAssertTrue(bleController.backgroundReadNearbyBLEDeviceIDs.isEmpty)
        reloaded.setBluetoothDeviceHidden(trustedCandidate.id.rowID, hidden: false)
        await waitForMobileReader { mobile.backgroundReadDeviceIDs == [.trustedDevice("phone-a")] }
        XCTAssertEqual(mobile.backgroundReadDeviceIDs, [.trustedDevice("phone-a")])
        XCTAssertEqual(bleController.backgroundReadNearbyBLEDeviceIDs, [bleID])

        store.stop()
        await trustedReader.finishAll()
        await discoveryReader.finishAll()
    }

    func testHidingBLEAliasImmediatelyRevokesForegroundTrustedReadAndRejectsLateResult() async throws {
        let reader = ControlledMobileBatteryReader()
        let discovery = AppleDeviceDiscoveryController(reader: reader)
        let mobile = MobileBatteryController(reader: reader)
        let suite = makeSuite()
        defer { suite.defaults.removeTestSuite(named: suite.name) }
        let bleID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        let selection = NearbyBLEDeviceSelection(
            id: bleID, name: "Phone", vendor: .apple, model: "iPhone18,1",
            batteryLevel: 50, batteryLastUpdated: Date()
        )
        let trustedCandidate = AppleDeviceCandidate(
            id: .trustedDevice("phone-b"), name: "Phone", model: "iPhone18,1",
            transports: [.usb], trustRequired: false, evidence: .verifiedAppleModel
        )
        suite.defaults.set(
            try JSONEncoder().encode([selection]),
            forKey: SettingsStore.nearbyBLEConsentDefaultsKey
        )
        suite.defaults.set(
            try JSONEncoder().encode([trustedCandidate]),
            forKey: SettingsStore.trustedAppleDeviceMetadataDefaultsKey
        )
        let settings = SettingsStore(defaults: suite.defaults)
        settings.showsAppleDevicesAndBattery = true
        settings.showsBluetoothBatteryLevels = true
        settings.showsBluetoothDeviceList = true
        settings.setPopupSection(.bluetooth, enabled: true)
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(), wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(), mobileBattery: mobile,
            appleDeviceDiscovery: discovery
        )
        store.bindMobileBatterySettings(settings)
        store.setPopoverVisible(true)
        mobile.setAuthorizedDeviceIDs(AppleDeviceCatalog.readAuthorizedIDs(
            visibleIDs: [trustedCandidate.id],
            currentCandidates: [trustedCandidate]
        ))
        mobile.request("bluetooth.summary.mobileBatteryDevices")
        await waitForMobileReader { await reader.readCount == 1 }

        settings.setBluetoothDeviceHidden(BluetoothDeviceIdentity.bleRowID(bleID), hidden: true)
        await waitForMobileReader { await reader.cancellationCount == 1 }
        await reader.complete(0, with: MobileBatteryReadResult(snapshots: [MobileBatterySnapshot(
            id: "phone-b", parentID: nil, name: "Phone", model: "iPhone18,1",
            batteryLevel: 76, isCharging: false, transport: .usb, observedAt: Date()
        )]))
        XCTAssertTrue(mobile.snapshots.isEmpty, "a result from the revoked BLE-alias read cannot be published")

        settings.setBluetoothDeviceHidden(BluetoothDeviceIdentity.bleRowID(bleID), hidden: false)
        mobile.setAuthorizedDeviceIDs(AppleDeviceCatalog.readAuthorizedIDs(
            visibleIDs: [trustedCandidate.id],
            currentCandidates: [trustedCandidate]
        ))
        await waitForMobileReader { await reader.readCount == 2 }
        settings.setBluetoothDeviceHidden(trustedCandidate.id.rowID, hidden: true)
        await waitForMobileReader { await reader.cancellationCount == 2 }
        await reader.complete(1, with: MobileBatteryReadResult(snapshots: [MobileBatterySnapshot(
            id: "phone-b", parentID: nil, name: "Phone", model: "iPhone18,1",
            batteryLevel: 81, isCharging: false, transport: .usb, observedAt: Date()
        )]))

        XCTAssertTrue(mobile.snapshots.isEmpty, "a result from the revoked trusted-alias read cannot be published")
        store.stop()
        await reader.finishAll()
    }

    func testHiddenAliasSettingsImmediatelyRevokeForegroundBLEPermit() async throws {
        let suite = makeSuite()
        defer { suite.defaults.removeTestSuite(named: suite.name) }
        let bleID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B4")!
        let selection = NearbyBLEDeviceSelection(
            id: bleID, name: "Phone", vendor: .apple, model: "iPhone18,1",
            batteryLevel: 50, batteryLastUpdated: Date()
        )
        let trustedCandidate = AppleDeviceCandidate(
            id: .trustedDevice("phone-d"), name: "Phone", model: "iPhone18,1",
            transports: [.usb], trustRequired: false, evidence: .verifiedAppleModel
        )
        suite.defaults.set(
            try JSONEncoder().encode([selection]),
            forKey: SettingsStore.nearbyBLEConsentDefaultsKey
        )
        suite.defaults.set(
            try JSONEncoder().encode([trustedCandidate]),
            forKey: SettingsStore.trustedAppleDeviceMetadataDefaultsKey
        )
        let settings = SettingsStore(defaults: suite.defaults)
        settings.showsAppleDevicesAndBattery = true
        settings.showsBluetoothBatteryLevels = true
        settings.showsBluetoothDeviceList = true
        settings.setPopupSection(.bluetooth, enabled: true)
        let scanner = StoreIntervalScannerSpy()
        let stateMonitor = StoreBluetoothStateMonitorSpy()
        let bluetooth = BluetoothDeviceController(
            stateMonitor: stateMonitor,
            nearbyBatteryScanner: scanner
        )
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(), wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(), bluetoothDevices: bluetooth
        )
        store.bindMobileBatterySettings(settings)
        bluetooth.activate()
        stateMonitor.emit(authorization: .allowed, state: .poweredOn)
        store.setPopoverVisible(true)
        bluetooth.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        bluetooth.requestNearbyBLEDiscovery("foreground-summary")
        bluetooth.setVisibleNearbyBLEDevices([bleID], for: "bluetooth.summary.ble")

        XCTAssertEqual(scanner.allowedReadDeviceIDs, [bleID], "the visible foreground BLE row owns its read permit")
        let reading = NearbyBluetoothBatteryDevice(
            id: bleID, name: "Phone", batteryLevel: 50, model: "iPhone18,1",
            manufacturer: nil, lastUpdated: Date()
        )
        let callbackBeforeHide = scanner.onDevicesChanged

        for hiddenID in [BluetoothDeviceIdentity.bleRowID(bleID), trustedCandidate.id.rowID] {
            callbackBeforeHide?([reading])
            settings.setBluetoothDeviceHidden(hiddenID, hidden: true)

            XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "hiding either alias synchronously revokes the foreground BLE permit")
            await Task.yield()
            XCTAssertTrue(bluetooth.nearbyBatteryDevices.isEmpty, "a pre-hide callback cannot restore a hidden BLE reading")

            settings.setBluetoothDeviceHidden(hiddenID, hidden: false)
            XCTAssertEqual(scanner.allowedReadDeviceIDs, [bleID], "revealing the aliases restores the still-visible row permit")
        }

        store.stop()
    }

    func testSystemSleepStopsBackgroundBLEAndWakeResumesDemand() async {
        let reader = ControlledMobileBatteryReader()
        let discovery = AppleDeviceDiscoveryController(reader: reader)
        let mobile = MobileBatteryController(reader: reader)
        let suite = makeSuite()
        defer { suite.defaults.removeTestSuite(named: suite.name) }
        let settings = SettingsStore(defaults: suite.defaults)
        settings.showsAppleDevicesAndBattery = true
        settings.showsBluetoothBatteryLevels = true
        settings.showsBluetoothDeviceList = true
        settings.refreshesAppleBatteriesInBackground = true
        let wakeCenter = NotificationCenter()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            wakeNotificationCenter: wakeCenter,
            mobileBattery: mobile,
            appleDeviceDiscovery: discovery
        )
        store.bindMobileBatterySettings(settings)
        store.start()
        await waitForMobileReader { await reader.discoveryCount == 1 }

        wakeCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertTrue(discovery.isDiscovering, "trusted USB/Wi-Fi discovery is independent of Bluetooth radio sleep")

        wakeCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        let discoveryCount = await reader.discoveryCount
        XCTAssertEqual(discoveryCount, 1, "wake does not trigger an extra trusted helper cycle")
        store.stop()
        await reader.finishAll()
    }

    func testDisablingMobileBatteryWhileBluetoothViewIsAbsentClearsCacheAndReenableReadsFreshData() async {
        let reader = ControlledMobileBatteryReader()
        let mobile = MobileBatteryController(reader: reader)
        mobile.setAuthorizedDeviceIDs([.trustedDevice("phone-1")])
        let suite = makeSuite()
        defer { suite.defaults.removeTestSuite(named: suite.name) }
        let settings = SettingsStore(defaults: suite.defaults)
        settings.showsBluetoothBatteryLevels = true
        settings.showsAppleDevicesAndBattery = true
        settings.showsBluetoothDeviceList = true
        settings.setPopupSection(.bluetooth, enabled: true)
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            mobileBattery: mobile
        )

        store.bindMobileBatterySettings(settings)
        store.setPopoverVisible(true)
        mobile.request("summary")
        await waitForMobileReader { await reader.readCount == 1 }
        await reader.complete(0, with: MobileBatteryReadResult(snapshots: [MobileBatterySnapshot(
            id: "phone-1", parentID: nil, name: "Phone", model: "iPhone14,3",
            batteryLevel: 71, isCharging: nil, transport: .usb, observedAt: Date()
        )]))
        await waitForMobileReader { mobile.snapshots.count == 1 }

        // The status row has disappeared, so it releases while preserving the
        // ordinary short-lived cache. The settings pane then disables the
        // feature without that view mounted to receive an onChange.
        mobile.release("summary", keepingResults: true)
        XCTAssertEqual(mobile.snapshots.map(\.batteryLevel), [71])
        settings.showsAppleDevicesAndBattery = false
        XCTAssertTrue(mobile.snapshots.isEmpty)

        // Returning while disabled cannot restart reads or restore cached data.
        store.setPopoverVisible(false)
        store.setPopoverVisible(true)
        mobile.request("summary")
        await Task.yield()
        XCTAssertTrue(mobile.snapshots.isEmpty)
        let disabledReadCount = await reader.readCount
        XCTAssertEqual(disabledReadCount, 1)

        // Re-enabling opens a fresh generation through the normal active claim.
        settings.showsAppleDevicesAndBattery = true
        await waitForMobileReader { await reader.readCount == 2 }
        store.stop()
        await reader.finishAll()
    }

    func testDisablingAppleMasterStopsMetadataDiscoveryAndRevokesMobileReads() async {
        let discoveryReader = ControlledMobileBatteryReader()
        let batteryReader = ControlledMobileBatteryReader()
        let discovery = AppleDeviceDiscoveryController(reader: discoveryReader)
        let mobile = MobileBatteryController(reader: batteryReader)
        let suite = makeSuite()
        defer { suite.defaults.removeTestSuite(named: suite.name) }
        let settings = SettingsStore(defaults: suite.defaults)
        settings.showsBluetoothBatteryLevels = true
        settings.showsAppleDevicesAndBattery = true
        settings.showsBluetoothDeviceList = true
        settings.setPopupSection(.bluetooth, enabled: true)
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            mobileBattery: mobile,
            appleDeviceDiscovery: discovery
        )
        store.bindMobileBatterySettings(settings)
        store.setPopoverVisible(true)
        mobile.setAuthorizedDeviceIDs([.trustedDevice("phone-1")])
        mobile.request("summary")
        await waitForMobileReader("initial Apple discovery") { await discoveryReader.discoveryCount == 1 }
        await waitForMobileReader("initial mobile battery read") { await batteryReader.readCount == 1 }
        await discoveryReader.completeDiscovery(0, with: [AppleDeviceCandidate(
            id: .trustedDevice("phone-1"), name: "Phone", model: "iPhone18,1",
            transports: [.usb], trustRequired: false, evidence: .verifiedAppleModel
        )])
        await waitForMobileReader("discovered Apple candidate publication") { discovery.candidates.count == 1 }

        settings.showsAppleDevicesAndBattery = false

        XCTAssertTrue(discovery.candidates.isEmpty)
        XCTAssertTrue(mobile.snapshots.isEmpty)
        await waitForMobileReader("mobile read cancellation after master disable") {
            await batteryReader.cancellationCount == 1
        }
        store.stop()
        await batteryReader.finishAll()
        await discoveryReader.finishAll()
    }

    func testMobileUSBReadStartsWhileBluetoothIsNotActivated() async {
        let reader = ControlledMobileBatteryReader()
        let mobile = MobileBatteryController(reader: reader)
        mobile.setAuthorizedDeviceIDs([.trustedDevice("phone-1")])
        let bluetooth = BluetoothDeviceController(stateMonitor: DeniedBluetoothStateMonitor())
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            bluetoothDevices: bluetooth,
            mobileBattery: mobile
        )
        mobile.request("summary")
        store.setPopoverVisible(true)

        XCTAssertEqual(store.bluetoothDevices.authorization, .denied)
        XCTAssertFalse(store.bluetoothDevices.isActive)
        await waitForMobileReader { await reader.readCount == 1 }
        store.stop()
        await waitForMobileReader { await reader.cancellationCount == 1 }
        await reader.finishAll()
    }

    func testInputMonitorFollowsOptInSettingAndPopoverVisibility() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let input = FakeAudioInputMonitor()
        let wakeCenter = NotificationCenter()
        let suite = makeSuite()
        defer { suite.defaults.removeTestSuite(named: suite.name) }
        let settings = SettingsStore(defaults: suite.defaults)
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            inputMonitor: input,
            refreshInterval: .seconds(60),
            wakeNotificationCenter: wakeCenter
        )

        store.bindInputSettings(settings)
        store.start()

        XCTAssertEqual(input.enabledValues.last, false)
        store.setPopoverVisible(true)
        XCTAssertEqual(input.visibleValues, [true])

        settings.setPopupSection(.audioInput, enabled: true)
        XCTAssertEqual(input.enabledValues.last, true)
        XCTAssertEqual(input.visibleValues, [true, true])

        store.setPopoverVisible(false)
        XCTAssertEqual(input.visibleValues.last, false)
        store.setPopoverVisible(true)
        settings.setPopupSection(.audioInput, enabled: false)
        XCTAssertEqual(input.enabledValues.last, false)

        store.stop()
        XCTAssertEqual(input.stopCount, 1)
    }

    func testInputUpdatesDoNotChangeOutputOrIconProjections() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let input = FakeAudioInputMonitor()
        let suite = makeSuite()
        defer { suite.defaults.removeTestSuite(named: suite.name) }
        let settings = SettingsStore(defaults: suite.defaults)
        let outputStatus = VolumeStatus(scalar: 0.6, isMuted: false, deviceName: "Speakers")
        volume.send(outputStatus)
        let store = AppEnvironment.makeStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            inputMonitor: input
        )
        store.bindInputSettings(settings)
        store.start()
        settings.setPopupSection(.audioInput, enabled: true)
        await waitUntil { store.snapshot.volume == outputStatus }
        store.setPopoverVisible(true)

        let menuBarProjection = MenuBarStatus(snapshot: store.snapshot)
        let dockProjection = makeDockIconKey(for: menuBarProjection)
        let inputStatus = AudioInputStatus(
            devices: [AudioInputDevice(id: AudioDeviceID(42), uid: "input-42", name: "USB Mic")],
            defaultDeviceID: AudioDeviceID(42),
            deviceName: "USB Mic",
            scalar: 0.37,
            canSetVolume: true,
            muteState: .unmuted,
            canSetMute: true,
            isRefreshing: false,
            isBusy: false,
            error: nil
        )
        input.send(inputStatus)
        await waitUntil { store.liveInput == inputStatus }

        XCTAssertEqual(store.snapshot.volume, outputStatus)
        XCTAssertEqual(store.popupSnapshot.volume, outputStatus)
        XCTAssertEqual(MenuBarStatus(snapshot: store.snapshot), menuBarProjection)
        XCTAssertEqual(makeDockIconKey(for: MenuBarStatus(snapshot: store.snapshot)), dockProjection)

        store.stop()
    }

    func testInputCommandsForwardToMonitor() {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let input = FakeAudioInputMonitor()
        let store = makeStore(
            battery: battery,
            wifi: wifi,
            volume: volume,
            inputMonitor: input
        )

        store.selectInputDevice(AudioDeviceID(42))
        store.setInputScalar(0.45)
        store.toggleInputMute()

        XCTAssertEqual(input.selectedDeviceIDs, [AudioDeviceID(42)])
        XCTAssertEqual(input.scalarValues, [0.45])
        XCTAssertEqual(input.toggleMuteCount, 1)
        store.stop()
    }

    func testWakeNotificationRecoversInputMonitor() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let input = FakeAudioInputMonitor()
        let wakeCenter = NotificationCenter()
        let store = makeStore(
            battery: battery,
            wifi: wifi,
            volume: volume,
            inputMonitor: input,
            wakeNotificationCenter: wakeCenter
        )
        let suite = makeSuite()
        defer { suite.defaults.removeTestSuite(named: suite.name) }
        let settings = SettingsStore(defaults: suite.defaults)
        store.bindInputSettings(settings)
        store.start()
        settings.setPopupSection(.audioInput, enabled: true)

        wakeCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await waitUntil { input.recoverCount == 1 }

        XCTAssertEqual(input.recoverCount, 1)
        store.stop()
    }

    func testInputUpdatesAfterDisableAndStopAreIgnored() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let input = FakeAudioInputMonitor()
        let suite = makeSuite()
        defer { suite.defaults.removeTestSuite(named: suite.name) }
        let settings = SettingsStore(defaults: suite.defaults)
        let store = makeStore(
            battery: battery,
            wifi: wifi,
            volume: volume,
            inputMonitor: input
        )
        store.bindInputSettings(settings)
        store.start()
        settings.setPopupSection(.audioInput, enabled: true)
        let accepted = AudioInputStatus(
            devices: [], defaultDeviceID: nil, deviceName: "accepted", scalar: 0.2,
            canSetVolume: false, muteState: nil, canSetMute: false,
            isRefreshing: false, isBusy: false, error: nil
        )
        input.send(accepted)
        await waitUntil { store.liveInput == accepted }

        settings.setPopupSection(.audioInput, enabled: false)
        let disabledValue = AudioInputStatus(
            devices: [], defaultDeviceID: nil, deviceName: "disabled", scalar: 0.8,
            canSetVolume: false, muteState: nil, canSetMute: false,
            isRefreshing: false, isBusy: false, error: nil
        )
        input.send(disabledValue)
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(store.liveInput, accepted)

        store.stop()
        let stoppedValue = AudioInputStatus(
            devices: [], defaultDeviceID: nil, deviceName: "stopped", scalar: 0.9,
            canSetVolume: false, muteState: nil, canSetMute: false,
            isRefreshing: false, isBusy: false, error: nil
        )
        input.send(stoppedValue)
        try? await Task.sleep(for: .milliseconds(10))

        XCTAssertEqual(store.liveInput, accepted)
        XCTAssertEqual(input.stopCount, 1)
    }

    func testPopoverClosingExplicitlyDeactivatesBatteryDetails() async {
        let details = BatteryDetailsController { _, _ in BatteryDetails(cycleCount: 43) }
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(), wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(), batteryDetails: details
        )
        store.setPopoverVisible(true)
        details.activate(state: BatteryPowerState(.placeholder))
        for _ in 0..<100 where details.details == nil {
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertNotNil(details.details)
        store.setPopoverVisible(false)
        XCTAssertFalse(store.isPopoverVisible)
        XCTAssertNil(details.details, "Closing the popover stops collection even if its hosting view is retained")
        details.refresh()
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertNil(details.details)
        store.stop()
    }

    /// A confirmation is answered inside the panel, so closing the panel answers
    /// nothing: the question has to go away with the surface that asked it. The
    /// popover keeps its content view controller alive for a minute, so a view's
    /// own cleanup cannot be what does this — the close event has to.
    func testPopoverClosingCancelsAPendingBluetoothConfirmation() {
        let bluetoothDevices = BluetoothDeviceController()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            bluetoothDevices: bluetoothDevices
        )
        let keyboard = BluetoothDevice(
            id: "D3:6D:6C:40:A3:2E",
            name: "MX Keys",
            kind: .peripheral(.keyboard),
            isConnected: true
        )
        bluetoothDevices.requestDisconnectConfirmation(for: keyboard)
        XCTAssertEqual(
            bluetoothDevices.pendingDisconnectConfirmation,
            BluetoothBatteryReader.normalizedAddress(keyboard.id)
        )

        store.setPopoverVisible(false)

        XCTAssertNil(
            bluetoothDevices.pendingDisconnectConfirmation,
            "Closing the popover cancels a confirmation the panel was asking"
        )
        store.stop()
    }

    func testPopupDebounceIntervalIs500Milliseconds() {
        XCTAssertEqual(SystemStatusStore.popupDebounceInterval, .milliseconds(500))
    }

    func testReportsWhetherPopoverDetailsAreOpen() {
        let wifiNetworks = WiFiNetworkController()
        let bluetoothDevices = BluetoothDeviceController()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            wifiNetworks: wifiNetworks,
            bluetoothDevices: bluetoothDevices
        )
        XCTAssertFalse(store.hasOpenPopoverPanel)

        wifiNetworks.activate(nameAccess: .authorized)
        XCTAssertTrue(store.hasOpenPopoverPanel)

        store.closePopoverDetails()
        XCTAssertFalse(store.hasOpenPopoverPanel)

        store.setBluetoothEnabled(true)
        XCTAssertFalse(store.hasOpenPopoverPanel)

        store.setBluetoothEnabled(false)
        XCTAssertFalse(store.hasOpenPopoverPanel)
    }

    func testReadsTheWiredLinkOnlyWhileThePopoverIsOpenOnEthernet() async {
        let connection = FakeNetworkConnectionMonitor()
        let primaryLink = makePrimaryLinkController()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            connectionMonitor: connection,
            volumeMonitor: FakeVolumeMonitor(),
            primaryLink: primaryLink
        )

        store.start()
        await apply(.ethernet, from: connection, to: store)
        // The connection is wired, but nothing is looking at it yet.
        XCTAssertFalse(primaryLink.isActive)

        store.setPopoverVisible(true)
        XCTAssertTrue(primaryLink.isActive)

        store.setPopoverVisible(false)
        XCTAssertFalse(primaryLink.isActive, "Closing the popover drops the address a cable may have left behind")

        store.stop()
    }

    func testACablePluggedInWhileThePopoverIsOpenStartsTheWiredRead() async {
        let connection = FakeNetworkConnectionMonitor()
        let primaryLink = makePrimaryLinkController()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            connectionMonitor: connection,
            volumeMonitor: FakeVolumeMonitor(),
            primaryLink: primaryLink
        )

        store.start()
        await apply(.wifi, from: connection, to: store)
        store.setPopoverVisible(true)
        XCTAssertFalse(primaryLink.isActive, "A Wi-Fi primary connection has no wired link to report")

        await apply(.ethernet, from: connection, to: store)
        XCTAssertTrue(primaryLink.isActive)

        await apply(.offline, from: connection, to: store)
        XCTAssertFalse(primaryLink.isActive)
        store.stop()
    }

    func testReportsTheWiredPanelAsAnOpenPanel() {
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor()
        )
        XCTAssertFalse(store.hasOpenPopoverPanel)

        store.activatePrimaryLinkPanel()
        XCTAssertTrue(store.hasOpenPopoverPanel)

        store.closePopoverDetails()
        XCTAssertFalse(store.hasOpenPopoverPanel)
    }

    private func makePrimaryLinkController() -> PrimaryLinkController {
        PrimaryLinkController(
            reader: StubPrimaryLinkReader(),
            wiredInterfaces: StubWiredInterfaces(names: ["en0"]),
            periodicRefreshInterval: .seconds(600)
        )
    }

    /// Sends a connection change and waits until the store has applied it, so
    /// the assertion that follows observes the activation rule rather than the
    /// send.
    private func apply(
        _ value: NetworkConnection,
        from monitor: FakeNetworkConnectionMonitor,
        to store: SystemStatusStore,
        constrained: Bool = false
    ) async {
        monitor.send(value, constrained: constrained)
        for _ in 0..<200 where store.snapshot.connection != value
            || store.isNetworkConstrained != constrained {
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(store.snapshot.connection, value)
        XCTAssertEqual(store.isNetworkConstrained, constrained)
    }

    func testARestrictedPathReachesTheStore() async {
        let connection = FakeNetworkConnectionMonitor()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            connectionMonitor: connection,
            volumeMonitor: FakeVolumeMonitor()
        )

        store.start()
        XCTAssertFalse(store.isNetworkConstrained)

        await apply(.ethernet, from: connection, to: store, constrained: true)
        XCTAssertTrue(store.isNetworkConstrained)

        await apply(.ethernet, from: connection, to: store, constrained: false)
        XCTAssertFalse(store.isNetworkConstrained)

        store.stop()
    }

    func testPopupSnapshotDebouncesRapidUpdates() async {
        let battery = FakeBatteryMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            refreshInterval: .seconds(60),
            popupDebounceSleep: { _ in await sleeper.sleep() }
        )
        let finalPopupUpdate = expectation(description: "final popup snapshot published")
        var cancellables = Set<AnyCancellable>()
        store.$popupSnapshot
            .dropFirst()
            .sink { snapshot in
                if snapshot.battery.percentage == 55 {
                    finalPopupUpdate.fulfill()
                }
            }
            .store(in: &cancellables)

        store.start()
        store.setPopoverVisible(true)
        battery.send(makeBattery(percentage: 42))
        await sleeper.waitForCallCount(1)
        battery.send(makeBattery(percentage: 55))
        await sleeper.waitForCallCount(2)

        XCTAssertEqual(store.snapshot.battery.percentage, 55)
        XCTAssertEqual(store.popupSnapshot.battery.percentage, 100)

        sleeper.releaseAll()
        await fulfillment(of: [finalPopupUpdate], timeout: 1)

        XCTAssertEqual(store.popupSnapshot.battery.percentage, 55)
        cancellables.removeAll()
        store.stop()
    }

    func testPopoverOpeningBlanksWiFiNameUntilTheFreshNameArrives() async {
        let wifi = FakeWiFiMonitor()
        let store = makeStore(
            battery: FakeBatteryMonitor(),
            wifi: wifi,
            volume: FakeVolumeMonitor()
        )
        let connected = expectation(description: "connected snapshot applied")
        let named = expectation(description: "name applied to the popup snapshot")
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .sink { snapshot in
                if snapshot.wifi.state == .connected, snapshot.wifi.ssid == nil {
                    connected.fulfill()
                }
            }
            .store(in: &cancellables)
        store.$popupSnapshot
            .sink { snapshot in
                if snapshot.wifi.ssid == "Home" {
                    named.fulfill()
                }
            }
            .store(in: &cancellables)

        store.start()
        wifi.send(WiFiStatus(state: .connected, rssi: -52, nameAccess: .authorized))
        await fulfillment(of: [connected], timeout: 1)

        store.setPopoverVisible(true)
        XCTAssertTrue(store.isResolvingWiFiName)
        XCTAssertNil(store.popupSnapshot.wifi.ssid)

        wifi.send(WiFiStatus(state: .connected, rssi: -52, ssid: "Home", nameAccess: .authorized))
        await fulfillment(of: [named], timeout: 1)

        XCTAssertFalse(store.isResolvingWiFiName)
        XCTAssertEqual(store.popupSnapshot.wifi.ssid, "Home")
        cancellables.removeAll()
        store.stop()
    }

    func testPopoverOpeningKeepsStateTextWhenNoNameIsExpected() async {
        let cases: [(state: WiFiState, access: WiFiNameAccess, ssid: String?)] = [
            (.off, .authorized, nil),
            (.notAssociated, .authorized, nil),
            (.unavailable, .authorized, nil),
            (.connected, .notDetermined, nil),
            (.connected, .denied, nil),
            (.connected, .authorized, "Home")
        ]

        for testCase in cases {
            let wifi = FakeWiFiMonitor()
            let store = makeStore(
                battery: FakeBatteryMonitor(),
                wifi: wifi,
                volume: FakeVolumeMonitor()
            )
            let expected = WiFiStatus(
                state: testCase.state,
                rssi: -52,
                ssid: testCase.ssid,
                nameAccess: testCase.access
            )
            let applied = expectation(description: "snapshot applied")
            var cancellables = Set<AnyCancellable>()
            store.$snapshot
                .sink { snapshot in
                    if snapshot.wifi == expected {
                        applied.fulfill()
                    }
                }
                .store(in: &cancellables)

            store.start()
            wifi.send(expected)
            await fulfillment(of: [applied], timeout: 1)

            store.setPopoverVisible(true)
            XCTAssertFalse(
                store.isResolvingWiFiName,
                "\(testCase.state) \(testCase.access) \(testCase.ssid ?? "nil")"
            )

            cancellables.removeAll()
            store.stop()
        }
    }

    func testPopoverStopsWaitingForANameWhenItCloses() async {
        let wifi = FakeWiFiMonitor()
        let store = makeStore(
            battery: FakeBatteryMonitor(),
            wifi: wifi,
            volume: FakeVolumeMonitor()
        )
        let connected = expectation(description: "connected snapshot applied")
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .sink { snapshot in
                if snapshot.wifi.state == .connected {
                    connected.fulfill()
                }
            }
            .store(in: &cancellables)

        store.start()
        wifi.send(WiFiStatus(state: .connected, rssi: -52, nameAccess: .authorized))
        await fulfillment(of: [connected], timeout: 1)

        store.setPopoverVisible(true)
        XCTAssertTrue(store.isResolvingWiFiName)

        store.setPopoverVisible(false)
        XCTAssertFalse(store.isResolvingWiFiName)
        cancellables.removeAll()
        store.stop()
    }

    func testWiFiNameResolutionFallsBackToStateTextAfterTimeout() async {
        let sleeper = ManualSleeper()
        let wifi = FakeWiFiMonitor()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: wifi,
            volumeMonitor: FakeVolumeMonitor(),
            refreshInterval: .seconds(60),
            nameResolutionTimeout: .seconds(3),
            popupDebounceSleep: { duration in await sleeper.sleep(duration) }
        )
        let connected = expectation(description: "connected snapshot applied")
        let cleared = expectation(description: "name resolution cleared")
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .sink { snapshot in
                if snapshot.wifi.state == .connected {
                    connected.fulfill()
                }
            }
            .store(in: &cancellables)
        store.$isResolvingWiFiName
            .dropFirst()
            .sink { isResolving in
                if !isResolving {
                    cleared.fulfill()
                }
            }
            .store(in: &cancellables)

        store.start()
        wifi.send(WiFiStatus(state: .connected, rssi: -52, nameAccess: .authorized))
        await fulfillment(of: [connected], timeout: 1)

        store.setPopoverVisible(true)
        XCTAssertTrue(store.isResolvingWiFiName)
        await sleeper.waitForCallCount(1)
        XCTAssertEqual(sleeper.durations.last, .seconds(3))

        sleeper.releaseAll()
        await fulfillment(of: [cleared], timeout: 1)

        XCTAssertFalse(store.isResolvingWiFiName)
        cancellables.removeAll()
        store.stop()
    }

    func testWiFiStatusIsAwaitingNameOnlyWhileAuthorizedAndAssociated() {
        XCTAssertTrue(WiFiStatus(state: .connected, rssi: -52, nameAccess: .authorized).isAwaitingName)
        XCTAssertTrue(WiFiStatus(state: .hotspot, rssi: -52, nameAccess: .authorized).isAwaitingName)
        XCTAssertTrue(WiFiStatus(state: .shared, rssi: -52, nameAccess: .authorized).isAwaitingName)
        XCTAssertFalse(
            WiFiStatus(state: .connected, rssi: -52, ssid: "Home", nameAccess: .authorized).isAwaitingName
        )
        XCTAssertTrue(
            WiFiStatus(state: .connected, rssi: -52, ssid: "", nameAccess: .authorized).isAwaitingName
        )
        XCTAssertFalse(WiFiStatus(state: .connected, rssi: -52, nameAccess: .notDetermined).isAwaitingName)
        XCTAssertFalse(WiFiStatus(state: .connected, rssi: -52, nameAccess: .denied).isAwaitingName)
        XCTAssertFalse(WiFiStatus(state: .connected, rssi: -52, nameAccess: .restricted).isAwaitingName)
        XCTAssertFalse(WiFiStatus(state: .off, rssi: nil, nameAccess: .authorized).isAwaitingName)
        XCTAssertFalse(WiFiStatus(state: .notAssociated, rssi: nil, nameAccess: .authorized).isAwaitingName)
        XCTAssertFalse(WiFiStatus(state: .unavailable, rssi: nil, nameAccess: .authorized).isAwaitingName)
    }

    func testPopoverVisibilityUpdatesDetailsAndRefreshes() {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = makeStore(battery: battery, wifi: wifi, volume: volume)

        store.start()
        XCTAssertEqual(wifi.detailsVisibility, [false])
        XCTAssertEqual(volume.detailsVisibility, [false])
        let initialWiFiRefreshCount = wifi.refreshCount
        let initialVolumeRefreshCount = volume.refreshCount

        store.setPopoverVisible(true)
        XCTAssertEqual(wifi.detailsVisibility, [false, true])
        XCTAssertEqual(volume.detailsVisibility, [false, true])
        XCTAssertEqual(wifi.refreshCount, initialWiFiRefreshCount + 1)
        XCTAssertEqual(volume.refreshCount, initialVolumeRefreshCount + 1)

        store.setPopoverVisible(false)
        XCTAssertEqual(wifi.detailsVisibility, [false, true, false])
        XCTAssertEqual(volume.detailsVisibility, [false, true, false])
        store.stop()
    }

    func testSettingsVisibilityKeepsVolumeDetailsAvailableOutsidePopover() {
        let volume = FakeVolumeMonitor()
        let store = makeStore(
            battery: FakeBatteryMonitor(),
            wifi: FakeWiFiMonitor(),
            volume: volume
        )

        store.start()
        XCTAssertEqual(volume.detailsVisibility, [false])

        store.setSettingsVisible(true)
        XCTAssertEqual(volume.detailsVisibility, [false, true])

        store.setPopoverVisible(true)
        store.setPopoverVisible(false)
        XCTAssertEqual(volume.detailsVisibility, [false, true, true, true])

        store.setSettingsVisible(false)
        XCTAssertEqual(volume.detailsVisibility, [false, true, true, true, false])
        store.stop()
    }

    func testSetVolumeUpdatesVisibleVolumeImmediately() async {
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        // The feedback player is injected so this run stays silent: the store's
        // own default plays the bundled tick for a real volume change, which on
        // a Mac whose system switch is on would sound during the tests.
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: volume,
            volumeFeedback: FakeVolumeFeedbackPlayer(),
            refreshInterval: .seconds(60),
            popupDebounceSleep: { _ in await sleeper.sleep() }
        )

        store.start()
        volume.send(
            VolumeStatus(
                scalar: 0.4,
                isMuted: false,
                deviceName: "Speaker"
            )
        )
        await waitUntil { store.liveVolume.scalar == 0.4 }

        store.setVolume(0.7)

        XCTAssertEqual(store.liveVolume.scalar, 0.7)
        XCTAssertEqual(store.snapshot.volume.scalar, 0.7)
        XCTAssertEqual(volume.setVolumeValues, [0.7])

        sleeper.releaseAll()
        store.stop()
    }

    func testVolumeChangePlaysTheFeedbackOncePerRealChange() async {
        let volume = FakeVolumeMonitor()
        let feedback = FakeVolumeFeedbackPlayer()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: volume,
            volumeFeedback: feedback,
            refreshInterval: .seconds(60)
        )

        store.start()
        volume.send(
            VolumeStatus(
                scalar: 0.4,
                isMuted: false,
                deviceName: "Speaker"
            )
        )
        await waitUntil { store.liveVolume.scalar == 0.4 }

        store.setVolume(0.7)
        XCTAssertEqual(feedback.playCount, 1)

        store.setVolume(0.7)
        XCTAssertEqual(feedback.playCount, 1, "An unchanged scalar must stay silent.")

        store.setVolume(2)
        XCTAssertEqual(store.liveVolume.scalar, 1)
        XCTAssertEqual(feedback.playCount, 2)

        store.setVolume(2)
        XCTAssertEqual(
            feedback.playCount,
            2,
            "Scrolling past either end repeats the clamped scalar, which must stay silent."
        )

        store.stop()
    }

    func testMuteToggleDoesNotPlayTheVolumeFeedback() async {
        let volume = FakeVolumeMonitor()
        let feedback = FakeVolumeFeedbackPlayer()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: volume,
            volumeFeedback: feedback,
            refreshInterval: .seconds(60)
        )

        store.start()
        volume.send(
            VolumeStatus(
                scalar: 0.4,
                isMuted: false,
                deviceName: "Speaker"
            )
        )
        await waitUntil { store.liveVolume.scalar == 0.4 }

        store.toggleMute()

        XCTAssertEqual(feedback.playCount, 0)
        store.stop()
    }

    func testMuteToggleWithoutMuteCapabilityDoesNotMutateOrCallController() async {
        let volume = FakeVolumeMonitor()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(), wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: volume, refreshInterval: .seconds(60)
        )
        store.start()
        let status = VolumeStatus(scalar: 0.75, isMuted: false, deviceName: "XV272U",
                                  canSetVolume: true, canMute: false)
        volume.send(status)
        await waitUntil { store.liveVolume == status }

        store.toggleMute()

        XCTAssertEqual(store.liveVolume, status)
        XCTAssertEqual(volume.toggleMuteCount, 0)
        store.stop()
    }

    func testSetVolumePreservesCurrentOutputDevice() async {
        let volume = FakeVolumeMonitor()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: volume,
            volumeFeedback: FakeVolumeFeedbackPlayer(),
            refreshInterval: .seconds(60)
        )
        let currentDevice = AudioOutputDevice(
            id: 42,
            name: "AirPods Pro",
            uid: "airpods-pro",
            isCurrent: true,
            volume: 0.4,
            transport: .bluetooth
        )

        store.start()
        volume.send(VolumeStatus(
            scalar: 0.4,
            isMuted: false,
            deviceName: currentDevice.name,
            currentDevice: currentDevice
        ))
        await waitUntil { store.liveVolume.currentDevice == currentDevice }

        store.setVolume(0.7)

        XCTAssertEqual(store.liveVolume.currentDevice, currentDevice)
        XCTAssertEqual(store.snapshot.volume.currentDevice, currentDevice)
        store.stop()
    }

    func testUnchangedVolumeYieldDoesNotRepublishLiveVolume() async {
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            popupDebounceSleep: { _ in await sleeper.sleep() }
        )

        store.start()
        let unchanged = VolumeStatus(scalar: 0.4, isMuted: false, deviceName: "Speaker")
        volume.send(unchanged)
        await waitUntil { store.liveVolume == unchanged }

        var changeCount = 0
        let cancellable = store.objectWillChange.sink { _ in changeCount += 1 }

        // A fallback poll that re-reads the same scalar, followed by a real
        // change. The stream is FIFO, so observing the second value proves the
        // first one was applied. The changed reading publishes twice — once for
        // `liveVolume` and once for `snapshot` — and the repeated reading must
        // publish nothing at all, so the total is exactly two.
        volume.send(unchanged)
        volume.send(VolumeStatus(scalar: 0.7, isMuted: false, deviceName: "Speaker"))
        await waitUntil { store.liveVolume.scalar == 0.7 }

        XCTAssertEqual(store.snapshot.volume.scalar, 0.7)
        XCTAssertEqual(changeCount, 2)

        cancellable.cancel()
        store.stop()
        sleeper.releaseAll()
    }

    func testLiveVolumeUsesSnapshotWhilePopupSnapshotIsDebounced() async {
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            popupDebounceSleep: { _ in await sleeper.sleep() }
        )
        let liveUpdate = expectation(description: "live volume snapshot published")
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                if snapshot.volume.scalar == 0.42 {
                    liveUpdate.fulfill()
                }
            }
            .store(in: &cancellables)

        store.start()
        store.setPopoverVisible(true)
        volume.send(
            VolumeStatus(
                scalar: 0.42,
                isMuted: false,
                deviceName: "Speaker"
            )
        )
        await fulfillment(of: [liveUpdate], timeout: 1)
        await sleeper.waitForCallCount(1)

        XCTAssertEqual(store.snapshot.volume.scalar, 0.42)
        XCTAssertNil(store.popupSnapshot.volume.scalar)
        XCTAssertEqual(store.liveVolume.scalar, 0.42)

        sleeper.releaseAll()
        cancellables.removeAll()
        store.stop()
    }

    func testOpeningPopupFlushesLatestSnapshotAndRefreshesMonitors() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60)
        )

        let batteryUpdated = expectation(description: "battery snapshot published")
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                if snapshot.battery.percentage == 42 {
                    batteryUpdated.fulfill()
                }
            }
            .store(in: &cancellables)

        store.start()
        battery.send(makeBattery(percentage: 42))
        await fulfillment(of: [batteryUpdated], timeout: 1)

        XCTAssertEqual(store.snapshot.battery.percentage, 42)
        XCTAssertEqual(store.popupSnapshot.battery.percentage, 100)

        store.refreshForPopoverOpening()

        XCTAssertEqual(store.popupSnapshot.battery.percentage, 42)
        XCTAssertEqual(battery.refreshCount, 1)
        XCTAssertEqual(wifi.refreshCount, 1)
        XCTAssertEqual(volume.refreshCount, 1)
        cancellables.removeAll()
        store.stop()
    }

    func testStopCancelsPendingPopupSnapshot() async {
        let battery = FakeBatteryMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            refreshInterval: .seconds(60),
            popupDebounceSleep: { _ in await sleeper.sleep() }
        )

        store.start()
        store.setPopoverVisible(true)
        battery.send(makeBattery(percentage: 42))
        await sleeper.waitForCallCount(1)
        store.stop()

        sleeper.releaseAll()
        await drainMainActorTasks()

        XCTAssertEqual(store.popupSnapshot.battery.percentage, 100)
    }

    func testEqualSnapshotsDoNotPublishTwice() async {
        let battery = FakeBatteryMonitor()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            refreshInterval: .seconds(60)
        )

        let barrierPublished = expectation(description: "barrier snapshot published")
        var placeholderPublishCount = 0
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                if snapshot.battery == .placeholder {
                    placeholderPublishCount += 1
                }
                if snapshot.battery.percentage == 42 {
                    barrierPublished.fulfill()
                }
            }
            .store(in: &cancellables)

        store.start()
        battery.send(.placeholder)
        battery.send(.placeholder)
        battery.send(makeBattery(percentage: 42))
        await fulfillment(of: [barrierPublished], timeout: 1)

        XCTAssertEqual(placeholderPublishCount, 1)
        cancellables.removeAll()
        store.stop()
    }

    func testMakeStoreUsesInjectedConnectionMonitor() async {
        let connection = FakeNetworkConnectionMonitor()
        let store = AppEnvironment.makeStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            connectionMonitor: connection,
            volumeMonitor: FakeVolumeMonitor()
        )
        let updateApplied = expectation(description: "injected connection monitor update applied")
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                guard snapshot.connection == .ethernet else { return }
                updateApplied.fulfill()
            }
            .store(in: &cancellables)

        store.start()
        connection.send(.ethernet)
        await fulfillment(of: [updateApplied], timeout: 1)

        XCTAssertEqual(store.snapshot.connection, .ethernet)
        cancellables.removeAll()
        store.stop()
    }

    func testMakeStoreUsesInjectedMonitors() async {
        let battery = FakeBatteryMonitor()
        let store = AppEnvironment.makeStore(
            batteryMonitor: battery,
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor()
        )

        let updateApplied = expectation(description: "injected monitor update applied")
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                guard snapshot.battery.percentage == 55 else { return }
                updateApplied.fulfill()
            }
            .store(in: &cancellables)

        store.start()
        battery.send(makeBattery(percentage: 55))
        await fulfillment(of: [updateApplied], timeout: 1)

        XCTAssertEqual(store.snapshot.battery.percentage, 55)
        cancellables.removeAll()
        store.stop()
    }

    func testStartTwiceStartsEachMonitorExactlyOnce() {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = makeStore(battery: battery, wifi: wifi, volume: volume)

        store.start()
        store.start()

        XCTAssertEqual(battery.startCount, 1)
        XCTAssertEqual(wifi.startCount, 1)
        XCTAssertEqual(volume.startCount, 1)
        store.stop()
    }

    func testRequestWiFiNameAccessForwardsToMonitor() {
        let wifi = FakeWiFiMonitor()
        wifi.nameAccessRequestResult = .openLocationSettings
        let store = makeStore(
            battery: FakeBatteryMonitor(),
            wifi: wifi,
            volume: FakeVolumeMonitor()
        )

        store.start()
        XCTAssertEqual(store.requestWiFiNameAccess(), .openLocationSettings)

        XCTAssertEqual(wifi.nameAccessRequestCount, 1)
        store.stop()
        XCTAssertEqual(store.requestWiFiNameAccess(), .notNeeded)
        XCTAssertEqual(wifi.nameAccessRequestCount, 1)
    }

    func testStopTwiceStopsEachMonitorExactlyOnce() {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = makeStore(battery: battery, wifi: wifi, volume: volume)

        store.start()
        store.stop()
        store.stop()

        XCTAssertEqual(battery.stopCount, 1)
        XCTAssertEqual(wifi.stopCount, 1)
        XCTAssertEqual(volume.stopCount, 1)
    }

    func testBufferedMonitorUpdateAfterStopDoesNotMutateSnapshot() async {
        let battery = FakeBatteryMonitor()
        let store = makeStore(
            battery: battery,
            wifi: FakeWiFiMonitor(),
            volume: FakeVolumeMonitor()
        )

        store.start()
        let stoppedSnapshot = store.snapshot
        battery.send(makeBattery(percentage: 42))
        store.stop()
        await drainMainActorTasks()

        XCTAssertEqual(store.snapshot, stoppedSnapshot)
        XCTAssertEqual(battery.stopCount, 1)
    }

    func testStartAfterStopDoesNotStartMonitorsAgain() {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = makeStore(battery: battery, wifi: wifi, volume: volume)

        store.start()
        store.stop()
        store.start()

        XCTAssertEqual(battery.startCount, 1)
        XCTAssertEqual(wifi.startCount, 1)
        XCTAssertEqual(volume.startCount, 1)
        XCTAssertEqual(battery.stopCount, 1)
        XCTAssertEqual(wifi.stopCount, 1)
        XCTAssertEqual(volume.stopCount, 1)
    }

    func testPeriodicRefreshUsesInjectedSleep() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() }
        )

        store.start()
        await sleeper.waitForCallCount(1)
        sleeper.releaseNext()
        await sleeper.waitForCallCount(2)

        // The popover and the Settings window are both closed, so the battery —
        // which is drawn into the icon — is refreshed and the two detail-level
        // monitors wait for the watchdog tick.
        XCTAssertEqual(battery.refreshCount, 1)
        XCTAssertEqual(wifi.refreshCount, 0)
        XCTAssertEqual(volume.refreshCount, 0)

        store.stop()
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(2)
    }

    func testChangingRefreshIntervalAffectsNextSleepCycle() async {
        let sleeper = ManualSleeper()
        let battery = FakeBatteryMonitor()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            refreshInterval: .seconds(60),
            sleep: { duration in await sleeper.sleep(duration) }
        )

        store.start()
        await sleeper.waitForCallCount(1)

        store.setRefreshInterval(.seconds(5))
        sleeper.releaseNext()
        await sleeper.waitForCompletionCount(1)
        await sleeper.waitForCallCount(2)

        XCTAssertEqual(sleeper.durations, [.seconds(60), .seconds(5)])
        store.stop()
    }

    func testFallbackSleepToleranceCoversTheAdjustableRange() {
        // A fifth of the interval. The fallback poll is a safety net behind the
        // push channels, so macOS may slide it onto another timer, but the sampling
        // cadence has to survive that.
        XCTAssertEqual(SystemStatusStore.refreshSleepTolerance(for: .seconds(5)), .seconds(1))
        XCTAssertEqual(SystemStatusStore.refreshSleepTolerance(for: .seconds(10)), .seconds(2))
        XCTAssertEqual(SystemStatusStore.refreshSleepTolerance(for: .seconds(15)), .seconds(3))
        XCTAssertEqual(SystemStatusStore.refreshSleepTolerance(for: .seconds(30)), .seconds(6))
        XCTAssertEqual(SystemStatusStore.refreshSleepTolerance(for: .seconds(60)), .seconds(12))
        XCTAssertEqual(SystemStatusStore.refreshSleepTolerance(for: .seconds(1)), .milliseconds(200))
    }

    func testFallbackPollDefaultsToFifteenSeconds() async {
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            sleep: { duration in await sleeper.sleep(duration) }
        )

        store.start()
        await sleeper.waitForCallCount(1)

        XCTAssertEqual(sleeper.durations.first, .seconds(15))
        store.stop()
        sleeper.releaseAll()
    }

    func testStopPreventsFurtherPeriodicRefresh() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() }
        )

        store.start()
        // Opening the popover refreshes everything, and the tick that follows
        // refreshes everything again while it stays open.
        store.setPopoverVisible(true)
        await sleeper.waitForCallCount(1)
        sleeper.releaseNext()
        await sleeper.waitForCallCount(2)

        store.stop()
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(2)
        store.refreshAll()

        XCTAssertEqual(battery.refreshCount, 2)
        XCTAssertEqual(wifi.refreshCount, 2)
        XCTAssertEqual(volume.refreshCount, 2)
    }

    func testFallbackTickRefreshesBatteryEveryTickAndWiFiAndVolumeOnTheHiddenStride() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() }
        )

        store.start()
        for tick in 1...SystemStatusStore.hiddenFallbackTickStride {
            await sleeper.waitForCallCount(tick)
            sleeper.releaseNext()
            await sleeper.waitForCompletionCount(tick)
        }
        await sleeper.waitForCallCount(SystemStatusStore.hiddenFallbackTickStride + 1)

        XCTAssertEqual(battery.refreshCount, SystemStatusStore.hiddenFallbackTickStride)
        XCTAssertEqual(wifi.refreshCount, 1, "one watchdog refresh against a missed CoreWLAN event")
        XCTAssertEqual(volume.refreshCount, 1, "one watchdog refresh against a missed CoreAudio event")

        store.stop()
        sleeper.releaseAll()
    }

    func testFallbackTickRefreshesWiFiAndVolumeWhileThePopoverIsOpen() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() }
        )

        store.start()
        store.setPopoverVisible(true)
        await sleeper.waitForCallCount(1)
        sleeper.releaseNext()
        await sleeper.waitForCompletionCount(1)
        await sleeper.waitForCallCount(2)

        XCTAssertEqual(battery.refreshCount, 2)
        XCTAssertEqual(wifi.refreshCount, 2)
        XCTAssertEqual(volume.refreshCount, 2)

        store.stop()
        sleeper.releaseAll()
    }

    func testPushedWiFiAndVolumeStillUpdateTheSnapshotWhileThePopoverIsClosed() async {
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() }
        )

        store.start()
        XCTAssertFalse(store.isPopoverVisible)

        wifi.send(WiFiStatus(state: .connected, rssi: -42))
        volume.send(VolumeStatus(scalar: 0.8, isMuted: false, deviceName: "Studio Display"))
        await waitUntil {
            store.snapshot.wifi.rssi == -42 && store.snapshot.volume.scalar == 0.8
        }

        XCTAssertEqual(store.snapshot.wifi.state, .connected)
        XCTAssertEqual(store.snapshot.volume.scalar, 0.8)
        store.stop()
        sleeper.releaseAll()
    }

    func testFallbackTickSkipsWhileTheDisplayIsAsleepAndRefreshesOnDisplayWake() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let displayCenter = NotificationCenter()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() },
            wakeNotificationCenter: displayCenter
        )

        store.start()
        displayCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        // The observer hops through the main actor, so wait for the flag before
        // releasing the tick that must be skipped.
        await waitUntil { store.isDisplayAsleep }

        await sleeper.waitForCallCount(1)
        sleeper.releaseNext()
        await sleeper.waitForCompletionCount(1)
        await sleeper.waitForCallCount(2)

        XCTAssertEqual(battery.refreshCount, 0, "a sleeping display has no menu bar to keep fresh")
        XCTAssertEqual(wifi.refreshCount, 0)
        XCTAssertEqual(volume.refreshCount, 0)

        displayCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        await waitUntil { battery.refreshCount == 1 }

        XCTAssertFalse(store.isDisplayAsleep)
        XCTAssertEqual(wifi.refreshCount, 1)
        XCTAssertEqual(volume.refreshCount, 1)
        XCTAssertEqual(battery.recoverCount, 1, "the display wake resynchronizes the monitors")

        store.stop()
        sleeper.releaseAll()
    }

    /// Regression: a display-only sleep — a screen saver, the display-sleep
    /// timer, or any Mac whose system sleep is off — is cleared only by
    /// `screensDidWakeNotification`. If that one notification is lost, the
    /// display-asleep flag must not stop the fallback poll for the rest of the
    /// session: the bounded skip counter runs one tick per cap, so the battery
    /// percentage drawn into the icon cannot freeze while the display is on.
    func testFallbackTickSelfHealsAfterTheDisplayAsleepSkipCap() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let displayCenter = NotificationCenter()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() },
            wakeNotificationCenter: displayCenter
        )

        store.start()
        displayCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        await waitUntil { store.isDisplayAsleep }

        // Drive exactly the cap's worth of ticks and never deliver a wake
        // notification. Every tick but the last must skip; the last one must run
        // the battery refresh anyway.
        let cap = SystemStatusStore.maximumDisplayAsleepSkips
        for tick in 1...cap {
            await sleeper.waitForCallCount(tick)
            sleeper.releaseNext()
            await sleeper.waitForCompletionCount(tick)
        }
        await sleeper.waitForCallCount(cap + 1)

        XCTAssertTrue(store.isDisplayAsleep, "no wake notification was delivered")
        XCTAssertEqual(
            battery.refreshCount,
            1,
            "the cap must refresh the battery instead of skipping for the rest of the session"
        )
        XCTAssertEqual(wifi.refreshCount, 0, "the forced tick is not a hidden-stride tick")
        XCTAssertEqual(volume.refreshCount, 0)

        // The counter reset with the forced tick, so the next cap's worth of
        // ticks skips again before the one after it runs: the poll stays bounded
        // instead of latching on.
        for tick in (cap + 1)...(cap * 2 - 1) {
            await sleeper.waitForCallCount(tick)
            sleeper.releaseNext()
            await sleeper.waitForCompletionCount(tick)
        }
        await sleeper.waitForCallCount(cap * 2)

        XCTAssertEqual(
            battery.refreshCount,
            1,
            "the cap resets the skip counter instead of refreshing on every later tick"
        )

        store.stop()
        sleeper.releaseAll()
    }

    /// Regression: the system wake must clear the display-asleep flag on its
    /// own. `screensDidWakeNotification` is the only other path that clears it,
    /// so a wake cycle that delivers only `didWakeNotification` would otherwise
    /// leave the flag set and the fallback poll disabled for the rest of the
    /// session.
    func testSystemWakeAloneClearsDisplayAsleepAndResumesFallbackTick() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let wakeCenter = NotificationCenter()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() },
            wakeNotificationCenter: wakeCenter
        )

        store.start()
        wakeCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        await waitUntil { store.isDisplayAsleep }

        // The first tick is parked on the manual sleeper. Release it before
        // asserting, otherwise the tick has not run yet and the assertions below
        // would hold no matter what the guard does.
        await sleeper.waitForCallCount(1)
        sleeper.releaseNext()
        await sleeper.waitForCompletionCount(1)
        await sleeper.waitForCallCount(2)

        XCTAssertEqual(battery.refreshCount, 0, "a sleeping display must skip the tick")
        XCTAssertEqual(wifi.refreshCount, 0)
        XCTAssertEqual(volume.refreshCount, 0)

        // Only the system wake, never `screensDidWakeNotification`.
        wakeCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await waitUntil { !store.isDisplayAsleep }
        await waitUntil { battery.refreshCount == 1 }

        XCTAssertFalse(
            store.isDisplayAsleep,
            "the system wake notification must clear the display-asleep flag"
        )
        XCTAssertEqual(battery.recoverCount, 1, "the system wake resynchronizes the monitors")

        // The wake refreshed on its own; now release the parked tick and prove
        // the poll resumes because the guard no longer blocks it.
        sleeper.releaseNext()
        await waitUntil { battery.refreshCount == 2 }

        XCTAssertEqual(battery.refreshCount, 2, "the fallback tick must resume after a system wake")
        // The two counts below come from different work: `wifi`/`volume` at 1 are
        // the wake handler's `refreshAll()`. The resumed tick is the first tick of
        // a new stride cycle, so it refreshes the battery only and adds nothing to
        // Wi-Fi or volume.
        XCTAssertEqual(
            wifi.refreshCount,
            1,
            "only the wake handler's refreshAll() may refresh Wi-Fi here"
        )
        XCTAssertEqual(
            volume.refreshCount,
            1,
            "only the wake handler's refreshAll() may refresh volume here"
        )

        store.stop()
        sleeper.releaseAll()
    }

    func testDisplayWakeRecoversBeforeItRefreshes() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let displayCenter = NotificationCenter()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() },
            wakeNotificationCenter: displayCenter
        )
        var recoveryAndRefreshOrder: [String] = []
        battery.onRecover = { recoveryAndRefreshOrder.append("battery.recover") }
        wifi.onRecover = { recoveryAndRefreshOrder.append("wifi.recover") }
        volume.onRecover = { recoveryAndRefreshOrder.append("volume.recover") }
        battery.onRefresh = { recoveryAndRefreshOrder.append("battery.refresh") }
        wifi.onRefresh = { recoveryAndRefreshOrder.append("wifi.refresh") }
        volume.onRefresh = { recoveryAndRefreshOrder.append("volume.refresh") }

        store.start()
        displayCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        await waitUntil { store.isDisplayAsleep }

        displayCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        await waitUntil { !store.isDisplayAsleep && volume.refreshCount == 1 }

        XCTAssertEqual(recoveryAndRefreshOrder, [
            "battery.recover",
            "wifi.recover",
            "volume.recover",
            "battery.refresh",
            "wifi.refresh",
            "volume.refresh"
        ])

        store.stop()
        sleeper.releaseAll()
    }

    func testWakeNotificationRefreshesAllMonitorsExactlyOnce() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let wakeCenter = NotificationCenter()
        let store = makeStore(
            battery: battery,
            wifi: wifi,
            volume: volume,
            wakeNotificationCenter: wakeCenter
        )
        let refreshed = expectation(description: "all monitors refreshed after wake")
        refreshed.assertForOverFulfill = true
        var recoveryAndRefreshOrder: [String] = []
        battery.onRecover = { recoveryAndRefreshOrder.append("battery.recover") }
        wifi.onRecover = { recoveryAndRefreshOrder.append("wifi.recover") }
        volume.onRecover = { recoveryAndRefreshOrder.append("volume.recover") }
        battery.onRefresh = { recoveryAndRefreshOrder.append("battery.refresh") }
        wifi.onRefresh = { recoveryAndRefreshOrder.append("wifi.refresh") }
        volume.onRefresh = {
            recoveryAndRefreshOrder.append("volume.refresh")
            refreshed.fulfill()
        }

        store.start()
        wakeCenter.post(
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        await fulfillment(of: [refreshed], timeout: 1)

        XCTAssertEqual(battery.refreshCount, 1)
        XCTAssertEqual(wifi.refreshCount, 1)
        XCTAssertEqual(volume.refreshCount, 1)
        XCTAssertEqual(battery.recoverCount, 1)
        XCTAssertEqual(wifi.recoverCount, 1)
        XCTAssertEqual(volume.recoverCount, 1)
        XCTAssertEqual(recoveryAndRefreshOrder, [
            "battery.recover",
            "wifi.recover",
            "volume.recover",
            "battery.refresh",
            "wifi.refresh",
            "volume.refresh"
        ])
        store.stop()
    }

    func testWakeNotificationAfterStopDoesNotRefresh() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let wakeCenter = SpyWakeNotificationCenter()
        let store = makeStore(
            battery: battery,
            wifi: wifi,
            volume: volume,
            wakeNotificationCenter: wakeCenter
        )
        let noRefresh = expectation(description: "no refresh after stop")
        noRefresh.isInverted = true
        noRefresh.assertForOverFulfill = true
        battery.onRefresh = { noRefresh.fulfill() }

        store.start()
        XCTAssertEqual(wakeCenter.addCount, 4)
        store.stop()
        XCTAssertEqual(wakeCenter.removeCount, 4)
        wakeCenter.post(
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        await fulfillment(of: [noRefresh], timeout: 0.2)

        XCTAssertEqual(battery.refreshCount, 0)
        XCTAssertEqual(wifi.refreshCount, 0)
        XCTAssertEqual(volume.refreshCount, 0)
        XCTAssertEqual(battery.recoverCount, 0)
        XCTAssertEqual(wifi.recoverCount, 0)
        XCTAssertEqual(volume.recoverCount, 0)
    }

    func testStoreDeallocatesWhenMonitorTasksOnlyReferenceItWeakly() {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        weak var weakStore: SystemStatusStore?

        do {
            var store: SystemStatusStore? = makeStore(
                battery: battery,
                wifi: wifi,
                volume: volume
            )
            weakStore = store
            store?.start()
            store = nil
        }

        XCTAssertNil(weakStore)
        battery.stop()
        wifi.stop()
        volume.stop()
    }

    func testUnavailableMonitorDoesNotPreventOtherValuesFromMerging() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = makeStore(battery: battery, wifi: wifi, volume: volume)
        let merged = expectation(description: "available monitors merged around unavailable Wi-Fi")
        let fulfillOnce = SingleFulfillment()
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                guard snapshot.battery.percentage == 42,
                      snapshot.wifi.state == .unavailable,
                      snapshot.volume.scalar == 0.6 else { return }
                fulfillOnce.fulfill(merged)
            }
            .store(in: &cancellables)

        store.start()
        battery.send(makeBattery(percentage: 42))
        wifi.send(.placeholder)
        volume.send(VolumeStatus(scalar: 0.6, isMuted: false, deviceName: "Speaker"))
        await fulfillment(of: [merged], timeout: 1)

        XCTAssertEqual(store.snapshot.battery.percentage, 42)
        XCTAssertEqual(store.snapshot.wifi.state, .unavailable)
        XCTAssertEqual(store.snapshot.volume.scalar, 0.6)
        cancellables.removeAll()
        store.stop()
    }

    func testFinishedMonitorStreamDoesNotPreventOtherMonitorsFromPublishing() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = makeStore(battery: battery, wifi: wifi, volume: volume)
        let merged = expectation(description: "remaining monitors continue publishing")
        let fulfillOnce = SingleFulfillment()
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                guard snapshot.battery.percentage == 42,
                      snapshot.wifi.state == .unavailable,
                      snapshot.volume.scalar == 0.6 else { return }
                fulfillOnce.fulfill(merged)
            }
            .store(in: &cancellables)

        store.start()
        wifi.finishUpdates()
        battery.send(makeBattery(percentage: 42))
        volume.send(VolumeStatus(scalar: 0.6, isMuted: false, deviceName: "Speaker"))
        await fulfillment(of: [merged], timeout: 1)

        XCTAssertEqual(wifi.finishCount, 1)
        XCTAssertEqual(store.snapshot.battery.percentage, 42)
        XCTAssertEqual(store.snapshot.wifi.state, .unavailable)
        XCTAssertEqual(store.snapshot.volume.scalar, 0.6)
        cancellables.removeAll()
        store.stop()
    }

    func testConnectionMonitorUpdateIsPublished() async {
        let connection = FakeNetworkConnectionMonitor()
        let store = makeStore(
            battery: FakeBatteryMonitor(),
            wifi: FakeWiFiMonitor(),
            volume: FakeVolumeMonitor(),
            connection: connection
        )
        let updated = expectation(description: "connection update published")
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                guard snapshot.connection == .ethernet else { return }
                updated.fulfill()
            }
            .store(in: &cancellables)

        store.start()
        connection.send(.ethernet)
        await fulfillment(of: [updated], timeout: 1)

        XCTAssertEqual(store.snapshot.connection, .ethernet)
        cancellables.removeAll()
        store.stop()
    }

    private func makeStore(
        battery: FakeBatteryMonitor,
        wifi: FakeWiFiMonitor,
        volume: FakeVolumeMonitor,
        connection: FakeNetworkConnectionMonitor? = nil,
        inputMonitor: FakeAudioInputMonitor? = nil,
        wakeNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) -> SystemStatusStore {
        if let connection {
            return SystemStatusStore(
                batteryMonitor: battery,
                wifiMonitor: wifi,
                connectionMonitor: connection,
                volumeMonitor: volume,
                inputMonitor: inputMonitor,
                refreshInterval: .seconds(60),
                wakeNotificationCenter: wakeNotificationCenter
            )
        }
        return SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            inputMonitor: inputMonitor,
            refreshInterval: .seconds(60),
            wakeNotificationCenter: wakeNotificationCenter
        )
    }

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.SystemStatusStore.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("could not create isolated user defaults suite")
        }
        defaults.removeTestSuite(named: name)
        return (defaults, name)
    }

    private func makeDockIconKey(for status: MenuBarStatus) -> DockIconRenderKey {
        DockIconRenderKey(
            scene: makeIconPresentationScene(
                status: status,
                volume: VolumeIconOptions(displayStyle: .arc)
            ),
            backgroundStyle: .light,
            pixelLength: DockIconRenderer.pixelSize
        )
    }

    private func makeBattery(percentage: Int) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
    }

    private func drainMainActorTasks() async {
        await Task { @MainActor in }.value
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))

        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for the expected state")
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private func waitForMobileReader(
        _ message: String = "mobile reader state did not settle",
        condition: () async -> Bool
    ) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()), ContinuousClock.now < deadline {
            await Task.yield()
        }
        let reached = await condition()
        XCTAssertTrue(reached, message)
    }
}

@MainActor
private final class FakeVPNMonitor: VPNMonitoring {
    let updates: AsyncStream<VPNStatus>
    private let continuation: AsyncStream<VPNStatus>.Continuation
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var refreshCount = 0
    private(set) var recoverCount = 0

    init() {
        (updates, continuation) = MonitorStream.make(of: VPNStatus.self)
    }

    func start() {
        startCount += 1
        refresh()
    }
    func stop() { stopCount += 1 }
    func refresh() { refreshCount += 1 }
    func recover() { recoverCount += 1 }
}

@MainActor
private final class ManualSleeper {
    private(set) var callCount = 0
    private(set) var completionCount = 0
    private(set) var durations: [Duration] = []

    private var sleepContinuations: [CheckedContinuation<Void, Never>] = []
    private var callWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var completionWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func sleep(_ duration: Duration = .zero) async {
        callCount += 1
        durations.append(duration)
        resumeCallWaiters()

        await withCheckedContinuation { continuation in
            sleepContinuations.append(continuation)
        }

        completionCount += 1
        resumeCompletionWaiters()
    }

    func waitForCallCount(_ count: Int) async {
        guard callCount < count else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((count, continuation))
        }
    }

    func waitForCompletionCount(_ count: Int) async {
        guard completionCount < count else { return }
        await withCheckedContinuation { continuation in
            completionWaiters.append((count, continuation))
        }
    }

    func releaseNext() {
        guard !sleepContinuations.isEmpty else { return }
        sleepContinuations.removeFirst().resume()
    }

    func releaseAll() {
        let continuations = sleepContinuations
        sleepContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    private func resumeCallWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in callWaiters {
            if callCount >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        callWaiters = remaining
    }

    private func resumeCompletionWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in completionWaiters {
            if completionCount >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        completionWaiters = remaining
    }
}

@MainActor
private final class SingleFulfillment {
    private var hasFulfilled = false

    func fulfill(_ expectation: XCTestExpectation) {
        guard !hasFulfilled else { return }
        hasFulfilled = true
        expectation.fulfill()
    }
}

private final class SpyWakeNotificationCenter: NotificationCenter, @unchecked Sendable {
    private(set) var addCount = 0
    private(set) var removeCount = 0

    override func addObserver(
        forName name: NSNotification.Name?,
        object: Any?,
        queue: OperationQueue?,
        using block: @escaping @Sendable (Notification) -> Void
    ) -> NSObjectProtocol {
        addCount += 1
        return super.addObserver(forName: name, object: object, queue: queue, using: block)
    }

    override func removeObserver(_ observer: Any) {
        removeCount += 1
        super.removeObserver(observer)
    }
}

@MainActor
private final class StoreIntervalScannerSpy: BluetoothLEBatteryScanning {
    var onDevicesChanged: (([NearbyBluetoothBatteryDevice]) -> Void)?
    var onCandidatesChanged: (([NearbyBLEDeviceCandidate]) -> Void)?
    var onReadFailures: ((Set<UUID>) -> Void)?
    var onIsScanningChanged: ((Bool) -> Void)?
    private(set) var allowedReadDeviceIDs: Set<UUID> = []
    private(set) var isRunning = false
    private(set) var isScanning = false
    private(set) var backgroundRefreshIntervals: [Duration?] = []

    func setAllowedReadDeviceIDs(_ ids: Set<UUID>) { allowedReadDeviceIDs = ids }
    func revokeReadDeviceIDs(_ ids: Set<UUID>) { allowedReadDeviceIDs.subtract(ids) }
    func setInitialReadCandidateIDs(_ ids: Set<UUID>) { _ = ids }
    func setBackgroundRefreshInterval(_ interval: Duration?) { backgroundRefreshIntervals.append(interval) }
    func start() { isRunning = true }
    func refresh() {}
    func stop() { isRunning = false; isScanning = false }
}

@MainActor
private final class StoreBluetoothStateMonitorSpy: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    private(set) var authorization: BluetoothAuthorizationStatus = .allowed

    func start() {}
    func stop() {}

    func emit(authorization: BluetoothAuthorizationStatus, state: BluetoothManagerState) {
        self.authorization = authorization
        onStateChange?(authorization, state)
    }
}

@MainActor
private final class FakeNetworkConnectionMonitor: NetworkConnectionMonitoring {
    let updates: AsyncStream<NetworkPathSnapshot>
    private let continuation: AsyncStream<NetworkPathSnapshot>.Continuation

    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() {}
    func stop() { continuation.finish() }
    func recover() {}

    /// These tests are about the store, not about `NWPath`, so they name the
    /// connection they mean and the snapshot is spelled out here once.
    func send(_ value: NetworkConnection, constrained: Bool = false) {
        continuation.yield(
            NetworkPathSnapshot(
                connected: value != .offline,
                wired: value == .ethernet,
                wireless: value == .wifi,
                constrained: constrained
            )
        )
    }

    func send(_ path: NetworkPathSnapshot) { continuation.yield(path) }
}

/// Answers nothing: these tests observe whether the wired read runs, not what it
/// finds. The resolution itself is covered by `PrimaryLinkTests`.
private final class StubPrimaryLinkReader: PrimaryLinkReading {
    func read(
        wiredInterfaces: [WiredInterface],
        completion: @escaping @Sendable (PrimaryLinkDetails?) -> Void
    ) {}
}

private struct StubWiredInterfaces: WiredInterfaceProviding {
    let names: [String]

    func wiredInterfaces() -> [WiredInterface] { names.map { WiredInterface(name: $0) } }
}

@MainActor
private final class DeniedBluetoothStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .denied

    func start() { onStateChange?(.denied, .unknown) }
    func stop() {}
}

@MainActor
private final class FakeBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var refreshCount = 0
    private(set) var recoverCount = 0
    var onRecover: (() -> Void)?
    var onRefresh: (() -> Void)?
    private let continuation: AsyncStream<BatteryStatus>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() { startCount += 1 }
    func stop() {
        stopCount += 1
        continuation.finish()
    }
    func refresh() {
        refreshCount += 1
        onRefresh?()
    }
    func recover() {
        recoverCount += 1
        onRecover?()
    }
    func send(_ value: BatteryStatus) { continuation.yield(value) }
}

@MainActor
private final class FakeWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var refreshCount = 0
    private(set) var recoverCount = 0
    private(set) var finishCount = 0
    private(set) var nameAccessRequestCount = 0
    var nameAccessRequestResult: WiFiNameAccessRequestResult = .requested
    private(set) var detailsVisibility: [Bool] = []
    var onRecover: (() -> Void)?
    var onRefresh: (() -> Void)?
    private let continuation: AsyncStream<WiFiStatus>.Continuation

    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() { startCount += 1 }
    func stop() {
        stopCount += 1
        continuation.finish()
    }
    func refresh() {
        refreshCount += 1
        onRefresh?()
    }
    func recover() {
        recoverCount += 1
        onRecover?()
    }
    func requestNameAccess() -> WiFiNameAccessRequestResult {
        nameAccessRequestCount += 1
        return nameAccessRequestResult
    }

    func setDetailsVisible(_ visible: Bool) {
        detailsVisibility.append(visible)
    }
    func send(_ value: WiFiStatus) { continuation.yield(value) }
    func finishUpdates() {
        finishCount += 1
        continuation.finish()
    }
}

@MainActor
private final class FakeAudioInputMonitor: AudioInputMonitoring {
    let updates: AsyncStream<AudioInputStatus>
    private let continuation: AsyncStream<AudioInputStatus>.Continuation
    private(set) var enabledValues: [Bool] = []
    private(set) var visibleValues: [Bool] = []
    private(set) var recoverCount = 0
    private(set) var stopCount = 0
    private(set) var selectedDeviceIDs: [AudioDeviceID] = []
    private(set) var scalarValues: [Double] = []
    private(set) var toggleMuteCount = 0

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func setEnabled(_ enabled: Bool) { enabledValues.append(enabled) }
    func setVisible(_ visible: Bool) { visibleValues.append(visible) }
    func recover() { recoverCount += 1 }
    func select(_ id: AudioDeviceID) { selectedDeviceIDs.append(id) }
    func setScalar(_ value: Double) { scalarValues.append(value) }
    func toggleMute() { toggleMuteCount += 1 }
    func stop() { stopCount += 1 }
    func send(_ value: AudioInputStatus) { continuation.yield(value) }
}

@MainActor
private final class FakeVolumeMonitor: VolumeMonitoring, VolumeControlling {
    let updates: AsyncStream<VolumeStatus>
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var refreshCount = 0
    private(set) var recoverCount = 0
    private(set) var setVolumeValues: [Double] = []
    private(set) var toggleMuteCount = 0
    private(set) var selectedOutputDeviceIDs: [AudioDeviceID] = []
    private(set) var detailsVisibility: [Bool] = []
    var onRecover: (() -> Void)?
    var onRefresh: (() -> Void)?
    private let continuation: AsyncStream<VolumeStatus>.Continuation

    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() { startCount += 1 }
    func stop() {
        stopCount += 1
        continuation.finish()
    }
    func refresh() {
        refreshCount += 1
        onRefresh?()
    }
    func recover() {
        recoverCount += 1
        onRecover?()
    }
    func setVolume(_ scalar: Double) {
        setVolumeValues.append(scalar)
    }
    func toggleMute() {
        toggleMuteCount += 1
    }
    func selectOutputDevice(_ deviceID: AudioDeviceID) {
        selectedOutputDeviceIDs.append(deviceID)
    }

    func setDetailsVisible(_ visible: Bool) {
        detailsVisibility.append(visible)
    }
    func send(_ value: VolumeStatus) { continuation.yield(value) }
}
