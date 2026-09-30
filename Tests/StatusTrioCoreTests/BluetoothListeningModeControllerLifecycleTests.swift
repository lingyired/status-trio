import CoreAudio
import Foundation
import XCTest

@testable import StatusTrioCore

/// A discovery source that returns canned endpoints and counts how often it was
/// asked, so the tests can pin the plan's "one discovery per refresh, never on a
/// timer" guarantee without touching CoreAudio.
private final class FakeEndpointProvider: CoreAudioBluetoothEndpointProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    let endpoints: [BluetoothListeningModeEndpoint]

    init(endpoints: [BluetoothListeningModeEndpoint]) {
        self.endpoints = endpoints
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _callCount
    }

    func discoverEndpoints(using hal: BluetoothListeningModeHAL) -> [BluetoothListeningModeEndpoint] {
        lock.lock()
        _callCount += 1
        lock.unlock()
        return endpoints
    }
}

/// The lifecycle the row depends on: resolution only for connected AirPods, a
/// write that publishes an in-flight state and reconciles it against the
/// read-back, a failure that rolls back to what the device actually reports,
/// cancellation when the device goes away, and no residual work once the panel
/// closes. The write side reuses the same scripted backend the HAL suite proves,
/// so the controller is tested against the real confirm/unconfirm/fail outcomes
/// rather than a mock of them.
@MainActor
final class BluetoothListeningModeControllerLifecycleTests: XCTestCase {
    private let deviceAddress = "AA:BB:CC:DD:EE:FF"
    private var key: String { BluetoothBatteryReader.normalizedAddress(deviceAddress) }
    private let endpointID: AudioDeviceID = 42

    // MARK: - Fixtures

    private func device(connected: Bool = true, airPods: Bool = true) -> BluetoothDevice {
        BluetoothDevice(
            id: deviceAddress,
            name: airPods ? "AirPods Pro" : "Plain Buds",
            kind: .audio,
            isConnected: connected
        )
    }

    private func capability(
        modes: [BluetoothListeningMode] = [.noiseCancellation, .transparency, .adaptive],
        current: BluetoothListeningMode? = .noiseCancellation,
        canSet: Bool = true
    ) -> BluetoothListeningModeCapability {
        BluetoothListeningModeCapability(
            audioDeviceID: endpointID,
            availableModes: modes,
            currentMode: current,
            canSet: canSet
        )
    }

    private func endpoint(
        address: String? = "aa:bb:cc:dd:ee:ff",
        isDefault: Bool = true,
        capability: BluetoothListeningModeCapability? = nil
    ) -> BluetoothListeningModeEndpoint {
        BluetoothListeningModeEndpoint(
            audioDeviceID: endpointID,
            capability: capability ?? self.capability(),
            isDefaultOutput: isDefault,
            bluetoothAddress: address
        )
    }

    /// A controller whose HAL writes through a scripted backend and settles the
    /// read-back instantly, with a short failure linger so rollback tests can
    /// observe the failure before it clears.
    ///
    /// The listener seam defaults to a fresh fake so a test can drive it directly;
    /// passing `nil` for `listenerBackend` opts out and installs a bare fake.
    private func makeController(
        endpoints: [BluetoothListeningModeEndpoint],
        backend: FakeListeningModeBackend = FakeListeningModeBackend(),
        listenerBackend: FakeListeningModeListenerBackend = FakeListeningModeListenerBackend(),
        attempts: Int = 16
    ) -> (BluetoothListeningModeController, FakeEndpointProvider, FakeListeningModeListenerBackend) {
        let hal = BluetoothListeningModeHAL(
            backend: backend,
            sleeper: ImmediateListeningModeSleeper(),
            retryAttempts: attempts,
            retryDelay: .milliseconds(1)
        )
        let provider = FakeEndpointProvider(endpoints: endpoints)
        let controller = BluetoothListeningModeController(
            hal: hal,
            endpointProvider: provider,
            listenerBackend: listenerBackend,
            failureClearDelay: .milliseconds(30)
        )
        return (controller, provider, listenerBackend)
    }

    /// Polls the main actor until `condition` holds, so a spawned write task gets a
    /// chance to run and publish before the assertion. Fails if it never settles.
    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("condition was not met within \(timeout)")
    }

    // MARK: - Resolution

    func testRefreshPublishesPresentationForResolvedEndpoint() {
        let (controller, _, _) = makeController(endpoints: [endpoint()])
        controller.refresh(devices: [device()])

        let presentation = controller.presentations[key]
        XCTAssertEqual(presentation?.availableModes, [.noiseCancellation, .transparency, .adaptive])
        XCTAssertEqual(presentation?.selectedMode, .noiseCancellation, "the current mode highlights")
        XCTAssertEqual(presentation?.actionState, .idle)
    }

    func testRefreshIgnoresDisconnectedAndNonAirPods() {
        let (controller, provider, _) = makeController(endpoints: [endpoint()])
        controller.refresh(devices: [device(connected: false), device(airPods: false)])

        XCTAssertTrue(controller.presentations.isEmpty, "nothing to control")
        XCTAssertEqual(provider.callCount, 0, "discovery runs only when there is an eligible device")
    }

    func testRefreshUsesConservativeFallbackWhenEndpointCarriesNoAddress() {
        // §6's accepted fallback path end-to-end: a single connected AirPods, a single
        // controllable endpoint that is the default output, no address evidence.
        let (controller, _, _) = makeController(endpoints: [endpoint(address: nil, isDefault: true)])
        controller.refresh(devices: [device()])
        XCTAssertNotNil(controller.presentations[key])
    }

    func testRefreshSkipsAmbiguousIdentityAndPublishesNothing() {
        // Two connected AirPods sharing no address evidence is ambiguous, so neither
        // resolves and no button appears — the safe outcome.
        let (controller, _, _) = makeController(endpoints: [endpoint(address: nil, isDefault: true)])
        let other = BluetoothDevice(
            id: "11:22:33:44:55:66",
            name: "Other AirPods",
            kind: .audio,
            isConnected: true
        )
        controller.refresh(devices: [device(), other])
        XCTAssertTrue(controller.presentations.isEmpty, "ambiguous identity fails closed")
    }

    func testRefreshDropsPresentationWhenDeviceGoesAway() async {
        let (controller, _, _) = makeController(endpoints: [endpoint()])
        controller.refresh(devices: [device()])
        XCTAssertNotNil(controller.presentations[key])

        controller.refresh(devices: [])
        XCTAssertTrue(controller.presentations.isEmpty)

        // The dropped address has no lingering presentation the next refresh could
        // accidentally resurrect from an old write's late completion.
        await waitUntil { controller.presentations.isEmpty }
    }

    // MARK: - Write: confirmed

    func testSetModePublishesChangingThenConfirms() async {
        // A scriptless backend stores the write, so the read-back settles on the target
        // and the controller reports it confirmed.
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2 // NC
        let (controller, _, _) = makeController(endpoints: [endpoint()], backend: backend)
        controller.refresh(devices: [device()])

        controller.setMode(.transparency, for: device())
        XCTAssertEqual(controller.presentations[key]?.actionState, .changing(to: .transparency))
        XCTAssertEqual(
            controller.presentations[key]?.selectedMode,
            .noiseCancellation,
            "the last confirmed selection stays visible while switching"
        )

        await waitUntil { controller.presentations[key]?.actionState == .idle }
        XCTAssertEqual(controller.presentations[key]?.selectedMode, .transparency)
        XCTAssertEqual(backend.writeCount, 1)
    }

    func testReTapOfSelectedModeWritesNothing() async {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 3 // already Transparency, and the capability highlights it
        let cap = capability(current: .transparency)
        let (controller, _, _) = makeController(
            endpoints: [endpoint(capability: cap)],
            backend: backend
        )
        controller.refresh(devices: [device()])
        XCTAssertEqual(controller.presentations[key]?.selectedMode, .transparency)

        controller.setMode(.transparency, for: device())

        XCTAssertEqual(controller.presentations[key]?.actionState, .idle, "a re-tap never starts a write")
        await waitUntil { backend.writeCount == 0 }
        XCTAssertEqual(backend.writeCount, 0)
    }

    func testRepeatTapWhileChangingDoesNotStackAWrite() async {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2
        backend.lstmReadScript = [2, 2, 2] // never confirms, so the first write lingers
        let (controller, _, _) = makeController(
            endpoints: [endpoint()],
            backend: backend,
            attempts: 4
        )
        controller.refresh(devices: [device()])

        controller.setMode(.transparency, for: device())
        XCTAssertEqual(controller.presentations[key]?.actionState, .changing(to: .transparency))
        // A second tap on a different mode while one is in flight is ignored.
        controller.setMode(.adaptive, for: device())
        XCTAssertEqual(
            controller.presentations[key]?.actionState,
            .changing(to: .transparency),
            "the in-flight request is not replaced mid-write"
        )
    }

    // MARK: - Write: unconfirmed / failed rollback

    func testUnconfirmedWriteRollsBackToObservedMode() async {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2
        backend.lstmReadScript = [2, 2, 2] // the setter accepted it but the device stays on NC
        let (controller, _, _) = makeController(
            endpoints: [endpoint()],
            backend: backend,
            attempts: 3
        )
        controller.refresh(devices: [device()])

        controller.setMode(.transparency, for: device())
        await waitUntil { self.isFailed(controller.presentations[key]?.actionState) }

        let presentation = controller.presentations[key]
        XCTAssertEqual(presentation?.selectedMode, .noiseCancellation, "rolls back to the observed mode")
        XCTAssertNotEqual(presentation?.selectedMode, .transparency, "never shows the mode that failed to land")
        XCTAssertTrue(isFailed(presentation?.actionState))

        // The failure then clears itself back to idle without changing the selection.
        await waitUntil { controller.presentations[key]?.actionState == .idle }
        XCTAssertEqual(controller.presentations[key]?.selectedMode, .noiseCancellation)
    }

    func testFailedWriteRollsBackThroughAReRead() async {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2
        backend.writeStatus = kAudioHardwareBadObjectError
        let (controller, _, _) = makeController(endpoints: [endpoint()], backend: backend)
        controller.refresh(devices: [device()])

        controller.setMode(.transparency, for: device())
        await waitUntil { self.isFailed(controller.presentations[key]?.actionState) }

        // The `.failed` path re-reads the live mode, which still reads NC.
        XCTAssertEqual(controller.presentations[key]?.selectedMode, .noiseCancellation)
        XCTAssertTrue(isFailed(controller.presentations[key]?.actionState))
    }

    // MARK: - Cancellation & teardown

    func testStopClearsSurfaceAndStopsPublishing() async {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2
        backend.lstmReadScript = [2, 2, 2]
        let (controller, _, _) = makeController(endpoints: [endpoint()], backend: backend, attempts: 8)
        controller.refresh(devices: [device()])
        controller.setMode(.transparency, for: device())

        controller.stop()
        XCTAssertTrue(controller.presentations.isEmpty)

        // A completion from the cancelled write cannot repopulate a cleared surface.
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(controller.presentations.isEmpty)
    }

    func testDroppedAddressRejectsLateCompletion() async {
        // Start a write that will finish unconfirmed, then drop the device so the
        // write's generation is invalidated; its late apply must not republish.
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2
        backend.lstmReadScript = [2, 2, 2]
        let (controller, _, _) = makeController(endpoints: [endpoint()], backend: backend, attempts: 8)
        controller.refresh(devices: [device()])
        controller.setMode(.transparency, for: device())

        controller.refresh(devices: []) // supersede the write's generation

        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertNil(controller.presentations[key], "a stale completion is discarded")
    }

    func testDiscoveryRunsOncePerRefreshNotOnATimer() async {
        let (controller, provider, _) = makeController(endpoints: [endpoint()])
        controller.refresh(devices: [device()])
        XCTAssertEqual(provider.callCount, 1)

        // No background task re-reads it: left alone, the count never climbs.
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(provider.callCount, 1, "there is no polling")
    }

    // MARK: - External `lstm` change

    func testRefreshSubscribesListeningModeListenerPerEndpoint() {
        let (controller, _, listener) = makeController(endpoints: [endpoint()])
        controller.refresh(devices: [device()])

        XCTAssertTrue(listener.hasRegistration(for: endpointID))
        XCTAssertEqual(listener.addCount, 1)
    }

    func testPreviewModeSubscribesNothing() {
        let (controller, _, listener) = makeController(endpoints: [endpoint()])
        controller.previewMode = true
        controller.refresh(devices: [device()])

        XCTAssertEqual(listener.addCount, 0, "preview has no real device to listen to")
        XCTAssertFalse(listener.hasRegistration(for: endpointID))
    }

    func testExternalChangeRepublishesSelectedMode() async {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2 // NC at refresh time
        let (controller, _, listener) = makeController(endpoints: [endpoint()], backend: backend)
        controller.refresh(devices: [device()])
        XCTAssertEqual(controller.presentations[key]?.selectedMode, .noiseCancellation)

        // The stem (or Control Center) moves the device to Transparency. Our scripted
        // backend stores the value; `handleExternalChange` re-reads `lstm` on the
        // MainActor hop and settles the presentation on what the device reports.
        backend.lstm.value = 3
        listener.trigger(deviceID: endpointID)

        await waitUntil { self.controllerHasMode(controller, mode: .transparency) }
        XCTAssertEqual(controller.presentations[key]?.actionState, .idle)
    }

    func testExternalChangeIsIgnoredWhileOurWriteIsInFlight() async {
        // A "stalled" sleeper keeps the write's read-back parked in `await sleep`,
        // so the presentation stays `.changing(to:)` while we fire the external
        // signal. This proves `handleExternalChange` never overwrites an in-flight
        // write — if it did, the tap's spinner would disappear under the finger.
        //
        // Sequencing matters: `hal.setMode` shortcuts to `.confirmed` when the
        // device already reads the target, which would skip the parked await and
        // settle the presentation. We let the write task start first, then flip
        // the stored value; `writeUInt32` in the fake already moves `lstm.value`
        // to the target before `confirmWrite` parks, so the flip is a no-op for
        // the read-back — it only represents that "the device is now on the
        // target for reasons beyond our write", the case the guard must ignore.
        struct StalledSleeper: BluetoothListeningModeSleeping {
            func sleep(for duration: Duration) async {
                try? await Task.sleep(for: .seconds(60))
            }
        }

        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2 // NC at refresh
        let listener = FakeListeningModeListenerBackend()
        let hal = BluetoothListeningModeHAL(
            backend: backend,
            sleeper: StalledSleeper(),
            retryAttempts: 4,
            retryDelay: .seconds(1)
        )
        let controller = BluetoothListeningModeController(
            hal: hal,
            endpointProvider: FakeEndpointProvider(endpoints: [endpoint()]),
            listenerBackend: listener,
            failureClearDelay: .milliseconds(30)
        )
        controller.refresh(devices: [device()])
        controller.setMode(.transparency, for: device())
        XCTAssertEqual(controller.presentations[key]?.actionState, .changing(to: .transparency))

        // Let the write task's `hal.setMode` complete its synchronous prefix (initial
        // read reports NC, write succeeds) and park inside `confirmWrite`'s first
        // `await sleeper.sleep`. From this point the presentation is genuinely in
        // flight until the 60-second sleep expires.
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(
            controller.presentations[key]?.actionState,
            .changing(to: .transparency),
            "write task parked in the sleeper, presentation still in flight"
        )

        // Fire the "external" signal. A naive handler would publish `.settled(on:
        // .transparency)` — matching the value the device now reports — and clear
        // the spinner. The correct behavior is to drop the signal and let the write
        // path settle when CoreAudio confirms.
        listener.trigger(deviceID: endpointID)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(
            controller.presentations[key]?.actionState,
            .changing(to: .transparency),
            "an external signal never overwrites a write still reconciling"
        )

        controller.stop() // release the stalled write task
    }

    func testEndpointDropUnsubscribes() {
        let (controller, _, listener) = makeController(endpoints: [endpoint()])
        controller.refresh(devices: [device()])
        XCTAssertTrue(listener.hasRegistration(for: endpointID))

        controller.refresh(devices: []) // AirPods disconnected
        XCTAssertFalse(listener.hasRegistration(for: endpointID))
        XCTAssertEqual(listener.removeCount, 1)
    }

    func testStopRemovesEverySubscription() {
        let (controller, _, listener) = makeController(endpoints: [endpoint()])
        controller.refresh(devices: [device()])
        XCTAssertEqual(listener.addCount, 1)

        controller.stop()
        XCTAssertFalse(listener.hasRegistration(for: endpointID), "panel close leaves no residual listener")
        XCTAssertEqual(listener.removeCount, 1)
    }

    func testRealToPreviewTransitionUnsubscribes() {
        let (controller, _, listener) = makeController(endpoints: [endpoint()])
        controller.refresh(devices: [device()])
        XCTAssertTrue(listener.hasRegistration(for: endpointID))

        controller.previewMode = true
        controller.refresh(devices: [device()])
        XCTAssertFalse(
            listener.hasRegistration(for: endpointID),
            "preview takes over — the real endpoint's subscription must go away"
        )
    }

    private func controllerHasMode(
        _ controller: BluetoothListeningModeController,
        mode: BluetoothListeningMode
    ) -> Bool {
        controller.presentations[key]?.selectedMode == mode
    }

    private func isFailed(_ state: BluetoothListeningModeActionState?) -> Bool {
        if case .failed = state { return true }
        return false
    }
}
