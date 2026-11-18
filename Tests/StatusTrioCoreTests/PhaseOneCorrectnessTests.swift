import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class PhaseOneCorrectnessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - 1.1 snapshot publish order

    func testSubscriberReadsUpdatedSnapshotNotPreviousValue() {
        let observable = HardwareMonitorObservable()
        var delivered: HardwareMetricsSnapshot?
        var readBack: HardwareMetricsSnapshot?
        let cancellable = observable.snapshotPublisher.sink { value in
            delivered = value
            readBack = observable.snapshot
        }
        defer { cancellable.cancel() }

        var snapshot = HardwareMetricsSnapshot()
        snapshot.samples[.cpuUsage] = HardwareMetricSample(
            value: 42, unit: .percent, sampledAt: now, source: .mach, availability: .measured)
        observable.update(snapshot, now: now)

        XCTAssertEqual(delivered?.cpuUsage.value, 42)
        XCTAssertEqual(readBack?.cpuUsage.value, 42,
                       "synchronous subscriber must read the same snapshot it was handed")
    }

    // MARK: - 1.2 colour / cap sync through the appearance publishers

    private func makeStore() throws -> SettingsStore {
        let name = "StatusTrioCoreTests.PhaseOne.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return SettingsStore(defaults: defaults)
    }

    func testColorEditImmediatelyPublishedToIconSettings() throws {
        let store = try makeStore()
        var latest: IconPresentationSettings?
        let cancellable = store.iconPresentationPublisher.sink { latest = $0 }
        defer { cancellable.cancel() }

        let magenta = IconRGBA(red: 1, green: 0, blue: 1, alpha: 1)
        store.setHardwareColor(magenta, for: .cpuUsage)

        XCTAssertEqual(latest?.hardwareMetricColors[.cpuUsage], magenta)
    }

    func testSpeedCapEditImmediatelyPublished() throws {
        let store = try makeStore()
        var latest: IconPresentationSettings?
        let cancellable = store.iconPresentationPublisher.sink { latest = $0 }
        defer { cancellable.cancel() }

        store.hardwareDownloadCapMbps = 500
        XCTAssertEqual(latest?.hardwareDownloadCapMbps, 500)
    }

    // MARK: - 1.3 top marker geometry stability

    func testTopValueKeepsGapWhenDataUnavailableThenRecovers() {
        let configuration = HardwareRingConfiguration(
            layout: .single, primaryMetric: .cpuUsage, topContent: .value(.cpuUsage),
            color: HardwareRingColorConfiguration(monochrome: false, thresholdColors: true))

        let empty = HardwareRingMapper.resolve(snapshot: .empty, configuration: configuration, now: now)
        guard case let .text(unavailable)? = empty.accessory else { return XCTFail("placeholder text expected") }
        XCTAssertEqual(unavailable.text, "--")
        XCTAssertEqual(empty.gap, .value)

        var snapshot = HardwareMetricsSnapshot()
        snapshot.samples[.cpuUsage] = HardwareMetricSample(
            value: 45, unit: .percent, sampledAt: now, source: .mach, availability: .measured)
        let recovered = HardwareRingMapper.resolve(snapshot: snapshot, configuration: configuration, now: now)
        guard case let .text(value)? = recovered.accessory else { return XCTFail("value text expected") }
        XCTAssertEqual(value.text, "45")
        XCTAssertEqual(recovered.gap, .value, "gap must not change when data recovers")
        XCTAssertEqual(recovered.segments[0].progress, 0.45, accuracy: 0.0001)
    }

    func testDualTopValueKeepsAccessoryWhenDataUnavailable() {
        let configuration = HardwareRingConfiguration(
            layout: .dual, primaryMetric: .cpuUsage, secondaryMetric: .gpuUsage,
            topContent: .value(.cpuUsage),
            color: HardwareRingColorConfiguration(monochrome: false, thresholdColors: true))
        let state = HardwareRingMapper.resolve(snapshot: .empty, configuration: configuration, now: now)
        guard case let .text(text)? = state.accessory else { return XCTFail("placeholder text expected") }
        XCTAssertEqual(text.text, "--")
        XCTAssertEqual(state.layout, .leftRight)
    }

    // MARK: - Phase 2 demand lifecycle

    func testHardwareRingDemandsFollowPlacementAndFallback() {
        var config = IconConfigurationV1.classic
        config.composition.outerRing = SlotSelection(primary: .hardwareMonitor)
        config.behaviors.hardwareRing = HardwareRingConfiguration(
            layout: .dual, primaryMetric: .cpuUsage, secondaryMetric: .gpuUsage)

        let dockOnly = IconSourceDemandPolicy.hardwareRingDemands(configuration: config, placement: .dock)
        XCTAssertNil(dockOnly.menuBar)
        XCTAssertEqual(dockOnly.dock, Set([HardwareMetricID.cpuUsage, .gpuUsage]))

        let menuOnly = IconSourceDemandPolicy.hardwareRingDemands(configuration: config, placement: .menuBar)
        XCTAssertNotNil(menuOnly.menuBar)
        XCTAssertNil(menuOnly.dock)

        let both = IconSourceDemandPolicy.hardwareRingDemands(configuration: config, placement: .both)
        XCTAssertNotNil(both.menuBar)
        XCTAssertNotNil(both.dock)

        // Non-hardware source: no demand.
        var battery = IconConfigurationV1.classic
        battery.composition.outerRing = SlotSelection(primary: .systemBattery)
        XCTAssertEqual(IconSourceDemandPolicy.hardwareRingDemands(configuration: battery, placement: .both), .none)

        // Hardware as fallback keeps the demand warm for the switch.
        var fallback = IconConfigurationV1.classic
        fallback.composition.outerRing = SlotSelection(primary: .systemBattery, fallback: .hardwareMonitor)
        fallback.behaviors.hardwareRing = config.behaviors.hardwareRing
        XCTAssertNotNil(IconSourceDemandPolicy.hardwareRingDemands(configuration: fallback, placement: .menuBar).menuBar)
    }


    func testStatusPanelBoldTextDefaultsOffAndPersists() throws {
        let store = try makeStore()
        XCTAssertFalse(store.statusPanelBoldTextEnabled)
        store.statusPanelBoldTextEnabled = false
        let name = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "StatusTrioCoreTests.Bold.\(name)"))
        defaults.removePersistentDomain(forName: "StatusTrioCoreTests.Bold.\(name)")
        addTeardownBlock { defaults.removePersistentDomain(forName: "StatusTrioCoreTests.Bold.\(name)") }
        let first = SettingsStore(defaults: defaults)
        first.statusPanelBoldTextEnabled = false
        XCTAssertFalse(SettingsStore(defaults: defaults).statusPanelBoldTextEnabled)
    }


    func testPanelTextWeightAndKeepOpenSettingsDefaultsAndPersist() throws {
        let name = "StatusTrioCoreTests.PanelText.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let first = SettingsStore(defaults: defaults)
        XCTAssertFalse(first.statusPanelBoldTextEnabled)
        XCTAssertTrue(first.statusPanelMediumTextEnabled)
        XCTAssertFalse(first.keepsPanelOpenWhenOpeningSettings)
        first.statusPanelMediumTextEnabled = false
        first.keepsPanelOpenWhenOpeningSettings = true
        let reopened = SettingsStore(defaults: defaults)
        XCTAssertFalse(reopened.statusPanelMediumTextEnabled)
        XCTAssertTrue(reopened.keepsPanelOpenWhenOpeningSettings)
    }
}
