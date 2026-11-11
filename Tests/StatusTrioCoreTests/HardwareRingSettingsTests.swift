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
}
