import XCTest
@testable import StatusTrioCore

final class IconPresentationMapperTests: XCTestCase {
    func testDotAndSignalNoiseProduceOneScene() {
        let a = IconPresentationInputs(snapshot: PresentationFixtures.snapshot(rssi: -61, scalar: 0.51), audioIcon: nil)
        let b = IconPresentationInputs(snapshot: PresentationFixtures.snapshot(rssi: -62, scalar: 0.74), audioIcon: nil)

        XCTAssertEqual(IconPresentationMapper.scene(inputs: a, configuration: .standard),
                       IconPresentationMapper.scene(inputs: b, configuration: .standard))
    }

    func testMutedArcIgnoresHiddenScalar() {
        let configuration = IconPresentationConfiguration(battery: .standard,
            connection: .standard, volume: VolumeIconOptions(displayStyle: .arc), bluetooth: .standard)
        let a = IconPresentationInputs(snapshot: PresentationFixtures.snapshot(scalar: 0.2, muted: true), audioIcon: nil)
        let b = IconPresentationInputs(snapshot: PresentationFixtures.snapshot(scalar: 0.9, muted: true), audioIcon: nil)

        XCTAssertEqual(IconPresentationMapper.scene(inputs: a, configuration: configuration),
                       IconPresentationMapper.scene(inputs: b, configuration: configuration))
    }

    func testUnmutedArcPreservesContinuousScalarChanges() {
        let configuration = IconPresentationConfiguration(battery: .standard,
            connection: .standard, volume: VolumeIconOptions(displayStyle: .arc), bluetooth: .standard)
        let a = IconPresentationInputs(snapshot: PresentationFixtures.snapshot(scalar: 0.51, muted: false), audioIcon: nil)
        let b = IconPresentationInputs(snapshot: PresentationFixtures.snapshot(scalar: 0.74, muted: false), audioIcon: nil)
        let sceneA = IconPresentationMapper.scene(inputs: a, configuration: configuration)
        let sceneB = IconPresentationMapper.scene(inputs: b, configuration: configuration)

        XCTAssertEqual(sceneA.footer, .arc(ArcState(progress: 0.51, color: .primary,
                                                    strokeScale: VolumeIconOptions.standard.ringStrokeScale)))
        XCTAssertEqual(sceneB.footer, .arc(ArcState(progress: 0.74, color: .primary,
                                                    strokeScale: VolumeIconOptions.standard.ringStrokeScale)))
        XCTAssertNotEqual(sceneA, sceneB)
    }

    func testBatteryRingMapsProgressColorGapAndChargingEffect() {
        let battery = BatteryStatus(rawPercentage: 19, isPresent: true, isCharging: true,
                                    isLowPowerMode: true, isConnectedToPower: true)
        let snapshot = StatusSnapshot(battery: battery, wifi: .placeholder, volume: .placeholder)
        let configuration = IconPresentationConfiguration(
            battery: BatteryIconOptions(showsChargingEffect: true, showsChargingBoltHeartbeat: true),
            connection: .standard, volume: .standard, bluetooth: .standard)

        let scene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil), configuration: configuration)

        XCTAssertEqual(scene.outerRing?.segments, [RingSegmentState(progress: 0.19, color: .critical)])
        XCTAssertEqual(scene.outerRing?.gap, .indicator)
        XCTAssertEqual(scene.outerRing?.accessory, .symbol(IconSymbolState(
            source: .primitive(.bolt), color: .primary, scale: 1.8)))
        XCTAssertEqual(scene.outerRing?.effect, RingEffectState(pulsesAccessory: true, tintsAccessory: true))
    }

    func testBatteryGapHonorsPresencePercentageAndPowerOptions() {
        let options = BatteryIconOptions(showsPercentage: true, showsChargingIndicator: true,
                                         connectedIndicator: .percentage)
        let connectedFull = BatteryStatus(rawPercentage: 100, isPresent: true, isCharging: false,
                                          isCharged: true, isLowPowerMode: false, isConnectedToPower: true)
        let absent = BatteryStatus(rawPercentage: 42, isPresent: false, isCharging: false,
                                   isLowPowerMode: false, isConnectedToPower: false)

        let fullScene = scene(snapshot: snapshot(battery: connectedFull), batteryOptions: options)
        let absentScene = scene(snapshot: snapshot(battery: absent), batteryOptions: options)

        XCTAssertEqual(fullScene.outerRing?.gap, RingGapStyle.value)
        XCTAssertEqual(fullScene.outerRing?.accessory, RingAccessoryState.text(IconTextState(text: "100", color: .primary, scale: 1.8)))
        XCTAssertEqual(absentScene.outerRing?.gap, RingGapStyle.value)
        XCTAssertEqual(absentScene.outerRing?.accessory, RingAccessoryState.text(IconTextState(text: "100", color: .primary, scale: 1.8)))
        XCTAssertNil(absentScene.outerRing?.effect)
    }

    func testBatteryUsesPlugWhenConnectedPercentageIsDisabledAndCanHidePercentage() {
        let plugged = BatteryStatus(rawPercentage: 100, isPresent: true, isCharging: false,
                                    isCharged: true, isLowPowerMode: false, isConnectedToPower: true)
        let plugOptions = BatteryIconOptions(showsPercentage: true, showsChargingIndicator: true,
                                             connectedIndicator: .plug)
        let plug = scene(snapshot: snapshot(battery: plugged), batteryOptions: plugOptions).outerRing
        XCTAssertEqual(plug?.gap, .indicator)
        XCTAssertEqual(plug?.accessory, .symbol(IconSymbolState(
            source: .primitive(.plug), color: .primary, scale: 1.8)))

        let hidden = BatteryIconOptions(showsPercentage: false, showsChargingIndicator: false)
        let noPercentage = scene(snapshot: snapshot(battery: plugged), batteryOptions: hidden).outerRing
        XCTAssertEqual(noPercentage?.gap, .closed)
        XCTAssertNil(noPercentage?.accessory)
    }

    func testBatteryEffectRequiresPresentActiveUnchargedBatteryAndEnabledOption() {
        let active = BatteryStatus(rawPercentage: 50, isPresent: true, isCharging: true,
                                   isLowPowerMode: false, isConnectedToPower: true)
        let cases: [(BatteryStatus, BatteryIconOptions, Bool)] = [
            (active, BatteryIconOptions(showsChargingEffect: true), true),
            (active, BatteryIconOptions(showsChargingEffect: false), false),
            (BatteryStatus(rawPercentage: 50, isPresent: true, isCharging: true, isCharged: true,
                           isLowPowerMode: false, isConnectedToPower: true), .standard, false),
            (BatteryStatus(rawPercentage: 50, isPresent: false, isCharging: true,
                           isLowPowerMode: false, isConnectedToPower: true), .standard, false),
            (BatteryStatus(rawPercentage: 50, isPresent: true, isCharging: false,
                           isLowPowerMode: false, isConnectedToPower: true), .standard, false)
        ]

        for (battery, options, shouldShow) in cases {
            XCTAssertEqual(scene(snapshot: snapshot(battery: battery), batteryOptions: options).outerRing?.effect != nil,
                           shouldShow, "battery=\(battery), effect=\(options.showsChargingEffect)")
        }

        let pulsingOnly = scene(snapshot: snapshot(battery: active), batteryOptions: BatteryIconOptions(
            showsChargingEffect: true, showsChargingBoltHeartbeat: true, usesStatusColors: false)).outerRing?.effect
        XCTAssertEqual(pulsingOnly, RingEffectState(pulsesAccessory: true, tintsAccessory: false))

        let tintedOnly = scene(snapshot: snapshot(battery: active), batteryOptions: BatteryIconOptions(
            showsChargingEffect: true, showsChargingBoltHeartbeat: false, usesStatusColors: true)).outerRing?.effect
        XCTAssertEqual(tintedOnly, RingEffectState(pulsesAccessory: false, tintsAccessory: false))

        let noHeartbeatNoStatusColors = scene(snapshot: snapshot(battery: active), batteryOptions: BatteryIconOptions(
            showsChargingEffect: true, showsChargingBoltHeartbeat: false, usesStatusColors: false)).outerRing?.effect
        XCTAssertEqual(tintedOnly, noHeartbeatNoStatusColors)
    }

    func testAChargingEffectCanBeRemovedForOneSurfaceWithoutChangingTheRestOfTheScene() {
        let battery = BatteryStatus(
            rawPercentage: 62,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
        let fullScene = scene(
            snapshot: snapshot(battery: battery),
            batteryOptions: BatteryIconOptions(showsChargingEffect: true)
        )

        let staticScene = fullScene.withChargingEffectEnabled(false)

        XCTAssertNotNil(fullScene.outerRing?.effect)
        XCTAssertNil(staticScene.outerRing?.effect)
        XCTAssertEqual(staticScene.outerRing?.segments, fullScene.outerRing?.segments)
        XCTAssertEqual(staticScene.outerRing?.gap, fullScene.outerRing?.gap)
        XCTAssertEqual(staticScene.outerRing?.accessory, fullScene.outerRing?.accessory)
        XCTAssertEqual(staticScene.center, fullScene.center)
        XCTAssertEqual(staticScene.footer, fullScene.footer)
    }

    func testChargingEffectDoesNotTargetPercentageOrMissingAccessory() {
        let active = BatteryStatus(rawPercentage: 68, isPresent: true, isCharging: true,
                                   isLowPowerMode: false, isConnectedToPower: true)
        let percentageOptions = BatteryIconOptions(showsPercentage: true,
            showsChargingIndicator: false, showsChargingEffect: true,
            showsChargingBoltHeartbeat: true, usesStatusColors: true)
        let percentageRing = scene(snapshot: snapshot(battery: active), batteryOptions: percentageOptions).outerRing
        XCTAssertEqual(percentageRing?.gap, RingGapStyle.value)
        XCTAssertNotNil(percentageRing?.effect, "The ring effect stays active while charging")
        XCTAssertEqual(percentageRing?.effect, RingEffectState(pulsesAccessory: false, tintsAccessory: false))

        let emptyOptions = BatteryIconOptions(showsPercentage: false,
            showsChargingIndicator: false, showsChargingEffect: true,
            showsChargingBoltHeartbeat: true, usesStatusColors: true)
        let emptyRing = scene(snapshot: snapshot(battery: active), batteryOptions: emptyOptions).outerRing
        XCTAssertEqual(emptyRing?.gap, RingGapStyle.closed)
        XCTAssertNotNil(emptyRing?.effect, "The ring effect stays active without a gap accessory")
        XCTAssertEqual(emptyRing?.effect, RingEffectState(pulsesAccessory: false, tintsAccessory: false))
    }

    /// Issue #105: the ring has to close at the level the user calls full, and
    /// the same scene feeds the menu bar and the Dock, so one assertion covers
    /// both surfaces.
    func testBatteryRingClosesAtTheConfiguredFullThreshold() {
        let battery = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: true,
                                    isLowPowerMode: false, isConnectedToPower: true)

        let raw = scene(snapshot: snapshot(battery: battery), batteryOptions: .standard)
        XCTAssertEqual(raw.outerRing?.segments.first?.progress ?? -1, 0.8, accuracy: 0.0001)

        let capped = scene(snapshot: snapshot(battery: battery),
                           batteryOptions: BatteryIconOptions(fullThreshold: 80))
        XCTAssertEqual(capped.outerRing?.segments.first?.progress ?? -1, 1.0, accuracy: 0.0001)

        let halfway = scene(snapshot: snapshot(battery: battery),
                            batteryOptions: BatteryIconOptions(fullThreshold: 40))
        XCTAssertEqual(halfway.outerRing?.segments.first?.progress ?? -1, 1.0, accuracy: 0.0001)
    }

    func testBatteryColorPriorityAndThresholdBoundary() {
        let cases: [(Int, Int, Bool, Bool, IconColorRole)] = [
            (19, 20, false, false, .critical),
            (20, 20, true, true, .lowPower),
            (50, 20, true, true, .lowPower),
            (50, 20, false, true, .powered),
            (50, 20, false, false, .primary)
        ]
        for (percentage, threshold, lowPower, connected, color) in cases {
            let battery = BatteryStatus(rawPercentage: percentage, isPresent: true, isCharging: connected,
                                        isLowPowerMode: lowPower, isConnectedToPower: connected)
            let options = BatteryIconOptions(criticalThreshold: threshold)
            XCTAssertEqual(scene(snapshot: snapshot(battery: battery), batteryOptions: options).outerRing?.segments,
                           [RingSegmentState(progress: Double(percentage) / 100, color: color)])
        }
    }

    func testBatteryPercentageCenterShowsItsNumberWhenOutagePriorityIsOff() {
        let battery = BatteryStatus(rawPercentage: 45, isPresent: true, isCharging: false,
                                    isLowPowerMode: false, isConnectedToPower: false)
        let snapshot = StatusSnapshot(battery: battery,
            wifi: WiFiStatus(state: .noInternet, rssi: -45), connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output", currentDevice: PresentationFixtures.bluetoothDevice))
        let configuration = IconPresentationConfiguration(
            battery: .standard,
            connection: ConnectionIconOptions(centerSource: .batteryPercentage,
                                              prioritizesNetworkErrors: false), volume: .standard,
            bluetooth: BluetoothAudioIconOptions())

        let center = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: .symbol(name: "airpods.pro", variableValue: nil, fallback: "headphones")),
            configuration: configuration).center

        XCTAssertEqual(center, .text(IconTextState(text: "45", color: .primary, scale: 1)))
    }

    func testConnectionMappingHandlesEthernetSignalAndWiFiStateOverrides() {
        let options = ConnectionIconOptions(showsWiFiIconForEthernet: true,
                                            showsWiFiIconForHotspot: true,
                                            showsWiFiIconForTemporaryConnection: true,
                                            showsWiFiIconForInternetSharing: true)
        let cases: [(NetworkConnection, WiFiState, Int?, ConnectionIconOptions, CenterState?)] = [
            (.ethernet, .off, nil, options, .symbol(IconSymbolState(source: .symbol(name: "wifi", variableValue: 1, fallback: nil), color: .primary, scale: 1))),
            (.wifi, .connected, -89, options, .symbol(IconSymbolState(source: .symbol(name: "wifi", variableValue: 0, fallback: nil), color: .inactive, scale: 1))),
            (.wifi, .hotspot, -75, options, .symbol(IconSymbolState(source: .symbol(name: "wifi", variableValue: 0.66, fallback: nil), color: .primary, scale: 1))),
            (.wifi, .temporary, -50, ConnectionIconOptions(), .symbol(IconSymbolState(source: .primitive(.screenWedge), color: .primary, scale: 1))),
            (.wifi, .shared, -50, ConnectionIconOptions(), .symbol(IconSymbolState(source: .primitive(.arrowWedge), color: .primary, scale: 1))),
            (.wifi, .off, -50, options, .symbol(IconSymbolState(source: .symbol(name: "wifi.slash", variableValue: 1, fallback: nil), color: .primary, scale: 1)))
        ]

        for (connection, wifiState, rssi, caseOptions, expected) in cases {
            let snapshot = snapshot(connection: connection, wifi: WiFiStatus(state: wifiState, rssi: rssi))
            XCTAssertEqual(scene(snapshot: snapshot, connectionOptions: caseOptions).center, expected,
                           "connection=\(connection), wifi=\(wifiState)")
        }
    }

    func testNetworkOutageOverridesNumericMiddleContent() {
        let offline = snapshot(connection: .offline, wifi: WiFiStatus(state: .noInternet, rssi: nil))
        for source in [ConnectionCenterSource.power, .batteryPercentage] {
            let output = scene(snapshot: offline, connectionOptions: ConnectionIconOptions(centerSource: source))
            XCTAssertEqual(output.center, .symbol(IconSymbolState(
                source: .symbol(name: "wifi.exclamationmark", variableValue: 1, fallback: nil),
                color: .primary,
                scale: 1
            )), "The outage priority must also cover \(source)")
        }
    }

    func testConnectionSlotToggleShowsPresentBatteryPercentage() {
        let config = ConnectionIconOptions(centerSource: .batteryPercentage)
        let output = scene(snapshot: PresentationFixtures.snapshot(), connectionOptions: config).center
        XCTAssertEqual(output, .text(IconTextState(text: "68", color: .primary, scale: 1)))
    }

    func testPowerCenterSlotRendersIntegerWattsWithoutUnitOrDecimal() {
        let now = Date(timeIntervalSince1970: 1_789_555_974)
        let config = ConnectionIconOptions(centerSource: .power)
        let cases: [(Double, String)] = [
            (23.6, "24"),
            (0.4, "0"),
            (-2, "0"),
            (999.4, "999"),
            (1_204, "999")
        ]
        for (watts, expected) in cases {
            let sample = SystemPowerSample(watts: watts, readAt: now)
            let output = IconPresentationMapper.scene(
                inputs: IconPresentationInputs(
                    snapshot: PresentationFixtures.snapshot(),
                    audioIcon: nil,
                    systemPower: sample
                ),
                configuration: configuration(connection: config),
                now: now
            ).center
            XCTAssertEqual(output, .text(IconTextState(text: expected, color: .primary, scale: 1)),
                           "watts=\(watts)")
        }
    }

    func testPowerTextFollowsTheWifiIconSizeScale() {
        let now = Date(timeIntervalSince1970: 1_789_555_974)
        let config = ConnectionIconOptions(centerSource: .power, wifiScale: 1.8)
        let sample = SystemPowerSample(watts: 23.6, readAt: now)
        let scene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: PresentationFixtures.snapshot(),
                audioIcon: nil,
                systemPower: sample
            ),
            configuration: configuration(connection: config),
            now: now
        )
        XCTAssertEqual(scene.center,
                       .text(IconTextState(text: "24", color: .primary, scale: 1.8)),
                       "The wattage must grow with the Wi-Fi Icon Size setting")
    }

    func testBatteryPercentageCentreUsesTheSameWifiIconSizeScale() {
        let config = ConnectionIconOptions(
            centerSource: .batteryPercentage,
            prioritizesNetworkErrors: false,
            wifiScale: 1.8
        )
        let center = scene(snapshot: snapshot(battery: BatteryStatus(
            rawPercentage: 68, isPresent: true, isCharging: false,
            isLowPowerMode: false, isConnectedToPower: false
        )), connectionOptions: config).center
        XCTAssertEqual(center, .text(IconTextState(text: "68", color: .primary, scale: 1.8)))
    }

    func testPowerCenterSlotFallsBackToBatteryThenPlaceholder() {
        let now = Date(timeIntervalSince1970: 1_789_555_974)
        let config = ConnectionIconOptions(centerSource: .power, prioritizesNetworkErrors: false)
        let stale = SystemPowerSample(watts: 23.6, readAt: now.addingTimeInterval(-120))

        let present = BatteryStatus(rawPercentage: 68, isPresent: true, isCharging: false,
                                    isLowPowerMode: false, isConnectedToPower: false)
        let withBattery = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: snapshot(battery: present),
                audioIcon: nil,
                systemPower: stale
            ),
            configuration: configuration(connection: config),
            now: now
        ).center
        XCTAssertEqual(withBattery, .text(IconTextState(text: "68", color: .primary, scale: 1)),
                       "A battery Mac may still show its level instead of a fake wattage")

        let nonFinite = SystemPowerSample(watts: .infinity, readAt: now)
        let nonFiniteCenter = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: snapshot(battery: present),
                audioIcon: nil,
                systemPower: nonFinite
            ),
            configuration: configuration(connection: config),
            now: now
        ).center
        XCTAssertEqual(nonFiniteCenter, .text(IconTextState(text: "68", color: .primary, scale: 1)),
                       "A non-finite sample must fall back instead of trapping Int conversion")

        let noBattery = BatteryStatus(rawPercentage: nil, isPresent: false, isCharging: false,
                                      isLowPowerMode: false, isConnectedToPower: false)
        let placeholder = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: snapshot(battery: noBattery),
                audioIcon: nil,
                systemPower: nil
            ),
            configuration: configuration(connection: config),
            now: now
        ).center
        XCTAssertEqual(placeholder, .text(IconTextState(text: "--", color: .primary, scale: 1)),
                       "A Mac with no battery must not invent a percentage or a 0 W reading")
    }

    func testBatteryPercentageCenterShowsOneHundredWhenBatteryIsAbsent() {
        // A Mac with no battery reports 100 through `BatteryStatus.percentage`.
        // The connection slot must show that same value instead of falling back
        // to the network glyph, matching the top battery indicator.
        let absent = BatteryStatus(rawPercentage: nil, isPresent: false, isCharging: false,
                                   isLowPowerMode: false, isConnectedToPower: false)
        let config = ConnectionIconOptions(
            centerSource: .batteryPercentage,
            prioritizesNetworkErrors: false
        )
        let center = scene(snapshot: snapshot(battery: absent), connectionOptions: config).center
        XCTAssertEqual(center, .text(IconTextState(text: "100", color: .primary, scale: 1)))
    }

    func testOffAndUnavailableWifiShareOneVisualState() {
        let off = snapshot(wifi: WiFiStatus(state: .off, rssi: -40))
        let unavailable = snapshot(wifi: WiFiStatus(state: .unavailable, rssi: -90))
        XCTAssertEqual(scene(snapshot: off), scene(snapshot: unavailable))
    }

    func testSpecialWifiConnectionOptionsReplaceEachMarkWithSignalSymbol() {
        let cases: [(WiFiState, ConnectionIconOptions, CenterState, ConnectionIconOptions)] = [
            (.hotspot, ConnectionIconOptions(), .symbol(IconSymbolState(
                source: .symbol(name: "personalhotspot", variableValue: 1, fallback: nil), color: .primary, scale: 1)),
             ConnectionIconOptions(showsWiFiIconForHotspot: true)),
            (.temporary, ConnectionIconOptions(), .symbol(IconSymbolState(
                source: .primitive(.screenWedge), color: .primary, scale: 1)),
             ConnectionIconOptions(showsWiFiIconForTemporaryConnection: true)),
            (.shared, ConnectionIconOptions(), .symbol(IconSymbolState(
                source: .primitive(.arrowWedge), color: .primary, scale: 1)),
             ConnectionIconOptions(showsWiFiIconForInternetSharing: true))
        ]

        for (state, disabledOptions, disabledState, enabledOptions) in cases {
            let snapshot = snapshot(wifi: WiFiStatus(state: state, rssi: -75))
            XCTAssertEqual(scene(snapshot: snapshot, connectionOptions: disabledOptions).center, disabledState)
            XCTAssertEqual(scene(snapshot: snapshot, connectionOptions: enabledOptions).center,
                           .symbol(IconSymbolState(source: .symbol(name: "wifi", variableValue: 0.66, fallback: nil),
                                                   color: .primary, scale: 1)))
        }
    }

    func testBluetoothOverrideWorksWithoutOutputAndNetworkErrorsWinWhenPrioritized() {
        let bluetooth = BluetoothAudioIconOptions(networkIconSymbolOverride: "custom.device")
        let connected = scene(
            snapshot: snapshot(wifi: WiFiStatus(state: .connected, rssi: -50)),
            connectionOptions: ConnectionIconOptions(centerSource: .bluetoothDevice),
            bluetoothOptions: bluetooth
        ).center
        XCTAssertEqual(connected, .symbol(IconSymbolState(source: .symbol(name: "custom.device", variableValue: nil, fallback: "dot.radiowaves.left.and.right"), color: .bluetooth, scale: 1.6)))

        let error = scene(
            snapshot: snapshot(wifi: WiFiStatus(state: .noInternet, rssi: nil)),
            connectionOptions: ConnectionIconOptions(centerSource: .bluetoothDevice),
            bluetoothOptions: bluetooth
        ).center
        XCTAssertEqual(error, .symbol(IconSymbolState(source: .symbol(name: "wifi.exclamationmark", variableValue: 1, fallback: nil), color: .primary, scale: 1)))
    }

    func testBluetoothCurrentOutputUsesResolvedIconAndPrioritizedErrorsKeepNetworkCenter() {
        let output = snapshot(wifi: WiFiStatus(state: .connected, rssi: -45),
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output", currentDevice: PresentationFixtures.bluetoothDevice))
        let options = BluetoothAudioIconOptions()
        let input = IconPresentationInputs(snapshot: output,
            audioIcon: .image(url: URL(fileURLWithPath: "/audio.png"), fallbackSymbol: "headphones"))
        XCTAssertEqual(IconPresentationMapper.scene(inputs: input,
            configuration: IconPresentationConfiguration(
                battery: .standard,
                connection: ConnectionIconOptions(centerSource: .bluetoothDevice),
                volume: .standard,
                bluetooth: options
            )).center,
            .symbol(IconSymbolState(source: .image(url: URL(fileURLWithPath: "/audio.png"), fallbackSymbol: "headphones"),
                                    color: .bluetooth, scale: 1.6)))

        let error = snapshot(connection: .wifi, wifi: WiFiStatus(state: .noInternet, rssi: -45),
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output", currentDevice: PresentationFixtures.bluetoothDevice))
        XCTAssertEqual(scene(
            snapshot: error,
            connectionOptions: ConnectionIconOptions(centerSource: .bluetoothDevice),
            bluetoothOptions: options
        ).center,
                       .symbol(IconSymbolState(source: .symbol(name: "wifi.exclamationmark", variableValue: 1, fallback: nil),
                                               color: .primary, scale: 1)))
    }

    func testVolumeNilNonFiniteMuteAndClampingProduceFiniteStableFooter() {
        let arcConfiguration = VolumeIconOptions(displayStyle: .arc)
        for scalar in [Double.nan, .infinity, -.infinity, -1, 0, 1, 2] as [Double] {
            let muted = scene(snapshot: PresentationFixtures.snapshot(scalar: scalar, muted: true), volumeOptions: arcConfiguration).footer
            XCTAssertEqual(muted, .arc(ArcState(progress: 0, color: .primary, strokeScale: arcConfiguration.ringStrokeScale)))
        }

        XCTAssertEqual(scene(snapshot: PresentationFixtures.snapshot(scalar: nil), volumeOptions: arcConfiguration).footer,
                       .arc(ArcState(progress: 0, color: .primary, strokeScale: arcConfiguration.ringStrokeScale)))
        XCTAssertEqual(scene(snapshot: PresentationFixtures.snapshot(scalar: 2), volumeOptions: arcConfiguration).footer,
                       .arc(ArcState(progress: 1, color: .primary, strokeScale: arcConfiguration.ringStrokeScale)))
    }

    func testVolumeDotBucketsAndBluetoothColorDependOnCurrentOutput() {
        let bluetooth = PresentationFixtures.bluetoothDevice
        let outputSnapshot = snapshot(volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output", currentDevice: bluetooth))
        let options = BluetoothAudioIconOptions(usesVolumeColor: true)

        XCTAssertEqual(scene(snapshot: outputSnapshot, bluetoothOptions: options).footer,
                       .dots(DotsState(count: 4, activeCount: 2, color: .bluetooth, strokeScale: VolumeIconOptions.standard.ringStrokeScale)))
        let noBluetooth = snapshot(volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output"))
        XCTAssertEqual(scene(snapshot: noBluetooth, bluetoothOptions: options).footer,
                       .dots(DotsState(count: 4, activeCount: 2, color: .primary, strokeScale: VolumeIconOptions.standard.ringStrokeScale)))
    }

    func testDotVolumeNormalizesNilNonFiniteAndBoundaryValues() {
        let cases: [(Double?, Int)] = [
            (nil, 0),
            (.nan, 0),
            (.infinity, 0),
            (-.infinity, 0),
            (-1, 0),
            (0, 0),
            (0.25, 1),
            (0.2501, 2),
            (0.5, 2),
            (0.5001, 3),
            (0.75, 3),
            (0.7501, 4),
            (1, 4),
            (2, 4)
        ]
        for (scalar, expectedSteps) in cases {
            let snapshot = PresentationFixtures.snapshot(scalar: scalar)
            XCTAssertEqual(scene(snapshot: snapshot).footer,
                           .dots(DotsState(count: 4, activeCount: expectedSteps, color: .primary,
                                           strokeScale: VolumeIconOptions.standard.ringStrokeScale)),
                           "scalar=\(String(describing: scalar))")
        }
    }

    func testEmptyVolumeFillCanonicalizesBluetoothColorForDotsAndArc() {
        let device = PresentationFixtures.bluetoothDevice
        let bluetoothOptions = BluetoothAudioIconOptions(usesVolumeColor: true)
        let emptyScalars: [Double?] = [nil, .nan, .infinity, -.infinity, -1, 0]

        for scalar in emptyScalars {
            let bluetoothSnapshot = snapshot(volume: VolumeStatus(scalar: scalar, isMuted: false,
                deviceName: "Output", currentDevice: device))
            let ordinarySnapshot = snapshot(volume: VolumeStatus(scalar: scalar, isMuted: false,
                deviceName: "Output"))
            XCTAssertEqual(scene(snapshot: bluetoothSnapshot, bluetoothOptions: bluetoothOptions).footer,
                           .dots(DotsState(count: 4, activeCount: 0, color: .primary,
                                           strokeScale: VolumeIconOptions.standard.ringStrokeScale)))
            XCTAssertEqual(scene(snapshot: bluetoothSnapshot, bluetoothOptions: bluetoothOptions).footer,
                           scene(snapshot: ordinarySnapshot).footer)
        }

        let arc = VolumeIconOptions(displayStyle: .arc)
        for scalar in emptyScalars {
            let bluetoothSnapshot = snapshot(volume: VolumeStatus(scalar: scalar, isMuted: false,
                deviceName: "Output", currentDevice: device))
            let ordinarySnapshot = snapshot(volume: VolumeStatus(scalar: scalar, isMuted: false,
                deviceName: "Output"))
            XCTAssertEqual(scene(snapshot: bluetoothSnapshot, volumeOptions: arc,
                                 bluetoothOptions: bluetoothOptions).footer,
                           .arc(ArcState(progress: 0, color: .primary, strokeScale: arc.ringStrokeScale)))
            XCTAssertEqual(scene(snapshot: bluetoothSnapshot, volumeOptions: arc,
                                 bluetoothOptions: bluetoothOptions).footer,
                           scene(snapshot: ordinarySnapshot, volumeOptions: arc).footer)
        }
    }

    // MARK: - Charging status inside the ring (#253)

    private func chargingScene(
        battery: BatteryStatus,
        source: ConnectionCenterSource,
        batteryOptions: BatteryIconOptions = .standard,
        connection: NetworkConnection = .wifi,
        wifi: WiFiStatus = .placeholder
    ) -> IconSceneState {
        scene(
            snapshot: snapshot(battery: battery, connection: connection, wifi: wifi),
            batteryOptions: batteryOptions,
            connectionOptions: ConnectionIconOptions(
                centerSource: source,
                prioritizesNetworkErrors: false,
                wifiScale: 1
            )
        )
    }

    func testChargingStatusCentresTheBoltAndKeepsThePercentageInTheTopGap() {
        let battery = BatteryStatus(rawPercentage: 55, isPresent: true, isCharging: true,
                                    isLowPowerMode: false, isConnectedToPower: true)
        let scene = chargingScene(battery: battery, source: .chargingStatus)
        // The centre already shows the bolt, so the top gap is free to carry the
        // level percentage instead of closing and losing it.
        XCTAssertEqual(scene.outerRing?.gap, .value)
        guard case let .text(text)? = scene.outerRing?.accessory else {
            return XCTFail("expected the level percentage in the top gap")
        }
        XCTAssertEqual(text.text, "55")
        guard case let .symbol(symbol)? = scene.center, case .primitive(.bolt) = symbol.source else {
            return XCTFail("expected the bolt in the centre slot")
        }
    }

    func testChargingStatusShowsThePlugWhenConnectedWithoutCharging() {
        let charged = BatteryStatus(rawPercentage: 100, isPresent: true, isCharging: false,
                                    isCharged: true, isLowPowerMode: false,
                                    isConnectedToPower: true)
        // A charge-limited / held battery is connected but neither charging nor full.
        let held = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: false,
                                 isLowPowerMode: false, isConnectedToPower: true)
        for battery in [charged, held] {
            let scene = chargingScene(battery: battery, source: .chargingStatus)
            // The centre shows the plug, so the top gap keeps the level percentage.
            XCTAssertEqual(scene.outerRing?.gap, .value)
            guard case let .text(text)? = scene.outerRing?.accessory else {
                return XCTFail("expected the level percentage in the top gap for \(battery)")
            }
            XCTAssertEqual(text.text, "\(battery.percentage)")
            guard case let .symbol(symbol)? = scene.center, case .primitive(.plug) = symbol.source else {
                return XCTFail("expected a centred plug for \(battery)")
            }
        }
    }

    func testChargingStatusShowsTheLevelPercentageOnBattery() {
        let battery = BatteryStatus(rawPercentage: 62, isPresent: true, isCharging: false,
                                    isLowPowerMode: false, isConnectedToPower: false)
        let scene = chargingScene(battery: battery, source: .chargingStatus)
        XCTAssertEqual(scene.outerRing?.gap, .closed)
        XCTAssertEqual(scene.center,
                       .text(IconTextState(text: "62", color: .primary, scale: 1)))
    }

    func testChargingStatusFallsBackToNetworkWithoutABattery() {
        let absent = BatteryStatus(rawPercentage: nil, isPresent: false, isCharging: false,
                                   isLowPowerMode: false, isConnectedToPower: true)
        let scene = chargingScene(battery: absent, source: .chargingStatus)
        // A machine with no battery has no status to invent and no ring to close.
        XCTAssertNotEqual(scene.outerRing?.gap, .closed)
        guard case .symbol? = scene.center else {
            return XCTFail("expected the network glyph fallback")
        }
    }

    func testOtherCentreSourcesKeepTheTopGapAccessoryAndTheCentreGlyph() {
        let battery = BatteryStatus(rawPercentage: 55, isPresent: true, isCharging: true,
                                    isLowPowerMode: false, isConnectedToPower: true)
        let scene = chargingScene(battery: battery, source: .network)
        XCTAssertEqual(scene.outerRing?.gap, .indicator)
        guard case let .symbol(symbol)? = scene.outerRing?.accessory,
              case .primitive(.bolt) = symbol.source else {
            return XCTFail("expected a top-gap bolt")
        }
        XCTAssertNotNil(scene.center)
    }

    func testChargingStatusSplitsGapProgressWhileTheTopGapShowsThePercentage() {
        let battery = BatteryStatus(rawPercentage: 55, isPresent: true, isCharging: true,
                                    isLowPowerMode: false, isConnectedToPower: true)
        let split = BatteryIconOptions(splitGapProgress: true)
        let open = chargingScene(battery: battery, source: .chargingStatus,
                                 batteryOptions: split)
        XCTAssertEqual(open.outerRing?.gap, .value)
        XCTAssertEqual(open.outerRing?.gapProgressMode, .split)

        let historical = chargingScene(battery: battery, source: .network,
                                       batteryOptions: split)
        XCTAssertEqual(historical.outerRing?.gap, .indicator)
        XCTAssertEqual(historical.outerRing?.gapProgressMode, .split)
    }

    private func scene(
        snapshot: StatusSnapshot = PresentationFixtures.snapshot(),
        batteryOptions: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothOptions: BluetoothAudioIconOptions = .standard,
        audioIcon: IconSymbolSource? = nil
    ) -> IconSceneState {
        IconPresentationMapper.scene(inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: audioIcon),
            configuration: IconPresentationConfiguration(battery: batteryOptions, connection: connectionOptions,
                                                         volume: volumeOptions, bluetooth: bluetoothOptions))
    }

    private func configuration(
        connection: ConnectionIconOptions
    ) -> IconPresentationConfiguration {
        IconPresentationConfiguration(
            battery: .standard,
            connection: connection,
            volume: .standard,
            bluetooth: .standard
        )
    }

    private func snapshot(battery: BatteryStatus = BatteryStatus(rawPercentage: 68, isPresent: true, isCharging: false,
                                                                  isLowPowerMode: false, isConnectedToPower: false),
                          connection: NetworkConnection = .wifi, wifi: WiFiStatus = .placeholder,
                          volume: VolumeStatus = .placeholder) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: wifi, connection: connection, volume: volume)
    }
}
