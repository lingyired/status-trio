import Combine
import XCTest
@testable import StatusTrioCore

/// The outer ring can show the Mac battery or the AirPods battery, with the Mac
/// battery as an optional fallback when no AirPods are connected.
@MainActor
final class OuterRingContentSelectionTests: XCTestCase {
    private func store() throws -> SettingsStore {
        let suite = "StatusTrioCoreTests.OuterRing.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return SettingsStore(defaults: defaults)
    }

    private func snapshot() -> StatusSnapshot {
        StatusSnapshot(
            battery: BatteryStatus(rawPercentage: 62, isPresent: true, isCharging: false, isLowPowerMode: false, isConnectedToPower: false),
            wifi: WiFiStatus(state: .connected, rssi: -50),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output", currentDevice: nil)
        )
    }

    private func airPodsSources() -> IconSourceSnapshot {
        let now = Date()
        let snapshot = AirPodsBatteryIconSnapshot(
            deviceAddress: "AA:BB:CC:DD:EE:FF",
            model: .airPodsPro,
            main: nil, left: 80, right: 60, caseLevel: nil, observedAt: now
        )
        return IconSourceSnapshot(
            availability: [RingSource.airPodsBattery.rawValue: .available],
            airPodsBattery: snapshot
        )
    }

    func testDefaultIsSystemBatteryRing() throws {
        let store = try store()
        let config = store.derivedIconConfigurationFromSettings()
        XCTAssertEqual(config.composition.outerRing.primary, .systemBattery)
        XCTAssertEqual(config.behaviors.airPodsRing, .single)
        XCTAssertFalse(config.behaviors.showsAirPodsTopSymbol)
    }

    func testAirPodsContentSelectsAirPodsRingWithBatteryFallback() throws {
        let store = try store()
        store.outerRingContent = .airPodsBattery
        store.airPodsRingUsesDualRing = true
        store.showsAirPodsTopSymbolInRing = true
        store.airPodsRingFallsBackToBattery = true
        let config = store.derivedIconConfigurationFromSettings()
        XCTAssertEqual(config.composition.outerRing.primary, .airPodsBattery)
        XCTAssertEqual(config.composition.outerRing.fallback, .systemBattery)
        XCTAssertEqual(config.behaviors.airPodsRing, .dual)
        XCTAssertTrue(config.behaviors.showsAirPodsTopSymbol)
    }

    func testNoAirPodsFallsBackToTheSystemBatteryRing() throws {
        let store = try store()
        store.outerRingContent = .airPodsBattery
        store.airPodsRingFallsBackToBattery = true
        let output = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationInputs(snapshot: snapshot(), audioIcon: nil),
                sources: .empty
            ),
            configuration: store.derivedIconConfigurationFromSettings()
        )
        XCTAssertNotNil(output.scene.outerRing, "no AirPods must fall back to the battery ring")
        XCTAssertEqual(output.trace.outerRing.selectedSourceID, RingSource.systemBattery.rawValue)
    }

    func testNoAirPodsWithoutFallbackLeavesTheRingEmpty() throws {
        let store = try store()
        store.outerRingContent = .airPodsBattery
        store.airPodsRingFallsBackToBattery = false
        let output = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationInputs(snapshot: snapshot(), audioIcon: nil),
                sources: .empty
            ),
            configuration: store.derivedIconConfigurationFromSettings()
        )
        XCTAssertNil(output.scene.outerRing, "no fallback and no AirPods must leave the ring empty")
    }

    func testAirPodsPresentRendersDualRing() throws {
        let store = try store()
        store.outerRingContent = .airPodsBattery
        store.airPodsRingUsesDualRing = true
        let output = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationInputs(snapshot: snapshot(), audioIcon: nil),
                sources: airPodsSources()
            ),
            configuration: store.derivedIconConfigurationFromSettings()
        )
        XCTAssertEqual(output.trace.outerRing.selectedSourceID, RingSource.airPodsBattery.rawValue)
        XCTAssertEqual(output.scene.outerRing?.layout, .leftRight)
    }

    func testSwitchingOuterRingContentRendersImmediately() throws {
        let store = try store()
        var seed: IconPresentationSettings?
        let seedSub = store.iconPresentationPublisher.first().sink { seed = $0 }
        seedSub.cancel()
        let snap = snapshot()
        let view = IconPresentationViewModel(
            snapshot: snap,
            settings: try XCTUnwrap(seed),
            snapshots: CurrentValueSubject<StatusSnapshot, Never>(snap).eraseToAnyPublisher(),
            preferences: store.iconPresentationPublisher,
            resolveInputs: { [store] s in
                var inputs = IconPresentationResourceResolver.inputs(snapshot: s)
                inputs.sources = IconPresentationResourceResolver.sourceSnapshot(snapshot: s)
                return inputs
            },
            mapScene: { inputs, _, configuration in
                IconCompositionResolver.resolve(
                    inputs: IconResolutionInputs(system: inputs, sources: inputs.sources),
                    configuration: configuration
                ).scene
            },
            snapshotScheduler: ManualIconPresentationScheduler()
        )
        view.start()
        // Turn off the battery fallback so the ring actually disappears when the
        // content switches to (absent) AirPods, making the change observable.
        store.airPodsRingFallsBackToBattery = false
        let before = view.output.scene
        store.outerRingContent = .airPodsBattery
        XCTAssertNotEqual(view.output.scene, before, "switching the ring content must re-render immediately")
        view.stop()
    }
}
