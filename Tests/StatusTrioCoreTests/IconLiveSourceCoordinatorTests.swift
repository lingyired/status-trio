import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconLiveSourceCoordinatorTests: XCTestCase {
    func testOneBindingUsedBySeveralConsumersStartsOnceAndStopsAfterTheLastOne() {
        var started: [IconLiveSourceCoordinator.SubscriptionToken] = []
        var stopped: [IconContentBinding] = []
        var activeHistory: [Set<IconContentBinding>] = []
        let coordinator = IconLiveSourceCoordinator(
            start: { started.append($0) },
            stop: { stopped.append($0) },
            onChange: { activeHistory.append($0) }
        )
        let binding = IconContentBinding(pluginID: "test.external", presentationID: "latency")

        coordinator.setBindings([binding], for: .init(surface: "menuBar", slot: .center))
        coordinator.setBindings([binding], for: .init(surface: "dock", slot: .center))
        coordinator.setBindings([binding], for: .init(surface: "menuBar", slot: .footer))

        XCTAssertEqual(started.count, 1, "the same source must start once")
        XCTAssertEqual(coordinator.activeBindings, [binding])

        coordinator.removeConsumer(.init(surface: "menuBar", slot: .center))
        coordinator.removeConsumer(.init(surface: "dock", slot: .center))
        XCTAssertTrue(stopped.isEmpty, "other consumers still own the source")

        coordinator.removeConsumer(.init(surface: "menuBar", slot: .footer))
        XCTAssertEqual(stopped, [binding])
        XCTAssertTrue(coordinator.activeBindings.isEmpty)
        XCTAssertEqual(activeHistory.last, [])
        XCTAssertTrue(activeHistory.dropLast().allSatisfy { $0 == [binding] })
    }

    func testLateCallbackFromAnOldSubscriptionIsRejected() {
        var tokens: [IconLiveSourceCoordinator.SubscriptionToken] = []
        let coordinator = IconLiveSourceCoordinator(
            start: { tokens.append($0) },
            stop: { _ in }
        )
        let binding = IconContentBinding(pluginID: "test.external", presentationID: "latency")
        let consumer = IconLiveSourceCoordinator.Consumer(surface: "menuBar", slot: .center)

        coordinator.setBindings([binding], for: consumer)
        let first = tokens[0]
        XCTAssertTrue(coordinator.accepts(first))

        coordinator.removeConsumer(consumer)
        let replacement = IconContentBinding(pluginID: "test.external", presentationID: "other")
        coordinator.setBindings([replacement], for: consumer)
        XCTAssertFalse(coordinator.accepts(first))
        XCTAssertTrue(coordinator.accepts(tokens[1]))
    }

    func testDifferentBindingWithTheSamePixelsStillNotifiesDemand() throws {
        let snapshot = CurrentValueSubject<StatusSnapshot, Never>(.placeholder)
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(
            IconPresentationSettings(configuration: .standard, menuBarSize: 24, testsChargingEffect: false))
        let scene = IconSceneState(center: .text(IconTextState(text: "42 ms", color: .primary, scale: 1)))
        var demand = IconPresentationDemand(
            selectedBindings: [.init(pluginID: "test.one", presentationID: "text")],
            subscribedBindings: [.init(pluginID: "test.one", presentationID: "text")])
        let view = IconPresentationViewModel(
            snapshot: .placeholder,
            settings: preferences.value,
            snapshots: snapshot.eraseToAnyPublisher(),
            preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) },
            mapScene: { _, _, _, _ in IconSceneMapping(scene: scene, demand: demand) },
            snapshotScheduler: ManualIconPresentationScheduler()
        )
        var demandUpdates = 0
        var outputUpdates = 0
        let demandCancellable = view.$demand.dropFirst().sink { _ in demandUpdates += 1 }
        let outputCancellable = view.$output.dropFirst().sink { _ in outputUpdates += 1 }
        defer {
            demandCancellable.cancel()
            outputCancellable.cancel()
        }
        view.start()

        demand = IconPresentationDemand(
            selectedBindings: [.init(pluginID: "test.two", presentationID: "text")],
            subscribedBindings: [.init(pluginID: "test.two", presentationID: "text")])
        preferences.send(IconPresentationSettings(
            configuration: .standard, menuBarSize: 24, testsChargingEffect: false))

        XCTAssertEqual(demandUpdates, 1)
        XCTAssertEqual(outputUpdates, 0, "identical pixels must not republish the scene")
        XCTAssertEqual(view.demand.selectedBindings.first?.pluginID, "test.two")
    }

    func testExternalPrimaryStaysSubscribedWhileItsFallbackDraws() throws {
        let bindings = IconSlotBindingsV1(
            schemaVersion: 1,
            outerRing: .init(primary: .init(pluginID: "builtin.system-battery", presentationID: "ring")),
            center: .init(
                primary: .init(pluginID: "test.external", presentationID: "latency"),
                fallback: .init(pluginID: "builtin.network", presentationID: "center")),
            footer: .init(primary: .init(pluginID: "builtin.system-volume", presentationID: "footer"))
        )
        let unavailable = IconResolutionInputs(
            system: IconPresentationInputs(snapshot: .placeholder, audioIcon: nil),
            sources: IconSourceSnapshot(availability: ["test.external": .unavailable(.unavailable)])
        )
        let registry = try Self.registry()
        let fallback = IconCompositionResolver.resolve(
            inputs: unavailable, configuration: .classic, bindings: bindings, registry: registry)
        XCTAssertEqual(fallback.trace.center.role, .fallback)
        XCTAssertTrue(fallback.demand.subscribedBindings.contains(
            .init(pluginID: "test.external", presentationID: "latency")))
        XCTAssertFalse(fallback.demand.selectedBindings.contains(
            .init(pluginID: "test.external", presentationID: "latency")))
        XCTAssertTrue(fallback.demand.selectedBindings.contains(
            .init(pluginID: "builtin.network", presentationID: "center")))

        let available = IconResolutionInputs(
            system: IconPresentationInputs(snapshot: .placeholder, audioIcon: nil),
            sources: .empty
        )
        let primary = IconCompositionResolver.resolve(
            inputs: available, configuration: .classic, bindings: bindings, registry: registry)
        XCTAssertEqual(primary.trace.center.role, .primary)
        XCTAssertTrue(primary.demand.selectedBindings.contains(
            .init(pluginID: "test.external", presentationID: "latency")))
    }

    func testHardwareFallbackOnlySamplesWhenItActuallyDraws() throws {
        var configuration = IconConfigurationV1.classic
        configuration.behaviors.hardwareRing = HardwareRingConfiguration(
            layout: .dual, primaryMetric: .cpuUsage, secondaryMetric: .memoryUsage)
        configuration.composition.outerRing = SlotSelection(primary: .systemBattery, fallback: .hardwareMonitor)
        let bindings = IconSlotBindingsV1(
            schemaVersion: 1,
            outerRing: .init(
                primary: .init(pluginID: "test.external", presentationID: "ring"),
                fallback: .init(pluginID: "builtin.hardware-monitor", presentationID: "ring")),
            center: .init(primary: .init(pluginID: "builtin.network", presentationID: "center")),
            footer: .init(primary: .init(pluginID: "builtin.system-volume", presentationID: "footer"))
        )
        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(snapshot: .placeholder, audioIcon: nil),
            sources: IconSourceSnapshot(availability: ["test.external": .unavailable(.unavailable)])
        )
        let output = IconCompositionResolver.resolve(
            inputs: inputs, configuration: configuration, bindings: bindings, registry: try Self.registry())
        XCTAssertEqual(output.trace.outerRing.role, .fallback)
        XCTAssertEqual(output.demand.hardwareMetricIDs, [.cpuUsage, .memoryUsage])

        // The fallback is not sampled while the primary draws.
        let primaryInputs = IconResolutionInputs(
            system: IconPresentationInputs(snapshot: .placeholder, audioIcon: nil),
            sources: .empty
        )
        let primary = IconCompositionResolver.resolve(
            inputs: primaryInputs, configuration: configuration, bindings: bindings, registry: try Self.registry())
        XCTAssertEqual(primary.trace.outerRing.role, .primary)
        XCTAssertTrue(primary.demand.hardwareMetricIDs.isEmpty)
    }

    func testVolumeAndWiFiDoNotDemandHardwareMetrics() throws {
        var configuration = IconConfigurationV1.classic
        configuration.behaviors.hardwareRing = HardwareRingConfiguration(
            layout: .dual, primaryMetric: .cpuUsage, secondaryMetric: .memoryUsage)
        configuration.composition.outerRing = SlotSelection(primary: .systemBattery)
        let bindings = IconSlotBindingsV1(
            schemaVersion: 1,
            outerRing: .init(primary: .init(pluginID: "builtin.system-battery", presentationID: "ring")),
            center: .init(primary: .init(pluginID: "builtin.network", presentationID: "center")),
            footer: .init(primary: .init(pluginID: "builtin.network", presentationID: "footer"))
        )
        let output = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationInputs(snapshot: .placeholder, audioIcon: nil,
                                               bottomIndicatorSource: .wifi),
                sources: .empty),
            configuration: configuration,
            bindings: bindings,
            registry: try Self.registry()
        )
        XCTAssertTrue(output.demand.hardwareMetricIDs.isEmpty)
        XCTAssertFalse(output.demand.dependencies.requiresHardwareMonitor)
    }

    func testCoalescerRunsFirstImmediatelyAndKeepsTheTrailingValue() {
        var now = Date(timeIntervalSince1970: 1_000)
        var scheduled: [(TimeInterval, @MainActor () -> Void)] = []
        let coalescer = IconLiveResolutionCoalescer(
            minimumInterval: 0.25,
            timing: .init(
                now: { now },
                schedule: { delay, action in scheduled.append((delay, action)) }
            )
        )
        var values: [Int] = []

        coalescer.request { values.append(1) }
        XCTAssertEqual(values, [1], "the first meaningful value must appear immediately")

        coalescer.request { values.append(2) }
        coalescer.request { values.append(3) }
        XCTAssertEqual(values, [1], "bursts wait for the rate limit")
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled[0].0, 0.25, accuracy: 0.0001)

        now = now.addingTimeInterval(0.25)
        scheduled[0].1()
        XCTAssertEqual(values, [1, 3], "only the newest trailing value runs")

        // A continuous stream cannot starve the tail: the last action still runs.
        now = now.addingTimeInterval(0.05)
        coalescer.request { values.append(4) }
        now = now.addingTimeInterval(0.05)
        coalescer.request { values.append(5) }
        XCTAssertEqual(scheduled.count, 2)
        now = now.addingTimeInterval(0.15)
        scheduled[1].1()
        XCTAssertEqual(values, [1, 3, 5])
    }

    // MARK: - Fixtures

    private static func registry() throws -> IconContentPluginRegistry {
        try IconContentPluginRegistry(plugins: [
            InputSourceIconPlugin(), NetworkIconPlugin(), BluetoothDeviceIconPlugin(),
            SystemBatteryIconPlugin(), AirPodsBatteryIconPlugin(),
            HardwareMonitorIconPlugin(), SystemVolumeIconPlugin(), LegacyIconPlugin(),
            DemandTestPlugin()
        ])
    }
}

private struct DemandTestPlugin: IconContentPlugin {
    let descriptor = IconContentPluginDescriptor(id: "test.external", presentations: [
        .init(id: "latency", slot: .center, title: .iconDesignerSourceNetwork,
              isSelectable: true, summary: .iconDesignerNetworkSummary),
        .init(id: "ring", slot: .outerRing, title: .iconDesignerSourceNetwork,
              isSelectable: true, summary: .iconDesignerNetworkSummary)
    ])

    func resolve(presentationID: String, context: IconContentContext) -> SourceResult<IconContentPayload> {
        if case let .unavailable(reason) = context.inputs.sources.result(
            for: "test.external", default: .available(true)) {
            return .unavailable(reason)
        }
        switch presentationID {
        case "latency":
            return .available(.center(.text(IconTextState(text: "42 ms", color: .primary, scale: 1))))
        case "ring":
            return .available(.outerRing(nil))
        default:
            return .unavailable(.unavailable)
        }
    }
}
