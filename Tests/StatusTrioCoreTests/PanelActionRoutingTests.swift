import AudioToolbox
import XCTest
@testable import StatusTrioCore

@MainActor
final class PanelActionRoutingTests: XCTestCase {
    func testOutputSelectionIgnoresRemovedDeviceAndReusedIDWithDifferentUID() {
        var devices = [makeOutput(id: 7, uid: "old")]
        var selected: [AudioOutputDevice] = []
        let actions = StatusPanelActions(
            outputDevices: { devices },
            selectOutput: { selected.append($0) }
        )
        let oldKey = PanelAudioDeviceID(id: 7, uid: "old")

        devices = []
        actions.selectOutput(oldKey)
        devices = [makeOutput(id: 7, uid: "replacement")]
        actions.selectOutput(oldKey)
        actions.selectOutput(PanelAudioDeviceID(id: 7, uid: nil))

        XCTAssertEqual(selected.map(\.uid), ["replacement"])
    }

    func testInputSelectionIgnoresRemovedDeviceAndReusedIDWithDifferentUID() {
        var devices = [AudioInputDevice(id: AudioDeviceID(9), uid: "old", name: "Mic")]
        var selected: [AudioInputDevice] = []
        let actions = StatusPanelActions(
            inputDevices: { devices },
            selectInput: { selected.append($0) }
        )
        let oldKey = PanelAudioDeviceID(id: 9, uid: "old")

        devices = []
        actions.selectInput(oldKey)
        devices = [AudioInputDevice(id: AudioDeviceID(9), uid: "replacement", name: "Mic")]
        actions.selectInput(oldKey)
        actions.selectInput(PanelAudioDeviceID(id: 9, uid: nil))

        XCTAssertEqual(selected.map(\.uid), ["replacement"])
    }

    func testActionsClampFiniteScalarsFlushAndForwardEachCommandOnce() {
        var outputScalars: [Double] = []
        var inputScalars: [Double] = []
        var finishes = 0
        var muteToggles = 0
        var inputMuteToggles = 0
        let actions = StatusPanelActions(
            setVolume: { outputScalars.append($0) },
            finishVolumeAdjustment: { finishes += 1 },
            toggleMute: { muteToggles += 1 },
            setInputScalar: { inputScalars.append($0) },
            toggleInputMute: { inputMuteToggles += 1 }
        )

        actions.setVolume(0.64)
        actions.setVolume(2)
        actions.setVolume(.infinity)
        actions.finishVolumeAdjustment()
        actions.toggleMute()
        actions.setInputScalar(-1)
        actions.setInputScalar(.nan)
        actions.toggleInputMute()

        XCTAssertEqual(outputScalars, [0.64, 1])
        XCTAssertEqual(inputScalars, [0])
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(muteToggles, 1)
        XCTAssertEqual(inputMuteToggles, 1)
    }

    func testBluetoothActionsResolveCurrentAddressesAndRequireExistingListeningControl() {
        var devices = [
            BluetoothDevice(id: "AA:00:00:00:00:01", name: "Keyboard", kind: .peripheral(.keyboard), isConnected: true),
            BluetoothDevice(id: "AA:00:00:00:00:02", name: "Headphones", kind: .audio, isConnected: true)
        ]
        var performed: [String] = []
        var confirmed: [String] = []
        let pendingConfirmation: String? = nil
        var modes: [(BluetoothListeningMode, String)] = []
        let actions = StatusPanelActions(
            bluetoothDevices: { devices },
            performBluetoothAction: { performed.append($0.id) },
            requestDisconnect: { confirmed.append($0.id) },
            disconnectConfirmationAddress: { pendingConfirmation },
            setListeningMode: { modes.append(($0, $1)) },
            listeningModePresentations: {
                ["AA0000000002": BluetoothListeningModePresentation(
                    availableModes: [.noiseCancellation, .transparency],
                    selectedMode: .noiseCancellation
                )]
            }
        )

        actions.performBluetoothAction(address: "aa-00-00-00-00-02")
        actions.performBluetoothAction(address: "AA:00:00:00:00:09")
        actions.requestDisconnect(address: "AA:00:00:00:00:02")
        actions.requestDisconnect(address: "AA:00:00:00:00:01")
        actions.setListeningMode(address: "aa-00-00-00-00-02", mode: .transparency)
        actions.setListeningMode(address: "aa-00-00-00-00-02", mode: .adaptive)
        actions.setListeningMode(address: "AA:00:00:00:00:01", mode: .transparency)

        devices.removeAll()
        actions.performBluetoothAction(address: "AA:00:00:00:00:02")

        XCTAssertEqual(performed, ["AA:00:00:00:00:02"])
        XCTAssertEqual(confirmed, ["AA:00:00:00:00:01"])
        XCTAssertEqual(modes.count, 1)
        XCTAssertEqual(modes.first?.0, .transparency)
        XCTAssertEqual(modes.first?.1, "AA0000000002")
    }

    func testBluetoothActionsIgnoreSynthesizedReadOnlyRows() {
        let synthesized = BluetoothDevice(
            id: "peripheral-id",
            name: "Travel Phone",
            kind: .mobile(.phone),
            isConnected: false,
            isReadOverTheAir: true
        )
        var performed: [String] = []
        var confirmations: [String] = []
        let actions = StatusPanelActions(
            bluetoothDevices: { [synthesized] },
            performBluetoothAction: { performed.append($0.id) },
            requestDisconnect: { confirmations.append($0.id) }
        )

        actions.rowTapped(address: synthesized.id)
        actions.performBluetoothAction(address: synthesized.id)
        actions.requestDisconnect(address: synthesized.id)

        XCTAssertTrue(performed.isEmpty)
        XCTAssertTrue(confirmations.isEmpty)
    }

    func testBluetoothRowTapRequestsInputConfirmationAndConfirmedActionChecksCurrentPendingAddress() {
        let keyboard = BluetoothDevice(id: "AA:00:00:00:00:01", name: "Keyboard", kind: .peripheral(.keyboard), isConnected: true)
        let headphones = BluetoothDevice(id: "AA:00:00:00:00:02", name: "Headphones", kind: .audio, isConnected: true)
        var performed: [String] = []
        var requested: [String] = []
        var pendingAddress: String?
        let actions = StatusPanelActions(
            bluetoothDevices: { [keyboard, headphones] },
            performBluetoothAction: { performed.append($0.id) },
            requestDisconnect: {
                pendingAddress = BluetoothBatteryReader.normalizedAddress($0.id)
                requested.append($0.id)
            },
            disconnectConfirmationAddress: { pendingAddress },
            cancelDisconnect: { pendingAddress = nil }
        )

        actions.rowTapped(address: keyboard.id)
        actions.rowTapped(address: headphones.id)
        actions.performBluetoothAction(address: keyboard.id)
        actions.confirmBluetoothDisconnect(address: "aa-00-00-00-00-01")
        actions.cancelDisconnect()
        actions.confirmBluetoothDisconnect(address: keyboard.id)

        XCTAssertEqual(requested, [keyboard.id])
        XCTAssertEqual(performed, [headphones.id, keyboard.id])
    }

    func testDetailAndVisibleSurfaceActionsRouteLifecycleAndWiFiCommands() {
        var activatedBattery: BatteryPowerState?
        var batteryCloseCount = 0
        var wifiActivations: [WiFiNameAccess] = []
        var wifiCloseCount = 0
        var wifiPower: [Bool] = []
        var wifiRefresh: [WiFiNameAccess] = []
        var heldSummary = 0
        var releasedSummary = 0
        var refreshedModes = 0
        var stoppedModes = 0
        var permissionRequests = 0
        var permissionSettingsOpens = 0

        let battery = BatteryStatus(
            rawPercentage: 42,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
        let actions = StatusPanelActions(
            requestBluetoothAuthorization: { permissionRequests += 1 },
            openBluetoothPermissionSettings: { permissionSettingsOpens += 1 },
            batteryStatus: { battery },
            activateBatteryDetails: { activatedBattery = $0 },
            closeBatteryDetails: { batteryCloseCount += 1 },
            wifiNameAccess: { .denied },
            activateWiFiDetails: { wifiActivations.append($0) },
            closeWiFiDetails: { wifiCloseCount += 1 },
            setWiFiPower: { wifiPower.append($0) },
            refreshWiFi: { wifiRefresh.append($0) },
            openWiredDetails: { heldSummary += 1 },
            closeWiredDetails: { releasedSummary += 1 },
            holdBluetoothSummary: { heldSummary += 1 },
            releaseBluetoothSummary: { releasedSummary += 1 },
            refreshVolumeListeningModes: { refreshedModes += 1 },
            stopVolumeListeningModes: { stoppedModes += 1 }
        )

        actions.batteryDetailsAppeared()
        actions.batteryDetailsClosed()
        actions.wifiDetailsOpened()
        actions.wifiDetailsClosed()
        actions.setWiFiPower(false)
        actions.refreshWiFi()
        actions.wiredDetailsOpened()
        actions.wiredDetailsClosed()
        actions.bluetoothSummaryAppeared()
        actions.bluetoothSummaryDisappeared()
        actions.volumeListAppeared()
        actions.volumeListDisappeared()
        actions.requestBluetoothAuthorization()
        actions.openBluetoothPermissionSettings()

        XCTAssertEqual(activatedBattery, BatteryPowerState(battery))
        XCTAssertEqual(batteryCloseCount, 1)
        XCTAssertEqual(wifiActivations, [.denied])
        XCTAssertEqual(wifiCloseCount, 1)
        XCTAssertEqual(wifiPower, [false])
        XCTAssertEqual(wifiRefresh, [.denied])
        XCTAssertEqual(heldSummary, 2)
        XCTAssertEqual(releasedSummary, 2)
        XCTAssertEqual(refreshedModes, 1)
        XCTAssertEqual(stoppedModes, 1)
        XCTAssertEqual(permissionRequests, 1)
        XCTAssertEqual(permissionSettingsOpens, 1)
    }

    func testBluetoothSummaryClaimsStayIndependentAndOnlyReadLevelsForConnectedAvailableDevices() {
        let connected = BluetoothDevice(id: "AA:00:00:00:00:01", name: "AirPods", kind: .audio, isConnected: true)
        var availability: BluetoothAvailability = .available
        var devices = [connected]
        var batteryClaims: [String] = []
        var batteryReleases: [String] = []
        var nearbyClaims: [String] = []
        var nearbyReleases: [String] = []
        let actions = StatusPanelActions(
            bluetoothDevices: { devices },
            bluetoothAvailability: { availability },
            requestBatteryLevels: { batteryClaims.append($0) },
            releaseBatteryLevels: { batteryReleases.append($0) },
            requestNearbyBatteryDevices: { nearbyClaims.append($0) },
            releaseNearbyBatteryDevices: { address, _ in nearbyReleases.append(address) }
        )

        actions.updateBluetoothBatteryLevelsClaim(enabled: true)
        actions.updateBluetoothNearbyBatteryClaim(enabled: true)
        availability = .poweredOff
        actions.updateBluetoothBatteryLevelsClaim(enabled: true)
        availability = .available
        devices.removeAll()
        actions.updateBluetoothBatteryLevelsClaim(enabled: true)
        actions.updateBluetoothNearbyBatteryClaim(enabled: false)
        actions.bluetoothSummaryAppeared()
        actions.bluetoothSummaryDisappeared()

        XCTAssertEqual(batteryClaims, ["bluetooth.summary"])
        XCTAssertEqual(batteryReleases, ["bluetooth.summary", "bluetooth.summary", "bluetooth.summary"])
        XCTAssertEqual(nearbyClaims, ["bluetooth.summary.nearbyBatteryDevices"])
        XCTAssertEqual(nearbyReleases, [
            "bluetooth.summary.nearbyBatteryDevices",
            "bluetooth.summary.nearbyBatteryDevices"
        ])
    }

    func testBluetoothSummaryDisappearanceReleasesNearbyClaimAndKeepsItsCache() {
        var releasedNearby: [(String, Bool)] = []
        let actions = StatusPanelActions(
            releaseNearbyBatteryDevices: { releasedNearby.append(($0, $1)) }
        )

        actions.bluetoothSummaryDisappeared()

        XCTAssertEqual(releasedNearby.map(\.0), ["bluetooth.summary.nearbyBatteryDevices"])
        XCTAssertEqual(releasedNearby.map(\.1), [true])
        actions.updateBluetoothNearbyBatteryClaim(enabled: false)
        XCTAssertEqual(releasedNearby.map(\.1), [true, false])
    }

    private func makeOutput(id: UInt32, uid: String?) -> AudioOutputDevice {
        AudioOutputDevice(id: AudioDeviceID(id), name: "Speaker", uid: uid, isCurrent: false)
    }
}
