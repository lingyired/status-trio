import XCTest
@testable import StatusTrioCore

final class IconLegacyCompatibilityTests: XCTestCase {
    func testLegacyPercentagePreemptsBluetoothAndNetworkError() {
        let snapshot = makeSnapshot(
            battery: BatteryStatus(rawPercentage: 45, isPresent: true, isCharging: false,
                                   isLowPowerMode: false, isConnectedToPower: false),
            wifi: WiFiStatus(state: .noInternet, rssi: -45),
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output",
                                 currentDevice: PresentationFixtures.bluetoothDevice)
        )
        let configuration = IconPresentationConfiguration(
            battery: .standard,
            connection: ConnectionIconOptions(showsBatteryPercentageInConnectionSlot: true),
            volume: .standard,
            bluetooth: BluetoothAudioIconOptions(replacesNetworkIcon: true, prioritizesNetworkErrors: true)
        )
        let scene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: snapshot,
                audioIcon: .symbol(name: "airpods.pro", variableValue: nil, fallback: "headphones")
            ),
            configuration: configuration
        )

        XCTAssertEqual(scene.center, .text(IconTextState(text: "45", color: .primary, scale: 1)))
        XCTAssertEqual(scene.outerRing?.segments, [RingSegmentState(progress: 0.45, color: .primary)])
    }

    func testPinnedGlyphSurvivesDisconnectedAudio() {
        let snapshot = makeSnapshot(
            wifi: WiFiStatus(state: .connected, rssi: -55),
            volume: VolumeStatus(scalar: 0.4, isMuted: false, deviceName: nil, currentDevice: nil)
        )
        let options = BluetoothAudioIconOptions(
            replacesNetworkIcon: true,
            networkIconSymbolOverride: "airpods.pro"
        )
        let scene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: IconPresentationConfiguration(
                battery: .standard, connection: .standard, volume: .standard, bluetooth: options
            )
        )

        XCTAssertEqual(scene.center, .symbol(IconSymbolState(
            source: .symbol(name: "airpods.pro", variableValue: nil, fallback: "dot.radiowaves.left.and.right"),
            color: .bluetooth,
            scale: BluetoothAudioIconOptions.defaultSymbolScale
        )))
    }

    func testEthernetAndWiFiOffMapping() {
        let ethernet = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: makeSnapshot(connection: .ethernet, wifi: WiFiStatus(state: .off, rssi: nil)),
                audioIcon: nil
            ),
            configuration: .standard
        )
        let wifiOff = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: makeSnapshot(connection: .wifi, wifi: WiFiStatus(state: .off, rssi: nil)),
                audioIcon: nil
            ),
            configuration: .standard
        )

        XCTAssertEqual(ethernet.center, .symbol(IconSymbolState(
            source: .primitive(.wiredPort), color: .primary, scale: 1
        )))
        XCTAssertEqual(wifiOff.center, .symbol(IconSymbolState(
            source: .symbol(name: "wifi.slash", variableValue: 1, fallback: nil), color: .primary, scale: 1
        )))
    }

    func testSharedStrokeAffectsRingAndFooter() {
        let battery = BatteryIconOptions(ringStrokeScale: 1.5)
        let volume = VolumeIconOptions(displayStyle: .arc, ringStrokeScale: 1.5)
        let scene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: makeSnapshot(), audioIcon: nil),
            configuration: IconPresentationConfiguration(
                battery: battery, connection: .standard, volume: volume, bluetooth: .standard
            )
        )

        XCTAssertEqual(scene.outerRing?.strokeScale, 1.5)
        XCTAssertEqual(scene.footer, .arc(ArcState(progress: 0.51, color: .primary, strokeScale: 1.5)))
    }

    func testClassicBatteryAndVolumeSceneAnchors() {
        let cases: [(BatteryStatus, RingGapStyle, RingAccessoryState?, IconColorRole)] = [
            (BatteryStatus(rawPercentage: 68, isPresent: true, isCharging: true, isLowPowerMode: false,
                           isConnectedToPower: true), .indicator,
             .symbol(IconSymbolState(source: .primitive(.bolt), color: .primary, scale: 1.8)), .powered),
            (BatteryStatus(rawPercentage: 100, isPresent: true, isCharging: false, isCharged: true,
                           isLowPowerMode: false, isConnectedToPower: true), .indicator,
             .symbol(IconSymbolState(source: .primitive(.plug), color: .primary, scale: 1.8)), .powered),
            (BatteryStatus(rawPercentage: 19, isPresent: true, isCharging: false, isLowPowerMode: false,
                           isConnectedToPower: false), .value,
             .text(IconTextState(text: "19", color: .primary, scale: 1.8)), .critical),
            (BatteryStatus(rawPercentage: 68, isPresent: false, isCharging: false, isLowPowerMode: false,
                           isConnectedToPower: false), .value,
             .text(IconTextState(text: "100", color: .primary, scale: 1.8)), .primary)
        ]

        for (battery, gap, accessory, color) in cases {
            let scene = IconPresentationMapper.scene(
                inputs: IconPresentationInputs(
                    snapshot: makeSnapshot(battery: battery, volume: VolumeStatus(
                        scalar: 0.51, isMuted: false, deviceName: "Output"
                    )),
                    audioIcon: nil
                ),
                configuration: .standard
            )
            XCTAssertEqual(scene.outerRing?.segments, [RingSegmentState(
                progress: Double(battery.percentage) / 100, color: color
            )])
            XCTAssertEqual(scene.outerRing?.gap, gap)
            XCTAssertEqual(scene.outerRing?.accessory, accessory)
            XCTAssertEqual(scene.footer, .dots(DotsState(
                count: 4, activeCount: 3, color: .primary,
                strokeScale: VolumeIconOptions.standard.ringStrokeScale
            )))
        }

        let lowPowerBattery = BatteryStatus(rawPercentage: 40, isPresent: true, isCharging: false,
                                            isLowPowerMode: true, isConnectedToPower: false)
        let lowPowerScene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: makeSnapshot(battery: lowPowerBattery), audioIcon: nil),
            configuration: .standard
        )
        XCTAssertEqual(lowPowerScene.outerRing?.segments.first?.color, .lowPower)

        let arcScene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: makeSnapshot(), audioIcon: nil),
            configuration: IconPresentationConfiguration(
                battery: .standard, connection: .standard,
                volume: VolumeIconOptions(displayStyle: .arc), bluetooth: .standard
            )
        )
        XCTAssertEqual(arcScene.footer, .arc(ArcState(
            progress: 0.51, color: .primary, strokeScale: VolumeIconOptions.standard.ringStrokeScale
        )))
    }

    func testClassicHotspotTemporaryAndSharedNetworkSymbols() {
        let expected: [(WiFiState, CenterState)] = [
            (.hotspot, .symbol(IconSymbolState(
                source: .symbol(name: "personalhotspot", variableValue: 1, fallback: nil),
                color: .primary, scale: 1
            ))),
            (.temporary, .symbol(IconSymbolState(
                source: .primitive(.screenWedge), color: .primary, scale: 1
            ))),
            (.shared, .symbol(IconSymbolState(
                source: .primitive(.arrowWedge), color: .primary, scale: 1
            )))
        ]
        for (wifiState, center) in expected {
            let scene = IconPresentationMapper.scene(
                inputs: IconPresentationInputs(
                    snapshot: makeSnapshot(wifi: WiFiStatus(state: wifiState, rssi: -55)), audioIcon: nil
                ),
                configuration: .standard
            )
            XCTAssertEqual(scene.center, center, "wifiState=\(wifiState)")
        }
    }

    private func makeSnapshot(
        battery: BatteryStatus = BatteryStatus(rawPercentage: 68, isPresent: true, isCharging: false,
                                               isLowPowerMode: false, isConnectedToPower: false),
        connection: NetworkConnection = .wifi,
        wifi: WiFiStatus = WiFiStatus(state: .connected, rssi: -55),
        volume: VolumeStatus = VolumeStatus(scalar: 0.51, isMuted: false, deviceName: "Output")
    ) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: wifi, connection: connection, volume: volume)
    }
}
