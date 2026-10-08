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
