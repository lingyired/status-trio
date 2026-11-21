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

    func testHardwareRingDemandsFollowPlacementAndSelectedSource() {
        var config = IconConfigurationV1.classic
        config.composition.outerRing = SlotSelection(primary: .hardwareMonitor)
        config.behaviors.hardwareRing = HardwareRingConfiguration(
            layout: .dual, primaryMetric: .cpuUsage, secondaryMetric: .gpuUsage)

        let dockOnly = IconSourceDemandPolicy.hardwareRingDemands(
            configuration: config, placement: .dock, isHardwareRingSelected: true)
        XCTAssertNil(dockOnly.menuBar)
        XCTAssertEqual(dockOnly.dock, Set([HardwareMetricID.cpuUsage, .gpuUsage]))

        let menuOnly = IconSourceDemandPolicy.hardwareRingDemands(
            configuration: config, placement: .menuBar, isHardwareRingSelected: true)
        XCTAssertNotNil(menuOnly.menuBar)
        XCTAssertNil(menuOnly.dock)

        let both = IconSourceDemandPolicy.hardwareRingDemands(
            configuration: config, placement: .both, isHardwareRingSelected: true)
        XCTAssertNotNil(both.menuBar)
        XCTAssertNotNil(both.dock)

        // A configured-but-not-selected hardware ring (e.g. only a fallback
        // while another source is on screen) must not start the sampler.
        XCTAssertEqual(IconSourceDemandPolicy.hardwareRingDemands(
            configuration: config, placement: .both, isHardwareRingSelected: false), .none)

        // Non-hardware source: no demand even if a stale selection flag is set.
        var battery = IconConfigurationV1.classic
        battery.composition.outerRing = SlotSelection(primary: .systemBattery)
        XCTAssertEqual(IconSourceDemandPolicy.hardwareRingDemands(
            configuration: battery, placement: .both, isHardwareRingSelected: false), .none)

        // The fallback activates only when the selected source says so, and then
        // demands exactly its configured metrics.
        var fallback = IconConfigurationV1.classic
        fallback.composition.outerRing = SlotSelection(primary: .systemBattery, fallback: .hardwareMonitor)
        fallback.behaviors.hardwareRing = config.behaviors.hardwareRing
        XCTAssertEqual(IconSourceDemandPolicy.hardwareRingDemands(
            configuration: fallback, placement: .menuBar, isHardwareRingSelected: false), .none)
        XCTAssertNotNil(IconSourceDemandPolicy.hardwareRingDemands(
            configuration: fallback, placement: .menuBar, isHardwareRingSelected: true).menuBar)
    }

    func testVolumeOrWifiOnlyRingDemandsNoHardwareSampling() {
        var config = IconConfigurationV1.classic
        config.composition.outerRing = SlotSelection(primary: .hardwareMonitor)
        config.behaviors.hardwareRing = HardwareRingConfiguration(
            layout: .single, primaryMetric: .volume, secondaryMetric: nil)
        XCTAssertEqual(IconSourceDemandPolicy.hardwareRingDemands(
            configuration: config, placement: .both, isHardwareRingSelected: true), .none)

        config.behaviors.hardwareRing = HardwareRingConfiguration(
            layout: .single, primaryMetric: .wifiSignal, secondaryMetric: nil)
        XCTAssertEqual(IconSourceDemandPolicy.hardwareRingDemands(
            configuration: config, placement: .both, isHardwareRingSelected: true), .none)

        // A mixed CPU + volume ring demands only CPU.
        config.behaviors.hardwareRing = HardwareRingConfiguration(
            layout: .dual, primaryMetric: .cpuUsage, secondaryMetric: .volume)
        XCTAssertEqual(IconSourceDemandPolicy.hardwareRingDemands(
            configuration: config, placement: .both, isHardwareRingSelected: true).dock,
            Set([HardwareMetricID.cpuUsage]))
    }

    /// The icon scene is built from the live, appearance-derived configuration.
    /// The persisted `settings.iconConfiguration` snapshot is only rewritten by
    /// the editor API, so a ring metric chosen on the settings surface (a dual
    /// CPU + memory ring here) is absent from it. Demand must follow the live
    /// configuration; reading the snapshot would prune memory back to CPU-only on
    /// the first icon tick, leaving the memory arc blank until the panel reopened.
    func testHardwareRingDemandFollowsLiveConfigurationNotPersistedSnapshot() throws {
        let store = try makeStore()
        store.hardwareRingConfiguration = HardwareRingConfiguration(
            layout: .dual, primaryMetric: .cpuUsage, secondaryMetric: .memoryUsage)

        var live: IconPresentationSettings?
        let cancellable = store.iconPresentationPublisher.sink { live = $0 }
        defer { cancellable.cancel() }

        let liveConfiguration = try XCTUnwrap(live?.iconConfiguration)
        let liveDemands = IconSourceDemandPolicy.hardwareRingDemands(
            configuration: liveConfiguration, placement: .menuBar, isHardwareRingSelected: true)
        XCTAssertEqual(liveDemands.menuBar, Set([HardwareMetricID.cpuUsage, .memoryUsage]),
                       "demand must follow the live presentation configuration")

        let staleDemands = IconSourceDemandPolicy.hardwareRingDemands(
            configuration: store.iconConfiguration, placement: .menuBar, isHardwareRingSelected: true)
        XCTAssertEqual(staleDemands.menuBar, Set([HardwareMetricID.cpuUsage]),
                       "the persisted snapshot still looks CPU-only; demand must not read it")
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

    /// The single "Bold panel text" switch must move both weight tiers together
    /// so "on" restores the classic bold + medium look and "off" is all regular.
    func testBoldPanelTextToggleDrivesBothBoldAndMediumTiers() throws {
        let store = try makeStore()
        XCTAssertFalse(store.statusPanelBoldTextEnabled, "defaults to the current regular look")

        store.applyPanelBoldTextToggle(true)
        XCTAssertTrue(store.statusPanelBoldTextEnabled)
        XCTAssertTrue(store.statusPanelMediumTextEnabled)

        store.applyPanelBoldTextToggle(false)
        XCTAssertFalse(store.statusPanelBoldTextEnabled)
        XCTAssertFalse(store.statusPanelMediumTextEnabled)
    }
}
