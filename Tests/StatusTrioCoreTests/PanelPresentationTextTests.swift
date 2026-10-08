import XCTest
@testable import StatusTrioCore

@MainActor
final class PresentationTextMapperTests: XCTestCase {
    func testBatteryTitleAndSubtitlePriority() {
        let localization = makeLocalization(.simplifiedChinese)

        XCTAssertEqual(
            PanelPresentationMapper.batteryTitle(
                makeBattery(percentage: 68),
                localization: localization
            ),
            "电池 · 68%"
        )
        XCTAssertEqual(
            PanelPresentationMapper.batterySubtitle(
                makeBattery(
                    isPresent: false,
                    isCharging: true,
                    isCharged: true,
                    isLowPowerMode: true,
                    isConnectedToPower: true
                ),
                localization: localization
            ),
            "无电池设备"
        )
        XCTAssertEqual(
            PanelPresentationMapper.batterySubtitle(
                makeBattery(
                    isCharging: true,
                    isCharged: true,
                    isLowPowerMode: true,
                    isConnectedToPower: true
                ),
                localization: localization
            ),
            "已充满"
        )
        XCTAssertEqual(
            PanelPresentationMapper.batterySubtitle(
                makeBattery(
                    isCharging: true,
                    isLowPowerMode: true,
                    isConnectedToPower: true,
                    timeToFullChargeMinutes: 85
                ),
                localization: localization
            ),
            "预计 1 小时 25 分钟充满"
        )
        XCTAssertEqual(
            PanelPresentationMapper.batterySubtitle(
                makeBattery(isCharging: true, isConnectedToPower: true),
                localization: localization
            ),
            "正在计算充满时间"
        )
        XCTAssertEqual(
            PanelPresentationMapper.batterySubtitle(
                makeBattery(isLowPowerMode: true, isConnectedToPower: true),
                localization: localization
            ),
            "低电量模式"
        )
        XCTAssertEqual(
            PanelPresentationMapper.batterySubtitle(
                makeBattery(isConnectedToPower: true),
                localization: localization
            ),
            "已连接电源"
        )
        XCTAssertEqual(
            PanelPresentationMapper.batterySubtitle(
                makeBattery(),
                localization: localization
            ),
            "电池供电"
        )
    }

    func testBatteryTimeToFullFormatting() {
        let localization = makeLocalization(.simplifiedChinese)
        let cases: [(Int?, String)] = [
            (1, "预计 1 分钟充满"),
            (59, "预计 59 分钟充满"),
            (60, "预计 1 小时充满"),
            (85, "预计 1 小时 25 分钟充满"),
            (120, "预计 2 小时充满"),
            (nil, "正在计算充满时间"),
            (0, "正在计算充满时间"),
            (-1, "正在计算充满时间")
        ]

        for (minutes, expected) in cases {
            XCTAssertEqual(
                PanelPresentationMapper.batteryTimeToFullText(
                    minutes: minutes,
                    localization: localization
                ),
                expected,
                "minutes: \(String(describing: minutes))"
            )
        }
    }

    func testWiFiValueAndSubtitleForEveryState() {
        let localization = makeLocalization(.simplifiedChinese)
        let cases: [(WiFiStatus, String, String)] = [
            (WiFiStatus(state: .connected, rssi: -55), "3 格", "已连接"),
            (WiFiStatus(state: .notAssociated, rssi: nil), "未关联", "Wi-Fi 开启，未关联"),
            (WiFiStatus(state: .off, rssi: nil), "关闭", "Wi-Fi 关闭或不可用"),
            (WiFiStatus(state: .noInternet, rssi: nil), "无互联网", "网络可达性检查失败"),
            (WiFiStatus(state: .hotspot, rssi: nil), "iPhone 热点", "使用 iPhone 热点"),
            (WiFiStatus(state: .temporary, rssi: nil), "临时连接", "临时 Wi-Fi 连接"),
            (WiFiStatus(state: .shared, rssi: nil), "正在共享", "正在共享互联网"),
            (WiFiStatus(state: .unavailable, rssi: nil), "不可用", "无法读取网络状态")
        ]

        for (wifi, expectedValue, expectedSubtitle) in cases {
            XCTAssertEqual(
                PanelPresentationMapper.wifiValue(wifi, localization: localization),
                expectedValue,
                "value for \(wifi.state)"
            )
            XCTAssertEqual(
                PanelPresentationMapper.wifiSubtitle(wifi, localization: localization),
                expectedSubtitle,
                "subtitle for \(wifi.state)"
            )
        }
    }

    func testActionKeysUseSelectedLanguage() {
        let localization = makeLocalization(.simplifiedChinese)

        XCTAssertEqual(localization.string(.menuSettings), "设置…")
        XCTAssertEqual(localization.string(.wifiActionRequestNameAccess), "允许定位以显示 Wi-Fi 名称")
        XCTAssertEqual(localization.string(.wifiActionOpenLocationSettings), "去设置中允许定位")
        XCTAssertEqual(localization.string(.wifiActionOpenSettings), "打开 Wi-Fi 设置")
        XCTAssertEqual(localization.string(.batteryActionOpenSettings), "打开电源设置")
        XCTAssertEqual(localization.string(.volumeActionOpenSettings), "打开声音设置")
    }

    func testWiFiSubtitlePrefersSSID() {
        let localization = makeLocalization(.simplifiedChinese)

        XCTAssertEqual(
            PanelPresentationMapper.wifiSubtitle(
                WiFiStatus(
                    state: .connected,
                    rssi: -55,
                    ssid: "Studio Wi-Fi",
                    nameAccess: .authorized
                ),
                localization: localization
            ),
            "Studio Wi-Fi"
        )
    }

    func testStatusItemAccessibilitySummaryIncludesAllThreeStatuses() {
        let localization = makeLocalization(.simplifiedChinese)
        let snapshot = StatusSnapshot(
            battery: makeBattery(
                isCharging: true,
                isConnectedToPower: true,
                percentage: 73,
                timeToFullChargeMinutes: 85
            ),
            wifi: WiFiStatus(state: .connected, rssi: -55),
            volume: VolumeStatus(
                scalar: 0.5,
                isMuted: false,
                deviceName: "MacBook Pro Speakers"
            )
        )

        XCTAssertEqual(
            AccessibilityPresentation.statusItemValue(
                snapshot,
                localization: localization
            ),
            "电池 73%（预计 1 小时 25 分钟充满），Wi-Fi 3 格，音量 50% · 2 格"
        )
    }

    func testStatusItemAccessibilitySummaryIncludesWiFiNameWhenAvailable() {
        let localization = makeLocalization(.simplifiedChinese)
        let snapshot = StatusSnapshot(
            battery: makeBattery(percentage: 73),
            wifi: WiFiStatus(
                state: .connected,
                rssi: -55,
                ssid: "Office",
                nameAccess: .authorized
            ),
            volume: VolumeStatus(
                scalar: 0.5,
                isMuted: false,
                deviceName: "MacBook Pro Speakers"
            )
        )

        XCTAssertEqual(
            AccessibilityPresentation.statusItemValue(
                snapshot,
                localization: localization
            ),
            "电池 73%，Wi-Fi Office，3 格，音量 50% · 2 格"
        )
    }

    func testStatusItemAccessibilitySummaryUsesEthernetWhenWired() {
        let localization = makeLocalization(.simplifiedChinese)
        let snapshot = StatusSnapshot(
            battery: makeBattery(percentage: 73),
            wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .ethernet,
            volume: VolumeStatus(
                scalar: 0.5,
                isMuted: false,
                deviceName: "MacBook Pro Speakers"
            )
        )

        XCTAssertEqual(
            AccessibilityPresentation.statusItemValue(
                snapshot,
                localization: localization
            ),
            "电池 73%，以太网已连接，音量 50% · 2 格"
        )
    }

    func testEnglishPanelAndAccessibilityText() {
        let localization = makeLocalization(.english)

        XCTAssertEqual(
            PanelPresentationMapper.batteryTitle(
                makeBattery(percentage: 68),
                localization: localization
            ),
            "Battery · 68%"
        )
        XCTAssertEqual(
            AccessibilityPresentation.volumeValue(
                VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Speaker"),
                localization: localization
            ),
            "50% · 2 bars"
        )
    }

    func testVolumeValueForNilMutedAndNormalStates() {
        let localization = makeLocalization(.simplifiedChinese)

        XCTAssertEqual(
            AccessibilityPresentation.volumeValue(
                VolumeStatus(scalar: nil, isMuted: false, deviceName: nil),
                localization: localization
            ),
            "—"
        )
        XCTAssertEqual(
            AccessibilityPresentation.volumeValue(
                VolumeStatus(scalar: 0.62, isMuted: true, deviceName: "Speaker"),
                localization: localization
            ),
            "静音"
        )
        XCTAssertEqual(
            AccessibilityPresentation.volumeValue(
                VolumeStatus(scalar: 0.62, isMuted: false, deviceName: "Speaker"),
                localization: localization
            ),
            "62% · 3 格"
        )
        XCTAssertEqual(
            AccessibilityPresentation.volumeValue(
                VolumeStatus(scalar: 0.625, isMuted: false, deviceName: "Speaker"),
                localization: localization
            ),
            "63% · 3 格"
        )
    }

    func testVolumeValueRejectsNonFiniteScalars() {
        let localization = makeLocalization(.simplifiedChinese)

        for scalar in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(
                AccessibilityPresentation.volumeValue(
                    VolumeStatus(scalar: scalar, isMuted: false, deviceName: "Speaker"),
                    localization: localization
                ),
                "—",
                "value for \(scalar)"
            )
        }
    }

    func testVolumeValueClampsFiniteScalars() {
        let localization = makeLocalization(.simplifiedChinese)

        XCTAssertEqual(
            AccessibilityPresentation.volumeValue(
                VolumeStatus(scalar: -0.5, isMuted: false, deviceName: "Speaker"),
                localization: localization
            ),
            "0% · 0 格"
        )
        XCTAssertEqual(
            AccessibilityPresentation.volumeValue(
                VolumeStatus(scalar: 1.5, isMuted: false, deviceName: "Speaker"),
                localization: localization
            ),
            "100% · 4 格"
        )
    }

    func testVolumeValueStepMapping() {
        let localization = makeLocalization(.simplifiedChinese)
        let cases: [(Double, Int)] = [
            (0.00, 0),
            (0.01, 1),
            (0.25, 1),
            (0.26, 2),
            (0.50, 2),
            (0.51, 3),
            (0.75, 3),
            (0.76, 4),
            (1.00, 4)
        ]

        for (scalar, steps) in cases {
            XCTAssertEqual(
                AccessibilityPresentation.volumeValue(
                    VolumeStatus(scalar: scalar, isMuted: false, deviceName: "Speaker"),
                    localization: localization
                ),
                "\(Int((scalar * 100).rounded()))% · \(steps) 格"
            )
        }
    }

    func testVolumeSummaryUsesDeviceNameFallbackAndPercentSubtitle() {
        let localization = makeLocalization(.simplifiedChinese)
        let named = AudioPanelMapper.volume(
            VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "MacBook Speakers"),
            controllerAvailable: true,
            localization: localization
        )
        let unnamed = AudioPanelMapper.volume(
            VolumeStatus(scalar: 0.5, isMuted: false, deviceName: nil),
            controllerAvailable: true,
            localization: localization
        )

        XCTAssertEqual(named.summary.title, "MacBook Speakers")
        XCTAssertEqual(named.summary.subtitle, "音量 · 50%")
        XCTAssertEqual(unnamed.summary.title, "无默认输出设备")
        XCTAssertEqual(unnamed.summary.subtitle, "音量 · 50%")
    }

    /// The VPN row leads with the service name when the system has one, falls
    /// back to the generic label for a bare tunnel, and names the kind when a
    /// proxy is all that is up.
    func testVPNRowLeadsWithTheServiceName() {
        let localization = makeLocalization(.simplifiedChinese)

        let named = VPNStatus(
            tunnelInterfaces: ["utun4"],
            serviceName: "工作 VPN",
            proxy: nil
        )
        XCTAssertEqual(
            PanelPresentationMapper.vpnTitle(named, localization: localization),
            "工作 VPN"
        )
        XCTAssertEqual(
            PanelPresentationMapper.vpnSubtitle(named, localization: localization),
            "已连接"
        )

        let bareTunnel = VPNStatus(
            tunnelInterfaces: ["utun4"],
            serviceName: nil,
            proxy: nil
        )
        XCTAssertEqual(
            PanelPresentationMapper.vpnTitle(bareTunnel, localization: localization),
            "VPN"
        )
        XCTAssertEqual(
            PanelPresentationMapper.vpnSubtitle(bareTunnel, localization: localization),
            "已连接"
        )
    }

    func testVPNRowReportsAProxyWithoutATunnel() {
        let localization = makeLocalization(.simplifiedChinese)

        let proxyOnly = VPNStatus(
            tunnelInterfaces: [],
            serviceName: nil,
            proxy: VPNProxyStatus(kind: .http, host: "127.0.0.1", port: 10808)
        )
        XCTAssertEqual(
            PanelPresentationMapper.vpnTitle(proxyOnly, localization: localization),
            "系统代理"
        )
        XCTAssertEqual(
            PanelPresentationMapper.vpnSubtitle(proxyOnly, localization: localization),
            "127.0.0.1:10808"
        )
    }

    func testVPNRowAppendsTheProxyToAConnectedTunnel() {
        let localization = makeLocalization(.simplifiedChinese)

        let both = VPNStatus(
            tunnelInterfaces: ["utun4"],
            serviceName: nil,
            proxy: VPNProxyStatus(kind: .socks, host: "127.0.0.1", port: 7891)
        )

        XCTAssertEqual(
            PanelPresentationMapper.vpnSubtitle(both, localization: localization),
            "已连接 · 代理 127.0.0.1:7891"
        )
    }

    func testVPNRowWithoutAnythingUpReadsAsDisconnected() {
        let localization = makeLocalization(.simplifiedChinese)
        let off = VPNStatus(tunnelInterfaces: [], serviceName: nil, proxy: nil)

        XCTAssertEqual(
            PanelPresentationMapper.vpnTitle(off, localization: localization),
            "VPN"
        )
        XCTAssertEqual(
            PanelPresentationMapper.vpnSubtitle(off, localization: localization),
            "未连接"
        )
    }

    /// A PAC script has no endpoint to print, so the row names its kind.
    func testVPNRowNamesAnAutomaticConfiguration() {
        let localization = makeLocalization(.simplifiedChinese)

        let pac = VPNStatus(
            tunnelInterfaces: [],
            serviceName: nil,
            proxy: VPNProxyStatus(
                kind: .automaticConfiguration,
                host: "http://example.invalid/proxy.pac",
                port: nil
            )
        )

        XCTAssertEqual(
            PanelPresentationMapper.vpnTitle(pac, localization: localization),
            "系统代理"
        )
        XCTAssertEqual(
            PanelPresentationMapper.vpnSubtitle(pac, localization: localization),
            "自动配置"
        )
    }

    private func makeLocalization(_ language: AppLanguage) -> Localization {
        let suiteName = "StatusTrioCoreTests.PresentationTextMapper.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removeTestSuite(named: suiteName)
        addTeardownBlock { TestUserDefaults.removeSuite(named: suiteName) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))
        return localization
    }

    private func makeBattery(
        isPresent: Bool = true,
        isCharging: Bool = false,
        isCharged: Bool = false,
        isLowPowerMode: Bool = false,
        isConnectedToPower: Bool = false,
        percentage: Int = 100,
        timeToFullChargeMinutes: Int? = nil
    ) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: isPresent,
            isCharging: isCharging,
            isCharged: isCharged,
            timeToFullChargeMinutes: timeToFullChargeMinutes,
            isLowPowerMode: isLowPowerMode,
            isConnectedToPower: isConnectedToPower
        )
    }
}
