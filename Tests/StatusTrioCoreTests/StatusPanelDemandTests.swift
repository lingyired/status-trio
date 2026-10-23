import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class StatusPanelDemandTests: XCTestCase {
    func testHidingSectionsSynchronouslyStopsOldSourcesAndEnableMapsLatestValues() async {
        let fixture = PanelStoreFixture()
        for section in PopupSection.allCases {
            fixture.settings.setPopupSection(section, enabled: false)
        }
        fixture.settings.setPopupSection(.audioInput, enabled: true)
        fixture.settings.setPopupSection(.inputSource, enabled: true)

        let storeSettings = SettingsStore(
            defaults: UserDefaults(
                suiteName: "StatusPanelDemandTests.store.\(UUID().uuidString)"
            )!
        )
        storeSettings.setPopupSection(.audioInput, enabled: true)
        fixture.store.bindInputSettings(storeSettings)

        let inputReader = DemandInputSourceReader(
            selectedID: "com.apple.keylayout.ABC",
            sources: [demandInputSource(id: "com.apple.keylayout.ABC", name: "ABC")]
        )
        let inputSourceController = InputSourceController(
            reader: inputReader,
            switcher: DemandInputSourceSwitcher(),
            notifications: DemandInputSourceNotifications()
        )
        let panel = fixture.makePanel(inputSourceController: inputSourceController)
        inputSourceController.start()
        panel.start()
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        defer {
            panel.stop()
            inputSourceController.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }

        XCTAssertEqual(fixture.input.enabledValues.last, true)
        let (initialAudioDelivered, initialAudioCancellable) = expectDelivery(
            from: fixture.store.$liveInput.eraseToAnyPublisher(),
            description: "initial audio input reaches the store"
        ) {
            $0.scalar == 0.68
        }
        fixture.input.send(demandAudioInputStatus(name: "Latest USB Mic", scalar: 0.68))
        await fulfillment(of: [initialAudioDelivered], timeout: 1)
        initialAudioCancellable.cancel()

        XCTAssertEqual(panel.audioInput.scalar, 0.68)
        XCTAssertEqual(panel.audioInput.summary.subtitle, "Latest USB Mic")
        XCTAssertEqual(panel.inputSource.currentName, "ABC")
        let visibleAudioInput = panel.audioInput
        let visibleInputSource = panel.inputSource

        fixture.settings.setPopupSection(.audioInput, enabled: false)
        fixture.settings.setPopupSection(.inputSource, enabled: false)
        XCTAssertTrue(fixture.updateScheduler.hasPendingUpdate)

        let (hiddenAudioDelivered, hiddenAudioCancellable) = expectDelivery(
            from: fixture.store.$liveInput.eraseToAnyPublisher(),
            description: "hidden audio input still reaches its store"
        ) {
            $0.scalar == 0.73
        }
        let hiddenAudioRequestID = UUID()
        fixture.input.send(
            demandAudioInputStatus(
                name: "Hidden USB Mic",
                scalar: 0.73,
                completedScalarRequestID: hiddenAudioRequestID
            )
        )
        inputReader.selectedID = "com.example.pinyin"
        inputReader.sources = [demandInputSource(id: "com.example.pinyin", name: "Pinyin")]
        inputSourceController.refresh()
        await fulfillment(of: [hiddenAudioDelivered], timeout: 1)
        hiddenAudioCancellable.cancel()

        XCTAssertEqual(inputSourceController.state.selectedID, "com.example.pinyin")
        XCTAssertEqual(panel.audioInput, visibleAudioInput)
        XCTAssertEqual(panel.inputSource, visibleInputSource)

        fixture.updateScheduler.runScheduled()
        XCTAssertEqual(panel.audioInput, visibleAudioInput)
        XCTAssertEqual(panel.inputSource, visibleInputSource)

        fixture.settings.setPopupSection(.inputSource, enabled: true)
        XCTAssertTrue(fixture.updateScheduler.hasPendingUpdate)
        fixture.updateScheduler.runScheduled()
        XCTAssertEqual(panel.inputSource.currentName, "Pinyin")

        fixture.settings.setPopupSection(.audioInput, enabled: true)
        XCTAssertTrue(fixture.updateScheduler.hasPendingUpdate)
        fixture.updateScheduler.runScheduled()
        XCTAssertEqual(panel.audioInput.scalar, 0.73)
        XCTAssertEqual(panel.audioInput.summary.subtitle, "Hidden USB Mic")
        XCTAssertEqual(panel.audioInput.completedScalarRequestID, hiddenAudioRequestID)
        XCTAssertTrue(panel.bluetooth.pairedRows.isEmpty)
    }

    func testHiddenBluetoothKeepsAirPodsDataForVisibleAudioRegion() async {
        let latestDevice = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:02",
            name: "AirPods Pro",
            kind: .audio,
            isConnected: true
        )
        let fixture = PanelStoreFixture()
        fixture.settings.setPopupSection(.bluetooth, enabled: false)
        fixture.settings.setPopupSection(.volume, enabled: true)
        fixture.store.bindBluetoothSettings(fixture.settings)
        let actions = StatusPanelActions(store: fixture.store, settings: fixture.settings)
        let panel = fixture.makePanel(actions: actions)
        panel.start()
        defer {
            panel.stop()
            fixture.bluetoothDevices.deactivate()
            fixture.bluetoothListeningModes.stop()
        }

        let (devicesDelivered, devicesCancellable) = expectDelivery(
            from: fixture.bluetoothDevices.$devices.eraseToAnyPublisher(),
            description: "the AirPods device reaches the controller"
        ) {
            $0 == [latestDevice]
        }
        fixture.bluetoothWorker.devices = [latestDevice]
        panel.actions.volumeListAppeared()
        fixture.bluetoothDevices.activate()
        await fulfillment(of: [devicesDelivered], timeout: 1)
        devicesCancellable.cancel()

        XCTAssertTrue(fixture.updateScheduler.hasPendingUpdate)
        fixture.updateScheduler.runScheduled()
        XCTAssertTrue(panel.volume.listeningModeTaskID.contains("AABBCCDDEE02"))
        XCTAssertTrue(panel.bluetooth.pairedRows.isEmpty)
    }

    func testBluetoothOnlyRefreshesListeningIdentityWithoutPublishingHiddenVolume() async {
        let latestDevice = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:02",
            name: "HUAWEI FreeBuds",
            kind: .audio,
            isConnected: true,
            vendorID: 0x027D
        )
        let fixture = PanelStoreFixture()
        fixture.settings.setPopupSection(.bluetooth, enabled: true)
        fixture.settings.setPopupSection(.volume, enabled: false)
        fixture.store.bindBluetoothSettings(fixture.settings)
        let actions = StatusPanelActions(store: fixture.store, settings: fixture.settings)
        let panel = fixture.makePanel(actions: actions)
        panel.start()
        fixture.store.start()
        defer {
            fixture.store.setPopoverVisible(false)
            panel.stop()
            fixture.bluetoothDevices.deactivate()
            fixture.bluetoothListeningModes.stop()
            fixture.store.stop()
        }

        let hiddenVolume = panel.volume
        var volumePublications = 0
        let volumeObservation = panel.$volume
            .dropFirst()
            .sink { _ in volumePublications += 1 }
        defer { volumeObservation.cancel() }

        let (devicesDelivered, devicesCancellable) = expectDelivery(
            from: fixture.bluetoothDevices.$devices.eraseToAnyPublisher(),
            description: "the HUAWEI device reaches the Bluetooth-only popover"
        ) {
            $0 == [latestDevice]
        }
        fixture.bluetoothWorker.devices = [latestDevice]
        panel.actions.volumeListChanged()
        fixture.store.setPopoverVisible(true)
        await fulfillment(of: [devicesDelivered], timeout: 1)
        devicesCancellable.cancel()

        XCTAssertTrue(fixture.updateScheduler.hasPendingUpdate)
        fixture.updateScheduler.runScheduled()

        XCTAssertTrue(panel.listeningModeTaskID.contains("AABBCCDDEE02"))
        XCTAssertEqual(panel.volume, hiddenVolume)
        XCTAssertEqual(volumePublications, 0)

        let output = AudioOutputDevice(
            id: 42,
            name: "HUAWEI FreeBuds",
            uid: "huawei-freebuds",
            isCurrent: true
        )
        let (volumeDelivered, volumeCancellable) = expectDelivery(
            from: fixture.store.$liveVolume.eraseToAnyPublisher(),
            description: "the Bluetooth-only popover receives output membership"
        ) {
            $0.outputDevices == [output]
        }
        let (identityDelivered, identityCancellable) = expectDelivery(
            from: panel.$listeningModeTaskID.eraseToAnyPublisher(),
            description: "output membership updates the shared discovery identity"
        ) {
            $0.contains("|outputs:42|current:42|")
        }
        fixture.volume.send(
            VolumeStatus(
                scalar: 0.4,
                isMuted: false,
                deviceName: output.name,
                currentDevice: output,
                outputDevices: [output]
            )
        )
        await fulfillment(of: [volumeDelivered, identityDelivered], timeout: 1)
        volumeCancellable.cancel()
        identityCancellable.cancel()

        XCTAssertTrue(panel.listeningModeTaskID.contains("|outputs:42|current:42|"))
        XCTAssertEqual(panel.volume, hiddenVolume)
        XCTAssertEqual(volumePublications, 0)
    }

    func testDetailsMapOnlyWhileTheirControllersReportOpenOwnership() async {
        let fixture = PanelStoreFixture()
        let actions = StatusPanelActions(store: fixture.store, settings: fixture.settings)
        let panel = fixture.makePanel(actions: actions)
        panel.start()
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        defer {
            panel.actions.batteryDetailsClosed()
            panel.actions.wifiDetailsClosed()
            fixture.store.setPopoverVisible(false)
            panel.stop()
            fixture.store.stop()
        }

        let closedBatteryDetails = panel.batteryDetails
        let closedWiFiDetails = panel.wifiDetails
        XCTAssertFalse(fixture.store.batteryDetails.isActive)
        XCTAssertFalse(fixture.store.wifiNetworks.isActive)

        let (firstSnapshotDelivered, firstSnapshotCancellable) = expectDelivery(
            from: fixture.store.$popupSnapshot.eraseToAnyPublisher(),
            description: "closed detail sources deliver their newest summary snapshot"
        ) {
            $0.battery.rawPercentage == 41 && $0.wifi.ssid == "Hidden"
        }
        fixture.battery.send(demandBatteryStatus(41))
        fixture.wifi.send(
            WiFiStatus(state: .connected, rssi: -70, ssid: "Hidden", nameAccess: .authorized)
        )
        await fixture.popupSleeper.waitForCallCount(2)
        fixture.popupSleeper.releaseAll()
        await fulfillment(of: [firstSnapshotDelivered], timeout: 1)
        firstSnapshotCancellable.cancel()
        fixture.updateScheduler.runScheduled()

        XCTAssertEqual(panel.battery.title, "Battery · 41%")
        XCTAssertEqual(panel.batteryDetails, closedBatteryDetails)
        XCTAssertEqual(panel.wifiDetails, closedWiFiDetails)

        panel.actions.batteryDetailsAppeared()
        panel.actions.wifiDetailsOpened()
        XCTAssertTrue(fixture.store.batteryDetails.isActive)
        XCTAssertTrue(fixture.store.wifiNetworks.isActive)

        let (secondSnapshotDelivered, secondSnapshotCancellable) = expectDelivery(
            from: fixture.store.$popupSnapshot.eraseToAnyPublisher(),
            description: "owned detail controllers receive a newer snapshot"
        ) {
            $0.battery.rawPercentage == 39 && $0.wifi.ssid == "Visible"
        }
        fixture.battery.send(demandBatteryStatus(39))
        fixture.wifi.send(
            WiFiStatus(state: .connected, rssi: -61, ssid: "Visible", nameAccess: .authorized)
        )
        await fixture.popupSleeper.waitForCallCount(4)
        fixture.popupSleeper.releaseAll()
        await fulfillment(of: [secondSnapshotDelivered], timeout: 1)
        secondSnapshotCancellable.cancel()
        if fixture.updateScheduler.hasPendingUpdate {
            fixture.updateScheduler.runScheduled()
        }

        XCTAssertNotEqual(panel.batteryDetails, closedBatteryDetails)
        XCTAssertNotEqual(panel.wifiDetails, closedWiFiDetails)
        let openedBatteryDetails = panel.batteryDetails

        panel.actions.batteryDetailsClosed()
        panel.actions.wifiDetailsClosed()
        fixture.battery.send(demandBatteryStatus(37))
        fixture.wifi.send(
            WiFiStatus(state: .connected, rssi: -49, ssid: "Closed Again", nameAccess: .authorized)
        )
        let (thirdSnapshotDelivered, thirdSnapshotCancellable) = expectDelivery(
            from: fixture.store.$popupSnapshot.eraseToAnyPublisher(),
            description: "closed detail controllers still receive summary data"
        ) {
            $0.battery.rawPercentage == 37 && $0.wifi.ssid == "Closed Again"
        }
        await fixture.popupSleeper.waitForCallCount(6)
        fixture.popupSleeper.releaseAll()
        await fulfillment(of: [thirdSnapshotDelivered], timeout: 1)
        thirdSnapshotCancellable.cancel()
        fixture.updateScheduler.runScheduled()

        XCTAssertEqual(panel.battery.title, "Battery · 37%")
        XCTAssertEqual(panel.batteryDetails, openedBatteryDetails)
    }

    func testWiFiFailureStateChangeQueuesTheFailurePresentation() async {
        let fixture = PanelStoreFixture()
        let actions = StatusPanelActions(store: fixture.store, settings: fixture.settings)
        let panel = fixture.makePanel(actions: actions)
        panel.start()
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        defer {
            panel.actions.wifiDetailsClosed()
            fixture.store.setPopoverVisible(false)
            panel.stop()
            fixture.store.stop()
        }

        let (scanFailed, scanFailedCancellable) = expectDelivery(
            from: fixture.store.wifiNetworks.$state.eraseToAnyPublisher(),
            description: "the Wi-Fi controller reaches its failed state"
        ) {
            $0 == .failed
        }
        panel.actions.wifiDetailsOpened()
        await fulfillment(of: [scanFailed], timeout: 1)
        scanFailedCancellable.cancel()

        XCTAssertTrue(
            fixture.updateScheduler.hasPendingUpdate,
            "a Wi-Fi state-only failure must queue a detail remap"
        )
        fixture.updateScheduler.runScheduled()
        XCTAssertFalse(panel.wifiDetails.isScanning)
        XCTAssertEqual(
            panel.wifiDetails.message,
            fixture.localization.string(.wifiScanFailed)
        )
        XCTAssertEqual(panel.wifiDetails.messageIntent, .none)
    }

    func testPendingSchedulerActionCannotOverwriteRestartedPresentation() async {
        let fixture = PanelStoreFixture()
        fixture.settings.setPopupSection(.audioInput, enabled: true)
        let scheduler = DemandPanelUpdateScheduler()
        let panel = StatusPanelViewModel(
            store: fixture.store,
            settings: fixture.settings,
            localization: fixture.localization,
            actions: StatusPanelActions(),
            updateScheduler: scheduler
        )
        panel.start()
        fixture.store.start()
        defer {
            panel.stop()
            fixture.store.stop()
        }

        let (firstInputDelivered, firstInputCancellable) = expectDelivery(
            from: fixture.store.$liveInput.eraseToAnyPublisher(),
            description: "the stopped lifecycle has an initial audio value"
        ) {
            $0.scalar == 0.21
        }
        fixture.input.send(demandAudioInputStatus(name: "First Mic", scalar: 0.21))
        await fulfillment(of: [firstInputDelivered], timeout: 1)
        firstInputCancellable.cancel()
        scheduler.runAllScheduled()
        XCTAssertFalse(panel.audioInput.rows.isEmpty)

        // Queue generation 1. `stop()` clears the panel's pending region set,
        // but the deliberately manual scheduler retains this callback.
        fixture.settings.alwaysShowsAllOutputDevices = true
        XCTAssertEqual(scheduler.pendingCount, 1)
        panel.stop()
        panel.releaseInactivePresentationState()
        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertTrue(panel.audioInput.rows.isEmpty)

        fixture.settings.alwaysShowsAllOutputDevices = false
        fixture.localization.setPreference(.language(.simplifiedChinese))
        let (latestInputDelivered, latestInputCancellable) = expectDelivery(
            from: fixture.store.$liveInput.eraseToAnyPublisher(),
            description: "the restarted lifecycle reads the latest stopped-state input"
        ) {
            $0.scalar == 0.84
        }
        fixture.input.send(demandAudioInputStatus(name: "Latest Mic", scalar: 0.84))
        await fulfillment(of: [latestInputDelivered], timeout: 1)
        latestInputCancellable.cancel()

        panel.start()
        let restartedBattery = panel.battery
        let restartedAudioInput = panel.audioInput
        XCTAssertEqual(restartedAudioInput.scalar, 0.84)
        XCTAssertEqual(restartedAudioInput.summary.subtitle, "Latest Mic")
        XCTAssertEqual(panel.visiblePopupSections, fixture.settings.visiblePopupSections)
        XCTAssertEqual(panel.battery, restartedBattery)
        XCTAssertEqual(panel.audioInput, restartedAudioInput)
        XCTAssertNotNil(panel.volume.visibleLimit)

        // Queue generation 3 while generation 1 is still pending. Both
        // callbacks are now in the scheduler, but only the new callback may
        // consume the new `.all` region.
        fixture.settings.alwaysShowsAllOutputDevices = true
        XCTAssertEqual(scheduler.pendingCount, 2)

        XCTAssertTrue(scheduler.runNextScheduled())
        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertEqual(panel.battery, restartedBattery, "the old callback must not consume restart work")
        XCTAssertEqual(panel.audioInput, restartedAudioInput)
        XCTAssertNotNil(
            panel.volume.visibleLimit,
            "the old callback must leave the new `.all` region pending"
        )

        XCTAssertTrue(scheduler.runNextScheduled())
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertNil(panel.volume.visibleLimit, "the restarted callback consumes and applies its own work")
    }

    func testReleaseRequiresStoppedInvisibleAndNoOpenDetailPanel() async {
        let fixture = PanelStoreFixture()
        fixture.settings.setPopupSection(.audioInput, enabled: true)
        let actions = StatusPanelActions(store: fixture.store, settings: fixture.settings)
        let panel = fixture.makePanel(actions: actions)
        panel.start()
        fixture.store.start()
        defer {
            panel.actions.batteryDetailsClosed()
            fixture.store.setPopoverVisible(false)
            panel.stop()
            fixture.store.stop()
        }

        let (inputDelivered, inputCancellable) = expectDelivery(
            from: fixture.store.$liveInput.eraseToAnyPublisher(),
            description: "release has panel rows to retain or clear"
        ) {
            $0.scalar == 0.52
        }
        fixture.input.send(demandAudioInputStatus(name: "Running Mic", scalar: 0.52))
        await fulfillment(of: [inputDelivered], timeout: 1)
        inputCancellable.cancel()
        fixture.updateScheduler.runScheduled()
        let runningRows = panel.audioInput.rows
        XCTAssertFalse(runningRows.isEmpty)

        panel.releaseInactivePresentationState()
        XCTAssertEqual(panel.audioInput.rows, runningRows, "a running panel is never released")

        panel.stop()
        fixture.store.setPopoverVisible(true)
        panel.releaseInactivePresentationState()
        XCTAssertEqual(panel.audioInput.rows, runningRows, "a visible popover is never released")

        fixture.store.setPopoverVisible(false)
        panel.actions.batteryDetailsAppeared()
        XCTAssertFalse(fixture.store.isPopoverVisible)
        XCTAssertTrue(fixture.store.hasOpenPopoverPanel)
        panel.releaseInactivePresentationState()
        XCTAssertEqual(
            panel.audioInput.rows,
            runningRows,
            "hasOpenPopoverPanel alone must block release"
        )

        panel.actions.batteryDetailsClosed()
        XCTAssertFalse(fixture.store.hasOpenPopoverPanel)
        panel.releaseInactivePresentationState()
        XCTAssertTrue(panel.audioInput.rows.isEmpty)
    }

    private func expectDelivery<T>(
        from publisher: AnyPublisher<T, Never>,
        description: String,
        matching predicate: @escaping (T) -> Bool = { _ in true }
    ) -> (XCTestExpectation, AnyCancellable) {
        let delivered = expectation(description: description)
        let cancellable = publisher
            .filter(predicate)
            .prefix(1)
            .sink { _ in delivered.fulfill() }
        return (delivered, cancellable)
    }
}

@MainActor
private final class DemandPanelUpdateScheduler: PanelPresentationUpdateScheduling {
    private var pendingUpdates: [@MainActor () -> Void] = []

    var pendingCount: Int { pendingUpdates.count }

    func schedule(_ update: @escaping @MainActor () -> Void) {
        pendingUpdates.append(update)
    }

    @discardableResult
    func runNextScheduled() -> Bool {
        guard !pendingUpdates.isEmpty else { return false }
        pendingUpdates.removeFirst()()
        return true
    }

    func runAllScheduled() {
        while runNextScheduled() {}
    }
}

private final class DemandInputSourceReader: InputSourceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var storedSelectedID: String?
    private var storedSources: [RawInputSource]

    init(selectedID: String?, sources: [RawInputSource]) {
        storedSelectedID = selectedID
        storedSources = sources
    }

    var selectedID: String? {
        get { lock.withLock { storedSelectedID } }
        set { lock.withLock { storedSelectedID = newValue } }
    }

    var sources: [RawInputSource] {
        get { lock.withLock { storedSources } }
        set { lock.withLock { storedSources = newValue } }
    }

    func currentKeyboardInputSourceID() -> String? {
        lock.withLock { storedSelectedID }
    }

    func keyboardInputSources() -> [RawInputSource] {
        lock.withLock { storedSources }
    }
}

private struct DemandInputSourceSwitcher: InputSourceSwitching {
    func select(id: String) -> InputSourceSelectionResult {
        .selected
    }
}

@MainActor
private final class DemandInputSourceNotifications: InputSourceNotificationObserving {
    func observe(
        _ name: Notification.Name,
        handler: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        NSObject()
    }

    func remove(_ token: NSObjectProtocol) {}
}

@MainActor
private func demandInputSource(id: String, name: String) -> RawInputSource {
    RawInputSource(
        id: id,
        localizedName: name,
        languages: [],
        iconImageURL: nil,
        isEnabled: true,
        isSelectCapable: true
    )
}

@MainActor
private func demandAudioInputStatus(
    name: String,
    scalar: Double,
    completedScalarRequestID: UUID? = nil
) -> AudioInputStatus {
    var status = AudioInputStatus(
        devices: [AudioInputDevice(id: 22, uid: name, name: name)],
        defaultDeviceID: 22,
        deviceName: name,
        scalar: scalar,
        canSetVolume: true,
        muteState: .unmuted,
        canSetMute: true,
        isRefreshing: false,
        isBusy: false,
        error: nil
    )
    status.completedScalarRequestID = completedScalarRequestID
    return status
}

@MainActor
private func demandBatteryStatus(_ percentage: Int) -> BatteryStatus {
    BatteryStatus(
        rawPercentage: percentage,
        isPresent: true,
        isCharging: false,
        isLowPowerMode: false,
        isConnectedToPower: false
    )
}
