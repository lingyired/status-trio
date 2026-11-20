import Combine
import XCTest
@testable import StatusTrioCore

/// Integration coverage for the production demand path: the live settings
/// publisher feeds the icon scene resolver, the icon output changes the selected
/// outer-ring source, and the demand wiring must keep sampling the metrics the
/// live configuration actually draws.
@MainActor
final class IconLiveDemandIntegrationTests: XCTestCase {
    func testLiveConfigurationKeepsDualHardwareRingDemandAfterIconOutput() throws {
        let settings = try makeSettings()
        settings.outerRingContent = .hardwareMonitor
        settings.hardwareRingConfiguration = HardwareRingConfiguration(
            layout: .dual, primaryMetric: .cpuUsage, secondaryMetric: .memoryUsage)
        settings.appIconPlacement = .both

        let harness = try makeHarness(settings: settings)
        defer { harness.stop() }

        XCTAssertEqual(
            harness.demands.value.last,
            IconSourceDemandPolicy.HardwareRingDemands(
                menuBar: [.cpuUsage, .memoryUsage],
                dock: [.cpuUsage, .memoryUsage]
            ),
            "demand must follow the live configuration even when the persisted V1 payload is still CPU-only"
        )
        XCTAssertEqual(settings.iconConfiguration.composition.outerRing.primary, .automaticLegacy,
                       "precondition: the persisted editor snapshot is stale on purpose")

        // Hide one surface: only that surface's demand is released.
        settings.appIconPlacement = .menuBar
        XCTAssertEqual(
            harness.demands.value.last,
            IconSourceDemandPolicy.HardwareRingDemands(
                menuBar: [.cpuUsage, .memoryUsage],
                dock: nil
            )
        )

        // A later demand reconcile must not prune memory back to the persisted
        // CPU-only set.
        harness.refreshDemand()
        XCTAssertEqual(
            harness.demands.value.last,
            IconSourceDemandPolicy.HardwareRingDemands(
                menuBar: [.cpuUsage, .memoryUsage],
                dock: nil
            )
        )
    }

    func testDemandFollowsTheSourceTheSceneActuallySelected() throws {
        let settings = try makeSettings()
        settings.outerRingContent = .systemBattery
        settings.hardwareRingConfiguration = HardwareRingConfiguration(
            layout: .single, primaryMetric: .cpuUsage, secondaryMetric: nil)
        settings.appIconPlacement = .both

        let harness = try makeHarness(settings: settings)
        defer { harness.stop() }

        XCTAssertEqual(harness.demands.value.last, IconSourceDemandPolicy.HardwareRingDemands.none,
                       "a battery ring must not start the hardware sampler")

        settings.outerRingContent = .hardwareMonitor
        XCTAssertEqual(
            harness.demands.value.last,
            IconSourceDemandPolicy.HardwareRingDemands(
                menuBar: [.cpuUsage],
                dock: [.cpuUsage]
            )
        )
    }

    /// The real settings projection must carry the network-error precedence into
    /// the V1 override policy. Otherwise turning the setting on never changes
    /// what the scene draws, even though the legacy preview honours it.
    func testPrioritizesNetworkErrorsFeedsTheProjectedCenterOverride() throws {
        let settings = try makeSettings()
        settings.connectionCenterSource = .inputSource

        settings.prioritizesNetworkErrors = true
        var live = try latestSettings(settings)
        XCTAssertTrue(live.iconConfiguration.composition.centerOverride.networkProblemOverridesPrimary)

        let inputSource = InputSourceDescriptor(
            id: "com.example.input-source",
            localizedName: "Example Input Source",
            primaryLanguage: "en",
            iconURL: nil,
            shortLabel: "E"
        )
        let offline = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .off, rssi: nil),
            connection: .offline,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Built-in")
        )
        let offlineResult = resolve(offline, settings: live, inputSource: inputSource)
        XCTAssertEqual(offlineResult.trace.center.reason, SlotResolutionReason.overridden(.networkProblem))
        XCTAssertEqual(offlineResult.trace.center.selectedSourceID, CenterSource.network.rawValue)

        settings.prioritizesNetworkErrors = false
        live = try latestSettings(settings)
        let inputResult = resolve(offline, settings: live, inputSource: inputSource)
        XCTAssertEqual(inputResult.trace.center.selectedSourceID, CenterSource.inputSource.rawValue)

        settings.prioritizesNetworkErrors = true
        live = try latestSettings(settings)
        let online = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -45),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Built-in")
        )
        let onlineResult = resolve(online, settings: live, inputSource: inputSource)
        XCTAssertEqual(onlineResult.trace.center.selectedSourceID, CenterSource.inputSource.rawValue)
    }

    // MARK: - Harness

    private func makeSettings() throws -> SettingsStore {
        let name = "StatusTrioCoreTests.IconLiveDemand.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return SettingsStore(defaults: defaults)
    }

    private func latestSettings(_ settings: SettingsStore) throws -> IconPresentationSettings {
        var latest: IconPresentationSettings?
        let cancellable = settings.iconPresentationPublisher.sink { latest = $0 }
        defer { cancellable.cancel() }
        return try XCTUnwrap(latest)
    }

    private func resolve(
        _ snapshot: StatusSnapshot,
        settings: IconPresentationSettings,
        inputSource: InputSourceDescriptor?
    ) -> IconResolutionOutput {
        IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationInputs(
                    snapshot: snapshot, audioIcon: nil, inputSource: inputSource),
                sources: .empty
            ),
            configuration: settings.iconConfiguration
        )
    }

    private struct Harness {
        let demands: CurrentValueSubject<[IconSourceDemandPolicy.HardwareRingDemands], Never>
        let refreshDemand: () -> Void
        let stop: () -> Void
    }

    private func makeHarness(settings: SettingsStore) throws -> Harness {
        let initial = try latestSettings(settings)
        let viewModel = IconPresentationViewModel(
            snapshot: .placeholder,
            settings: initial,
            snapshots: Just(.placeholder).eraseToAnyPublisher(),
            preferences: settings.iconPresentationPublisher,
            resolveInputs: { snapshot in
                IconPresentationInputs(snapshot: snapshot, audioIcon: nil)
            },
            mapScene: { inputs, _, configuration, bindings in
                let resolution = IconCompositionResolver.resolve(
                    inputs: IconResolutionInputs(system: inputs, sources: inputs.sources),
                    configuration: configuration,
                    bindings: bindings
                )
                return IconSceneMapping(scene: resolution.scene, demand: resolution.demand)
            }
        )
        let sceneTicks: AnyPublisher<Void, Never> = viewModel.$output
            .map { _ in () }
            .eraseToAnyPublisher()
        let demands = CurrentValueSubject<[IconSourceDemandPolicy.HardwareRingDemands], Never>([])
        let wiring = IconHardwareDemandWiring(
            demand: viewModel.demand,
            placement: settings.appIconPlacement,
            apply: { demands.value.append($0) }
        )
        wiring.start(
            demands: viewModel.$demand.eraseToAnyPublisher(),
            placements: settings.$appIconPlacement.eraseToAnyPublisher()
        )
        viewModel.start()
        return Harness(
            demands: demands,
            refreshDemand: { wiring.reconcile() },
            stop: {
                wiring.stop()
                viewModel.stop()
            }
        )
    }
}
