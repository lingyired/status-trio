import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class HardwareRingSettingsTests: XCTestCase {
    private func makeStore() throws -> (SettingsStore, UserDefaults, String) {
        let name = "StatusTrioCoreTests.HardwareRing.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return (SettingsStore(defaults: defaults), defaults, name)
    }

    private var dualConfig: HardwareRingConfiguration {
        HardwareRingConfiguration(
            layout: .dual,
            primaryMetric: .cpuUsage,
            secondaryMetric: .gpuUsage,
            topContent: .value(.cpuTemperature),
            color: HardwareRingColorConfiguration(mode: .status)
        )
    }

    func testHardwareRingConfigurationPersists() throws {
        let (store, defaults, _) = try makeStore()
        store.hardwareRingConfiguration = dualConfig
        let reopened = SettingsStore(defaults: defaults)
        XCTAssertEqual(reopened.hardwareRingConfiguration, dualConfig.normalized())
    }

    func testDerivedConfigurationProjectsHardwareMonitorSource() throws {
        let (store, _, _) = try makeStore()
        store.outerRingContent = .hardwareMonitor
        store.hardwareRingConfiguration = dualConfig
        let derived = store.derivedIconConfigurationFromSettings()
        XCTAssertEqual(derived.composition.outerRing.primary, .hardwareMonitor)
        XCTAssertEqual(derived.behaviors.hardwareRing, dualConfig.normalized())
    }

    func testDefaultIsSystemBatteryEvenWithHardwareConfigStored() throws {
        let (store, _, _) = try makeStore()
        store.hardwareRingConfiguration = dualConfig
        let derived = store.derivedIconConfigurationFromSettings()
        XCTAssertEqual(derived.composition.outerRing.primary, .systemBattery)
    }

    // MARK: - Plugin / dependency wiring

    func testRegistryExposesHardwareMonitorRingPresentation() {
        let options = BuiltinIconPlugins.makeRegistry().presentations(for: .outerRing)
        XCTAssertTrue(options.contains { $0.binding.pluginID == "builtin.hardware-monitor" })
    }

    func testLegacyAdapterMapsHardwareMonitorSource() {
        let binding = IconContentLegacyAdapter.binding(for: RingSource.hardwareMonitor)
        XCTAssertEqual(binding?.pluginID, "builtin.hardware-monitor")
        XCTAssertEqual(IconContentLegacyAdapter.ringSource(for: binding!), .hardwareMonitor)
    }

    func testDependenciesDeclareHardwareMetrics() {
        var config = IconConfigurationV1.classic
        config.composition.outerRing = SlotSelection(primary: .hardwareMonitor)
        config.behaviors.hardwareRing = dualConfig
        let dependencies = IconContentDependencyResolver.dependencies(configuration: config, targetIsAudio: false)
        XCTAssertTrue(dependencies.requiresHardwareMonitor)
        XCTAssertTrue(dependencies.samples.contains(.hardwareMonitor))
        XCTAssertEqual(dependencies.hardwareMetricIDs,
                       Set([HardwareMonitorMetric.cpuUsage.metricID,
                            HardwareMonitorMetric.gpuUsage.metricID,
                            HardwareMonitorMetric.cpuTemperature.metricID]))
    }

    func testResolvesTrackOnlyRingWhenSnapshotEmpty() {
        var config = IconConfigurationV1.classic
        config.composition.outerRing = SlotSelection(primary: .hardwareMonitor)
        config.behaviors.hardwareRing = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage)
        var inputs = IconPreviewInputBuilder.simulated(
            samples: IconPreviewSampleValues(),
            configuration: config,
            target: .currentAudioOutput,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        inputs.sources.hardwareMetrics = .empty
        let output = IconCompositionResolver.resolve(inputs: inputs, configuration: config,
                                                      now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertNotNil(output.scene.outerRing)
        XCTAssertEqual(output.trace.outerRing.selectedSourceID, RingSource.hardwareMonitor.rawValue)
        XCTAssertEqual(output.scene.outerRing?.segments.first?.color, .inactive)
    }

    func testMetricColorsPersistAndShareOneField() throws {
        let (store, defaults, _) = try makeStore()
        XCTAssertEqual(store.hardwareColor(for: .cpuUsage),
                       HardwareRingColorConfiguration.recommendedBaseColor(for: .cpuUsage))
        let custom = IconRGBA(red: 1, green: 0, blue: 1, alpha: 1)
        store.setHardwareColor(custom, for: .cpuUsage)
        XCTAssertEqual(store.hardwareColor(for: .cpuUsage), custom)

        let reopened = SettingsStore(defaults: defaults)
        XCTAssertEqual(reopened.hardwareColor(for: .cpuUsage), custom)
        // Other metrics keep the recommended default until edited.
        XCTAssertEqual(reopened.hardwareColor(for: .gpuUsage),
                       HardwareRingColorConfiguration.recommendedBaseColor(for: .gpuUsage))
    }

    func testRingResolverUsesSharedMetricColor() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var config = IconConfigurationV1.classic
        config.composition.outerRing = SlotSelection(primary: .hardwareMonitor)
        config.behaviors.hardwareRing = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage,
                                                                  color: HardwareRingColorConfiguration(mode: .status))
        let custom = IconRGBA(red: 1, green: 0, blue: 1, alpha: 1)
        let inputs = IconPreviewInputBuilder.simulated(
            samples: IconPreviewSampleValues(),
            configuration: config,
            target: .currentAudioOutput,
            now: now,
            hardwareMetricColors: [.cpuUsage: custom]
        )
        let output = IconCompositionResolver.resolve(inputs: inputs, configuration: config, now: now)
        XCTAssertEqual(output.scene.outerRing?.segments.first?.color, .custom(custom))
    }

    func testCardTilesUseSharedMetricColor() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = HardwareMetricsSnapshot()
        snapshot.samples = [
            .cpuUsage: HardwareMetricSample(value: 45, unit: .percent, sampledAt: now,
                                            source: .mach, availability: .measured)
        ]
        let custom = IconRGBA(red: 1, green: 0, blue: 1, alpha: 1)
        let tiles = HardwareMetricTilePresentation.tiles(
            metrics: [.cpuUsage], snapshot: snapshot, localization: Localization(),
            colors: [.cpuUsage: custom]
        )
        XCTAssertEqual(tiles.first?.tint, custom)
    }

    // MARK: - Integration: dual ring + palette precedence

    func testDualHardwareRingSceneAndPalettePrecedence() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var config = IconConfigurationV1.classic
        config.composition.outerRing = SlotSelection(primary: .hardwareMonitor)
        config.behaviors.hardwareRing = dualConfig
        // A battery-ring fixed colour must not override the hardware segment colours.
        config.appearance.outerRing.color = .fixed(IconRGBA(red: 1, green: 0, blue: 0, alpha: 1))

        let inputs = IconPreviewInputBuilder.simulated(
            samples: IconPreviewSampleValues(),
            configuration: config,
            target: .currentAudioOutput,
            now: now
        )
        let output = IconCompositionResolver.resolve(inputs: inputs, configuration: config, now: now)
        let ring = try! XCTUnwrap(output.scene.outerRing)
        XCTAssertEqual(ring.layout, .leftRight)
        XCTAssertEqual(ring.segments.count, 2)
        XCTAssertEqual(Set(ring.segments.compactMap(\.position)), Set([.left, .right]))
        // hardware colours (green left / blue right) survive, red fixed colour is ignored.
        XCTAssertEqual(ring.segments.first { $0.position == .left }?.color,
                       .custom(HardwareRingColorConfiguration.recommendedBaseColor(for: .cpuUsage)))
        XCTAssertEqual(ring.segments.first { $0.position == .right }?.color,
                       .custom(HardwareRingColorConfiguration.recommendedBaseColor(for: .gpuUsage)))
    }

    func testSharedTopMarkerScaleProjectsToBatteryAndHardware() throws {
        let (store, _, _) = try makeStore()
        store.batterySymbolScale = 1.3
        store.outerRingContent = .hardwareMonitor
        let derived = store.derivedIconConfigurationFromSettings()
        XCTAssertEqual(derived.behaviors.systemBatteryRing.textScale,
                       1.3 * BatteryIconOptions.defaultTextScale, accuracy: 0.001)
        XCTAssertEqual(derived.behaviors.hardwareRing.topMarkerScale, 1.3, accuracy: 0.001)
    }

    func testAirPodsTopSymbolUsesSharedScale() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = AirPodsBatteryIconSnapshot(
            deviceAddress: "AA:BB:CC:DD:EE:FF", model: .airPodsPro,
            main: nil, left: 80, right: 60, caseLevel: nil, observedAt: now
        )
        let state = AirPodsRingMapper.resolve(
            snapshot: snapshot, behavior: .dual, now: now,
            showsTopSymbol: true, topSymbolScale: 2.34
        )
        guard case let .symbol(symbol)? = state?.accessory else { return XCTFail("expected symbol") }
        XCTAssertEqual(symbol.scale, 2.34, accuracy: 0.001)
    }
}
