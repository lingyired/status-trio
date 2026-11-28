import Combine
import XCTest
@testable import StatusTrioCore

/// Bottom-indicator data source: storage, mapper output for every source and
/// style, the scene-level volume classifier, and the guarantee that the source
/// stays independent from the stored display style.
@MainActor
final class BottomIndicatorSourceTests: XCTestCase {
    // MARK: Fixtures

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.BottomIndicatorSource.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("could not create isolated user defaults suite")
        }
        defaults.removeTestSuite(named: name)
        addTeardownBlock { TestUserDefaults.removeSuite(named: name) }
        return (defaults, name)
    }

    private func bluetoothDevice() -> AudioOutputDevice {
        AudioOutputDevice(
            id: 1,
            name: "AirPods",
            uid: "bottom-indicator.test.bluetooth",
            isCurrent: true,
            volume: 0.5,
            transport: .bluetooth
        )
    }

    private func snapshot(
        battery: BatteryStatus = BatteryStatus(
            rawPercentage: 68,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        ),
        wifi: WiFiStatus = WiFiStatus(state: .connected, rssi: -60),
        connection: NetworkConnection = .wifi,
        volume: VolumeStatus = VolumeStatus(scalar: 0.6, isMuted: false, deviceName: "Output")
    ) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: wifi, connection: connection, volume: volume)
    }

    private func scene(
        source: BottomIndicatorSource,
        style: VolumeDisplayStyle = .dots,
        snapshot: StatusSnapshot? = nil,
        batteryOptions: BatteryIconOptions = .standard,
        bluetoothOptions: BluetoothAudioIconOptions = .standard
    ) -> IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: snapshot ?? self.snapshot(),
                audioIcon: nil,
                bottomIndicatorSource: source
            ),
            configuration: IconPresentationConfiguration(
                battery: batteryOptions,
                connection: .standard,
                volume: VolumeIconOptions(displayStyle: style),
                bluetooth: bluetoothOptions
            )
        )
    }

    // MARK: Storage

    func testDefaultsToVolumeAndPersists() {
        let suite = makeSuite()
        let store = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(store.bottomIndicatorSource, .volume)

        store.bottomIndicatorSource = .wifi
        XCTAssertEqual(
            SettingsStore(defaults: suite.defaults).bottomIndicatorSource,
            .wifi,
            "The selected source must survive a relaunch."
        )
    }

    func testUnknownStoredValueFallsBackToVolume() {
        let suite = makeSuite()
        suite.defaults.set("not-a-source", forKey: SettingsStore.bottomIndicatorSourceDefaultsKey)
        XCTAssertEqual(SettingsStore(defaults: suite.defaults).bottomIndicatorSource, .volume)
    }

    func testSourceAndStyleAreStoredIndependently() {
        let suite = makeSuite()
        let store = SettingsStore(defaults: suite.defaults)
        store.volumeDisplayStyle = .arc
        store.bottomIndicatorSource = .battery

        let reopened = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(reopened.volumeDisplayStyle, .arc)
        XCTAssertEqual(reopened.bottomIndicatorSource, .battery)
    }

    func testRuntimeOptionsCarryTheSource() {
        let suite = makeSuite()
        let store = SettingsStore(defaults: suite.defaults)
        store.bottomIndicatorSource = .battery
        XCTAssertEqual(store.iconRuntimePresentationOptions.bottomIndicatorSource, .battery)
        store.bottomIndicatorSource = .metric
        store.bottomIndicatorMetric = .memoryPressure
        XCTAssertEqual(store.iconRuntimePresentationOptions.bottomIndicatorSource, .metric)
        XCTAssertEqual(store.iconRuntimePresentationOptions.bottomIndicatorMetric, .memoryPressure)
    }

    func testEnumCapabilities() {
        XCTAssertEqual(BottomIndicatorSource.default, .volume)
        XCTAssertTrue(BottomIndicatorSource.volume.supportsBluetoothVolumeColor)
        XCTAssertFalse(BottomIndicatorSource.wifi.supportsBluetoothVolumeColor)
        XCTAssertFalse(BottomIndicatorSource.battery.supportsBluetoothVolumeColor)
        XCTAssertFalse(BottomIndicatorSource.hidden.showsStyleOptions)
        XCTAssertTrue(BottomIndicatorSource.volume.showsStyleOptions)
        XCTAssertTrue(BottomIndicatorSource.metric.showsStyleOptions)
        XCTAssertFalse(BottomIndicatorSource.metric.supportsBluetoothVolumeColor)
        XCTAssertEqual(BottomIndicatorSource.allCases.map(\.rawValue), ["volume", "wifi", "battery", "metric", "hidden"])
    }

    // MARK: Volume regression

    func testVolumeSourceKeepsExistingDotsAndArcBehaviour() {
        let dots = scene(source: .volume, style: .dots).footer
        guard case let .dots(d)? = dots else { return XCTFail("expected dots") }
        XCTAssertEqual(d.count, 4)
        XCTAssertEqual(d.activeCount, 3, "scalar 0.6 is three steps, unchanged from before")

        let arc = scene(source: .volume, style: .arc).footer
        guard case let .arc(a)? = arc else { return XCTFail("expected arc") }
        XCTAssertEqual(a.progress, 0.6, accuracy: 0.0001)
    }

    func testVolumeSourceKeepsBluetoothColour() {
        let device = bluetoothDevice()
        let volume = VolumeStatus(
            scalar: 0.5,
            isMuted: false,
            deviceName: device.name,
            currentDevice: device
        )
        let options = BluetoothAudioIconOptions(usesVolumeColor: true)
        let footer = scene(source: .volume, style: .dots, snapshot: snapshot(volume: volume),
                           bluetoothOptions: options).footer
        guard case let .dots(d)? = footer else { return XCTFail("expected dots") }
        XCTAssertEqual(d.color, .bluetooth)
    }

    // MARK: Wi-Fi

    func testWiFiBarsMapToDots() {
        // The real Wi-Fi glyph has three bars, but the footer has four dots, so
        // a full (3-bar) reading must fill all four dots rather than leave one
        // empty.
        let cases: [(Int, Int)] = [(-60, 4), (-75, 3), (-85, 1), (-95, 0)]
        for (rssi, dots) in cases {
            let footer = scene(source: .wifi, style: .dots,
                               snapshot: snapshot(wifi: WiFiStatus(state: .connected, rssi: rssi))).footer
            guard case let .dots(d)? = footer else { return XCTFail("expected dots at \(rssi)") }
            XCTAssertEqual(d.count, 4)
            XCTAssertEqual(d.activeCount, dots, "rssi \(rssi) should show \(dots) dots")
        }
    }

    func testWiFiFullSignalFillsAllFourDots() {
        let footer = scene(source: .wifi, style: .dots,
                           snapshot: snapshot(wifi: WiFiStatus(state: .connected, rssi: -58))).footer
        guard case let .dots(d)? = footer else { return XCTFail("expected dots") }
        XCTAssertEqual(d.activeCount, 4, "Full Wi-Fi signal must fill all four dots.")
    }

    func testWiFiBarsMapToArcProgress() {
        for (rssi, bars) in [(-60, 3), (-75, 2), (-85, 1), (-95, 0)] {
            let footer = scene(source: .wifi, style: .arc,
                               snapshot: snapshot(wifi: WiFiStatus(state: .connected, rssi: rssi))).footer
            guard case let .arc(a)? = footer else { return XCTFail("expected arc at \(rssi)") }
            XCTAssertEqual(a.progress, Double(bars) / 3.0, accuracy: 0.0001)
        }
    }

    func testWiFiUnknownOrUnavailableHidesFooter() {
        let states: [WiFiStatus] = [
            WiFiStatus(state: .connected, rssi: nil),   // unknown / invalid reading
            WiFiStatus(state: .connected, rssi: 12),    // invalid positive value
            WiFiStatus(state: .notAssociated, rssi: nil),
            WiFiStatus(state: .off, rssi: nil),
            WiFiStatus(state: .unavailable, rssi: nil)
        ]
        for wifi in states {
            XCTAssertNil(
                scene(source: .wifi, snapshot: snapshot(wifi: wifi)).footer,
                "\(wifi.state) with rssi \(String(describing: wifi.rssi)) should hide the footer"
            )
        }
    }

    func testWiFiSourceOnWiredNetworkHidesFooter() {
        // Wi-Fi radio off while the active link is Ethernet: nothing to report.
        let wired = snapshot(
            wifi: WiFiStatus(state: .off, rssi: nil),
            connection: .ethernet
        )
        XCTAssertNil(scene(source: .wifi, snapshot: wired).footer)
    }

    // MARK: Battery

    func testBatteryLevelsMapToDots() {
        for (percentage, steps) in [(0, 0), (25, 1), (50, 2), (75, 3), (100, 4)] {
            let battery = BatteryStatus(
                rawPercentage: percentage,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            )
            let footer = scene(source: .battery, style: .dots,
                               snapshot: snapshot(battery: battery)).footer
            guard case let .dots(d)? = footer else { return XCTFail("expected dots at \(percentage)") }
            XCTAssertEqual(d.activeCount, steps, "\(percentage)% should be \(steps) dots")
        }
    }

    func testBatteryLevelsMapToArcProgress() {
        for percentage in [0, 1, 37, 99, 100] {
            let battery = BatteryStatus(
                rawPercentage: percentage,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            )
            let footer = scene(source: .battery, style: .arc,
                               snapshot: snapshot(battery: battery)).footer
            guard case let .arc(a)? = footer else { return XCTFail("expected arc at \(percentage)") }
            XCTAssertEqual(a.progress, Double(percentage) / 100.0, accuracy: 0.0001)
        }
    }

    func testBatterySourceWithoutBatteryHidesFooter() {
        XCTAssertNil(scene(source: .battery, snapshot: snapshot(battery: .absent)).footer)
    }

    private func batteryStatus(
        _ percentage: Int,
        charging: Bool = false,
        lowPower: Bool = false,
        connectedToPower: Bool = false
    ) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: true,
            isCharging: charging,
            isLowPowerMode: lowPower,
            isConnectedToPower: connectedToPower
        )
    }

    private func batteryFooterColor(
        _ battery: BatteryStatus,
        options: BatteryIconOptions = .standard
    ) -> IconColorRole? {
        let scene = scene(source: .battery, snapshot: snapshot(battery: battery), batteryOptions: options)
        guard case let .dots(dots)? = scene.footer else { return nil }
        return dots.color
    }

    func testBatteryFooterUsesTheSharedStatusColour() {
        // Same status → same colour as the top ring: critical, low power, and
        // the charging / connected colours all come through the shared field.
        XCTAssertEqual(batteryFooterColor(batteryStatus(10)), .critical)
        XCTAssertEqual(batteryFooterColor(batteryStatus(50, lowPower: true)), .lowPower)
        XCTAssertEqual(batteryFooterColor(batteryStatus(50, charging: true)), .powered)
        XCTAssertEqual(batteryFooterColor(batteryStatus(50, connectedToPower: true)), .connected)
        XCTAssertEqual(batteryFooterColor(batteryStatus(50)), .discharging)
    }

    func testBatteryFooterColourIsOffWhenStatusColoursAreOff() {
        let monochrome = BatteryIconOptions(usesStatusColors: false)
        XCTAssertEqual(batteryFooterColor(batteryStatus(10), options: monochrome), .primary)
        XCTAssertEqual(batteryFooterColor(batteryStatus(50, charging: true), options: monochrome), .primary)
    }

    func testBatteryFooterColourMatchesTheTopRingForEveryStatus() {
        let states: [BatteryStatus] = [
            batteryStatus(10),
            batteryStatus(50),
            batteryStatus(50, charging: true),
            batteryStatus(50, connectedToPower: true),
            batteryStatus(50, lowPower: true)
        ]
        for battery in states {
            let scene = scene(source: .battery, style: .arc, snapshot: snapshot(battery: battery))
            guard case let .arc(arc)? = scene.footer else { return XCTFail("expected arc footer") }
            let ringColor = scene.outerRing?.segments.first?.color
            XCTAssertEqual(arc.color, ringColor, "The bottom battery must use the top ring's colour.")
        }
    }

    // MARK: Hidden

    func testHiddenSourceReturnsNoFooter() {
        XCTAssertNil(scene(source: .hidden, style: .dots).footer)
        XCTAssertNil(scene(source: .hidden, style: .arc).footer)
    }

    // MARK: Dock cache

    func testDockRenderKeyDistinguishesSourcesEvenWithIdenticalFooter() {
        let sameFooter = DotsState(count: 4, activeCount: 0, color: .primary)
        let wifi = DockIconRenderKey(
            scene: IconSceneState(footer: .dots(sameFooter), bottomIndicatorSource: .wifi),
            backgroundStyle: .dark,
            pixelLength: 128
        )
        let battery = DockIconRenderKey(
            scene: IconSceneState(footer: .dots(sameFooter), bottomIndicatorSource: .battery),
            backgroundStyle: .dark,
            pixelLength: 128
        )
        XCTAssertNotEqual(wifi, battery, "A source change must invalidate the Dock cache.")

        var cache = DockIconRenderCache()
        XCTAssertTrue(cache.needsRender(wifi))
        cache.recordSuccessfulRender(wifi)
        XCTAssertTrue(cache.needsRender(battery))
    }

    // MARK: Scene + classifier

    func testSceneCarriesTheSource() {
        XCTAssertEqual(scene(source: .wifi).bottomIndicatorSource, .wifi)
        XCTAssertEqual(scene(source: .battery).bottomIndicatorSource, .battery)
        XCTAssertEqual(scene(source: .hidden).bottomIndicatorSource, .hidden)
    }

    func testOnlyVolumeSourceCountsAsVolumeValueChange() {
        let volumeLow = scene(source: .volume, style: .arc,
                              snapshot: snapshot(volume: VolumeStatus(scalar: 0.2, isMuted: false, deviceName: "Out")))
        let volumeHigh = scene(source: .volume, style: .arc,
                               snapshot: snapshot(volume: VolumeStatus(scalar: 0.8, isMuted: false, deviceName: "Out")))
        XCTAssertTrue(volumeHigh.isVolumeValueChange(from: volumeLow))

        let wifiWeak = scene(source: .wifi, style: .dots,
                             snapshot: snapshot(wifi: WiFiStatus(state: .connected, rssi: -85)))
        let wifiStrong = scene(source: .wifi, style: .dots,
                               snapshot: snapshot(wifi: WiFiStatus(state: .connected, rssi: -55)))
        XCTAssertFalse(wifiStrong.isVolumeValueChange(from: wifiWeak),
                       "A Wi-Fi signal update must not be rate-limited as a volume change.")

        let batteryLow = scene(source: .battery, style: .arc, snapshot: snapshot(battery: BatteryStatus(
            rawPercentage: 20, isPresent: true, isCharging: false,
            isLowPowerMode: false, isConnectedToPower: false)))
        let batteryHigh = scene(source: .battery, style: .arc, snapshot: snapshot(battery: BatteryStatus(
            rawPercentage: 90, isPresent: true, isCharging: false,
            isLowPowerMode: false, isConnectedToPower: false)))
        XCTAssertFalse(batteryHigh.isVolumeValueChange(from: batteryLow),
                       "A battery update must not be rate-limited as a volume change.")

        // Switching source is a settings change even when the footer kind matches.
        let volumeArc = scene(source: .volume, style: .arc)
        XCTAssertFalse(volumeArc.isVolumeValueChange(from: wifiStrong))
    }

    // MARK: Metric source

    private func metricSource(metric: HardwareMonitorMetric, value: Double) -> IconSourceSnapshot {
        var source = IconSourceSnapshot.empty
        var snap = HardwareMetricsSnapshot()
        snap.samples[metric.metricID] = HardwareMetricSample(
            value: value, unit: .percent, sampledAt: Date(),
            source: .mach, availability: .measured)
        source.hardwareMetrics = snap
        return source
    }

    private func cpuMetricScene(
        value: Double,
        style: VolumeDisplayStyle = .arc
    ) -> IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: snapshot(),
                audioIcon: nil,
                sources: metricSource(metric: .cpuUsage, value: value),
                bottomIndicatorSource: .metric,
                bottomIndicatorMetric: .cpuUsage
            ),
            configuration: IconPresentationConfiguration(
                battery: .standard,
                connection: .standard,
                volume: VolumeIconOptions(displayStyle: style),
                bluetooth: .standard
            )
        )
    }

    func testMetricSourcePersistsChosenMetric() {
        let suite = makeSuite()
        let store = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(store.bottomIndicatorMetric, .cpuUsage,
                       "Default metric keeps the source stable before the user chooses one.")
        store.bottomIndicatorSource = .metric
        store.bottomIndicatorMetric = .gpuTemperature

        let reopened = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(reopened.bottomIndicatorSource, .metric)
        XCTAssertEqual(reopened.bottomIndicatorMetric, .gpuTemperature)
    }

    func testMetricBindingRoundTrips() {
        let binding = IconContentLegacyAdapter.binding(for: .metric)
        XCTAssertEqual(binding,
                       IconContentBinding(pluginID: "builtin.hardware-monitor", presentationID: "footer"))
        XCTAssertEqual(binding.flatMap(IconContentLegacyAdapter.bottomIndicatorSource(for:)), .metric)
    }

    func testMetricFooterRendersFromHardwareSample() {
        let arc = cpuMetricScene(value: 42, style: .arc).footer
        guard case let .arc(a)? = arc else { return XCTFail("expected arc footer") }
        XCTAssertEqual(a.progress, 0.42, accuracy: 0.001)

        let dots = cpuMetricScene(value: 42, style: .dots).footer
        guard case let .dots(d)? = dots else { return XCTFail("expected dots footer") }
        XCTAssertEqual(d.count, 4)
        XCTAssertGreaterThan(d.activeCount, 0)
    }

    func testSavedMemoryUsageAndPressureRemainDistinct() {
        let suite = makeSuite()
        suite.defaults.set("dots", forKey: SettingsStore.metricBottomIndicatorStyleDefaultsKey)
        for metric in [BottomIndicatorMetric.memoryUsage, .memoryPressure] {
            suite.defaults.set(metric.rawValue, forKey: SettingsStore.bottomIndicatorMetricDefaultsKey)
            let store = SettingsStore(defaults: suite.defaults, systemChargeLimit: { nil })

            XCTAssertEqual(store.bottomIndicatorMetric, metric)
            XCTAssertEqual(store.metricBottomIndicatorStyle, .dots)
            XCTAssertEqual(suite.defaults.string(forKey: SettingsStore.bottomIndicatorMetricDefaultsKey), metric.rawValue)
        }
    }

    func testMemoryUsageFooterReadsPercentageAndKeepsFixedPalette() {
        let now = Date(timeIntervalSince1970: 1_000)
        var sources = metricSource(metric: .memoryUsage, value: 42)
        sources.hardwareMetrics.samples[.memoryUsage]?.sampledAt = now
        sources.hardwareMetrics.memoryPressure = .init(level: .critical, sampledAt: now)
        let inputs = IconPresentationInputs(snapshot: snapshot(), audioIcon: nil,
                                            sources: sources, bottomIndicatorSource: .metric,
                                            bottomIndicatorMetric: .memoryUsage, bottomIndicatorStyle: .arc)
        var configuration = IconConfigurationV1.classic
        configuration.appearance.footer.color = .fixed(.white)
        let resolution = IconCompositionResolver.resolve(
            inputs: .init(system: inputs, sources: sources), configuration: configuration, now: now,
            bindings: .migrated(from: configuration, bottomIndicatorSource: .metric))

        XCTAssertEqual(resolution.demand.hardwareMetricIDs, [.memoryUsage])
        guard case let .arc(arc)? = resolution.scene.footer else { return XCTFail("expected memory usage arc") }
        XCTAssertEqual(arc.progress, 0.42, accuracy: 0.0001)
        XCTAssertEqual(arc.color, .custom(.white))
    }

    func testPressureFooterUsesSystemLevelsInBothStylesDespiteFixedPalette() {
        let now = Date(timeIntervalSince1970: 1_000)
        var configuration = IconConfigurationV1.classic
        configuration.appearance.footer.color = .fixed(.white)
        configuration.behaviors.hardwareRing.color.monochrome = true
        configuration.behaviors.hardwareRing.color.thresholdColors = false
        let bindings = IconSlotBindingsV1.migrated(from: configuration, bottomIndicatorSource: .metric)
        let cases: [(MemoryPressureLevel, Int, Double, IconColorRole)] = [
            (.normal, 2, 0.5, .custom(.init(red: 52.0 / 255, green: 199.0 / 255, blue: 89.0 / 255, alpha: 1))),
            (.warning, 3, 0.75, .custom(HardwareRingColorConfiguration.warningColor)),
            (.critical, 4, 1, .custom(HardwareRingColorConfiguration.criticalColor)),
            (.unknown, 0, 0, .inactive),
        ]
        for (level, count, progress, color) in cases {
            var sources = IconSourceSnapshot.empty
            sources.hardwareMetrics.memoryPressure = MemoryPressureReading(level: level, sampledAt: now)
            for style in [VolumeDisplayStyle.dots, .arc] {
                let inputs = IconPresentationInputs(snapshot: snapshot(), audioIcon: nil,
                                                    sources: sources, bottomIndicatorSource: .metric,
                                                    bottomIndicatorMetric: .memoryPressure,
                                                    bottomIndicatorStyle: style)
                let resolution = IconCompositionResolver.resolve(
                    inputs: .init(system: inputs, sources: sources), configuration: configuration,
                    now: now, bindings: bindings)
                XCTAssertEqual(resolution.demand.hardwareMetricIDs, [.memoryPressure])
                switch (style, resolution.scene.footer) {
                case let (.dots, .dots(dots)?):
                    XCTAssertEqual(dots.count, 4)
                    XCTAssertEqual(dots.activeCount, count)
                    XCTAssertEqual(dots.color, color)
                    XCTAssertEqual(dots.inactiveColor, .inactive)
                case let (.arc, .arc(arc)?):
                    XCTAssertEqual(arc.progress, progress)
                    XCTAssertEqual(arc.color, color)
                    XCTAssertEqual(arc.inactiveColor, .inactive)
                default:
                    XCTFail("pressure must render the selected style, including its unknown state")
                }
            }
        }
    }

    func testPressureFooterUsesConfiguredLevelColors() {
        let now = Date(timeIntervalSince1970: 1_000)
        let custom = IconRGBA(red: 0.12, green: 0.34, blue: 0.56, alpha: 1)
        var configuration = IconConfigurationV1.classic
        configuration.behaviors.hardwareRing.color.memoryPressureWarningColor = custom
        let bindings = IconSlotBindingsV1.migrated(from: configuration, bottomIndicatorSource: .metric)
        var sources = IconSourceSnapshot.empty
        sources.hardwareMetrics.memoryPressure = MemoryPressureReading(level: .warning, sampledAt: now)
        let inputs = IconPresentationInputs(snapshot: snapshot(), audioIcon: nil,
                                            sources: sources, bottomIndicatorSource: .metric,
                                            bottomIndicatorMetric: .memoryPressure,
                                            bottomIndicatorStyle: .arc)
        let resolution = IconCompositionResolver.resolve(
            inputs: .init(system: inputs, sources: sources), configuration: configuration,
            now: now, bindings: bindings)
        guard case let .arc(arc)? = resolution.scene.footer else {
            return XCTFail("expected pressure arc")
        }
        XCTAssertEqual(arc.color, .custom(custom))
        XCTAssertEqual(MemoryPressureFooterMapper.color(
            for: .warning, colors: configuration.behaviors.hardwareRing.color), custom)
    }

    func testStalePressureShowsTheEmptyTrackWhileTopRingUsesMemoryUsage() {
        let now = Date(timeIntervalSince1970: 1_000)
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .hardwareMonitor)
        configuration.behaviors.hardwareRing = HardwareRingConfiguration(layout: .single, primaryMetric: .memoryUsage)
        let bindings = IconSlotBindingsV1.migrated(from: configuration, bottomIndicatorSource: .metric)
        var sources = IconSourceSnapshot.empty
        sources.hardwareMetrics.samples[.memoryUsage] = .init(value: 82, unit: .percent,
                                                               sampledAt: now, source: .mach, availability: .measured)
        sources.hardwareMetrics.memoryPressure = .init(level: .normal, sampledAt: now.addingTimeInterval(-9))
        let inputs = IconPresentationInputs(snapshot: snapshot(), audioIcon: nil, sources: sources,
                                            bottomIndicatorSource: .metric, bottomIndicatorMetric: .memoryPressure,
                                            bottomIndicatorStyle: .arc)
        let resolution = IconCompositionResolver.resolve(inputs: .init(system: inputs, sources: sources),
                                                          configuration: configuration, now: now, bindings: bindings)
        XCTAssertEqual(resolution.demand.hardwareMetricIDs, [.memoryUsage, .memoryPressure])
        XCTAssertEqual(resolution.scene.outerRing?.segments.first?.progress ?? 0, 0.82, accuracy: 0.0001)
        guard case let .arc(arc)? = resolution.scene.footer else { return XCTFail("expected the empty pressure arc") }
        XCTAssertEqual(arc.progress, 0)
        XCTAssertEqual(arc.color, .inactive)
    }

    func testMetricFooterWithoutSampleDrawsNothing() {
        let scene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: snapshot(),
                audioIcon: nil,
                bottomIndicatorSource: .metric,
                bottomIndicatorMetric: .gpuUsage
            ),
            configuration: IconPresentationConfiguration(
                battery: .standard, connection: .standard,
                volume: VolumeIconOptions(displayStyle: .arc), bluetooth: .standard))
        XCTAssertNil(scene.footer,
                     "No stale or invented metric reading may be drawn for a missing sample.")
    }

    func testMetricFooterDemandsItsMetricSample() {
        let registry = BuiltinIconPlugins.makeRegistry()
        let binding = IconContentBinding(pluginID: "builtin.hardware-monitor", presentationID: "footer")
        let context = IconContentDependencyContext(
            configuration: IconConfigurationV1.classic,
            targetIsAudio: false,
            bottomIndicatorMetric: .gpuUsage)
        let dependencies = registry.dependencies(for: binding, context: context)
        XCTAssertTrue(dependencies.requiresHardwareMonitor)
        XCTAssertEqual(dependencies.hardwareMetricIDs, [HardwareMetricID.gpuUsage])
    }

    func testMemoryPressureTopMarkerDemandsPressureSample() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .hardwareMonitor)
        configuration.behaviors.hardwareRing = HardwareRingConfiguration(
            layout: .single, primaryMetric: .cpuUsage, topContent: .memoryPressure)
        let registry = BuiltinIconPlugins.makeRegistry()
        let binding = IconContentBinding(pluginID: "builtin.hardware-monitor",
                                         presentationID: "ring")
        let context = IconContentDependencyContext(
            configuration: configuration,
            targetIsAudio: false,
            bottomIndicatorMetric: .cpuUsage)
        let dependencies = registry.dependencies(for: binding, context: context)
        XCTAssertTrue(dependencies.requiresHardwareMonitor)
        XCTAssertTrue(dependencies.hardwareMetricIDs.contains(.memoryPressure))
        XCTAssertTrue(dependencies.hardwareMetricIDs.contains(.cpuUsage))
    }

    func testCompositionResolvesMetricFooterAndDemandsIt() {
        let inputs = IconPresentationInputs(
            snapshot: snapshot(),
            audioIcon: nil,
            sources: metricSource(metric: .cpuUsage, value: 42),
            bottomIndicatorSource: .metric,
            bottomIndicatorMetric: .cpuUsage
        )
        let resolution = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(system: inputs, sources: inputs.sources),
            configuration: .classic,
            bindings: IconSlotBindingsV1.migrated(from: .classic, bottomIndicatorSource: .metric)
        )
        XCTAssertEqual(resolution.scene.bottomIndicatorSource, .metric)
        switch resolution.scene.footer {
        case let .arc(a)?:
            XCTAssertEqual(a.progress, 0.42, accuracy: 0.001)
        case let .dots(d)?:
            XCTAssertEqual(d.activeCount, 2, "0.42 fills two of the four dots")
        default:
            XCTFail("expected the hardware-monitor footer to resolve")
        }
        XCTAssertTrue(resolution.dependencies.requiresHardwareMonitor)
        XCTAssertEqual(resolution.dependencies.hardwareMetricIDs, [HardwareMetricID.cpuUsage])
        XCTAssertEqual(resolution.demand.hardwareMetricIDs, [HardwareMetricID.cpuUsage])
    }

    func testMetricSourceDefaultsToArcStyle() {
        let suite = makeSuite()
        let store = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(store.effectiveBottomIndicatorStyle, .dots,
                       "The volume source keeps its stored dot default.")
        store.bottomIndicatorSource = .metric
        XCTAssertEqual(store.metricBottomIndicatorStyle, .arc,
                       "The metric source defaults to the arc style.")
        XCTAssertEqual(store.effectiveBottomIndicatorStyle, .arc)

        store.metricBottomIndicatorStyle = .dots
        XCTAssertEqual(SettingsStore(defaults: suite.defaults).metricBottomIndicatorStyle, .dots,
                       "A chosen metric style must survive a relaunch.")
        XCTAssertEqual(SettingsStore(defaults: suite.defaults).volumeDisplayStyle, .dots,
                       "Changing the metric style must not restyle the volume source.")
    }

    func testCompositionHonoursMetricArcStyle() {
        let inputs = IconPresentationInputs(
            snapshot: snapshot(),
            audioIcon: nil,
            sources: metricSource(metric: .cpuUsage, value: 42),
            bottomIndicatorSource: .metric,
            bottomIndicatorMetric: .cpuUsage,
            bottomIndicatorStyle: .arc
        )
        let resolution = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(system: inputs, sources: inputs.sources),
            configuration: .classic,
            bindings: IconSlotBindingsV1.migrated(from: .classic, bottomIndicatorSource: .metric)
        )
        guard case let .arc(a)? = resolution.scene.footer else {
            return XCTFail("expected the metric footer to honour the arc style")
        }
        XCTAssertEqual(a.progress, 0.42, accuracy: 0.001)
    }

    /// End-to-end through the real runtime wiring: the store's computed runtime
    /// options (what AppEnvironment feeds the resolver) must carry the metric's
    /// own arc style into the resolved footer.
    func testRuntimeOptionsCarryMetricArcIntoComposition() {
        let suite = makeSuite()
        let store = SettingsStore(defaults: suite.defaults)
        store.bottomIndicatorSource = .metric
        store.bottomIndicatorMetric = .cpuUsage

        let runtime = store.iconRuntimePresentationOptions
        XCTAssertEqual(runtime.bottomIndicatorSource, .metric)
        XCTAssertEqual(runtime.bottomIndicatorStyle, .arc)

        var inputs = IconPresentationResourceResolver.inputs(
            snapshot: snapshot(), runtimeOptions: runtime)
        inputs.sources = metricSource(metric: .cpuUsage, value: 42)

        let resolution = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(system: inputs, sources: inputs.sources),
            configuration: .classic,
            bindings: IconSlotBindingsV1.migrated(from: .classic, bottomIndicatorSource: .metric)
        )
        guard case let .arc(a)? = resolution.scene.footer else {
            return XCTFail("expected the live runtime path to draw the arc metric footer")
        }
        XCTAssertEqual(a.progress, 0.42, accuracy: 0.001)

        // A user picking dots for the metric must flow through as dots too.
        store.metricBottomIndicatorStyle = .dots
        let dotRuntime = store.iconRuntimePresentationOptions
        XCTAssertEqual(dotRuntime.bottomIndicatorStyle, .dots)
    }

    /// Regression: the view model used to rebuild the resolution inputs and drop
    /// the metric + style fields, so the live icon fell back to CPU usage + dots
    /// even after the settings page switched to arc. resolvedInputs must carry
    /// them through from the published runtime options.
    func testResolvedInputsCarryMetricFields() {
        let suite = makeSuite()
        let store = SettingsStore(defaults: suite.defaults)
        store.bottomIndicatorSource = .metric
        store.bottomIndicatorMetric = .gpuUsage
        // default metric style is arc

        let inputs = IconPresentationViewModel.resolvedInputs(
            snapshot: snapshot(),
            inputSource: nil,
            systemPower: nil,
            isHighPowerMode: false,
            settingsRuntimeOptions: store.iconRuntimePresentationOptions,
            hardwareMetricColors: [:],
            hardwareDownloadCapMbps: 1000,
            hardwareUploadCapMbps: 100,
            resolveInputs: { snapshot in IconPresentationResourceResolver.inputs(snapshot: snapshot) }
        )
        XCTAssertEqual(inputs.bottomIndicatorSource, .metric)
        XCTAssertEqual(inputs.bottomIndicatorMetric, .gpuUsage)
        XCTAssertEqual(inputs.bottomIndicatorStyle, .arc)
    }

    func testEachBottomSourceKeepsItsOwnStyle() {
        let suite = makeSuite()
        let store = SettingsStore(defaults: suite.defaults)

        store.bottomIndicatorSource = .wifi
        store.wifiBottomIndicatorStyle = .arc
        store.bottomIndicatorSource = .battery
        XCTAssertEqual(store.effectiveBottomIndicatorStyle, .dots,
                       "Changing the Wi-Fi style must not touch the battery style.")
        store.batteryBottomIndicatorStyle = .arc
        store.bottomIndicatorSource = .volume
        XCTAssertEqual(store.effectiveBottomIndicatorStyle, .dots)
        store.bottomIndicatorSource = .metric
        XCTAssertEqual(store.effectiveBottomIndicatorStyle, .arc)

        let reopened = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(reopened.wifiBottomIndicatorStyle, .arc)
        XCTAssertEqual(reopened.batteryBottomIndicatorStyle, .arc)
        XCTAssertEqual(reopened.volumeDisplayStyle, .dots)
        XCTAssertEqual(reopened.metricBottomIndicatorStyle, .arc)
    }

    /// The Wi-Fi and battery sources each render with their own style through
    /// the live resolver (legacy volume style is driven by the runtime options).
    func testWifiSourceRendersItsOwnArcStyle() {
        let suite = makeSuite()
        let store = SettingsStore(defaults: suite.defaults)
        store.bottomIndicatorSource = .wifi
        store.wifiBottomIndicatorStyle = .arc

        let inputs = IconPresentationResourceResolver.inputs(
            snapshot: snapshot(), runtimeOptions: store.iconRuntimePresentationOptions)
        let resolution = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(system: inputs, sources: inputs.sources),
            configuration: .classic,
            bindings: IconSlotBindingsV1.migrated(from: .classic, bottomIndicatorSource: .wifi)
        )
        guard case .arc? = resolution.scene.footer else {
            return XCTFail("Wi-Fi should draw its own arc style, independent of the volume default")
        }
    }

    func testBluetoothVolumeColorDefaultsToAutomatic() {
        let suite = makeSuite()
        let store = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(store.bluetoothVolumeColor, .automatic)
        let custom = IconRGBA(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)
        store.bluetoothVolumeColor = .custom(custom)
        XCTAssertEqual(SettingsStore(defaults: suite.defaults).bluetoothVolumeColor, .custom(custom))
    }

    func testLegacyBluetoothBlueMigratesToBluePreset() {
        let suite = makeSuite()
        suite.defaults.set(true, forKey: SettingsStore.usesBluetoothAudioVolumeColorDefaultsKey)
        let store = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(store.bluetoothVolumeColor,
                       .custom(BluetoothVolumeColorSelection.legacyBlue))
        XCTAssertEqual(store.bluetoothAudioIconOptions.volumeColorRole,
                       .custom(BluetoothVolumeColorSelection.legacyBlue))
    }

    func testBluetoothVolumeColorTintsTheFooter() {
        let custom = IconRGBA(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)
        let device = bluetoothDevice()
        let volume = VolumeStatus(scalar: 0.5, isMuted: false,
                                  deviceName: device.name, currentDevice: device)
        let scene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: snapshot(volume: volume),
                audioIcon: nil,
                bottomIndicatorSource: .volume
            ),
            configuration: IconPresentationConfiguration(
                battery: .standard,
                connection: .standard,
                volume: VolumeIconOptions(displayStyle: .dots),
                bluetooth: BluetoothAudioIconOptions(
                    usesVolumeColor: true, volumeColorRole: .custom(custom))
            )
        )
        guard case let .dots(d)? = scene.footer else { return XCTFail("expected dots footer") }
        XCTAssertEqual(d.color, .custom(custom))
    }

    /// Regression: a custom Bluetooth volume colour must reach the live footer
    /// through the runtime options (the resolver legacy projection is otherwise
    /// blind to it).
    func testBluetoothVolumeColorFlowsThroughRuntimeIntoFooter() {
        let suite = makeSuite()
        let store = SettingsStore(defaults: suite.defaults)
        let custom = IconRGBA(red: 0.15, green: 0.55, blue: 0.35, alpha: 1)
        store.bluetoothVolumeColor = .custom(custom)

        let runtime = store.iconRuntimePresentationOptions
        XCTAssertEqual(runtime.bluetoothVolumeColorRole, .custom(custom))

        let device = bluetoothDevice()
        let volume = VolumeStatus(scalar: 0.5, isMuted: false,
                                  deviceName: device.name, currentDevice: device)
        let inputs = IconPresentationResourceResolver.inputs(
            snapshot: snapshot(volume: volume), runtimeOptions: runtime)
        let resolution = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(system: inputs, sources: inputs.sources),
            configuration: .classic,
            bindings: IconSlotBindingsV1.migrated(from: .classic, bottomIndicatorSource: .volume)
        )
        guard case let .dots(d)? = resolution.scene.footer else {
            return XCTFail("expected the volume footer to resolve")
        }
        XCTAssertEqual(d.color, .custom(custom))
    }

    func testHiddenThenMetricRestoresFooterBindingAndScene() {
        let suite = makeSuite()
        let store = SettingsStore(defaults: suite.defaults)
        store.bottomIndicatorSource = .hidden
        store.bottomIndicatorSource = .metric
        store.bottomIndicatorMetric = .cpuUsage

        let appearance = StatusIconAppearance(settings: store)
        let bindings = store.effectiveIconSlotBindings(
            appearance: appearance,
            inputSourceMarkerStyle: store.inputSourceMarkerStyle,
            bottomIndicatorSource: store.bottomIndicatorSource,
            bottomIndicatorMetric: store.bottomIndicatorMetric)
        XCTAssertEqual(bindings.footer.primary,
                       IconContentBinding(pluginID: "builtin.hardware-monitor",
                                          presentationID: "footer"))

        var inputs = IconPresentationResourceResolver.inputs(
            snapshot: snapshot(), runtimeOptions: store.iconRuntimePresentationOptions)
        inputs.sources = metricSource(metric: .cpuUsage, value: 42)
        let resolution = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(system: inputs, sources: inputs.sources),
            configuration: .classic,
            bindings: bindings)
        XCTAssertNotNil(resolution.scene.footer, "metric footer must draw after hidden")
    }

    /// The published settings (what the live view model consumes) must carry a
    /// bound footer after Hidden → metric, not just the on-demand derivation.
    func testSwitchingHiddenThenMetricPublishesBoundFooter() {
        let suite = makeSuite()
        let store = SettingsStore(defaults: suite.defaults)
        var latest: IconPresentationSettings?
        let cancellable = store.iconPresentationPublisher.sink { latest = $0 }
        defer { cancellable.cancel() }

        store.bottomIndicatorSource = .hidden
        store.bottomIndicatorSource = .metric
        XCTAssertEqual(
            latest?.slotBindings?.footer.primary,
            IconContentBinding(pluginID: "builtin.hardware-monitor", presentationID: "footer")
        )
    }

    /// The published settings and the resolver they drive must turn a custom
    /// Bluetooth volume colour into a custom-colour footer, matching the live
    /// menu-bar icon path.
    func testPublishedSettingsDriveCustomBluetoothFooter() throws {
        let suite = makeSuite()
        let store = SettingsStore(defaults: suite.defaults)
        store.bottomIndicatorSource = .volume
        var latest: IconPresentationSettings?
        let cancellable = store.iconPresentationPublisher.sink { latest = $0 }
        defer { cancellable.cancel() }

        let custom = IconRGBA(red: 0.9, green: 0.3, blue: 0.55, alpha: 1)
        store.bluetoothVolumeColor = .custom(custom)

        let settings = try XCTUnwrap(latest)
        XCTAssertEqual(settings.runtimeOptions?.bluetoothVolumeColorRole, .custom(custom))

        let device = bluetoothDevice()
        let volume = VolumeStatus(scalar: 0.5, isMuted: false,
                                  deviceName: device.name, currentDevice: device)
        let inputs = IconPresentationResourceResolver.inputs(
            snapshot: snapshot(volume: volume), runtimeOptions: settings.runtimeOptions)
        let resolution = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(system: inputs, sources: inputs.sources),
            configuration: settings.iconConfiguration,
            bindings: settings.slotBindings)
        guard case let .dots(d)? = resolution.scene.footer else {
            return XCTFail("expected volume footer")
        }
        XCTAssertEqual(d.color, .custom(custom))
    }

    func testUpgradeSeedsIndependentStylesFromTheLegacySharedArc() {
        let suite = makeSuite()
        suite.defaults.set("arc", forKey: SettingsStore.volumeDisplayStyleDefaultsKey)
        suite.defaults.set("wifi", forKey: SettingsStore.bottomIndicatorSourceDefaultsKey)
        let store = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(store.effectiveBottomIndicatorStyle, .arc)
        XCTAssertEqual(store.batteryBottomIndicatorStyle, .arc)
        XCTAssertEqual(store.metricBottomIndicatorStyle, .arc)

        store.volumeDisplayStyle = .dots
        store.wifiBottomIndicatorStyle = .dots
        let reopened = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(reopened.wifiBottomIndicatorStyle, .dots)
        XCTAssertEqual(reopened.batteryBottomIndicatorStyle, .arc,
                       "Changing volume must not overwrite the migrated battery style on relaunch")
    }

    func testDisablingTemperaturePublishesAndPersistsTheMatchingUsageFooter() {
        for (temperature, usage): (BottomIndicatorMetric, BottomIndicatorMetric) in [
            (.cpuTemperature, .cpuUsage), (.gpuTemperature, .gpuUsage)
        ] {
            let suite = makeSuite()
            let store = SettingsStore(defaults: suite.defaults)
            store.bottomIndicatorSource = .metric
            store.bottomIndicatorMetric = temperature
            var latest: IconPresentationSettings?
            let observation = store.iconPresentationPublisher.sink { latest = $0 }
            store.hardwareTemperatureMonitoringEnabled = false
            XCTAssertEqual(store.bottomIndicatorMetric, usage)
            XCTAssertEqual(latest?.runtimeOptions?.bottomIndicatorMetric, usage)
            store.hardwareTemperatureMonitoringEnabled = true
            XCTAssertEqual(store.bottomIndicatorMetric, usage)
            XCTAssertEqual(SettingsStore(defaults: suite.defaults).bottomIndicatorMetric, usage)
            withExtendedLifetime(observation) {}
        }
    }

    func testStartupRepairsAnUnavailableSavedFooterTemperature() {
        let suite = makeSuite()
        suite.defaults.set(false, forKey: SettingsStore.hardwareTemperatureMonitoringEnabledDefaultsKey)
        suite.defaults.set("gpuTemperature", forKey: SettingsStore.bottomIndicatorMetricDefaultsKey)
        let store = SettingsStore(defaults: suite.defaults, systemChargeLimit: { nil })
        XCTAssertEqual(store.bottomIndicatorMetric, .gpuUsage)
        XCTAssertEqual(suite.defaults.string(forKey: SettingsStore.bottomIndicatorMetricDefaultsKey), "gpuUsage")
    }
}
