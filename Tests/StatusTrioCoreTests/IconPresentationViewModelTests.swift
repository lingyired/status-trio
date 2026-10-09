import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconPresentationViewModelTests: XCTestCase {
    func testInjectedMapperBuildsInitialAndPublishedScenesForLatestInputsAndConfiguration() {
        let initialSnapshot = PresentationFixtures.snapshot(rssi: -45, scalar: 0.2)
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(initialSnapshot)
        let initialSettings = IconPresentationSettings(configuration: .standard, menuBarSize: 28, testsChargingEffect: false)
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(initialSettings)
        let scheduler = ManualIconPresentationScheduler()
        let customScene = IconSceneState(center: .text(IconTextState(text: "X", color: .primary, scale: 1)))
        var mapped: [(IconPresentationInputs, IconPresentationConfiguration)] = []
        let model = IconPresentationViewModel(
            snapshot: initialSnapshot,
            settings: initialSettings,
            snapshots: snapshots.eraseToAnyPublisher(),
            preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) },
            mapScene: { inputs, configuration in
                mapped.append((inputs, configuration))
                return customScene
            },
            snapshotScheduler: scheduler
        )

        XCTAssertEqual(model.output.scene, customScene)
        XCTAssertEqual(mapped.count, 1)
        XCTAssertEqual(mapped.first?.0.snapshot, initialSnapshot)
        XCTAssertEqual(mapped.first?.1, initialSettings.configuration)

        model.start()
        mapped.removeAll()
        let latestSnapshot = PresentationFixtures.snapshot(rssi: -80, scalar: 0.7)
        snapshots.send(PresentationFixtures.snapshot(rssi: -61, scalar: 0.3))
        snapshots.send(latestSnapshot)
        XCTAssertTrue(mapped.isEmpty)
        scheduler.runScheduled()
        XCTAssertEqual(mapped.count, 1)
        XCTAssertEqual(mapped.first?.0.snapshot, latestSnapshot)

        let updatedSettings = IconPresentationSettings(
            configuration: IconPresentationConfiguration(
                battery: BatteryIconOptions(showsPercentage: false),
                connection: .standard,
                volume: .standard,
                bluetooth: .standard
            ),
            menuBarSize: 31,
            testsChargingEffect: false
        )
        preferences.send(updatedSettings)
        XCTAssertEqual(mapped.count, 2)
        XCTAssertEqual(mapped.last?.0.snapshot, latestSnapshot)
        XCTAssertEqual(mapped.last?.1, updatedSettings.configuration)
        XCTAssertEqual(model.output.scene, customScene)
        XCTAssertEqual(model.output.menuBarSize, 31)
        XCTAssertFalse(scheduler.hasPendingAction)
        model.stop()
    }

    func testResolutionTracePublishesIndependentlyFromRenderedScene() {
        let initial = PresentationFixtures.snapshot(rssi: -40)
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(initial)
        let settings = IconPresentationSettings(
            configuration: .standard, menuBarSize: 28, testsChargingEffect: false,
            designerConfiguration: .classic
        )
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(settings)
        let scheduler = ManualIconPresentationScheduler()
        let scene = IconSceneState(center: .symbol(IconSymbolState(
            source: .symbol(name: "wifi", variableValue: nil, fallback: nil), color: .primary, scale: 1
        )))
        let model = IconPresentationViewModel(
            snapshot: initial, settings: settings,
            snapshots: snapshots.eraseToAnyPublisher(), preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) },
            mapResolution: { inputs, _, _ in
                let sourceID = inputs.snapshot.wifi.rssi == -40 ? "network" : "bluetoothAudioOutput"
                return IconResolutionOutput(
                    scene: scene,
                    trace: IconResolutionTrace(
                        outerRing: .empty,
                        center: SlotResolutionTrace(
                            selectedSourceID: sourceID, role: .primary, primaryFailure: nil, reason: .primary
                        ),
                        footer: .empty
                    )
                )
            },
            snapshotScheduler: scheduler
        )

        XCTAssertEqual(model.output.scene, scene)
        XCTAssertEqual(model.output.trace.center.selectedSourceID, "network")
        let menuBarKeyBefore = StatusBarRenderKey(
            scene: model.output.scene, iconSize: model.output.menuBarSize, backingScale: 2,
            appearanceName: "aqua", phase: nil
        )
        let dockKeyBefore = DockIconRenderKey(scene: model.output.scene, backgroundStyle: .dark, pixelLength: 1024)
        model.start()
        snapshots.send(PresentationFixtures.snapshot(rssi: -80))
        scheduler.runScheduled()

        XCTAssertEqual(model.output.scene, scene)
        XCTAssertEqual(model.output.trace.center.selectedSourceID, "bluetoothAudioOutput")
        XCTAssertEqual(StatusBarRenderKey(
            scene: model.output.scene, iconSize: model.output.menuBarSize, backingScale: 2,
            appearanceName: "aqua", phase: nil
        ), menuBarKeyBefore, "Resolution-only trace changes do not alter the Menu Bar raster key.")
        XCTAssertEqual(DockIconRenderKey(
            scene: model.output.scene, backgroundStyle: .dark, pixelLength: 1024
        ), dockKeyBefore, "Resolution-only trace changes do not alter the Dock raster key.")
        model.stop()
    }

    func testTemporarilyUnknownSourcePublishesExpiryWithoutWaitingForAnotherSnapshot() {
        let start = Date(timeIntervalSince1970: 1_000)
        var now = start
        let initial = PresentationFixtures.snapshot(rssi: -40)
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(initial)
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network)
        let settings = IconPresentationSettings(
            configuration: .standard, menuBarSize: 28, testsChargingEffect: false,
            designerConfiguration: configuration
        )
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(settings)
        let debounceScheduler = ManualIconPresentationScheduler()
        let expiryScheduler = ManualIconPresentationScheduler()
        let model = IconPresentationViewModel(
            snapshot: initial, settings: settings,
            snapshots: snapshots.eraseToAnyPublisher(), preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) },
            mapResolution: { inputs, configuration, sources in
                IconCompositionResolver.resolve(
                    inputs: IconResolutionInputs(system: inputs, sources: sources),
                    configuration: configuration
                )
            },
            resolveSourceSnapshot: { snapshot in
                IconSourceSnapshot(availability: [
                    CenterSource.network.rawValue: snapshot.wifi.rssi == -40
                        ? .available : .unavailable(.unknown)
                ])
            },
            now: { now },
            snapshotScheduler: debounceScheduler,
            holdExpiryScheduler: expiryScheduler
        )

        XCTAssertEqual(model.output.trace.center.selectedSourceID, CenterSource.network.rawValue)
        model.start()
        snapshots.send(PresentationFixtures.snapshot(rssi: -80))
        debounceScheduler.runScheduled()
        XCTAssertEqual(model.output.trace.center.selectedSourceID, CenterSource.network.rawValue, "The last-good source is held during transient unknown state.")
        XCTAssertEqual(expiryScheduler.scheduledDelays.last, .seconds(2))

        now = start.addingTimeInterval(2)
        expiryScheduler.runScheduled()
        XCTAssertNil(model.output.trace.center.selectedSourceID, "Expiry must republish even if no new snapshot arrives.")
        XCTAssertEqual(expiryScheduler.scheduledDelays, [.seconds(2)], "An expired hold must not schedule itself again.")
        XCTAssertFalse(expiryScheduler.hasPendingAction)
        now = start.addingTimeInterval(6)
        snapshots.send(PresentationFixtures.snapshot(rssi: -80))
        debounceScheduler.runScheduled()
        XCTAssertEqual(expiryScheduler.scheduledDelays, [.seconds(2)])
        XCTAssertFalse(expiryScheduler.hasPendingAction)
        model.stop()
    }

    func testHealthySourcesDoNotScheduleExpiryAtTwoFourOrSixSeconds() {
        let start = Date(timeIntervalSince1970: 3_000)
        var now = start
        let healthy = PresentationFixtures.snapshot(rssi: -40)
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(healthy)
        let configuration = IconConfigurationV1.classic
        let settings = IconPresentationSettings(configuration: .standard, menuBarSize: 28,
                                                testsChargingEffect: false, designerConfiguration: configuration)
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(settings)
        let debounce = ManualIconPresentationScheduler()
        let expiry = ManualIconPresentationScheduler()
        let model = IconPresentationViewModel(
            snapshot: healthy, settings: settings,
            snapshots: snapshots.eraseToAnyPublisher(), preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) },
            mapResolution: { inputs, configuration, sources in
                IconCompositionResolver.resolve(inputs: IconResolutionInputs(system: inputs, sources: sources),
                                                 configuration: configuration)
            },
            resolveSourceSnapshot: { IconPresentationResourceResolver.sourceSnapshot(snapshot: $0) },
            now: { now }, snapshotScheduler: debounce, holdExpiryScheduler: expiry
        )
        model.start()
        XCTAssertTrue(expiry.scheduledDelays.isEmpty)
        for seconds in [2.0, 4.0, 6.0] {
            now = start.addingTimeInterval(seconds)
            snapshots.send(healthy)
            debounce.runScheduled()
            XCTAssertTrue(expiry.scheduledDelays.isEmpty, "Healthy source at +\(seconds)s must not cause an expiry timer.")
            XCTAssertFalse(expiry.hasPendingAction)
        }
        model.stop()
    }

    func testStartedViewModelPreservesProductionAirPodsAndConnectedDevicePayloadThroughHoldExpiry() throws {
        let start = Date()
        let initial = PresentationFixtures.snapshot(rssi: -40)
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(initial)
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .airPodsBattery, fallback: .systemBattery)
        configuration.composition.center = SlotSelection(primary: .connectedBluetoothDevice, fallback: nil)
        configuration.behaviors.airPodsRing = .dual
        let settings = IconPresentationSettings(configuration: .standard, menuBarSize: 28,
                                                testsChargingEffect: false, designerConfiguration: configuration)
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(settings)
        let fixture = MutableIconSourcePayloadFixture(now: start)
        let debounce = ManualIconPresentationScheduler()
        let expiry = ManualIconPresentationScheduler()
        let model = IconPresentationViewModel(
            snapshot: initial, settings: settings,
            snapshots: snapshots.eraseToAnyPublisher(), preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationResourceResolver.inputs(snapshot: $0) },
            mapResolution: { inputs, configuration, sources in
                IconCompositionResolver.resolve(
                    inputs: IconResolutionInputs(system: inputs, sources: sources),
                    configuration: configuration,
                    now: fixture.now
                )
            },
            resolveSourceSnapshot: { snapshot in fixture.resolve(snapshot: snapshot) },
            now: { fixture.now }, snapshotScheduler: debounce, holdExpiryScheduler: expiry
        )

        model.start()
        model.refreshSourceState()
        XCTAssertEqual(model.output.trace.outerRing.selectedSourceID, RingSource.airPodsBattery.rawValue)
        XCTAssertEqual(model.output.scene.outerRing?.layout, .leftRight)
        XCTAssertEqual(model.output.scene.outerRing?.segments.map(\.progress), [0.35, 0.7])
        XCTAssertEqual(model.output.trace.center.selectedSourceID, CenterSource.connectedBluetoothDevice.rawValue)
        XCTAssertNotNil(model.output.scene.center)

        let freshInputs = IconResolutionInputs(
            system: IconPresentationResourceResolver.inputs(snapshot: initial),
            sources: fixture.resolve(snapshot: initial)
        )
        let preview = IconDesignerPreviewResolver.resolve(inputs: freshInputs, configuration: configuration)
        XCTAssertEqual(model.output.scene, preview.scene,
                       "Fresh Menu Bar and Designer preview resolution must use identical production payloads.")
        XCTAssertEqual(model.output.trace, preview.trace)

        fixture.batteryLevels = [:]
        fixture.now = start.addingTimeInterval(1)
        model.refreshSourceState()
        XCTAssertEqual(model.output.trace.outerRing.selectedSourceID, RingSource.airPodsBattery.rawValue)
        XCTAssertEqual(model.output.scene.outerRing?.segments.map(\.progress), [0.35, 0.7],
                       "A temporarily stale source keeps the last valid AirPods payload for its two-second hold.")
        XCTAssertNotNil(model.output.scene.center, "The fresh connected-device payload must survive source holding too.")
        XCTAssertEqual(expiry.scheduledDelays.last, .seconds(1))

        fixture.now = start.addingTimeInterval(2)
        expiry.runScheduled()
        XCTAssertEqual(model.output.trace.outerRing.selectedSourceID, RingSource.systemBattery.rawValue)
        XCTAssertEqual(model.output.trace.outerRing.role, .fallback)
        XCTAssertNil(model.output.scene.outerRing?.layout == .leftRight ? model.output.scene.outerRing : nil,
                     "AirPods payload must expire rather than remain visible indefinitely.")
        XCTAssertEqual(model.output.trace.center.selectedSourceID, CenterSource.connectedBluetoothDevice.rawValue)
        XCTAssertNotNil(model.output.scene.center)
        model.stop()
    }

    func testTransientPayloadLossHoldsOnlyAffectedSlotStatesUntilExpiry() {
        let start = Date(timeIntervalSince1970: 4_000)
        var now = start
        let healthy = PresentationFixtures.snapshot(rssi: -40, scalar: 0.7, muted: false)
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(healthy)
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network)
        let settings = IconPresentationSettings(configuration: .standard, menuBarSize: 28,
                                                testsChargingEffect: false, designerConfiguration: configuration)
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(settings)
        let debounce = ManualIconPresentationScheduler()
        let expiry = ManualIconPresentationScheduler()
        let model = IconPresentationViewModel(
            snapshot: healthy, settings: settings,
            snapshots: snapshots.eraseToAnyPublisher(), preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) },
            mapResolution: { inputs, configuration, sources in
                IconCompositionResolver.resolve(inputs: IconResolutionInputs(system: inputs, sources: sources),
                                                 configuration: configuration)
            },
            resolveSourceSnapshot: { IconPresentationResourceResolver.sourceSnapshot(snapshot: $0) },
            now: { now }, snapshotScheduler: debounce, holdExpiryScheduler: expiry
        )
        let lastGoodScene = model.output.scene
        model.start()
        let unavailable = StatusSnapshot(
            battery: healthy.battery,
            wifi: WiFiStatus(state: .unavailable, rssi: nil),
            connection: .wifi,
            volume: VolumeStatus(scalar: nil, isMuted: false, deviceName: "Output")
        )
        snapshots.send(unavailable)
        debounce.runScheduled()
        XCTAssertEqual(model.output.scene, lastGoodScene, "Unknown payloads must preserve the previous center and footer scenes, not map slash/zero.")
        now = start.addingTimeInterval(2)
        expiry.runScheduled()
        XCTAssertNil(model.output.scene.center)
        XCTAssertNil(model.output.scene.footer)
        model.stop()
    }

    func testStopStartClearsLastGoodSourceValue() {
        let now = Date(timeIntervalSince1970: 2_000)
        let connected = PresentationFixtures.snapshot(rssi: -40)
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(connected)
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .network)
        let settings = IconPresentationSettings(
            configuration: .standard, menuBarSize: 28, testsChargingEffect: false,
            designerConfiguration: configuration
        )
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(settings)
        let debounceScheduler = ManualIconPresentationScheduler()
        let expiryScheduler = ManualIconPresentationScheduler()
        let model = IconPresentationViewModel(
            snapshot: connected, settings: settings,
            snapshots: snapshots.eraseToAnyPublisher(), preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) },
            mapResolution: { inputs, configuration, sources in
                IconCompositionResolver.resolve(
                    inputs: IconResolutionInputs(system: inputs, sources: sources),
                    configuration: configuration
                )
            },
            resolveSourceSnapshot: { snapshot in
                IconSourceSnapshot(availability: [
                    CenterSource.network.rawValue: snapshot.wifi.state == .unavailable
                        ? .unavailable(.unknown) : .available
                ])
            },
            now: { now },
            snapshotScheduler: debounceScheduler,
            holdExpiryScheduler: expiryScheduler
        )

        model.start()
        XCTAssertEqual(model.output.trace.center.selectedSourceID, CenterSource.network.rawValue)
        let unknown = StatusSnapshot(
            battery: connected.battery,
            wifi: .placeholder,
            connection: .offline,
            volume: connected.volume
        )
        snapshots.send(unknown)
        debounceScheduler.runScheduled()
        XCTAssertEqual(model.output.trace.center.selectedSourceID, CenterSource.network.rawValue)
        XCTAssertTrue(expiryScheduler.hasPendingAction)

        model.stop()
        XCTAssertFalse(expiryScheduler.hasPendingAction)
        model.start()
        XCTAssertNil(model.output.trace.center.selectedSourceID)
        model.stop()
    }

    func testDesignerConfigurationPublishesImmediatelyWithoutWaitingForSnapshotDebounce() {
        let initial = PresentationFixtures.snapshot(rssi: -40)
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(initial)
        let initialConfiguration = IconConfigurationV1.classic
        let initialSettings = IconPresentationSettings(
            configuration: .standard, menuBarSize: 28, testsChargingEffect: false,
            designerConfiguration: initialConfiguration
        )
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(initialSettings)
        let scheduler = ManualIconPresentationScheduler()
        let model = IconPresentationViewModel(
            snapshot: initial, settings: initialSettings,
            snapshots: snapshots.eraseToAnyPublisher(), preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) },
            mapResolution: { inputs, configuration, sources in
                IconCompositionResolver.resolve(
                    inputs: IconResolutionInputs(system: inputs, sources: sources),
                    configuration: configuration
                )
            },
            snapshotScheduler: scheduler
        )
        model.start()
        XCTAssertEqual(model.output.trace.center.selectedSourceID, CenterSource.automaticLegacy.rawValue)

        var changedConfiguration = initialConfiguration
        changedConfiguration.composition.center = SlotSelection(primary: .network)
        preferences.send(IconPresentationSettings(
            configuration: .standard, menuBarSize: 28, testsChargingEffect: false,
            designerConfiguration: changedConfiguration
        ))

        XCTAssertEqual(model.output.trace.center.selectedSourceID, CenterSource.network.rawValue)
        XCTAssertFalse(scheduler.hasPendingAction, "Configuration changes map immediately rather than waiting for the snapshot debounce.")
        model.stop()
    }

    func testInjectedMapperBuildsCanonicalAndChargingTestScenesFromProjectedSnapshot() {
        let original = PresentationFixtures.snapshot()
        XCTAssertFalse(original.battery.isCharging)
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(original)
        let settings = IconPresentationSettings(configuration: .standard, menuBarSize: 28, testsChargingEffect: true)
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(settings)
        let customScene = IconSceneState(center: .text(IconTextState(text: "M", color: .primary, scale: 1)))
        var mappedSnapshots: [StatusSnapshot] = []
        let model = IconPresentationViewModel(
            snapshot: original,
            settings: settings,
            snapshots: snapshots.eraseToAnyPublisher(),
            preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) },
            mapScene: { inputs, _ in
                mappedSnapshots.append(inputs.snapshot)
                return customScene
            }
        )

        XCTAssertEqual(model.output.scene, customScene)
        XCTAssertEqual(model.output.menuBarTestScene, customScene)
        XCTAssertEqual(mappedSnapshots.count, 2)
        XCTAssertEqual(mappedSnapshots[0], original)
        XCTAssertTrue(mappedSnapshots[1].battery.isCharging)
        XCTAssertNotEqual(mappedSnapshots[1].battery, original.battery)
        XCTAssertFalse(original.battery.isCharging)

        model.start()
        mappedSnapshots.removeAll()
        let disabled = IconPresentationSettings(configuration: .standard, menuBarSize: 28, testsChargingEffect: false)
        preferences.send(disabled)
        XCTAssertNil(model.output.menuBarTestScene)
        XCTAssertEqual(mappedSnapshots, [original])

        let updated = PresentationFixtures.snapshot(rssi: -80)
        snapshots.send(updated)
        let reenabled = IconPresentationSettings(configuration: .standard, menuBarSize: 29, testsChargingEffect: true)
        preferences.send(reenabled)
        XCTAssertEqual(mappedSnapshots.count, 3)
        XCTAssertEqual(mappedSnapshots[1], updated)
        XCTAssertTrue(mappedSnapshots[2].battery.isCharging)
        XCTAssertEqual(model.output.scene, customScene)
        XCTAssertEqual(model.output.menuBarTestScene, customScene)
        model.stop()
    }

    func testInjectedMapperPreservesDedupStopAndRestartLifecycle() {
        let initial = PresentationFixtures.snapshot()
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(initial)
        let initialSettings = IconPresentationSettings(configuration: .standard, menuBarSize: 28, testsChargingEffect: false)
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(initialSettings)
        let scheduler = ManualIconPresentationScheduler()
        let constantScene = IconSceneState(center: .symbol(IconSymbolState(
            source: .symbol(name: "wifi", variableValue: nil, fallback: nil),
            color: .primary,
            scale: 1
        )))
        var mappedSnapshots: [StatusSnapshot] = []
        let model = IconPresentationViewModel(
            snapshot: initial,
            settings: initialSettings,
            snapshots: snapshots.eraseToAnyPublisher(),
            preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) },
            mapScene: { inputs, _ in
                mappedSnapshots.append(inputs.snapshot)
                return constantScene
            },
            snapshotScheduler: scheduler
        )
        var delivered: [IconPresentationOutput] = []
        let subscription = model.$output.dropFirst().sink { delivered.append($0) }
        model.start()
        mappedSnapshots.removeAll()

        let changedSnapshot = PresentationFixtures.snapshot(rssi: -80)
        snapshots.send(changedSnapshot)
        XCTAssertTrue(mappedSnapshots.isEmpty)
        scheduler.runScheduled()
        XCTAssertEqual(mappedSnapshots, [changedSnapshot])
        XCTAssertTrue(delivered.isEmpty, "An equal mapped scene must remain deduplicated.")

        preferences.send(IconPresentationSettings(configuration: .standard, menuBarSize: 30, testsChargingEffect: false))
        XCTAssertEqual(mappedSnapshots, [changedSnapshot, changedSnapshot])
        XCTAssertEqual(delivered.last?.scene, constantScene)
        XCTAssertEqual(delivered.last?.menuBarSize, 30)

        let pending = PresentationFixtures.snapshot(rssi: -55)
        snapshots.send(pending)
        XCTAssertTrue(scheduler.hasPendingAction)
        model.stop()
        XCTAssertFalse(scheduler.hasPendingAction)
        scheduler.runScheduled()
        XCTAssertEqual(mappedSnapshots, [changedSnapshot, changedSnapshot])

        let whileStopped = PresentationFixtures.snapshot(rssi: -40)
        snapshots.send(whileStopped)
        preferences.send(IconPresentationSettings(configuration: .standard, menuBarSize: 32, testsChargingEffect: false))
        model.start()
        XCTAssertEqual(mappedSnapshots.last, whileStopped)
        XCTAssertEqual(model.output.menuBarSize, 32)
        subscription.cancel()
        model.stop()
    }

    func testInitPublishesInitialOutputAndStatusChangesPublishOneCompleteOutput() {
        let initialSnapshot = PresentationFixtures.snapshot()
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(initialSnapshot)
        let initialSettings = IconPresentationSettings(
            configuration: .standard,
            menuBarSize: 28,
            testsChargingEffect: false
        )
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(initialSettings)
        let scheduler = ManualIconPresentationScheduler()
        let model = IconPresentationViewModel(
            snapshot: snapshots.value,
            settings: preferences.value,
            snapshots: snapshots.eraseToAnyPublisher(),
            preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) },
            snapshotScheduler: scheduler
        )

        var delivered: [IconPresentationOutput] = []
        let subscription = model.$output.sink { delivered.append($0) }
        XCTAssertEqual(delivered, [model.output])

        model.start()
        snapshots.send(PresentationFixtures.snapshot(rssi: -80, scalar: 0.74))

        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(model.output.scene, delivered.first?.scene)
        scheduler.runScheduled()
        XCTAssertEqual(delivered.count, 2)
        snapshots.send(PresentationFixtures.snapshot(rssi: -40, scalar: 0.1))

        XCTAssertEqual(delivered.count, 2)
        scheduler.runScheduled()
        XCTAssertEqual(delivered.count, 3)
        XCTAssertEqual(delivered.last?.menuBarSize, 28)
        XCTAssertNotEqual(delivered.last?.scene, delivered.first?.scene)
        subscription.cancel()
        model.stop()
    }

    func testDomainBurstDebouncesButSettingsMapImmediatelyToLatestSnapshot() {
        let initial = PresentationFixtures.snapshot(rssi: -40, scalar: 0.1)
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(initial)
        let initialSettings = IconPresentationSettings(configuration: .standard, menuBarSize: 28, testsChargingEffect: false)
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(initialSettings)
        let scheduler = ManualIconPresentationScheduler()
        let model = IconPresentationViewModel(
            snapshot: initial,
            settings: initialSettings,
            snapshots: snapshots.eraseToAnyPublisher(),
            preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) },
            snapshotScheduler: scheduler
        )
        var delivered: [IconPresentationOutput] = []
        let subscription = model.$output.dropFirst().sink { delivered.append($0) }
        model.start()

        let first = PresentationFixtures.snapshot(rssi: -61, scalar: 0.2)
        let settled = PresentationFixtures.snapshot(rssi: -79, scalar: 0.8)
        snapshots.send(first)
        snapshots.send(settled)
        XCTAssertEqual(delivered.count, 0, "Domain output waits for the 500 ms quiet period.")
        XCTAssertEqual(scheduler.scheduledDelays, [.milliseconds(500), .milliseconds(500)])

        let fastSetting = IconPresentationSettings(
            configuration: IconPresentationConfiguration(
                battery: BatteryIconOptions(showsPercentage: false),
                connection: .standard,
                volume: .standard,
                bluetooth: .standard
            ),
            menuBarSize: 30,
            testsChargingEffect: false
        )
        preferences.send(fastSetting)
        XCTAssertEqual(delivered.last, expectedOutput(snapshot: settled, settings: fastSetting))
        XCTAssertEqual(delivered.count, 1, "A settings change maps immediately using the latest raw snapshot.")

        scheduler.runScheduled()
        XCTAssertEqual(delivered.count, 1, "The pending domain map deduplicates after settings already mapped it.")
        subscription.cancel()
        model.stop()
    }

    func testStopCancelsPendingDomainDebounce() {
        let initial = PresentationFixtures.snapshot(rssi: -40)
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(initial)
        let settings = IconPresentationSettings(configuration: .standard, menuBarSize: 28, testsChargingEffect: false)
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(settings)
        let scheduler = ManualIconPresentationScheduler()
        let model = IconPresentationViewModel(
            snapshot: initial,
            settings: settings,
            snapshots: snapshots.eraseToAnyPublisher(),
            preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) },
            snapshotScheduler: scheduler
        )
        var delivered: [IconPresentationOutput] = []
        let subscription = model.$output.dropFirst().sink { delivered.append($0) }
        model.start()

        snapshots.send(PresentationFixtures.snapshot(rssi: -80))
        XCTAssertTrue(scheduler.hasPendingAction)
        model.stop()
        XCTAssertFalse(scheduler.hasPendingAction)
        scheduler.runScheduled()
        XCTAssertTrue(delivered.isEmpty)
        subscription.cancel()
    }

    func testStartIsIdempotentStopCancelsAndRestartUsesCurrentValues() {
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(PresentationFixtures.snapshot())
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(
            IconPresentationSettings(configuration: .standard, menuBarSize: 28, testsChargingEffect: false)
        )
        var snapshotSubscriptions = 0
        var snapshotCancellations = 0
        var preferenceSubscriptions = 0
        var preferenceCancellations = 0
        let snapshotPublisher = snapshots
            .handleEvents(
                receiveSubscription: { _ in snapshotSubscriptions += 1 },
                receiveCancel: { snapshotCancellations += 1 }
            )
            .eraseToAnyPublisher()
        let preferencePublisher = preferences
            .handleEvents(
                receiveSubscription: { _ in preferenceSubscriptions += 1 },
                receiveCancel: { preferenceCancellations += 1 }
            )
            .eraseToAnyPublisher()
        let scheduler = ManualIconPresentationScheduler()
        let model = IconPresentationViewModel(
            snapshot: snapshots.value,
            settings: preferences.value,
            snapshots: snapshotPublisher,
            preferences: preferencePublisher,
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) },
            snapshotScheduler: scheduler
        )
        var delivered: [IconPresentationOutput] = []
        let subscription = model.$output.dropFirst().sink { delivered.append($0) }

        XCTAssertEqual(snapshotSubscriptions, 0)
        XCTAssertEqual(preferenceSubscriptions, 0)
        model.start()
        model.start()
        XCTAssertEqual(snapshotSubscriptions, 1)
        XCTAssertEqual(preferenceSubscriptions, 1)
        snapshots.send(PresentationFixtures.snapshot(rssi: -80))
        scheduler.runScheduled()
        XCTAssertEqual(delivered.count, 1)

        model.stop()
        XCTAssertEqual(snapshotCancellations, 1)
        XCTAssertEqual(preferenceCancellations, 1)
        snapshots.send(PresentationFixtures.snapshot(rssi: -50))
        XCTAssertEqual(delivered.count, 1)

        model.start()
        XCTAssertEqual(snapshotSubscriptions, 2)
        XCTAssertEqual(preferenceSubscriptions, 2)
        XCTAssertEqual(delivered.count, 2)
        XCTAssertEqual(delivered.last?.scene, IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshots.value, audioIcon: nil),
            configuration: .standard
        ))

        subscription.cancel()
        model.stop()
        XCTAssertEqual(snapshotCancellations, 2)
        XCTAssertEqual(preferenceCancellations, 2)
    }

    func testSettingsPublishWholeLatestValueAndSizeDoesNotChangeScene() {
        let snapshot = PresentationFixtures.snapshot()
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(snapshot)
        let initial = IconPresentationSettings(configuration: .standard, menuBarSize: 28, testsChargingEffect: false)
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(initial)
        let model = IconPresentationViewModel(
            snapshot: snapshot,
            settings: initial,
            snapshots: snapshots.eraseToAnyPublisher(),
            preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) }
        )
        var delivered: [IconPresentationOutput] = []
        let subscription = model.$output.dropFirst().sink { delivered.append($0) }
        model.start()

        let initialScene = model.output.scene
        let sizeOnly = IconPresentationSettings(configuration: .standard, menuBarSize: 30, testsChargingEffect: false)
        preferences.send(sizeOnly)

        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered.last, expectedOutput(snapshot: snapshot, settings: sizeOnly))
        XCTAssertEqual(delivered.last?.scene, initialScene)

        let configurationOnly = IconPresentationSettings(
            configuration: IconPresentationConfiguration(
                battery: BatteryIconOptions(showsPercentage: false),
                connection: .standard,
                volume: .standard,
                bluetooth: .standard
            ),
            menuBarSize: 30,
            testsChargingEffect: false
        )
        preferences.send(configurationOnly)
        XCTAssertEqual(delivered.count, 2)
        XCTAssertEqual(delivered.last, expectedOutput(snapshot: snapshot, settings: configurationOnly))
        XCTAssertNotEqual(delivered.last?.scene, delivered.first?.scene)

        let chargingTestMode = IconPresentationSettings(
            configuration: configurationOnly.configuration,
            menuBarSize: 32,
            testsChargingEffect: true
        )
        preferences.send(chargingTestMode)
        XCTAssertEqual(delivered.count, 3)
        XCTAssertEqual(delivered.last, expectedOutput(snapshot: snapshot, settings: chargingTestMode))
        XCTAssertEqual(model.output, expectedOutput(snapshot: snapshot, settings: chargingTestMode))

        subscription.cancel()
        model.stop()
    }

    func testPublishedSinkMustUseDeliveredOutputBeforeStoredValueChanges() {
        let snapshot = PresentationFixtures.snapshot()
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(snapshot)
        let initial = IconPresentationSettings(configuration: .standard, menuBarSize: 28, testsChargingEffect: false)
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(initial)
        let model = IconPresentationViewModel(
            snapshot: snapshot,
            settings: initial,
            snapshots: snapshots.eraseToAnyPublisher(),
            preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) }
        )
        var deliveredBeforeStorageChange: IconPresentationOutput?
        let subscription = model.$output.dropFirst().sink { delivered in
            if model.output != delivered {
                deliveredBeforeStorageChange = delivered
            }
        }
        model.start()

        let changed = IconPresentationSettings(
            configuration: IconPresentationConfiguration(
                battery: BatteryIconOptions(showsPercentage: false),
                connection: .standard,
                volume: .standard,
                bluetooth: .standard
            ),
            menuBarSize: 28,
            testsChargingEffect: false
        )
        let expected = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: changed.configuration
        )
        preferences.send(changed)

        XCTAssertEqual(deliveredBeforeStorageChange?.scene, expected)
        XCTAssertEqual(model.output.scene, expected)
        subscription.cancel()
        model.stop()
    }

    func testChargingEffectTestModeProjectsSnapshotWithoutChangingOriginal() {
        let original = PresentationFixtures.snapshot()
        XCTAssertFalse(original.battery.isCharging)
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(original)
        let settings = IconPresentationSettings(configuration: .standard, menuBarSize: 28, testsChargingEffect: true)
        let model = IconPresentationViewModel(
            snapshot: original,
            settings: settings,
            snapshots: snapshots.eraseToAnyPublisher(),
            preferences: Just(settings).eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) }
        )

        XCTAssertNil(model.output.scene.outerRing?.effect)
        XCTAssertNotNil(model.output.menuBarTestScene?.outerRing?.effect)
        XCTAssertFalse(original.battery.isCharging)
        XCTAssertFalse(model.output.menuBarTestScene?.outerRing?.accessory == nil)
    }

    private func expectedOutput(
        snapshot: StatusSnapshot,
        settings: IconPresentationSettings
    ) -> IconPresentationOutput {
        let inputs = IconPresentationInputs(snapshot: snapshot, audioIcon: nil)
        let testScene = settings.testsChargingEffect
            ? IconPresentationMapper.scene(
                inputs: IconPresentationInputs(
                    snapshot: ChargingEffectTestMode.snapshot(snapshot, enabled: true),
                    audioIcon: nil
                ),
                configuration: settings.configuration
            )
            : nil
        return IconPresentationOutput(
            scene: IconPresentationMapper.scene(inputs: inputs, configuration: settings.configuration),
            menuBarTestScene: testScene,
            menuBarSize: settings.menuBarSize
        )
    }
}

@MainActor
private final class MutableIconSourcePayloadFixture {
    let airPods: BluetoothDevice
    let headphones: BluetoothDevice
    var batteryLevels: [String: BluetoothBatteryLevel]
    var batteryLevelsUpdatedAt: Date
    var now: Date

    init(now: Date) {
        self.now = now
        batteryLevelsUpdatedAt = now
        airPods = BluetoothDevice(id: "AA:BB:CC:DD:EE:10", name: "AirPods Pro", kind: .audio,
                                  isConnected: true, airPodsModel: .airPodsPro)
        headphones = BluetoothDevice(id: "AA:BB:CC:DD:EE:20", name: "Headphones", kind: .audio, isConnected: true)
        let key = BluetoothBatteryReader.normalizedAddress(airPods.id)
        batteryLevels = [key: BluetoothBatteryLevel(deviceAddress: airPods.id, main: 70, left: 35, right: 70, caseLevel: nil)]
    }

    func resolve(snapshot: StatusSnapshot) -> IconSourceSnapshot {
        IconPresentationResourceResolver.sourceSnapshot(
            snapshot: snapshot, bluetoothDevices: [airPods, headphones], batteryLevels: batteryLevels,
            batteryLevelsUpdatedAt: batteryLevelsUpdatedAt, selectedAirPodsAddress: airPods.id,
            selectedConnectedDeviceAddress: headphones.id, now: now
        )
    }
}
