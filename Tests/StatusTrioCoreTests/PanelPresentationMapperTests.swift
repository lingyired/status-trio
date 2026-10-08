import CoreAudio
import XCTest
@testable import StatusTrioCore

@MainActor
final class PanelPresentationMapperTests: XCTestCase {
    func testAbsentBatteryHasNoDetailAction() {
        let localization = makeLocalization(.english)
        let battery = BatteryStatus(
            rawPercentage: nil,
            isPresent: false,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )

        let row = PanelPresentationMapper.battery(battery, localization: localization)

        XCTAssertEqual(row.intent, .none)
        XCTAssertFalse(row.showsSettings)
        XCTAssertEqual(row.symbol, .symbol(name: "battery.slash", variableValue: nil, fallback: nil))
        XCTAssertEqual(row.title, "Battery · 100%")
        XCTAssertEqual(row.subtitle, "No battery")
        XCTAssertEqual(row.tint, .secondary)
    }

    func testBatterySummaryUsesTwentyPercentCriticalBoundary() {
        let localization = makeLocalization(.english)
        let atBoundary = makeBattery(percentage: 20)
        let belowBoundary = makeBattery(percentage: 19)

        XCTAssertEqual(PanelPresentationMapper.battery(atBoundary, localization: localization).tint, .critical)
        XCTAssertEqual(PanelPresentationMapper.battery(belowBoundary, localization: localization).tint, .critical)
        XCTAssertEqual(PanelPresentationMapper.battery(makeBattery(percentage: 21), localization: localization).tint, .primary)
    }

    func testBatteryTintPreservesChargingAndLowPowerPriority() {
        let localization = makeLocalization(.english)

        XCTAssertEqual(
            PanelPresentationMapper.battery(makeBattery(percentage: 5, isCharging: true), localization: localization).tint,
            .positive
        )
        XCTAssertEqual(
            PanelPresentationMapper.battery(makeBattery(percentage: 40, isLowPowerMode: true), localization: localization).tint,
            .caution
        )
    }

    func testNetworkWaitsForFreshWiFiNameAndPreservesPermissionAction() {
        let localization = makeLocalization(.english)
        let awaitingName = WiFiStatus(
            state: .connected,
            rssi: -58,
            ssid: nil,
            nameAccess: .authorized,
            band: .fiveGHz
        )
        let resolving = PanelPresentationMapper.network(
            wifi: awaitingName,
            connection: .wifi,
            wired: nil,
            isConstrained: false,
            isResolvingName: true,
            localization: localization
        )
        XCTAssertEqual(resolving.title, "Wi-Fi")
        XCTAssertEqual(resolving.subtitle, " ")
        XCTAssertNil(resolving.measurements)
        XCTAssertEqual(resolving.intent, .wifiDetails)

        let needsPermission = PanelPresentationMapper.network(
            wifi: WiFiStatus(state: .connected, rssi: -58, nameAccess: .notDetermined),
            connection: .wifi,
            wired: nil,
            isConstrained: false,
            isResolvingName: false,
            localization: localization
        )
        XCTAssertEqual(needsPermission.subtitle, "Allow location to show Wi-Fi name")
        XCTAssertEqual(needsPermission.intent, .requestWiFiNameAccess)

        let denied = PanelPresentationMapper.network(
            wifi: WiFiStatus(state: .connected, rssi: -58, nameAccess: .denied),
            connection: .wifi,
            wired: nil,
            isConstrained: false,
            isResolvingName: false,
            localization: localization
        )
        XCTAssertEqual(denied.intent, .locationSettings)
    }

    func testNetworkSummaryUsesNamedWiFiOnlyWhenTheWiFiPathIsSelected() {
        let localization = makeLocalization(.english)
        let wifi = WiFiStatus(
            state: .connected,
            rssi: -58,
            ssid: "Example Network",
            nameAccess: .authorized,
            band: .fiveGHz
        )

        let row = PanelPresentationMapper.network(
            wifi: wifi,
            connection: .wifi,
            wired: nil,
            isConstrained: false,
            isResolvingName: false,
            localization: localization
        )
        XCTAssertEqual(row.title, "Example Network")
        XCTAssertEqual(row.subtitle, "5 GHz · -58 dBm")
        XCTAssertEqual(row.measurements, "5 GHz · -58 dBm")
        XCTAssertEqual(row.accessibilityLabel, "Wi-Fi Example Network, 3 bars")
        XCTAssertEqual(row.accessibilityValue, "5 GHz · -58 dBm")
        XCTAssertEqual(row.intent, .wifiDetails)

        let wiredPath = PanelPresentationMapper.network(
            wifi: wifi,
            connection: .ethernet,
            wired: nil,
            isConstrained: false,
            isResolvingName: false,
            localization: localization
        )
        XCTAssertEqual(wiredPath.title, "Ethernet")
        XCTAssertEqual(wiredPath.subtitle, "Connected")
        XCTAssertEqual(wiredPath.intent, .wiredDetails)
        XCTAssertFalse(wiredPath.accessibilityLabel.contains("Example Network"))
    }

    func testWiredSummaryKeepsRestrictedPathAndSettingsAction() {
        let localization = makeLocalization(.english)
        let details = PrimaryLinkDetails(
            interfaceName: "en9",
            interfaceDisplayName: "iPhone USB",
            ipv4Addresses: ["172.20.10.8"],
            ipv6Addresses: [],
            router: nil,
            dnsServers: []
        )

        let row = PanelPresentationMapper.network(
            wifi: .placeholder,
            connection: .ethernet,
            wired: details,
            isConstrained: true,
            isResolvingName: false,
            localization: localization
        )

        XCTAssertEqual(row.title, "iPhone USB")
        XCTAssertEqual(row.subtitle, "en9 · Restricted network")
        XCTAssertEqual(row.intent, .wiredDetails)
        XCTAssertTrue(row.showsSettings)
        XCTAssertEqual(row.symbol, .symbol(name: "cable.connector", variableValue: nil, fallback: nil))
    }

    func testVPNSummaryIsIndependentAndPreservesProxySemantics() {
        let localization = makeLocalization(.english)
        let connected = VPNStatus(
            tunnelInterfaces: ["utun4"],
            serviceName: "Work VPN",
            proxy: VPNProxyStatus(kind: .https, host: "proxy.example", port: 443)
        )

        let row = PanelPresentationMapper.vpn(connected, localization: localization)

        XCTAssertEqual(row.title, "Work VPN")
        XCTAssertEqual(row.subtitle, "Connected · proxy proxy.example:443")
        XCTAssertEqual(row.accessibilityLabel, "VPN")
        XCTAssertEqual(row.accessibilityValue, "Work VPN, Connected · proxy proxy.example:443")
        XCTAssertEqual(row.tint, .positive)
        XCTAssertFalse(row.showsSettings)
        XCTAssertEqual(row.intent, .none)

        let proxyOnly = PanelPresentationMapper.vpn(
            VPNStatus(
                tunnelInterfaces: [],
                serviceName: nil,
                proxy: VPNProxyStatus(kind: .automaticConfiguration, host: nil, port: nil)
            ),
            localization: localization
        )
        XCTAssertEqual(proxyOnly.title, "System proxy")
        XCTAssertEqual(proxyOnly.subtitle, "Automatic configuration")
        XCTAssertEqual(proxyOnly.tint, .caution)
    }

    func testPanelSummaryUsesSelectedLanguageForTheSameBatteryInput() {
        let battery = makeBattery(percentage: 68)
        let english = PanelPresentationMapper.battery(battery, localization: makeLocalization(.english))
        let chinese = PanelPresentationMapper.battery(battery, localization: makeLocalization(.simplifiedChinese))
        let german = PanelPresentationMapper.battery(battery, localization: makeLocalization(.german))

        XCTAssertEqual(english.title, "Battery · 68%")
        XCTAssertEqual(chinese.title, "电池 · 68%")
        XCTAssertEqual(german.title, "Batterie · 68%")
        XCTAssertNotEqual(english.title, chinese.title)
        XCTAssertNotEqual(chinese.title, german.title)
    }

    func testInputIdentityTracksOnlyDefaultDeviceID() {
        var status = AudioInputStatus.empty
        status.devices = [AudioInputDevice(id: AudioDeviceID(11), uid: nil, name: "USB Mic")]
        status.defaultDeviceID = AudioDeviceID(11)
        status.deviceName = "USB Mic"
        status.scalar = 0.55
        status.canSetVolume = true

        let english = AudioPanelMapper.input(status, localization: makeLocalization(.english))

        status.devices = [AudioInputDevice(id: AudioDeviceID(11), uid: "late-uid", name: "Updated Mic Label")]
        status.deviceName = "Updated Mic Label"
        let metadataUpdated = AudioPanelMapper.input(status, localization: makeLocalization(.english))
        let languageUpdated = AudioPanelMapper.input(status, localization: makeLocalization(.simplifiedChinese))

        XCTAssertEqual(english.selectedDeviceIdentity, metadataUpdated.selectedDeviceIdentity)
        XCTAssertEqual(english.selectedDeviceIdentity, languageUpdated.selectedDeviceIdentity)

        status.defaultDeviceID = AudioDeviceID(22)
        status.devices.append(AudioInputDevice(id: AudioDeviceID(22), uid: "second", name: "Second Mic"))
        let selectedDeviceChanged = AudioPanelMapper.input(status, localization: makeLocalization(.english))
        XCTAssertNotEqual(english.selectedDeviceIdentity, selectedDeviceChanged.selectedDeviceIdentity)
    }

    private func makeLocalization(_ language: AppLanguage) -> Localization {
        let suiteName = "PanelPresentationMapperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { TestUserDefaults.removeSuite(named: suiteName) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))
        return localization
    }

    private func makeBattery(
        percentage: Int,
        isCharging: Bool = false,
        isLowPowerMode: Bool = false
    ) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: true,
            isCharging: isCharging,
            isLowPowerMode: isLowPowerMode,
            isConnectedToPower: isCharging
        )
    }
}
