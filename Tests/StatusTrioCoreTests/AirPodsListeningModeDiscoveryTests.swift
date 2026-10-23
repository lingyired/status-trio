import Combine
import CoreAudio
import Foundation
import Testing

@testable import StatusTrioCore

@MainActor
struct AirPodsListeningModeDiscoveryTests {
    private let device = BluetoothDevice(
        id: "AA:BB:CC:DD:EE:FF",
        name: "AirPods Pro 2",
        kind: .audio,
        isConnected: true
    )

    @Test(.timeLimit(.minutes(1)))
    func endpointBecomingReadyAfterConnectionPublishesControlsWithoutAnotherRefresh() async throws {
        let retryGate = DiscoveryRetryGate()
        let provider = DelayedAirPodsEndpointProvider()
        let controller = BluetoothListeningModeController(
            hal: BluetoothListeningModeHAL(backend: FakeListeningModeBackend()),
            endpointProvider: provider,
            listenerBackend: FakeListeningModeListenerBackend(),
            airPodsDiscoverySleep: { duration in await retryGate.sleep(duration) }
        )
        let events = observeDiscoveryUpdates(controller.$presentations)
        defer { controller.stop(); retryGate.releaseAll(); events.observation.cancel() }

        controller.refresh(devices: [device])
        #expect(controller.control(forEndpoint: 42) == nil)
        let retryDelay = await retryGate.nextCall()
        try #require(retryDelay == .milliseconds(150))
        provider.isReady = true
        retryGate.releaseAll()

        let appeared = await events.stream.first { @Sendable in $0["AABBCCDDEEFF"] != nil }
        try #require(appeared != nil, "A connected AirPods endpoint may become ready after the first discovery")
        #expect(controller.control(forEndpoint: 42)?.presentation.selectedMode == .noiseCancellation)
    }

    @Test func modePropertiesBecomingReadableAreRetriedWithoutWritingToTheDevice() async throws {
        let sleeper = ManualEventSleeper()
        let provider = DelayedAirPodsEndpointProvider()
        provider.isReady = true
        let backend = FakeListeningModeBackend()
        backend.lsms.exists = false
        let controller = makeController(provider: provider, sleeper: sleeper, backend: backend)
        defer { controller.stop(); sleeper.releaseAll() }
        controller.refresh(devices: [device])
        let waiting = await sleeper.waitForCallCount(1, timeout: .seconds(2))
        try #require(waiting)

        backend.lsms.exists = true
        sleeper.releaseAll()
        let appeared = await discoveryEventually { controller.control(forEndpoint: 42) != nil }
        #expect(appeared)
        #expect(backend.writeCount == 0)
        #expect(sleeper.callCount == 1, "Successful discovery must end the retry sequence")
    }

    @Test func unavailableEndpointsExhaustTheirBudgetUntilTheNextExplicitRefresh() async throws {
        let sleeper = ManualEventSleeper()
        let provider = DelayedAirPodsEndpointProvider()
        let controller = BluetoothListeningModeController(
            hal: BluetoothListeningModeHAL(backend: FakeListeningModeBackend()),
            endpointProvider: provider,
            listenerBackend: FakeListeningModeListenerBackend(),
            airPodsDiscoverySleep: { duration in await sleeper.sleep(duration) }
        )
        defer { controller.stop(); sleeper.releaseAll() }
        controller.refresh(devices: [device])

        for count in 1...3 {
            let waiting = await sleeper.waitForCallCount(count, timeout: .seconds(2))
            try #require(waiting)
            sleeper.releaseAll()
        }
        let exhausted = await discoveryEventually { sleeper.completionCount == 3 }
        try #require(exhausted)
        provider.isReady = true
        for _ in 0..<20 { await Task.yield() }
        #expect(controller.presentations.isEmpty)
        #expect(provider.discoveryCount == 4, "Initial discovery plus three retries; no recurring poll")
        #expect(sleeper.durations == [.milliseconds(150), .milliseconds(450), .seconds(1)])

        controller.refresh(devices: [device])
        #expect(controller.control(forEndpoint: 42) != nil)
    }

    enum EndOfDemand: CaseIterable {
        case stop, disconnect, preview
    }

    @Test(arguments: EndOfDemand.allCases)
    func endingDemandRejectsALateReadinessRetry(_ reason: EndOfDemand) async throws {
        let sleeper = ManualEventSleeper()
        let provider = DelayedAirPodsEndpointProvider()
        let controller = makeController(provider: provider, sleeper: sleeper)
        defer { controller.stop(); sleeper.releaseAll() }
        controller.refresh(devices: [device])
        let waiting = await sleeper.waitForCallCount(1, timeout: .seconds(2))
        try #require(waiting)

        switch reason {
        case .stop:
            controller.stop()
        case .disconnect:
            controller.refresh(devices: [])
        case .preview:
            controller.previewMode = true
            controller.refresh(devices: [
                BluetoothDevice(id: "PREVIEW:1", name: "Preview", kind: .audio, isConnected: true)
            ])
        }
        provider.isReady = true
        sleeper.releaseAll()
        let released = await discoveryEventually { sleeper.completionCount == 1 }
        #expect(released)
        #expect(controller.control(forEndpoint: 42) == nil)
        #expect(provider.discoveryCount == 1, "A cancelled retry must not probe even if its sleep ignores cancellation")
    }

    @Test func aNewDeviceSnapshotSupersedesThePendingDiscovery() async throws {
        let sleeper = ManualEventSleeper()
        let provider = DelayedAirPodsEndpointProvider()
        let controller = makeController(provider: provider, sleeper: sleeper)
        defer { controller.stop(); sleeper.releaseAll() }
        controller.refresh(devices: [device])
        let oldWaiting = await sleeper.waitForCallCount(1, timeout: .seconds(2))
        try #require(oldWaiting)

        let replacement = BluetoothDevice(
            id: "11:22:33:44:55:66", name: "Other AirPods", kind: .audio, isConnected: true
        )
        controller.refresh(devices: [replacement])
        let newWaiting = await sleeper.waitForCallCount(2, timeout: .seconds(2))
        try #require(newWaiting)
        provider.isReady = true
        sleeper.releaseAll()
        let appeared = await discoveryEventually { controller.control(forEndpoint: 42) != nil }
        #expect(appeared)
        #expect(controller.control(forEndpoint: 42)?.address == "112233445566")
        #expect(controller.presentations["AABBCCDDEEFF"] == nil)
    }

    @Test func ambiguousConnectionsDoNotStartReadinessRetries() async {
        let sleeper = ManualEventSleeper()
        let provider = DelayedAirPodsEndpointProvider()
        provider.isReady = true
        let controller = makeController(provider: provider, sleeper: sleeper)
        defer { controller.stop(); sleeper.releaseAll() }
        controller.refresh(devices: [
            device,
            BluetoothDevice(id: "11:22:33:44:55:66", name: "Other AirPods", kind: .audio, isConnected: true)
        ])
        for _ in 0..<20 { await Task.yield() }
        #expect(controller.presentations.isEmpty)
        #expect(sleeper.callCount == 0)
    }

    @Test func waitingForReadinessDoesNotRetainTheController() async throws {
        let sleeper = ManualEventSleeper()
        let provider = DelayedAirPodsEndpointProvider()
        var controller: BluetoothListeningModeController? = makeController(provider: provider, sleeper: sleeper)
        weak var releasedController = controller
        controller?.refresh(devices: [device])
        let waiting = await sleeper.waitForCallCount(1, timeout: .seconds(2))
        try #require(waiting)
        controller = nil
        #expect(releasedController == nil)
        sleeper.releaseAll()
    }

    @Test func observationPreservesReadyControlsEvenIfTheyAreClearedBeforeConsumption() async {
        let controller = BluetoothListeningModeController(
            hal: BluetoothListeningModeHAL(backend: FakeListeningModeBackend()),
            endpointProvider: DelayedAirPodsEndpointProvider(),
            listenerBackend: FakeListeningModeListenerBackend()
        )
        controller.previewMode = true
        let events = observeDiscoveryUpdates(controller.$presentations)
        controller.refresh(devices: [
            BluetoothDevice(id: "PREVIEW:1", name: "Preview", kind: .audio, isConnected: true)
        ])
        controller.stop()
        events.observation.cancel()

        var readyWasPublished = false
        for await presentations in events.stream {
            if !presentations.isEmpty { readyWasPublished = true }
        }
        #expect(readyWasPublished, "Clearing controls must not erase a prior readiness event from the observation")
    }

    private func makeController(
        provider: DelayedAirPodsEndpointProvider,
        sleeper: ManualEventSleeper,
        backend: FakeListeningModeBackend = FakeListeningModeBackend()
    ) -> BluetoothListeningModeController {
        BluetoothListeningModeController(
            hal: BluetoothListeningModeHAL(backend: backend),
            endpointProvider: provider,
            listenerBackend: FakeListeningModeListenerBackend(),
            airPodsDiscoveryRetryDelays: [.milliseconds(10), .milliseconds(20)],
            airPodsDiscoverySleep: { duration in await sleeper.sleep(duration) }
        )
    }
}

final class DelayedAirPodsEndpointProvider: CoreAudioBluetoothEndpointProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var ready = false
    private var discoveries = 0

    var discoveryCount: Int { lock.withLock { discoveries } }

    var isReady: Bool {
        get { lock.withLock { ready } }
        set { lock.withLock { ready = newValue } }
    }

    func discoverEndpoints(using hal: BluetoothListeningModeHAL) -> [BluetoothListeningModeEndpoint] {
        let ready = lock.withLock {
            discoveries += 1
            return self.ready
        }
        guard ready, let capability = hal.capability(for: 42) else { return [] }
        return [
            BluetoothListeningModeEndpoint(
                audioDeviceID: 42,
                capability: capability,
                isDefaultOutput: true,
                bluetoothAddress: nil
            )
        ]
    }
}

@MainActor
func observeDiscoveryUpdates<Value: Sendable>(
    _ publisher: Published<Value>.Publisher
) -> (stream: AsyncStream<Value>, observation: AnyCancellable) {
    let pair = AsyncStream<Value>.makeStream(bufferingPolicy: .unbounded)
    let subscription = publisher.dropFirst().sink { pair.continuation.yield($0) }
    return (pair.stream, AnyCancellable {
        subscription.cancel()
        pair.continuation.finish()
    })
}

@MainActor
private final class DiscoveryRetryGate {
    private let pair = AsyncStream<Duration>.makeStream(bufferingPolicy: .unbounded)
    private var sleepers: [CheckedContinuation<Void, Never>] = []

    func nextCall() async -> Duration? {
        var iterator = pair.stream.makeAsyncIterator()
        return await iterator.next()
    }

    func sleep(_ duration: Duration) async {
        pair.continuation.yield(duration)
        await withCheckedContinuation { sleepers.append($0) }
    }

    func releaseAll() {
        let pending = sleepers
        sleepers.removeAll()
        pending.forEach { $0.resume() }
    }
}

@MainActor
func discoveryEventually(_ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
