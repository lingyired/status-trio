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
        XCTAssertEqual(row.title, "Power · Unavailable")
        XCTAssertEqual(row.subtitle, "No battery")
        XCTAssertEqual(row.tint, .secondary)
    }

    func testAbsentBatteryShowsWholeMachinePowerWhenReadable() {
        let now = Date(timeIntervalSince1970: 1_789_555_974)
        let battery = BatteryStatus(
            rawPercentage: nil,
            isPresent: false,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
        let sample = SystemPowerSample(watts: 23.6, readAt: now)

        let row = PanelPresentationMapper.battery(
            battery,
            powerSample: sample,
            now: now,
            localization: makeLocalization(.english)
        )

        XCTAssertEqual(row.title, "Power · 24 W")
        XCTAssertEqual(row.subtitle, "No battery")
        XCTAssertEqual(row.intent, .batteryDetails)
        XCTAssertTrue(row.showsSettings)
    }

    func testAbsentBatteryRejectsAStalePowerReading() {
        let now = Date(timeIntervalSince1970: 1_789_555_974)
        let battery = BatteryStatus(
            rawPercentage: nil,
            isPresent: false,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
        let stale = SystemPowerSample(watts: 23.6, readAt: now.addingTimeInterval(-120))

        let row = PanelPresentationMapper.battery(
            battery,
            powerSample: stale,
            now: now,
            localization: makeLocalization(.english)
        )

        XCTAssertEqual(row.title, "Power · Unavailable")
        XCTAssertEqual(row.intent, .none)
        XCTAssertFalse(row.showsSettings, "A disabled entry must explain itself instead of opening an empty page")
    }

    func testPowerInfoBarShowsEachRailIndependentlyOnlyWhenEnabled() {
        let now = Date(timeIntervalSince1970: 1_789_555_974)
        let battery = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: false,
                                    isLowPowerMode: false, isConnectedToPower: true)
        let input = SystemPowerSample(watts: 30.2, readAt: now)
        let system = SystemPowerSample(watts: 18.0, readAt: now)
        let batteryPower = BatteryPowerSample(volts: 12, amps: 1.0, updatedAt: now)

        let on = PanelPresentationMapper.battery(
            battery,
            powerSample: system,
            inputPower: input,
            batteryPower: batteryPower,
            showsPowerInfoBar: true,
            now: now,
            localization: makeLocalization(.english)
        )
        XCTAssertEqual(on.powerInfoBar?.items.map(\.kind), [.input, .battery, .system])
        XCTAssertEqual(on.powerInfoBar?.items.map(\.value), ["30.2 W", "12.0 W", "18.0 W"])

        let off = PanelPresentationMapper.battery(
            battery,
            powerSample: system,
            inputPower: input,
            batteryPower: batteryPower,
            showsPowerInfoBar: false,
            now: now,
            localization: makeLocalization(.english)
        )
        XCTAssertNil(off.powerInfoBar, "The info bar must stay hidden until the setting is on")
    }

    func testPowerInfoBarSaysNotChargingAtZeroBatteryWatts() {
        let now = Date(timeIntervalSince1970: 1_789_555_974)
        let localization = makeLocalization(.english)
        let battery = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: false,
                                    isLowPowerMode: false, isConnectedToPower: true)
        let idleBattery = BatteryPowerSample(volts: 12, amps: 0, updatedAt: now)

        let row = PanelPresentationMapper.battery(
            battery,
            batteryPower: idleBattery,
            showsPowerInfoBar: true,
            now: now,
            localization: localization
        )

        let batteryItem = row.powerInfoBar?.items.first { $0.kind == .battery }
        XCTAssertEqual(batteryItem?.value, localization.string(.powerInfoBarNotCharging))
    }

    func testPowerInfoBarHidesBatteryAndMissingRails() {
        let now = Date(timeIntervalSince1970: 1_789_555_974)
        let noBattery = BatteryStatus(rawPercentage: nil, isPresent: false, isCharging: false,
                                      isLowPowerMode: false, isConnectedToPower: false)
        let input = SystemPowerSample(watts: 30.2, readAt: now)

        let row = PanelPresentationMapper.battery(
            noBattery,
            powerSample: nil,
            inputPower: input,
            batteryPower: BatteryPowerSample(volts: 12, amps: 1.0, updatedAt: now),
            showsPowerInfoBar: true,
            now: now,
            localization: makeLocalization(.english)
        )
        XCTAssertEqual(row.powerInfoBar?.items.map(\.kind), [.input],
                       "A no-battery Mac hides the battery rail; missing system power is absent")
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

    func testChargeToFullNowShowsCalculatingUntilATimeEstimateExists() {
        let localization = makeLocalization(.simplifiedChinese)
        let connectedNotYetCharging = makeBattery(
            percentage: 80,
            isCharging: false,
            isConnectedToPower: true
        )
        XCTAssertEqual(
            PanelPresentationMapper.battery(connectedNotYetCharging, localization: localization).subtitle,
            localization.string(.batteryStateConnectedToPower)
        )

        for action in [ChargeToFullNowPresentation.applying, .chargingToFull] {
            XCTAssertEqual(
                PanelPresentationMapper.battery(
                    connectedNotYetCharging,
                    localization: localization,
                    chargeToFullNow: action
                ).subtitle,
                localization.string(.batteryStateCalculatingTimeToFull)
            )
        }

        XCTAssertEqual(
            PanelPresentationMapper.battery(
                connectedNotYetCharging,
                localization: localization,
                chargeToFullNow: .limitRestored(limit: 95)
            ).subtitle,
            localization.string(.batteryStateConnectedToPower)
        )

        let charging = makeBattery(percentage: 80, isCharging: true, isConnectedToPower: true)
        XCTAssertEqual(
            PanelPresentationMapper.battery(
                charging,
                localization: localization,
                chargeToFullNow: .chargingToFull
            ).subtitle,
            localization.string(.batteryStateCalculatingTimeToFull)
        )

        let withEstimate = BatteryStatus(
            rawPercentage: 80,
            isPresent: true,
            isCharging: true,
            timeToFullChargeMinutes: 25,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
        XCTAssertEqual(
            PanelPresentationMapper.battery(
                withEstimate,
                localization: localization,
                chargeToFullNow: .chargingToFull
            ).subtitle,
            "预计 25 分钟充满"
        )
    }

    func testLowPowerModeStaysYellowWhileConnectedWithoutCharging() {
        let localization = makeLocalization(.english)
        let row = PanelPresentationMapper.battery(
            makeBattery(
                percentage: 80,
                isLowPowerMode: true,
                isConnectedToPower: true
            ),
            localization: localization
        )

        XCTAssertEqual(row.tint, .caution)
    }

    func testChargingKeepsGreenPriorityOverLowPowerMode() {
        let localization = makeLocalization(.english)
        let row = PanelPresentationMapper.battery(
            makeBattery(
                percentage: 80,
                isCharging: true,
                isLowPowerMode: true,
                isConnectedToPower: true
            ),
            localization: localization
        )

        XCTAssertEqual(row.tint, .positive)
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
        XCTAssertEqual(needsPermission.subtitle, "Connected · -58 dBm")
        XCTAssertEqual(needsPermission.intent, .wifiDetails)

        let denied = PanelPresentationMapper.network(
            wifi: WiFiStatus(state: .connected, rssi: -58, nameAccess: .denied),
            connection: .wifi,
            wired: nil,
            isConstrained: false,
            isResolvingName: false,
            localization: localization
        )
        XCTAssertEqual(denied.intent, .wifiDetails)
    }

    func testUnauthorizedNameDoesNotHideTheConnectionState() {
        let localization = makeLocalization(.english)
        for access in [WiFiNameAccess.denied, .restricted, .notDetermined] {
            let row = PanelPresentationMapper.network(
                wifi: WiFiStatus(
                    state: .connected,
                    rssi: -50,
                    nameAccess: access,
                    band: .fiveGHz
                ),
                connection: .wifi,
                wired: nil,
                isConstrained: false,
                isResolvingName: false,
                localIPAddress: "192.168.1.20",
                localization: localization
            )
            XCTAssertEqual(row.title, "Wi-Fi")
            XCTAssertEqual(row.subtitle, "192.168.1.20 · Connected · 5 GHz · -50 dBm")
            XCTAssertEqual(row.measurements, "192.168.1.20 · 5 GHz · -50 dBm")
            XCTAssertEqual(row.accessibilityValue, "192.168.1.20 · 5 GHz · -50 dBm")
            XCTAssertEqual(row.intent, .wifiDetails)
        }

        let notAssociated = PanelPresentationMapper.network(
            wifi: WiFiStatus(state: .notAssociated, rssi: nil, nameAccess: .denied),
            connection: .wifi,
            wired: nil,
            isConstrained: false,
            isResolvingName: false,
            localization: localization
        )
        XCTAssertEqual(notAssociated.subtitle, localization.string(.wifiSubtitleNotAssociated))
        XCTAssertEqual(notAssociated.intent, .wifiDetails)
    }

    /// The address rides at the front of the second line, and the Wi-Fi band and
    /// signal keep the slot they already had, so the row reads as the address
    /// first and then the network's own details.
    func testLocalIPLeadsTheWiFiSecondLine() {
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
            localIPAddress: "192.168.1.20",
            localization: localization
        )

        XCTAssertEqual(row.subtitle, "192.168.1.20 · 5 GHz · -58 dBm")
        XCTAssertEqual(row.measurements, "192.168.1.20 · 5 GHz · -58 dBm")
        XCTAssertEqual(row.accessibilityValue, "192.168.1.20 · 5 GHz · -58 dBm")
    }

    func testWiFiNamePermissionLeadsTheLocalIPAddress() {
        let localization = makeLocalization(.english)
        let row = PanelPresentationMapper.network(
            wifi: WiFiStatus(
                state: .connected,
                rssi: -58,
                nameAccess: .notDetermined,
                band: .fiveGHz
            ),
            connection: .wifi,
            wired: nil,
            isConstrained: false,
            isResolvingName: false,
            localIPAddress: "192.168.1.20",
            localization: localization
        )

        XCTAssertEqual(row.subtitle, "192.168.1.20 · Connected · 5 GHz · -58 dBm")
        XCTAssertEqual(row.intent, .wifiDetails)
    }

    func testWiFiLocationSettingsActionLeadsTheLocalIPAddress() {
        let localization = makeLocalization(.english)
        let row = PanelPresentationMapper.network(
            wifi: WiFiStatus(
                state: .connected,
                rssi: -58,
                nameAccess: .denied,
                band: .fiveGHz
            ),
            connection: .wifi,
            wired: nil,
            isConstrained: false,
            isResolvingName: false,
            localIPAddress: "192.168.1.20",
            localization: localization
        )

        XCTAssertEqual(
            row.subtitle,
            "192.168.1.20 · Connected · 5 GHz · -58 dBm"
        )
        XCTAssertEqual(row.intent, .wifiDetails)
    }

    func testLocalIPIsAbsentWhenTheRowIsNotGivenOne() {
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

        XCTAssertEqual(row.subtitle, "5 GHz · -58 dBm")
        XCTAssertEqual(row.measurements, "5 GHz · -58 dBm")
    }

    func testLocalIPLeadsTheWiredSecondLine() {
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
            isConstrained: false,
            isResolvingName: false,
            localIPAddress: "192.168.1.20",
            localization: localization
        )

        XCTAssertEqual(row.title, "iPhone USB")
        XCTAssertEqual(row.subtitle, "192.168.1.20 · en9")
        XCTAssertEqual(row.accessibilityValue, "192.168.1.20 · en9")
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
        isLowPowerMode: Bool = false,
        isConnectedToPower: Bool? = nil
    ) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: true,
            isCharging: isCharging,
            isLowPowerMode: isLowPowerMode,
            isConnectedToPower: isConnectedToPower ?? isCharging
        )
    }
}
