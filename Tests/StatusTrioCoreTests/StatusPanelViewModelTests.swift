import Combine
import CoreAudio
import XCTest
@testable import StatusTrioCore

@MainActor
final class StatusPanelViewModelTests: XCTestCase {
    func testStartPublishesInitialPanelsWithoutStartingDomainMonitoring() throws {
        let fixture = PanelStoreFixture()
        let panel = StatusPanelViewModel(
            store: fixture.store,
            settings: fixture.settings,
            localization: fixture.localization,
            actions: StatusPanelActions(),
            updateScheduler: fixture.updateScheduler
        )

        panel.start()

        XCTAssertEqual(panel.battery.title, "Battery · 72%")
        XCTAssertEqual(panel.volume.scalar, 0.4)
        XCTAssertFalse(fixture.battery.started)
        XCTAssertFalse(fixture.wifi.started)
        XCTAssertFalse(fixture.volume.started)
        XCTAssertFalse(fixture.store.wifiNetworks.isActive)

        panel.stop()
    }

    func testLiveVolumeUpdatesPanelImmediatelyWithoutPublishingOtherRegions() async throws {
        let fixture = PanelStoreFixture()
        let panel = StatusPanelViewModel(
            store: fixture.store,
            settings: fixture.settings,
            localization: fixture.localization,
            actions: StatusPanelActions(),
            updateScheduler: fixture.updateScheduler
        )
        panel.start()
        defer { panel.stop(); fixture.store.stop() }

        let volumeChanged = expectation(description: "volume panel receives live volume")
        var cancellables: Set<AnyCancellable> = []
        panel.$volume
            .dropFirst()
            .sink { state in
                guard state.scalar == 0.83 else { return }
                volumeChanged.fulfill()
            }
            .store(in: &cancellables)

        fixture.store.start()
        fixture.volume.send(VolumeStatus(scalar: 0.83, isMuted: false, deviceName: "Desk speakers"))
        await fulfillment(of: [volumeChanged], timeout: 1)

        XCTAssertEqual(panel.volume.scalar, 0.83)
        XCTAssertEqual(panel.battery.title, "Battery · 72%")
    }

    func testPopupBatteryAndNetworkUpdateThroughTheirDebouncedSource() async throws {
        let fixture = PanelStoreFixture()
        let panel = fixture.makePanel()
        panel.start()
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        let scansBeforeUpdates = fixture.scanner.scanCount

        fixture.battery.send(BatteryStatus(
            rawPercentage: 51,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        ))
        fixture.wifi.send(WiFiStatus(
            state: .connected,
            rssi: -72,
            ssid: "Guest",
            nameAccess: .authorized
        ))

        let popupDebouncesStarted = await fixture.popupSleeper.waitForCallCount(2, timeout: .seconds(1))
        XCTAssertTrue(popupDebouncesStarted)
        fixture.popupSleeper.releaseAll()
        let popupStateUpdated = await waitForYields {
            panel.battery.title == "Battery · 51%" && panel.network.subtitle == "Guest"
        }
        XCTAssertTrue(popupStateUpdated)
        XCTAssertEqual(fixture.scanner.scanCount, scansBeforeUpdates, "panel mapping cannot start Wi-Fi scans")
        panel.stop()
        fixture.store.stop()
    }

    func testWiFiDetailsUseTheWiFiValueDeliveredWithThePopupSnapshot() async {
        let fixture = PanelStoreFixture()
        let panel = fixture.makePanel()
        panel.start()
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        defer { panel.stop(); fixture.store.setPopoverVisible(false); fixture.store.stop() }

        XCTAssertTrue(panel.wifiDetails.powerIsOn)
        XCTAssertEqual(panel.wifiDetails.messageIntent, .none)

        fixture.wifi.send(WiFiStatus(state: .off, rssi: nil, nameAccess: .authorized))
        let offSnapshotQueued = await fixture.popupSleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertTrue(offSnapshotQueued)
        fixture.popupSleeper.releaseAll()
        let offValueDelivered = await waitForYields { fixture.store.popupSnapshot.wifi.state == .off }
        XCTAssertTrue(offValueDelivered)
        XCTAssertFalse(panel.wifiDetails.powerIsOn, "Wi-Fi details must consume the delivered off status")

        fixture.wifi.send(WiFiStatus(state: .connected, rssi: -48, nameAccess: .notDetermined))
        let connectedSnapshotQueued = await fixture.popupSleeper.waitForCallCount(2, timeout: .seconds(1))
        XCTAssertTrue(connectedSnapshotQueued)
        fixture.popupSleeper.releaseAll()
        let connectedValueDelivered = await waitForYields {
            fixture.store.popupSnapshot.wifi.nameAccess == .notDetermined
        }
        XCTAssertTrue(connectedValueDelivered)
        XCTAssertTrue(panel.wifiDetails.powerIsOn)
        XCTAssertEqual(panel.wifiDetails.messageIntent, .requestWiFiNameAccess)
    }

    func testListeningModeAndDevicePublicationsCoalesceToLatestVolumeStateAndRespectStop() async {
        let firstDevice = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:01",
            name: "AirPods Pro",
            kind: .audio,
            isConnected: true
        )
        let latestDevice = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:02",
            name: "AirPods Pro",
            kind: .audio,
            isConnected: true
        )
        let previewID = "PREVIEW:1"
        let previewDevice = BluetoothDevice(id: previewID, name: "AirPods Pro", kind: .audio, isConnected: true)
        let previewEndpoint = try! XCTUnwrap(BluetoothListeningModeController.syntheticEndpoint(for: previewID))
        let outputDevices = [
            AudioOutputDevice(id: 1, name: "Built-in Output", uid: "builtin", isCurrent: true),
            AudioOutputDevice(id: previewEndpoint, name: "AirPods Pro", uid: previewID, isCurrent: false)
        ]
        let fixture = PanelStoreFixture(outputDevices: outputDevices, pairedDevices: [firstDevice])
        fixture.bluetoothListeningModes.previewMode = true
        fixture.bluetoothListeningModes.refresh(devices: [previewDevice])
        let panel = fixture.makePanel()
        panel.start()
        defer {
            panel.stop()
            fixture.bluetoothDevices.deactivate()
            fixture.bluetoothListeningModes.stop()
            fixture.store.stop()
        }

        let previewRow = try! XCTUnwrap(panel.volume.rows.first { $0.key.id == previewEndpoint })
        XCTAssertEqual(previewRow.listeningMode?.selectedMode, .noiseCancellation)
        fixture.bluetoothDevices.activate()
        let firstDeviceDelivered = await waitForYields { fixture.bluetoothDevices.devices == [firstDevice] }
        XCTAssertTrue(firstDeviceDelivered)
        XCTAssertEqual(fixture.updateScheduler.pendingCount, 1)
        fixture.updateScheduler.runScheduled()
        XCTAssertEqual(panel.volume.listeningModeTaskID, "AABBCCDDEE01")

        fixture.bluetoothWorker.devices = [latestDevice]
        fixture.bluetoothDevices.refresh()
        let previewAddress = try! XCTUnwrap(
            panel.volume.rows.first { $0.key.id == previewEndpoint }?.listeningModeAddress
        )
        let latestModePublished = expectation(description: "latest settled listening mode is delivered")
        var deliveredMode: BluetoothListeningModePresentation?
        var cancellables: Set<AnyCancellable> = []
        fixture.bluetoothListeningModes.$presentations
            .dropFirst()
            .sink { presentations in
                guard let presentation = presentations[previewAddress],
                      presentation.selectedMode == .transparency,
                      presentation.actionState == .idle else { return }
                deliveredMode = presentation
                latestModePublished.fulfill()
            }
            .store(in: &cancellables)
        fixture.bluetoothListeningModes.setMode(.transparency, forAddress: previewAddress)
        await fulfillment(of: [latestModePublished], timeout: 1)
        let latestControllerValuesDelivered = await waitForYields {
            fixture.bluetoothDevices.devices == [latestDevice]
        }
        XCTAssertTrue(latestControllerValuesDelivered)
        XCTAssertEqual(fixture.updateScheduler.pendingCount, 1, "device and mode publications share one refresh")
        fixture.updateScheduler.runScheduled()

        let changingRow = try! XCTUnwrap(panel.volume.rows.first { $0.key.id == previewEndpoint })
        XCTAssertEqual(panel.volume.listeningModeTaskID, "AABBCCDDEE02")
        XCTAssertEqual(deliveredMode?.selectedMode, .transparency)
        XCTAssertEqual(changingRow.listeningMode?.selectedMode, .transparency)
        XCTAssertEqual(changingRow.listeningMode?.actionState, .idle)

        fixture.bluetoothListeningModes.refresh(devices: [])
        XCTAssertEqual(fixture.updateScheduler.pendingCount, 1)
        panel.stop()
        fixture.updateScheduler.runScheduled()
        let unchangedWhileStopped = try! XCTUnwrap(panel.volume.rows.first { $0.key.id == previewEndpoint })
        XCTAssertEqual(unchangedWhileStopped.listeningMode?.selectedMode, .transparency)

        panel.start()
        XCTAssertEqual(panel.volume.listeningModeTaskID, "AABBCCDDEE02")
        XCTAssertNil(panel.volume.rows.first { $0.key.id == previewEndpoint }?.listeningMode)
    }

    func testLiveInputUpdatesOnlyTheInputRegion() async throws {
        let fixture = PanelStoreFixture()
        fixture.settings.setPopupSection(.audioInput, enabled: true)
        let panel = fixture.makePanel()
        panel.start()
        fixture.store.start()
        defer { panel.stop(); fixture.store.stop() }

        let inputChanged = expectation(description: "input state reaches its own panel region")
        var otherRegionUpdates = 0
        var cancellables: Set<AnyCancellable> = []
        panel.$audioInput.dropFirst().sink { state in
            if state.summary.subtitle == "USB Mic" { inputChanged.fulfill() }
        }.store(in: &cancellables)
        panel.$battery.dropFirst().sink { _ in otherRegionUpdates += 1 }.store(in: &cancellables)
        panel.$network.dropFirst().sink { _ in otherRegionUpdates += 1 }.store(in: &cancellables)
        panel.$volume.dropFirst().sink { _ in otherRegionUpdates += 1 }.store(in: &cancellables)

        fixture.input.send(AudioInputStatus(
            devices: [
                AudioInputDevice(id: 11, uid: "builtin", name: "Built-in Mic"),
                AudioInputDevice(id: 22, uid: "usb", name: "USB Mic")
            ],
            defaultDeviceID: 22,
            deviceName: "USB Mic",
            scalar: 0.62,
            canSetVolume: true,
            muteState: .unmuted,
            canSetMute: true,
            isRefreshing: false,
            isBusy: false,
            error: nil
        ))
        await fulfillment(of: [inputChanged], timeout: 1)

        XCTAssertEqual(panel.audioInput.scalar, 0.62)
        XCTAssertEqual(otherRegionUpdates, 0)
    }

    func testSettingsWillChangeReadsCommittedSettingsAndStopCancelsQueuedRefresh() async {
        let fixture = PanelStoreFixture()
        let panel = fixture.makePanel()
        panel.start()
        defer { panel.stop(); fixture.store.stop() }
        let oldLimit = panel.volume.visibleLimit

        fixture.settings.alwaysShowsAllOutputDevices = true
        XCTAssertEqual(fixture.updateScheduler.pendingCount, 1)
        panel.stop()
        fixture.updateScheduler.runScheduled()
        await Task.yield()

        XCTAssertEqual(panel.volume.visibleLimit, oldLimit, "a queued willChange refresh must be cancelled on stop")
        panel.start()
        let committedSettingsRead = await waitForYields { panel.volume.visibleLimit == nil }
        XCTAssertTrue(committedSettingsRead)
    }

    func testRetainedOwnerRemapsWhenLanguageChanges() async {
        let fixture = PanelStoreFixture()
        let panel = fixture.makePanel()
        panel.start()
        defer { panel.stop(); fixture.store.stop() }
        let englishTitle = panel.battery.title
        let remapped = expectation(description: "retained panel title uses the new language")
        var cancellables: Set<AnyCancellable> = []
        panel.$battery.dropFirst().sink { state in
            if state.title != englishTitle { remapped.fulfill() }
        }.store(in: &cancellables)

        fixture.localization.setPreference(.language(.simplifiedChinese))
        XCTAssertEqual(fixture.updateScheduler.pendingCount, 1)
        fixture.updateScheduler.runScheduled()
        await fulfillment(of: [remapped], timeout: 1)
        XCTAssertEqual(fixture.store.snapshot, fixture.initialSnapshot, "language presentation must not alter icon input")
        XCTAssertEqual(fixture.scanner.scanCount, 0, "language remapping must not start a network scan")
    }

    func testStopUnsubscribesAndRestartReadsTheCurrentVolumeValue() async {
        let fixture = PanelStoreFixture()
        let panel = fixture.makePanel()
        panel.start()
        fixture.store.start()
        defer { panel.stop(); fixture.store.stop() }

        let firstRead = expectation(description: "owner receives live volume while started")
        var cancellables: Set<AnyCancellable> = []
        panel.$volume.dropFirst().sink { state in
            if state.scalar == 0.83 { firstRead.fulfill() }
        }.store(in: &cancellables)
        fixture.volume.send(VolumeStatus(scalar: 0.83, isMuted: false, deviceName: "Desk speakers"))
        await fulfillment(of: [firstRead], timeout: 1)

        panel.stop()
        fixture.volume.send(VolumeStatus(scalar: 0.21, isMuted: false, deviceName: "Desk speakers"))
        let storeReceivedLatestVolume = await waitForYields { fixture.store.liveVolume.scalar == 0.21 }
        XCTAssertTrue(storeReceivedLatestVolume)
        XCTAssertEqual(panel.volume.scalar, 0.83, "stopped owner no longer follows store publications")

        panel.start()
        XCTAssertEqual(panel.volume.scalar, 0.21, "restart begins from the store's latest value")
    }

    func testVPNUpdatesItsPanelWithoutPublishingAnIconSnapshot() async {
        let fixture = PanelStoreFixture()
        let panel = fixture.makePanel()
        panel.start()
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        defer { panel.stop(); fixture.store.setPopoverVisible(false); fixture.store.stop() }

        let vpnChanged = expectation(description: "VPN update reaches the VPN panel")
        var iconSnapshotPublishes = 0
        var cancellables: Set<AnyCancellable> = []
        panel.$vpn.dropFirst().sink { state in
            if state.title.contains("Work") { vpnChanged.fulfill() }
        }.store(in: &cancellables)
        fixture.store.$snapshot.dropFirst().sink { _ in iconSnapshotPublishes += 1 }.store(in: &cancellables)

        fixture.vpn.send(VPNStatus(tunnelInterfaces: ["utun4"], serviceName: "Work", proxy: nil))
        await fulfillment(of: [vpnChanged], timeout: 1)

        XCTAssertEqual(iconSnapshotPublishes, 0)
        XCTAssertEqual(fixture.store.snapshot, fixture.initialSnapshot)
    }

    func testRepeatedSettingsRefreshDoesNotRepublishUnchangedRegions() async {
        let fixture = PanelStoreFixture()
        let panel = fixture.makePanel()
        panel.start()
        defer { panel.stop(); fixture.store.stop() }
        var batteryPublishes = 0
        var networkPublishes = 0
        var inputPublishes = 0
        var settingsChanges = 0
        var cancellables: Set<AnyCancellable> = []
        fixture.settings.objectWillChange.sink { settingsChanges += 1 }.store(in: &cancellables)
        panel.$battery.dropFirst().sink { _ in batteryPublishes += 1 }.store(in: &cancellables)
        panel.$network.dropFirst().sink { _ in networkPublishes += 1 }.store(in: &cancellables)
        panel.$audioInput.dropFirst().sink { _ in inputPublishes += 1 }.store(in: &cancellables)

        let volumeUpdated = expectation(description: "new settings reach the volume region")
        panel.$volume.dropFirst().sink { state in
            if state.visibleLimit == nil { volumeUpdated.fulfill() }
        }.store(in: &cancellables)
        fixture.settings.alwaysShowsAllOutputDevices = true
        XCTAssertNil(fixture.settings.visibleOutputDeviceLimit)
        XCTAssertGreaterThan(settingsChanges, 0)
        XCTAssertEqual(fixture.updateScheduler.pendingCount, 1)
        fixture.updateScheduler.runScheduled()
        XCTAssertNil(panel.volume.visibleLimit)
        await fulfillment(of: [volumeUpdated], timeout: 1)

        XCTAssertEqual(batteryPublishes, 0)
        XCTAssertEqual(networkPublishes, 0)
        XCTAssertEqual(inputPublishes, 0)
    }

    func testCoalescedControllerSettingsAndLanguageChangesRefreshEveryDirtyRegion() {
        let fixture = PanelStoreFixture()
        let panel = fixture.makePanel()
        panel.start()
        defer { panel.stop(); fixture.store.stop() }
        let englishTitle = panel.battery.title

        // Controller willChange fires before its value mutation. Queue that region first,
        // then make relevant settings and language changes before the scheduler drains.
        fixture.store.bluetoothDevices.objectWillChange.send()
        fixture.settings.alwaysShowsAllOutputDevices = true
        fixture.localization.setPreference(.language(.simplifiedChinese))

        XCTAssertEqual(fixture.updateScheduler.pendingCount, 1)
        fixture.updateScheduler.runScheduled()

        XCTAssertNil(panel.volume.visibleLimit, "the coalesced settings refresh must reach volume")
        XCTAssertNotEqual(panel.battery.title, englishTitle, "the coalesced language refresh must reach localized panels")
        XCTAssertEqual(panel.bluetooth.summary.title, fixture.localization.string(.bluetoothTitle))
    }

    private func waitForYields(
        _ condition: @MainActor () -> Bool,
        count: Int = 100
    ) async -> Bool {
        for _ in 0..<count {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }
}

@MainActor
private final class PanelStoreFixture {
    let battery = PanelBatteryMonitor()
    let wifi = PanelWiFiMonitor()
    let volume = PanelVolumeMonitor()
    let input = PanelInputMonitor()
    let popupSleeper: ManualEventSleeper
    let scanner = PanelWiFiScanner()
    let vpn = PanelVPNMonitor()
    let updateScheduler = ManualPanelUpdateScheduler()
    let bluetoothWorker: PanelBluetoothWorker
    let bluetoothDevices: BluetoothDeviceController
    let bluetoothListeningModes: BluetoothListeningModeController
    let settings: SettingsStore
    let localization: Localization
    let store: SystemStatusStore
    let initialSnapshot: StatusSnapshot

    init(outputDevices: [AudioOutputDevice] = [], pairedDevices: [BluetoothDevice] = []) {
        let suiteName = "StatusPanelViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let sleeper = ManualEventSleeper()
        settings = SettingsStore(defaults: defaults)
        localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        popupSleeper = sleeper
        bluetoothWorker = PanelBluetoothWorker(devices: pairedDevices)
        bluetoothDevices = BluetoothDeviceController(
            worker: bluetoothWorker,
            stateMonitor: PanelBluetoothStateMonitor(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        bluetoothListeningModes = BluetoothListeningModeController(
            hal: BluetoothListeningModeHAL(
                backend: FakeListeningModeBackend(),
                sleeper: ImmediateListeningModeSleeper(),
                retryAttempts: 1,
                retryDelay: .milliseconds(1)
            ),
            endpointProvider: EmptyListeningModeEndpointProvider(),
            failureClearDelay: .milliseconds(30),
            previewSettleDelay: .milliseconds(0)
        )
        initialSnapshot = StatusSnapshot(
            battery: BatteryStatus(rawPercentage: 72, isPresent: true, isCharging: false, isLowPowerMode: false, isConnectedToPower: false),
            wifi: WiFiStatus(state: .connected, rssi: -54, ssid: "Studio", nameAccess: .authorized),
            volume: VolumeStatus(
                scalar: 0.4,
                isMuted: false,
                deviceName: "Desk speakers",
                currentDevice: outputDevices.first(where: \.isCurrent),
                outputDevices: outputDevices
            )
        )
        store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            vpnMonitor: vpn,
            volumeMonitor: volume,
            inputMonitor: input,
            popupDebounceSleep: { duration in await sleeper.sleep(duration) },
            wifiNetworks: WiFiNetworkController(scanWorker: scanner),
            bluetoothDevices: bluetoothDevices,
            bluetoothListeningModes: bluetoothListeningModes,
            initialSnapshot: initialSnapshot
        )
        store.bindInputSettings(settings)
    }

    func makePanel() -> StatusPanelViewModel {
        StatusPanelViewModel(
            store: store,
            settings: settings,
            localization: localization,
            actions: StatusPanelActions(),
            updateScheduler: updateScheduler
        )
    }
}

@MainActor
private final class PanelBatteryMonitor: BatteryMonitoring {
    private let pair = AsyncStream<BatteryStatus>.makeStream()
    var updates: AsyncStream<BatteryStatus> { pair.stream }
    private(set) var started = false
    func start() { started = true }
    func stop() { started = false }
    func refresh() {}
    func recover() {}
    func send(_ status: BatteryStatus) { pair.continuation.yield(status) }
}

@MainActor
private final class PanelWiFiMonitor: WiFiMonitoring {
    private let pair = AsyncStream<WiFiStatus>.makeStream()
    var updates: AsyncStream<WiFiStatus> { pair.stream }
    private(set) var started = false
    func start() { started = true }
    func stop() { started = false }
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
    func send(_ status: WiFiStatus) { pair.continuation.yield(status) }
}

@MainActor
private final class PanelVolumeMonitor: VolumeMonitoring {
    private let pair = AsyncStream<VolumeStatus>.makeStream()
    var updates: AsyncStream<VolumeStatus> { pair.stream }
    private(set) var started = false
    func start() { started = true }
    func stop() { started = false }
    func refresh() {}
    func recover() {}
    func send(_ status: VolumeStatus) { pair.continuation.yield(status) }
}

@MainActor
private final class PanelInputMonitor: AudioInputMonitoring {
    private let pair = AsyncStream<AudioInputStatus>.makeStream()
    var updates: AsyncStream<AudioInputStatus> { pair.stream }
    private(set) var enabledValues: [Bool] = []
    func setEnabled(_ enabled: Bool) { enabledValues.append(enabled) }
    func setVisible(_ visible: Bool) {}
    func recover() {}
    func select(_ id: AudioDeviceID) {}
    func setScalar(_ value: Double) {}
    func toggleMute() {}
    func stop() {}
    func send(_ status: AudioInputStatus) { pair.continuation.yield(status) }
}

@MainActor
private final class PanelVPNMonitor: VPNMonitoring {
    private let pair = AsyncStream<VPNStatus>.makeStream()
    var updates: AsyncStream<VPNStatus> { pair.stream }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func send(_ status: VPNStatus) { pair.continuation.yield(status) }
}

private final class PanelWiFiScanner: WiFiNetworkScanning, @unchecked Sendable {
    private let lock = NSLock()
    private var _scanCount = 0
    var scanCount: Int { lock.lock(); defer { lock.unlock() }; return _scanCount }

    func scan(completion: @escaping @Sendable (WiFiScanWorkerResult) -> Void) {
        lock.lock()
        _scanCount += 1
        lock.unlock()
        completion(.failed)
    }

    func setPower(_ isOn: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        completion(false)
    }
}

private final class PanelBluetoothWorker: BluetoothPairedDeviceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var storedDevices: [BluetoothDevice]

    init(devices: [BluetoothDevice]) {
        storedDevices = devices
    }

    var devices: [BluetoothDevice] {
        get { lock.withLock { storedDevices } }
        set { lock.withLock { storedDevices = newValue } }
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        completion(.success(devices))
    }
}

@MainActor
private final class PanelBluetoothStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() {
        onStateChange?(.allowed, .poweredOn)
    }

    func stop() {}
}

@MainActor
private final class ManualPanelUpdateScheduler: PanelPresentationUpdateScheduling {
    private var updates: [@MainActor () -> Void] = []
    var pendingCount: Int { updates.count }

    func schedule(_ update: @escaping @MainActor () -> Void) {
        updates.append(update)
    }

    func runScheduled() {
        let scheduled = updates
        updates.removeAll()
        scheduled.forEach { $0() }
    }
}
