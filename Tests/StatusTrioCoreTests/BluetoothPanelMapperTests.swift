import XCTest
@testable import StatusTrioCore

@MainActor
final class BluetoothPanelMapperTests: XCTestCase {
    func testMapperPreservesConnectedGroupsSavedOrderFiltersBatteryOptionsAndConfirmation() {
        let localization = makeLocalization()
        let devices = [
            device("AA:00:00:00:00:02", "Mouse", connected: false),
            device("AA:00:00:00:00:03", "AirPods", connected: true),
            device("AA:00:00:00:00:01", "Hidden", connected: true),
            device("AA:00:00:00:00:05", "Keyboard", connected: false),
            device("AA:00:00:00:00:04", "Ghost", connected: false, ghost: true)
        ]
        let state = BluetoothPanelMapper.map(
            availability: .available,
            devices: devices,
            batteryLevels: ["AA0000000003": BluetoothBatteryLevel(
                deviceAddress: "AA:00:00:00:00:03", main: 82, left: nil, right: nil, caseLevel: nil
            )],
            actionStates: [:],
            nearbyDevices: [nearby("Tracker", level: 42)],
            batteryLevelsReadFailed: false,
            isExpanded: false,
            options: BluetoothDeviceListOptions(
                showsList: true,
                maxVisibleDevices: 2,
                order: ["AA0000000002", "AA0000000003"],
                hidesGhostDevices: true,
                hiddenDeviceAddresses: ["AA0000000001"]
            ),
            showsBatteryLevels: true,
            showsNearbyBatteryDevices: true,
            confirmingAddress: "AA0000000002",
            localization: localization
        )

        XCTAssertEqual(state.pairedRows.map(\.address), ["AA0000000003", "AA0000000002"])
        XCTAssertEqual(state.pairedRows[0].batteryText, "82%")
        XCTAssertEqual(state.pairedRows[1].batteryText, nil)
        XCTAssertEqual(state.nearbyRows.map(\.title), ["Tracker"])
        XCTAssertEqual(state.confirmationAddress, "AA0000000002")
        XCTAssertTrue(state.canExpand)
        XCTAssertTrue(state.showsPairedHeading)
    }

    func testMapperHidesBatteryRowsAndNearbyRowsWhenTheirSettingsAreOff() {
        let state = BluetoothPanelMapper.map(
            availability: .available,
            devices: [device("AA:00:00:00:00:01", "AirPods", connected: true)],
            batteryLevels: ["AA0000000001": BluetoothBatteryLevel(
                deviceAddress: "AA:00:00:00:00:01", main: 82, left: nil, right: nil, caseLevel: nil
            )],
            actionStates: [:],
            nearbyDevices: [nearby("Tracker", level: 42)],
            batteryLevelsReadFailed: false,
            isExpanded: false,
            options: .standard,
            showsBatteryLevels: false,
            showsNearbyBatteryDevices: true,
            confirmingAddress: nil,
            localization: makeLocalization()
        )

        XCTAssertNil(state.pairedRows.first?.batteryText)
        XCTAssertTrue(state.nearbyRows.isEmpty)
    }

    func testMapperHidesSummaryDeviceSegmentsWhenVisibleListAlreadyShowsConnectedDevice() {
        let localization = makeLocalization()
        let airPods = device("AA:00:00:00:00:01", "AirPods", connected: true)
        let battery = BluetoothBatteryLevel(
            deviceAddress: airPods.id,
            main: 82,
            left: nil,
            right: nil,
            caseLevel: nil
        )

        let listVisible = BluetoothPanelMapper.map(
            availability: .available,
            devices: [airPods],
            batteryLevels: ["AA0000000001": battery],
            actionStates: [:],
            nearbyDevices: [],
            batteryLevelsReadFailed: false,
            isExpanded: false,
            options: .standard,
            showsBatteryLevels: true,
            showsNearbyBatteryDevices: false,
            confirmingAddress: nil,
            localization: localization
        )

        XCTAssertEqual(listVisible.summary.subtitle, "")
        XCTAssertNil(listVisible.summaryBatterySegments)
        XCTAssertEqual(listVisible.pairedRows.first?.batteryText, "82%")

        let listDisabled = BluetoothPanelMapper.map(
            availability: .available,
            devices: [airPods],
            batteryLevels: ["AA0000000001": battery],
            actionStates: [:],
            nearbyDevices: [],
            batteryLevelsReadFailed: false,
            isExpanded: false,
            options: BluetoothDeviceListOptions(
                showsList: false,
                maxVisibleDevices: 5,
                order: []
            ),
            showsBatteryLevels: true,
            showsNearbyBatteryDevices: false,
            confirmingAddress: nil,
            localization: localization
        )

        XCTAssertEqual(listDisabled.summary.subtitle, "AirPods · 82%")
        XCTAssertEqual(listDisabled.summaryBatterySegments?.plainText, "AirPods · 82%")
    }

    func testMapperPresentsBatteryReadFailureOnlyWhenPairedRowsAreVisible() {
        let state = BluetoothPanelMapper.map(
            availability: .available,
            devices: [device("AA:00:00:00:00:01", "AirPods", connected: true)],
            batteryLevels: [:],
            actionStates: [:],
            nearbyDevices: [],
            batteryLevelsReadFailed: true,
            isExpanded: false,
            options: .standard,
            showsBatteryLevels: true,
            showsNearbyBatteryDevices: false,
            confirmingAddress: nil,
            localization: makeLocalization()
        )

        XCTAssertEqual(state.errorText, makeLocalization().string(.bluetoothBatteryUnavailable))
    }

    func testMapperKeepsBusyAndFailedActionTextAndMapsBluetoothRefreshFailure() {
        let localization = makeLocalization()
        let device = device("AA:00:00:00:00:01", "Headphones", connected: false)
        let state = BluetoothPanelMapper.map(
            availability: .failed,
            devices: [device],
            batteryLevels: [:],
            actionStates: ["AA0000000001": .failed(.connect)],
            nearbyDevices: [],
            batteryLevelsReadFailed: false,
            isExpanded: false,
            options: .standard,
            showsBatteryLevels: false,
            showsNearbyBatteryDevices: false,
            confirmingAddress: "AA-00-00-00-00-01",
            localization: localization
        )

        XCTAssertTrue(state.pairedRows.isEmpty, "unavailable Bluetooth must not leave stale device rows visible")
        XCTAssertEqual(state.summary.subtitle, localization.string(.bluetoothReadFailed))
        XCTAssertEqual(state.confirmationAddress, "AA0000000001")

        let available = BluetoothPanelMapper.map(
            availability: .available,
            devices: [device],
            batteryLevels: [:],
            actionStates: ["AA0000000001": .failed(.connect)],
            nearbyDevices: [],
            batteryLevelsReadFailed: false,
            isExpanded: false,
            options: .standard,
            showsBatteryLevels: false,
            showsNearbyBatteryDevices: false,
            confirmingAddress: nil,
            localization: localization
        )
        XCTAssertEqual(available.pairedRows[0].subtitle, localization.string(.bluetoothStateConnectFailed))
        XCTAssertTrue(available.pairedRows[0].actionEnabled)
        XCTAssertFalse(available.pairedRows[0].isBusy)

        let busy = BluetoothPanelMapper.map(
            availability: .available,
            devices: [device],
            batteryLevels: [:],
            actionStates: ["AA0000000001": .connecting],
            nearbyDevices: [],
            batteryLevelsReadFailed: false,
            isExpanded: false,
            options: .standard,
            showsBatteryLevels: false,
            showsNearbyBatteryDevices: false,
            confirmingAddress: nil,
            localization: localization
        )
        XCTAssertFalse(busy.pairedRows[0].actionEnabled)
        XCTAssertTrue(busy.pairedRows[0].isBusy)
    }

    func testSummaryResolvesPermissionActionsAndKeepsRequestAccessibilityCopyDistinct() {
        let localization = makeLocalization()
        let request = mapSummary(.authorizationNotDetermined, localization: localization)
        XCTAssertEqual(request.summary.intent, .requestBluetoothAuthorization)
        XCTAssertEqual(request.summary.subtitle, localization.string(.bluetoothActionRequestAuthorization))
        XCTAssertEqual(request.summary.accessibilityValue, localization.string(.bluetoothAuthorizationNotDetermined))

        let denied = mapSummary(.authorizationDenied, localization: localization)
        XCTAssertEqual(denied.summary.intent, .openBluetoothPermissionSettings)
        XCTAssertEqual(denied.summary.subtitle, localization.string(.bluetoothActionOpenPermissionSettings))
        XCTAssertEqual(denied.summary.accessibilityValue, localization.string(.bluetoothActionOpenPermissionSettings))

        let restricted = mapSummary(.authorizationRestricted, localization: localization)
        XCTAssertEqual(restricted.summary.intent, .none)
        XCTAssertEqual(restricted.summary.subtitle, localization.string(.bluetoothAuthorizationRestricted))

        let ordinary = mapSummary(.poweredOff, localization: localization)
        XCTAssertEqual(ordinary.summary.intent, .none)
        XCTAssertEqual(ordinary.summary.subtitle, localization.string(.bluetoothOff))
    }

    func testPairedRowsKeepConnectedBatteryLayoutSegmentsFailureTintAndTapPolicy() {
        let localization = makeLocalization()
        let keyboard = device(
            "AA:00:00:00:00:01",
            "Keyboard",
            connected: true,
            kind: .peripheral(.keyboard)
        )
        let caseLevel = BluetoothBatteryLevel(
            deviceAddress: keyboard.id,
            main: nil,
            left: 88,
            right: 76,
            caseLevel: 45
        )
        let connected = mapRows(
            [keyboard],
            batteryLevels: ["AA0000000001": caseLevel],
            actionStates: [:],
            localization: localization
        ).pairedRows[0]

        XCTAssertTrue(connected.isConnected)
        XCTAssertEqual(
            connected.icon,
            .symbol(name: BluetoothDeviceRowIcon.symbolName(for: keyboard), variableValue: nil, fallback: "dot.radiowaves.left.and.right")
        )
        XCTAssertEqual(connected.batteryLayout, .components)
        XCTAssertEqual(connected.batterySegments, caseLevel.segments)
        XCTAssertTrue(connected.batterySegments?.contains(.symbol(
            name: BluetoothBatteryLevel.caseSymbolName,
            label: BluetoothBatteryLevel.caseTextLabel
        )) == true)
        XCTAssertTrue(connected.requiresConfirmation)
        XCTAssertEqual(connected.status, .connected)
        XCTAssertNil(connected.statusText)
        XCTAssertEqual(connected.statusTint, .secondary)

        let disconnected = device("AA:00:00:00:00:02", "Headphones", connected: false)
        let failure = mapRows(
            [disconnected],
            batteryLevels: [:],
            actionStates: ["AA0000000002": .failed(.connect)],
            localization: localization
        ).pairedRows[0]
        XCTAssertFalse(failure.isConnected)
        XCTAssertEqual(failure.batteryLayout, .inline)
        XCTAssertNil(failure.batterySegments)
        XCTAssertFalse(failure.requiresConfirmation)
        XCTAssertEqual(failure.status, .connectFailed)
        XCTAssertEqual(failure.statusText, localization.string(.bluetoothStateConnectFailed))
        XCTAssertEqual(failure.statusTint, .critical)
    }

    func testMapperFoldsNearbyMobileReadingsIntoReadOnlyRowsAndKeepsReportedBattery() {
        let iphone = nearby("Ling's iPhone", level: 31, model: "iPhone14,3")
        let tracker = nearby("Scale", level: 52, model: "Scale-1")
        let pairedIPhone = device("AA:00:00:00:00:09", "Ling's iPhone", connected: false, kind: .unknown)
        let reported = BluetoothBatteryLevel(
            deviceAddress: pairedIPhone.id,
            main: 88,
            left: nil,
            right: nil,
            caseLevel: nil
        )

        let state = BluetoothPanelMapper.map(
            availability: .available,
            devices: [pairedIPhone],
            batteryLevels: ["AA0000000009": reported],
            actionStates: [:],
            nearbyDevices: [iphone, tracker],
            batteryLevelsReadFailed: false,
            isExpanded: true,
            options: .standard,
            showsBatteryLevels: true,
            showsNearbyBatteryDevices: true,
            confirmingAddress: nil,
            localization: makeLocalization()
        )

        XCTAssertEqual(state.pairedRows.map(\.title), ["Ling's iPhone"])
        XCTAssertEqual(state.pairedRows[0].batteryText, "88%")
        XCTAssertEqual(state.pairedRows[0].icon, .symbol(name: BluetoothDeviceRowIcon.symbolName(for: pairedIPhone.identifiedByModel(.mobile(.phone))), variableValue: nil, fallback: "dot.radiowaves.left.and.right"))
        XCTAssertFalse(state.pairedRows[0].isActionable)
        XCTAssertFalse(state.pairedRows[0].actionEnabled)
        XCTAssertEqual(state.nearbyRows.map(\.title), ["Scale"])
    }

    func testMapperKeepsMainSavedOrderRulesForSynthesizedMobileRows() {
        let nearbyPhone = nearby("Travel Phone", level: 67, model: "iPhone15,2")
        let disconnected = device("AA:00:00:00:00:01", "Headphones", connected: false)
        let pairedUnknown = device("AA:00:00:00:00:02", "Travel Phone", connected: false, kind: .unknown)
        let laterDisconnected = device("AA:00:00:00:00:03", "Mouse", connected: false)

        let state = BluetoothPanelMapper.map(
            availability: .available,
            devices: [disconnected, pairedUnknown, laterDisconnected],
            batteryLevels: [:],
            actionStates: [:],
            nearbyDevices: [nearbyPhone],
            batteryLevelsReadFailed: false,
            isExpanded: true,
            options: BluetoothDeviceListOptions(
                showsList: true,
                maxVisibleDevices: 5,
                order: ["AA0000000003", "AA0000000001"]
            ),
            showsBatteryLevels: true,
            showsNearbyBatteryDevices: true,
            confirmingAddress: nil,
            localization: makeLocalization()
        )

        // 1.5.0 keeps main's list rule: the saved order only reorders devices
        // within their group, so the synthesized mobile row — which has no
        // saved rank — lands after the ranked rows.
        XCTAssertEqual(state.pairedRows.map(\.title), ["Mouse", "Headphones", "Travel Phone"])
        guard let mobileRow = state.pairedRows.last else {
            XCTFail("the synthesized mobile row is missing")
            return
        }
        XCTAssertEqual(mobileRow.title, "Travel Phone")
        XCTAssertFalse(mobileRow.isActionable)
        XCTAssertFalse(mobileRow.actionEnabled)
    }

    func testMapperUsesNearbyIPadModelToSupplyTabletGlyph() {
        let nearbyTablet = nearby("Family iPad", level: 74, model: "iPad11,1")
        let state = BluetoothPanelMapper.map(
            availability: .available,
            devices: [],
            batteryLevels: [:],
            actionStates: [:],
            nearbyDevices: [nearbyTablet],
            batteryLevelsReadFailed: false,
            isExpanded: true,
            options: .standard,
            showsBatteryLevels: true,
            showsNearbyBatteryDevices: true,
            confirmingAddress: nil,
            localization: makeLocalization()
        )

        XCTAssertEqual(state.pairedRows.map(\.title), ["Family iPad"])
        XCTAssertEqual(state.pairedRows[0].icon, .symbol(name: "ipad.landscape", variableValue: nil, fallback: "dot.radiowaves.left.and.right"))
        XCTAssertEqual(state.pairedRows[0].batteryText, "74%")
        XCTAssertFalse(state.pairedRows[0].isActionable)
    }

    private func mapSummary(
        _ availability: BluetoothAvailability,
        localization: Localization
    ) -> BluetoothPanelState {
        BluetoothPanelMapper.map(
            availability: availability,
            devices: [],
            batteryLevels: [:],
            actionStates: [:],
            nearbyDevices: [],
            batteryLevelsReadFailed: false,
            isExpanded: false,
            options: .standard,
            showsBatteryLevels: false,
            showsNearbyBatteryDevices: false,
            confirmingAddress: nil,
            localization: localization
        )
    }

    private func mapRows(
        _ devices: [BluetoothDevice],
        batteryLevels: [String: BluetoothBatteryLevel],
        actionStates: [String: BluetoothDeviceActionState],
        localization: Localization
    ) -> BluetoothPanelState {
        BluetoothPanelMapper.map(
            availability: .available,
            devices: devices,
            batteryLevels: batteryLevels,
            actionStates: actionStates,
            nearbyDevices: [],
            batteryLevelsReadFailed: false,
            isExpanded: true,
            options: .standard,
            showsBatteryLevels: true,
            showsNearbyBatteryDevices: false,
            confirmingAddress: nil,
            localization: localization
        )
    }

    private func device(
        _ address: String,
        _ name: String,
        connected: Bool,
        ghost: Bool = false,
        kind: BluetoothDeviceKind = .audio
    ) -> BluetoothDevice {
        BluetoothDevice(id: address, name: name, kind: kind, isConnected: connected, isUnpairedGhost: ghost)
    }

    private func nearby(_ name: String, level: Int, model: String? = nil) -> NearbyBluetoothBatteryDevice {
        NearbyBluetoothBatteryDevice(id: UUID(), name: name, batteryLevel: level, model: model, manufacturer: nil, lastUpdated: Date())
    }

    private func makeLocalization() -> Localization {
        let suite = "BluetoothPanelMapperTests.\(UUID().uuidString)"
        return Localization(defaults: UserDefaults(suiteName: suite) ?? .standard, preferredLanguages: ["en"])
    }
}
