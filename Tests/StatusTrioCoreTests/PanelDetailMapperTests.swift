import XCTest
@testable import StatusTrioCore

@MainActor
final class PanelDetailMapperTests: XCTestCase {
    func testBatteryMapperKeepsPowerTintTimestampAndExplanation() {
        let localization = makeLocalization()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let battery = BatteryStatus(
            rawPercentage: 67,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: true,
            isConnectedToPower: true
        )
        var details = BatteryDetails(adapterWatts: 30, cycleCount: 12, powerAvailability: .available)
        details.power = BatteryPowerSample(volts: 12, amps: 1, updatedAt: timestamp)
        details.systemPower = SystemPowerSample(watts: 18.2, readAt: timestamp)

        let state = PanelDetailMapper.battery(status: battery, details: details, localization: localization)

        XCTAssertEqual(state.rows.map(\.id), [
            LocalizationKey.batteryDetailsSystemPower.rawValue,
            LocalizationKey.batteryDetailsSystemReadAt.rawValue,
            LocalizationKey.batteryDetailsCharging.rawValue,
            LocalizationKey.batteryDetailsVoltage.rawValue,
            LocalizationKey.batteryDetailsCurrent.rawValue,
            LocalizationKey.batteryDetailsAdapter.rawValue,
            LocalizationKey.batteryDetailsCycles.rawValue,
            LocalizationKey.batteryDetailsLowPower.rawValue
        ])
        XCTAssertEqual(state.rows[0].value, "18.2 W")
        XCTAssertEqual(state.rows[0].tint, .primary)
        XCTAssertTrue(state.rows[1].value.contains(":20"))
        XCTAssertEqual(state.rows[2].tint, .positive)
        XCTAssertEqual(state.explanation, localization.string(.batteryDetailsExplanation))
        XCTAssertFalse(state.isLoading)
    }

    func testBatteryMapperRepresentsMissingDetailsAsLoadingAndWiredUnavailableKeepsFiveRows() {
        let localization = makeLocalization()
        let battery = BatteryStatus(
            rawPercentage: 50,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )

        let batteryState = PanelDetailMapper.battery(status: battery, details: nil, localization: localization)
        let wiredState = PanelDetailMapper.wired(details: nil, localization: localization)

        XCTAssertTrue(batteryState.isLoading)
        XCTAssertEqual(batteryState.rows.map(\.id), [LocalizationKey.batteryDetailsLowPower.rawValue])
        XCTAssertEqual(wiredState.rows.map(\.id), [
            LocalizationKey.networkDetailInterface.rawValue,
            LocalizationKey.networkDetailIPv4.rawValue,
            LocalizationKey.networkDetailIPv6.rawValue,
            LocalizationKey.networkDetailRouter.rawValue,
            LocalizationKey.networkDetailDNS.rawValue
        ])
        XCTAssertTrue(wiredState.rows.allSatisfy { $0.value == localization.string(.networkDetailUnavailable) })
        XCTAssertEqual(
            wiredState.rows.filter { $0.isCopyable }.map(\.id),
            [
                LocalizationKey.networkDetailIPv4.rawValue,
                LocalizationKey.networkDetailIPv6.rawValue,
                LocalizationKey.networkDetailRouter.rawValue,
                LocalizationKey.networkDetailDNS.rawValue
            ]
        )
    }

    func testWiFiMapperPreservesSSIDIdentityGroupsActionsAndScanCapabilities() {
        let localization = makeLocalization()
        let connected = network(ssid: "Home", security: .wpa2Personal, bssid: "AA", known: false)
        let whitespace = network(ssid: " Home ", security: .open, bssid: "BB", known: true)
        let other = network(ssid: "Cafe", security: .wpa3Personal, bssid: "CC", known: false)
        let status = WiFiStatus(state: .connected, rssi: -48, ssid: "Home", nameAccess: .authorized)
        let state = PanelDetailMapper.wifi(
            status: status,
            networks: [other, whitespace, connected],
            details: .unavailable,
            listState: .ready,
            localization: localization
        )

        XCTAssertEqual(state.knownRows.map(\.key.ssid), [" Home ", "Home"])
        XCTAssertEqual(state.otherRows.map(\.key.ssid), ["Cafe"])
        XCTAssertEqual(state.knownRows.map(\.opensSettings), [true, false])
        XCTAssertEqual(state.knownRows[0].name, " Home ")
        XCTAssertEqual(state.knownRows[0].securityMarker, nil)
        XCTAssertTrue(state.knownRows[1].selected)
        XCTAssertEqual(state.otherRows[0].securityMarker, "lock.fill")
        XCTAssertTrue(state.powerIsOn)
        XCTAssertTrue(state.canSetPower)
        XCTAssertTrue(state.canRefresh)
        XCTAssertFalse(state.isScanning)
        XCTAssertEqual(state.detail.rows.count, 17)
        XCTAssertEqual(state.detail.rows.map(\.id), [
            LocalizationKey.wifiDetailSSID.rawValue,
            LocalizationKey.wifiDetailBSSID.rawValue,
            LocalizationKey.wifiDetailBand.rawValue,
            LocalizationKey.wifiDetailChannel.rawValue,
            LocalizationKey.wifiDetailChannelWidth.rawValue,
            LocalizationKey.wifiDetailRSSI.rawValue,
            LocalizationKey.wifiDetailPHY.rawValue,
            LocalizationKey.wifiDetailTxRate.rawValue,
            LocalizationKey.wifiDetailSecurity.rawValue,
            LocalizationKey.wifiDetailNoise.rawValue,
            LocalizationKey.wifiDetailSNR.rawValue,
            LocalizationKey.wifiDetailCountryCode.rawValue,
            LocalizationKey.networkDetailInterface.rawValue,
            LocalizationKey.networkDetailIPv4.rawValue,
            LocalizationKey.networkDetailIPv6.rawValue,
            LocalizationKey.networkDetailRouter.rawValue,
            LocalizationKey.networkDetailDNS.rawValue
        ])
        XCTAssertEqual(state.collapsedDetailRowCount, 9)
        XCTAssertEqual(state.visibleDetailRows(expanded: false).count, 9)
        XCTAssertEqual(state.visibleDetailRows(expanded: true).count, 17)
        XCTAssertEqual(state.showMoreTitle, localization.string(.wifiDetailsMore))
        XCTAssertEqual(state.showLessTitle, localization.string(.wifiDetailsLess))
        XCTAssertTrue(state.detail.rows.first { $0.id == LocalizationKey.wifiDetailBSSID.rawValue }?.isCopyable == true)
        XCTAssertFalse(state.detail.rows.first { $0.id == LocalizationKey.wifiDetailSSID.rawValue }?.isCopyable ?? true)
    }

    func testWiredMappedAddressesKeepCopyAffordanceAndInterfaceDoesNot() {
        let state = PanelDetailMapper.wired(
            details: PrimaryLinkDetails(
                interfaceName: "en5",
                ipv4Addresses: ["192.168.1.20"],
                ipv6Addresses: ["fe80::1"],
                router: "192.168.1.1",
                dnsServers: ["1.1.1.1"]
            ),
            localization: makeLocalization()
        )

        XCTAssertEqual(
            state.rows.filter { $0.isCopyable }.map(\.id),
            [
                LocalizationKey.networkDetailIPv4.rawValue,
                LocalizationKey.networkDetailIPv6.rawValue,
                LocalizationKey.networkDetailRouter.rawValue,
                LocalizationKey.networkDetailDNS.rawValue
            ]
        )
        XCTAssertFalse(state.rows[0].isCopyable)
    }

    func testWiFiMapperResolvesFailureScanningPermissionAndPowerMessages() {
        let localization = makeLocalization()
        let status = WiFiStatus(state: .off, rssi: nil, nameAccess: .denied)

        let failed = PanelDetailMapper.wifi(status: status, networks: [], details: .unavailable, listState: .failed, localization: localization)
        let scanning = PanelDetailMapper.wifi(status: status, networks: [], details: .unavailable, listState: .scanning, localization: localization)
        let noInterface = PanelDetailMapper.wifi(status: status, networks: [], details: .unavailable, listState: .noInterface, localization: localization)
        let denied = PanelDetailMapper.wifi(status: status, networks: [], details: .unavailable, listState: .permissionDenied, localization: localization)
        let off = PanelDetailMapper.wifi(status: status, networks: [], details: .unavailable, listState: .poweredOff, localization: localization)
        let empty = PanelDetailMapper.wifi(status: status, networks: [], details: .unavailable, listState: .ready, localization: localization)

        XCTAssertEqual(failed.message, localization.string(.wifiScanFailed))
        XCTAssertEqual(failed.messageIntent, .none)
        XCTAssertEqual(scanning.message, localization.string(.wifiScanning))
        XCTAssertTrue(scanning.isScanning)
        XCTAssertFalse(scanning.canRefresh)
        XCTAssertFalse(noInterface.canSetPower)
        XCTAssertEqual(denied.messageIntent, .locationSettings)
        XCTAssertEqual(off.message, localization.string(.wifiPanelOff))
        XCTAssertFalse(off.powerIsOn)
        XCTAssertEqual(empty.message, localization.string(.wifiNoNetworks))
        XCTAssertTrue(empty.canRefresh)
    }

    private func network(ssid: String, security: WiFiSecurityKind, bssid: String, known: Bool) -> WiFiNetwork {
        WiFiNetwork(
            identity: WiFiNetworkIdentity(ssid: ssid, security: security),
            candidates: [WiFiNetworkCandidate(ssid: ssid, bssid: bssid, rssi: -55, channel: 36, security: security)],
            connectedBSSID: "AA",
            isKnown: known
        )
    }

    private func makeLocalization() -> Localization {
        let suite = "PanelDetailMapperTests.\(UUID().uuidString)"
        return Localization(defaults: UserDefaults(suiteName: suite) ?? .standard, preferredLanguages: ["en"])
    }
}
