import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class NearbyBLEControllerDemandTests: XCTestCase {
    func testBackgroundScannerStopsDuringSystemSleepAndResumesOnWake() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let selected = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [selected], hiddenIDs: [])
        controller.setNearbyBLEBackgroundRefresh(enabled: true, selectedIDs: [selected], interval: .seconds(120))
        XCTAssertTrue(scanner.isRunning)

        controller.setSystemSleeping(true)
        XCTAssertFalse(scanner.isRunning)

        controller.setSystemSleeping(false)
        XCTAssertTrue(scanner.isRunning)
        controller.deactivate()
    }

    func testGlobalBatteryOffRevokesPermitWithoutRemovingConsentOrSettingsDiscovery() async {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([id], for: "panel")
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [id])
        scanner.publish([device(id)])
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [], batteryLevelsEnabled: false)
        await Task.yield()
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty, "queued callback is rejected after global off")
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        XCTAssertTrue(scanner.isRunning)
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [id])
        controller.configureNearbyBLEDevices(enabled: false, knownIDs: [id], hiddenIDs: [])
        XCTAssertFalse(scanner.isRunning)
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        controller.deactivate()
    }

    func testSettingsDiscoveryTokenDoesNotStartScannerWithoutPopoverOrBackgroundPreference() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])

        controller.requestNearbyBLEDiscovery("settings")

        XCTAssertFalse(scanner.isRunning)
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "Settings does not request ongoing visible-row reads")
        controller.releaseNearbyBLEDiscovery("settings")
        XCTAssertFalse(scanner.isRunning)
        controller.deactivate()
    }

    func testAnyVisibleBLEUUIDAuthorizesAndAcceptsBatteryReads() async {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let selected = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [selected], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([selected], for: "panel")

        XCTAssertEqual(scanner.allowedReadDeviceIDs, [selected])
        scanner.publish([device(selected)])
        await Task.yield()
        XCTAssertEqual(controller.nearbyBatteryDevices.map(\.id), [selected])
        controller.setVisibleNearbyBLEDevices([], for: "panel")
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        controller.deactivate()
    }

    func testSelectedVisibleRowsNeverReceiveNearbyBLEReadPermission() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
        controller.setVisibleNearbyBLEDevices([id], for: "panel")
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)

        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "popover without the Bluetooth summary is insufficient")
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [id])

        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [id])
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        controller.deactivate()
    }

    func testPanelCloseStopsBLEScannerWhenBackgroundRefreshIsOff() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([id], for: "panel")
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [id])

        controller.releaseVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)

        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        XCTAssertFalse(scanner.isRunning, "Settings must not keep BLE discovery active")
        controller.releaseNearbyBLEDiscovery("settings")
        XCTAssertFalse(scanner.isRunning)
        controller.deactivate()
    }

    func testGeneralBatteryToggleOffStopsBLEScannerWithoutBackgroundOwner() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([id], for: "panel")
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [id])

        // The panel's general battery-level setting removes the read demand.
        controller.setVisibleNearbyBLEDevices([], for: "panel")

        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        XCTAssertTrue(scanner.isRunning, "open popover still owns bounded discovery")
        controller.releaseNearbyBLEDiscovery("settings")
        controller.releaseVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.releaseVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        XCTAssertFalse(scanner.isRunning)
        controller.deactivate()
    }

    func testHidingRowsNeverGrantsNearbyBLEReadPermission() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let visible = UUID()
        let offLimit = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [visible, offLimit], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([visible], for: "panel")
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [visible])

        controller.configureNearbyBLEDevices(
            enabled: true,
            knownIDs: [visible, offLimit],
            hiddenIDs: [offLimit]
        )

        XCTAssertEqual(scanner.allowedReadDeviceIDs, [visible])

        controller.configureNearbyBLEDevices(
            enabled: true,
            knownIDs: [visible],
            hiddenIDs: []
        )
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [visible], "deselecting off-limit B preserves visible A's permit")
        controller.deactivate()
    }

    func testFeatureOffAndBluetoothUnavailableKeepNearbyBLEReadsDisabled() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([id], for: "panel")
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [id])

        controller.configureNearbyBLEDevices(enabled: false, knownIDs: [id], hiddenIDs: [])
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        XCTAssertFalse(scanner.isRunning)

        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [id])
        monitor.emit(.poweredOff)
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        XCTAssertFalse(scanner.isRunning)
        controller.deactivate()
    }

    func testNearbyBLECallbacksAcceptOnlyCurrentlyVisibleUUIDs() async {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let selected = UUID()
        let stranger = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [selected], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([selected], for: "panel")
        scanner.publish([device(selected), device(stranger)])
        await Task.yield()

        XCTAssertEqual(controller.nearbyBatteryDevices.map(\.id), [selected])
        controller.setVisibleNearbyBLEDevices([], for: "panel")
        scanner.publish([device(selected)])
        await Task.yield()
        XCTAssertEqual(controller.nearbyBatteryDevices.map(\.id), [selected], "late callbacks cannot add a stranger after viewport release")
        controller.deactivate()
    }

    func testHideAndUnhideRejectsOldQueuedCallbackButAcceptsNewCallback() async {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([id], for: "panel")

        scanner.publish([device(id)])
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [id])
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
        await Task.yield()

        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)
        scanner.publish([device(id)])
        await Task.yield()
        XCTAssertEqual(controller.nearbyBatteryDevices.map(\.id), [id])
        controller.deactivate()
    }

    func testRevokingOneDeviceRejectsItsCallbackWithoutInvalidatingTheOther() async {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        let first = UUID()
        let second = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [first, second], hiddenIDs: [])
        monitor.emit(.poweredOn)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([first, second], for: "panel")

        let inFlight = scanner.capturedDevicesCallback([device(first), device(second)])
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [first, second], hiddenIDs: [second])
        inFlight()
        await Task.yield()

        XCTAssertEqual(controller.nearbyBatteryDevices.map(\.id), [first])
        controller.deactivate()
    }

    func testUnchangedAuthorizationKeepsAnotherDevicesInFlightCallback() async {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        let first = UUID()
        let second = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [first, second], hiddenIDs: [])
        monitor.emit(.poweredOn)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([first], for: "first")
        controller.setVisibleNearbyBLEDevices([second], for: "second")

        let inFlight = scanner.capturedDevicesCallback([device(second)])
        controller.setVisibleNearbyBLEDevices([first], for: "first")
        inFlight()
        await Task.yield()

        XCTAssertEqual(controller.nearbyBatteryDevices.map(\.id), [second])
        controller.deactivate()
    }

    func testUnchangedAuthorizationSnapshotRejectsRetiredDeviceFromCombinedCallback() async {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        let first = UUID()
        let second = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [first, second], hiddenIDs: [])
        monitor.emit(.poweredOn)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([first], for: "first")
        controller.setVisibleNearbyBLEDevices([second], for: "second")

        let inFlight = scanner.capturedDevicesCallback([device(first), device(second)])
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [first, second], hiddenIDs: [second])
        inFlight()
        await Task.yield()

        XCTAssertEqual(
            Set(controller.nearbyBatteryDevices.map(\.id)),
            [first],
            "the current grant survives while only the retired device is rejected"
        )
        controller.deactivate()
    }

    func testControllerTokenMapsTrackOnlyCurrentGrants() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        let current = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [current], hiddenIDs: [])
        monitor.emit(.poweredOn)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        for _ in 0..<10_000 {
            let id = UUID()
            controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
            controller.setVisibleNearbyBLEDevices([id], for: "panel")
        }
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [current], hiddenIDs: [])
        controller.setVisibleNearbyBLEDevices([current], for: "panel")

        XCTAssertEqual(controller.nearbyAuthorizationTokenCount, 1)
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [current])
        controller.deactivate()
    }

    func testSettingsDiscoveryNeverAddsUUIDToReadPermit() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        let candidate = NearbyBLEDeviceCandidate(id: UUID(), name: "Broadcast", vendor: .apple, lastSeen: Date())

        scanner.onCandidatesChanged?([candidate])

        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)
        controller.deactivate()
    }

    func testSettingsDiscoveryInitialReadsOnlyNewNonHiddenCandidatesAndRevokesOnBatteryOff() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)

        let candidateID = UUID(uuidString: "00000000-0000-0000-0000-000000000121")!
        let freshID = UUID(uuidString: "00000000-0000-0000-0000-000000000122")!
        let hiddenID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let expiredID = UUID(uuidString: "00000000-0000-0000-0000-000000000124")!
        let now = Date()
        scanner.discoveredCandidates = [
            .init(id: candidateID, name: "New phone", vendor: .apple, lastSeen: now),
            .init(id: freshID, name: "Fresh phone", vendor: .apple, lastSeen: now),
            .init(id: hiddenID, name: "Hidden phone", vendor: .apple, lastSeen: now),
            .init(id: expiredID, name: "Expired phone", vendor: .apple, lastSeen: now)
        ]
        controller.configureNearbyBLEDevices(
            enabled: true,
            knownIDs: [freshID, expiredID, hiddenID],
            hiddenIDs: [hiddenID],
            batteryLevelsEnabled: true,
            listVisible: true,
            persistedSelections: [NearbyBLEDeviceSelection(
                id: freshID, name: "Fresh phone", vendor: .apple, model: nil,
                batteryLevel: 77, batteryLastUpdated: now
            ), NearbyBLEDeviceSelection(
                id: expiredID, name: "Expired phone", vendor: .apple, model: nil,
                batteryLevel: 48, batteryLastUpdated: now.addingTimeInterval(-1201)
            )]
        )
        scanner.onCandidatesChanged?(scanner.discoveredCandidates)

        XCTAssertEqual(scanner.initialReadDeviceIDs, [candidateID, expiredID])
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "unrendered rows are not visible permits")

        controller.setNearbyBLEBackgroundRefresh(enabled: true, selectedIDs: [freshID], interval: .seconds(120))
        XCTAssertTrue(scanner.allowedReadDeviceIDs.contains(freshID), "background cadence refreshes even a still-fresh verified UUID")

        controller.configureNearbyBLEDevices(
            enabled: true,
            knownIDs: [freshID, hiddenID],
            hiddenIDs: [hiddenID],
            batteryLevelsEnabled: false,
            listVisible: true,
            persistedSelections: [NearbyBLEDeviceSelection(
                id: freshID, name: "Fresh phone", vendor: .apple, model: nil,
                batteryLevel: 77, batteryLastUpdated: now
            )]
        )
        XCTAssertTrue(scanner.initialReadDeviceIDs.isEmpty)
        controller.deactivate()
    }

    func testInitialReadGrantIssuesTokenAndRevocationRetiresIt() {
        let scanner = CoreBluetoothLEBatteryScanner()
        let candidateID = UUID()
        _ = scanner.setInitialReadCandidateIDs([candidateID])
        let token = scanner.initialReadToken(for: candidateID)

        XCTAssertNotNil(token)
        _ = scanner.setInitialReadCandidateIDs([])

        XCTAssertFalse(scanner.acceptsInitialRead(candidateID, token: token))
        XCTAssertNil(scanner.initialReadToken(for: candidateID))
    }

    func testInitialReadSurvivesExplicitAuthorizationOfTheSameID() {
        let scanner = CoreBluetoothLEBatteryScanner()
        let id = UUID()
        _ = scanner.setInitialReadCandidateIDs([id])
        let initialToken = scanner.initialReadToken(for: id)

        _ = scanner.setAllowedReadDeviceIDs([id])
        _ = scanner.setInitialReadCandidateIDs([])

        XCTAssertNotNil(initialToken)
        XCTAssertEqual(scanner.currentReadToken(for: id), initialToken)
        XCTAssertEqual(scanner.initialReadGrantCount, 0)
        XCTAssertEqual(scanner.readGrantCount, 1)
    }

    func testExplicitReadRevocationStillWinsWhenTheIDMovesToInitial() {
        let scanner = CoreBluetoothLEBatteryScanner()
        let id = UUID()
        _ = scanner.setAllowedReadDeviceIDs([id])
        let explicitToken = scanner.currentReadToken(for: id)

        _ = scanner.setAllowedReadDeviceIDs([])
        _ = scanner.setInitialReadCandidateIDs([id])

        XCTAssertNotNil(explicitToken)
        XCTAssertNotEqual(scanner.initialReadToken(for: id), explicitToken)
        XCTAssertNil(scanner.currentReadToken(for: id))
    }

    func testInitialToExplicitMigrationKeepsTheCurrentReadCompletionAuthorized() async {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        let id = UUID()
        let candidate = NearbyBLEDeviceCandidate(
            id: id,
            name: "Phone",
            vendor: .apple,
            lastSeen: Date()
        )
        scanner.discoveredCandidates = [candidate]
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [], hiddenIDs: [])
        monitor.emit(.poweredOn)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        scanner.onCandidatesChanged?([candidate])
        let initialToken = scanner.initialReadToken(for: id)

        controller.setVisibleNearbyBLEDevices([id], for: "panel")
        scanner.onInitialReadCandidateCompleted?(id, false, initialToken)
        await Task.yield()
        XCTAssertTrue(controller.nearbyBLEReadFailures.contains(id))
        scanner.publish([device(id)])
        await Task.yield()

        XCTAssertEqual(controller.nearbyBatteryDevices.map(\.id), [id])
        controller.deactivate()
    }

    func testInitialReadCandidateTokensRemainBoundedToCurrentCandidates() {
        let scanner = CoreBluetoothLEBatteryScanner()
        var priorID: UUID?
        for _ in 0..<10_000 {
            let current = UUID()
            _ = scanner.setInitialReadCandidateIDs([current])
            if let priorID {
                XCTAssertNil(scanner.initialReadToken(for: priorID))
            }
            priorID = current
        }
        let current = UUID()
        _ = scanner.setInitialReadCandidateIDs([current])

        XCTAssertEqual(scanner.initialReadGrantCount, 1)
        XCTAssertNotNil(scanner.initialReadToken(for: current))
    }

    func testOldInitialReadCallbackCannotDeliverAfterStopAndRestart() async {
        let scanner = CoreBluetoothLEBatteryScanner()
        let id = UUID()
        _ = scanner.setInitialReadCandidateIDs([id])
        let oldToken = scanner.initialReadToken(for: id)
        scanner.stop()
        _ = scanner.setInitialReadCandidateIDs([id])
        let newToken = scanner.initialReadToken(for: id)

        XCTAssertFalse(scanner.acceptsInitialRead(id, token: oldToken))
        XCTAssertNotEqual(oldToken, newToken)
        await Task.yield()
        scanner.stop()
    }

    func testOldInitialReadCompletionCannotUpdateTheRestartedControllerSession() async {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        let candidate = NearbyBLEDeviceCandidate(
            id: UUID(),
            name: "Phone",
            vendor: .apple,
            lastSeen: Date()
        )
        scanner.discoveredCandidates = [candidate]
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [], hiddenIDs: [])
        monitor.emit(.poweredOn)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        scanner.onCandidatesChanged?([candidate])
        let oldCompletion = scanner.onInitialReadCandidateCompleted
        let oldToken = scanner.initialReadToken(for: candidate.id)

        controller.deactivate()
        controller.activate()
        monitor.emit(.poweredOn)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        oldCompletion?(candidate.id, false, oldToken)
        await Task.yield()

        XCTAssertFalse(controller.nearbyBLEReadFailures.contains(candidate.id))
        controller.deactivate()
    }

    func testCurrentScannerInitialReadCompletionIsAccepted() async {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        let candidate = NearbyBLEDeviceCandidate(
            id: UUID(),
            name: "Phone",
            vendor: .apple,
            lastSeen: Date()
        )
        scanner.discoveredCandidates = [candidate]
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [], hiddenIDs: [])
        monitor.emit(.poweredOn)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        scanner.onCandidatesChanged?([candidate])
        let token = scanner.initialReadToken(for: candidate.id)

        scanner.onInitialReadCandidateCompleted?(candidate.id, false, token)
        await Task.yield()

        XCTAssertTrue(controller.nearbyBLEReadFailures.contains(candidate.id))
        controller.deactivate()
    }

    func testOldInitialReadCallbackCannotCompleteTheNewScannerGrant() {
        let scanner = CoreBluetoothLEBatteryScanner()
        let id = UUID()
        _ = scanner.setInitialReadCandidateIDs([id])
        let oldToken = scanner.initialReadToken(for: id)
        scanner.stop()
        _ = scanner.setInitialReadCandidateIDs([id])
        let newToken = scanner.initialReadToken(for: id)

        XCTAssertNotNil(oldToken)
        XCTAssertNotNil(newToken)
        XCTAssertFalse(scanner.acceptsInitialRead(id, token: oldToken))
        XCTAssertTrue(scanner.acceptsInitialRead(id, token: newToken))
        scanner.stop()
    }

    func testRetiredNilTokenCannotAuthorizeAnInitialRead() {
        let scanner = CoreBluetoothLEBatteryScanner()
        let id = UUID()
        _ = scanner.setInitialReadCandidateIDs([id])

        XCTAssertFalse(scanner.acceptsInitialRead(UUID(), token: nil))
        _ = scanner.setInitialReadCandidateIDs([])
        XCTAssertFalse(scanner.acceptsInitialRead(id, token: nil))
        scanner.stop()
    }

    private func makeController() -> (BluetoothDeviceController, DemandScannerSpy, DemandStateMonitorSpy) {
        let scanner = DemandScannerSpy()
        let monitor = DemandStateMonitorSpy()
        let controller = BluetoothDeviceController(
            worker: AvailableBluetoothPairedDeviceReader(),
            stateMonitor: monitor,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            nearbyBatteryScanner: scanner
        )
        return (controller, scanner, monitor)
    }

    private func device(_ id: UUID) -> NearbyBluetoothBatteryDevice {
        NearbyBluetoothBatteryDevice(
            id: id, name: "Device", batteryLevel: 42, model: nil, manufacturer: nil, lastUpdated: Date()
        )
    }
}

@MainActor
private final class DemandScannerSpy: BluetoothLEBatteryScanning {
    var onDevicesChanged: (([NearbyBluetoothBatteryDevice]) -> Void)?
    var onCandidatesChanged: (([NearbyBLEDeviceCandidate]) -> Void)?
    var onReadFailures: ((Set<UUID>) -> Void)?
    var onIsScanningChanged: ((Bool) -> Void)?
    private(set) var isRunning = false
    private(set) var isScanning = false
    private(set) var allowedReadDeviceIDs: Set<UUID> = []
    private var explicitReadTokenByID: [UUID: DeviceOperationToken] = [:]
    private(set) var initialReadDeviceIDs: Set<UUID> = []
    private(set) var initialReadTokens: [UUID: DeviceOperationToken] = [:]
    var onInitialReadCandidateCompleted: ((UUID, Bool, DeviceOperationToken?) -> Void)?
    var discoveredCandidates: [NearbyBLEDeviceCandidate] = []

    func setAllowedReadDeviceIDs(_ ids: Set<UUID>) -> [UUID: DeviceOperationToken] {
        allowedReadDeviceIDs = ids
        explicitReadTokenByID = currentExplicitTokens(ids)
        return explicitReadTokenByID
    }
    func setInitialReadCandidateIDs(_ ids: Set<UUID>) -> [UUID: DeviceOperationToken] {
        initialReadDeviceIDs = ids
        initialReadTokens = initialReadTokens.filter { id, token in
            ids.contains(id) && explicitReadTokenByID[id] != token
        }
        for id in ids where initialReadTokens[id] == nil {
            if let migrated = explicitReadTokenByID.removeValue(forKey: id) {
                initialReadTokens[id] = migrated
            } else {
                initialReadTokens[id] = DeviceOperationToken()
            }
        }
        return initialReadTokens
    }
    func initialReadToken(for id: UUID) -> DeviceOperationToken? {
        initialReadTokens[id]
    }
    private func currentExplicitTokens(
        _ ids: Set<UUID>
    ) -> [UUID: DeviceOperationToken] {
        var result: [UUID: DeviceOperationToken] = [:]
        for id in ids {
            result[id] = explicitReadTokenByID[id]
                ?? initialReadTokens[id]
                ?? DeviceOperationToken()
        }
        return result
    }
    func start() { isRunning = true }
    func refresh() {}
    func stop() {
        isRunning = false
        isScanning = false
        allowedReadDeviceIDs = []
        explicitReadTokenByID = [:]
        initialReadDeviceIDs = []
        initialReadTokens = [:]
    }
    func publish(_ devices: [NearbyBluetoothBatteryDevice]) { onDevicesChanged?(devices) }
    func capturedDevicesCallback(
        _ devices: [NearbyBluetoothBatteryDevice]
    ) -> () -> Void {
        guard let callback = onDevicesChanged else {
            XCTFail("scanner callback was not installed")
            return {}
        }
        return { callback(devices) }
    }
}

@MainActor
private final class DemandStateMonitorSpy: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed
    func start() { onStateChange?(.allowed, .poweredOff) }
    func stop() {}
    func emit(_ state: BluetoothManagerState) { onStateChange?(.allowed, state) }
}
