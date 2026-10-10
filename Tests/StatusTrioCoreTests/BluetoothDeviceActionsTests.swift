import Foundation
import XCTest
@testable import StatusTrioCore

/// Tapping a device row asks the system to connect or disconnect it. Nothing in
/// this path flips a row optimistically: the report decides, the request only
/// starts a wait that either sees the report change or fails.
@MainActor
final class BluetoothDeviceActionsTests: XCTestCase {
    private let airPodsAddress = "AC:90:85:C2:9C:1F"

    private func makeDevice(isConnected: Bool, name: String = "AirPods", kind: BluetoothDeviceKind = .audio) -> BluetoothDevice {
        BluetoothDevice(id: airPodsAddress, name: name, kind: kind, isConnected: isConnected)
    }

    private func makeController(
        device: BluetoothDevice,
        performer: any BluetoothDeviceActionPerforming,
        timeoutSleeper: ManualEventSleeper,
        failureSleeper: ManualEventSleeper
    ) -> (BluetoothDeviceController, MutableBluetoothDeviceReader) {
        let reader = MutableBluetoothDeviceReader(devices: [device])
        let controller = BluetoothDeviceController(
            worker: reader,
            stateMonitor: ActionTestStateMonitor(),
            batteryReader: SilentBluetoothBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            actionPerformer: performer,
            actionTimeoutSleep: { duration in await timeoutSleeper.sleep(duration) },
            failureVisibleSleep: { duration in await failureSleeper.sleep(duration) }
        )
        return (controller, reader)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for the controller to settle")
    }

    /// A row a reading created is not a paired device, so there is nothing for a
    /// tap to ask the system: the app knows it by a CoreBluetooth identifier,
    /// which is not a Bluetooth address the action could be aimed at. Its row is
    /// read-only, and the view reads this rule rather than deciding for itself.
    func testAPolicyOffersNoActionForARowAReadingCreated() {
        let reading = BluetoothDevice(
            id: UUID().uuidString,
            name: "Ling's iPhone",
            kind: .mobile(.phone),
            isConnected: false,
            isReadOverTheAir: true
        )

        XCTAssertFalse(BluetoothDeviceActionPolicy.isActionable(reading))
        XCTAssertTrue(BluetoothDeviceActionPolicy.isActionable(makeDevice(isConnected: true)))
    }

    func testTapOnAnUnconnectedDeviceAsksToConnectAndShowsConnecting() async {
        let device = makeDevice(isConnected: false)
        let performer = BluetoothActionPerformerStub()
        let timeoutSleeper = ManualEventSleeper()
        let failureSleeper = ManualEventSleeper()
        let (controller, _) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: timeoutSleeper,
            failureSleeper: failureSleeper
        )
        controller.activate()
        await waitUntil { controller.availability == .available }

        controller.performDeviceAction(for: device)

        XCTAssertEqual(performer.requests.map(\.connected), [true])
        XCTAssertEqual(
            performer.requests.map(\.address),
            [BluetoothBatteryReader.normalizedAddress(airPodsAddress)]
        )
        XCTAssertEqual(
            controller.deviceActionStates[BluetoothBatteryReader.normalizedAddress(airPodsAddress)],
            .connecting
        )
        XCTAssertEqual(
            BluetoothDeviceActionPolicy.status(for: device, actionState: .connecting),
            .connecting
        )
        controller.deactivate()
    }

    func testConnectingClearsOnlyWhenTheReportShowsTheDeviceConnected() async {
        let device = makeDevice(isConnected: false)
        let performer = BluetoothActionPerformerStub()
        let (controller, reader) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: ManualEventSleeper()
        )
        controller.activate()
        await waitUntil { controller.availability == .available }
        controller.performDeviceAction(for: device)
        let address = BluetoothBatteryReader.normalizedAddress(airPodsAddress)

        // The request was accepted, but the report has not changed yet: the row
        // must still say it is working.
        XCTAssertEqual(controller.deviceActionStates[address], .connecting)

        reader.devices = [makeDevice(isConnected: true)]
        controller.refresh()

        await waitUntil { controller.deviceActionStates[address] == nil }
        controller.deactivate()
    }

    func testDisconnectingClearsWhenTheReportShowsTheDeviceGone() async {
        let device = makeDevice(isConnected: true)
        let performer = BluetoothActionPerformerStub()
        let (controller, reader) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: ManualEventSleeper()
        )
        controller.activate()
        await waitUntil { controller.availability == .available }
        controller.performDeviceAction(for: device)
        let address = BluetoothBatteryReader.normalizedAddress(airPodsAddress)
        XCTAssertEqual(performer.requests.map(\.connected), [false])
        XCTAssertEqual(controller.deviceActionStates[address], .disconnecting)

        reader.devices = [makeDevice(isConnected: false)]
        controller.refresh()

        await waitUntil { controller.deviceActionStates[address] == nil }
        controller.deactivate()
    }

    func testARejectedRequestFailsImmediately() async {
        let device = makeDevice(isConnected: false)
        let performer = BluetoothActionPerformerStub()
        performer.accepted = false
        let (controller, _) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: ManualEventSleeper()
        )
        controller.activate()
        await waitUntil { controller.availability == .available }

        controller.performDeviceAction(for: device)
        let address = BluetoothBatteryReader.normalizedAddress(airPodsAddress)
        await waitUntil { controller.deviceActionStates[address] == .failed(.connect) }
        controller.deactivate()
    }

    func testAnAcceptedRequestThatNeverChangesTheReportTimesOut() async {
        let device = makeDevice(isConnected: false)
        let performer = BluetoothActionPerformerStub()
        let timeoutSleeper = ManualEventSleeper()
        let (controller, _) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: timeoutSleeper,
            failureSleeper: ManualEventSleeper()
        )
        controller.activate()
        await waitUntil { controller.availability == .available }
        controller.performDeviceAction(for: device)
        let address = BluetoothBatteryReader.normalizedAddress(airPodsAddress)

        let armed = await timeoutSleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertTrue(armed, "the action must arm a timeout")
        XCTAssertEqual(timeoutSleeper.durations.first, .seconds(10))
        timeoutSleeper.releaseAll()

        await waitUntil { controller.deviceActionStates[address] == .failed(.connect) }
        controller.deactivate()
    }

    func testAFailureClearsItselfAfterTheVisibleDuration() async {
        let device = makeDevice(isConnected: false)
        let performer = BluetoothActionPerformerStub()
        performer.accepted = false
        let failureSleeper = ManualEventSleeper()
        let (controller, _) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: failureSleeper
        )
        controller.activate()
        await waitUntil { controller.availability == .available }
        controller.performDeviceAction(for: device)
        let address = BluetoothBatteryReader.normalizedAddress(airPodsAddress)
        await waitUntil { controller.deviceActionStates[address] == .failed(.connect) }

        let armed = await failureSleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertTrue(armed, "a failure must arm its own clear")
        XCTAssertEqual(failureSleeper.durations.first, .seconds(4))
        failureSleeper.releaseAll()

        await waitUntil { controller.deviceActionStates[address] == nil }
        controller.deactivate()
    }

    func testASecondTapWhileInFlightSendsNoSecondRequest() async {
        let device = makeDevice(isConnected: false)
        let performer = BluetoothActionPerformerStub()
        let (controller, _) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: ManualEventSleeper()
        )
        controller.activate()
        await waitUntil { controller.availability == .available }

        controller.performDeviceAction(for: device)
        controller.performDeviceAction(for: device)
        controller.performDeviceAction(for: device)

        XCTAssertEqual(performer.requests.count, 1)
        controller.deactivate()
    }

    func testALateRefusalFromASupersededRequestDoesNotDecideTheRetry() async {
        let device = makeDevice(isConnected: false)
        let performer = DeferredBluetoothActionPerformer()
        let timeoutSleeper = ManualEventSleeper()
        let (controller, _) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: timeoutSleeper,
            failureSleeper: ManualEventSleeper()
        )
        controller.activate()
        await waitUntil { controller.availability == .available }
        let address = BluetoothBatteryReader.normalizedAddress(airPodsAddress)

        // The first request never answers: it blocks past the timeout, the row
        // reports the failure, and the user tries again.
        controller.performDeviceAction(for: device)
        _ = await timeoutSleeper.waitForCallCount(1, timeout: .seconds(1))
        timeoutSleeper.releaseAll()
        await waitUntil { controller.deviceActionStates[address] == .failed(.connect) }

        controller.performDeviceAction(for: device)
        await waitUntil { controller.deviceActionStates[address] == .connecting }

        // The superseded request finally answers "refused". That answer belongs
        // to the request the retry replaced, so the retry must be untouched.
        performer.answerFirst(accepted: false)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(
            controller.deviceActionStates[address],
            .connecting,
            "a superseded request must not decide the live one"
        )
        controller.deactivate()
    }

    func testALateRefusalAfterTheReportSettledShowsNoFailure() async {
        let device = makeDevice(isConnected: false)
        let performer = DeferredBluetoothActionPerformer()
        let (controller, reader) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: ManualEventSleeper()
        )
        controller.activate()
        await waitUntil { controller.availability == .available }
        let address = BluetoothBatteryReader.normalizedAddress(airPodsAddress)

        controller.performDeviceAction(for: device)
        // The device connects on its own before the command answers.
        reader.devices = [makeDevice(isConnected: true)]
        controller.refresh()
        await waitUntil { controller.deviceActionStates[address] == nil }

        // The now-redundant command finally answers "refused". It belongs to an
        // action the report already settled, so it must not paint a failure.
        performer.answerFirst(accepted: false)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(
            controller.deviceActionStates[address],
            "a settled action must not be failed by its own late answer"
        )
        controller.deactivate()
    }

    func testAFailedRowAcceptsARetry() async {
        let device = makeDevice(isConnected: false)
        let performer = BluetoothActionPerformerStub()
        performer.accepted = false
        let (controller, _) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: ManualEventSleeper()
        )
        controller.activate()
        await waitUntil { controller.availability == .available }
        controller.performDeviceAction(for: device)
        let address = BluetoothBatteryReader.normalizedAddress(airPodsAddress)
        await waitUntil { controller.deviceActionStates[address] == .failed(.connect) }

        controller.performDeviceAction(for: device)

        XCTAssertEqual(performer.requests.count, 2)
        controller.deactivate()
    }

    func testAConfirmationIsHeldUntilItIsCancelled() {
        let device = makeDevice(isConnected: true, name: "MX Keys", kind: .peripheral(.keyboard))
        let (controller, _) = makeController(
            device: device,
            performer: BluetoothActionPerformerStub(),
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: ManualEventSleeper()
        )

        controller.requestDisconnectConfirmation(for: device)
        XCTAssertEqual(
            controller.pendingDisconnectConfirmation,
            BluetoothBatteryReader.normalizedAddress(airPodsAddress)
        )

        controller.cancelDisconnectConfirmation()
        XCTAssertNil(controller.pendingDisconnectConfirmation)
    }

    func testAConfirmationIsOnlyHeldForADeviceThePolicyWouldAsk() {
        let audio = makeDevice(isConnected: true, kind: .audio)
        let idleKeyboard = makeDevice(isConnected: false, name: "MX Keys", kind: .peripheral(.keyboard))
        let (controller, _) = makeController(
            device: audio,
            performer: BluetoothActionPerformerStub(),
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: ManualEventSleeper()
        )

        controller.requestDisconnectConfirmation(for: audio)
        XCTAssertNil(controller.pendingDisconnectConfirmation)

        controller.requestDisconnectConfirmation(for: idleKeyboard)
        XCTAssertNil(controller.pendingDisconnectConfirmation)
    }

    func testPerformingAnActionAnswersAPendingConfirmation() async {
        let device = makeDevice(isConnected: true, name: "MX Keys", kind: .peripheral(.keyboard))
        let (controller, _) = makeController(
            device: device,
            performer: BluetoothActionPerformerStub(),
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: ManualEventSleeper()
        )
        controller.activate()
        await waitUntil { controller.availability == .available }
        controller.requestDisconnectConfirmation(for: device)

        controller.performDeviceAction(for: device)

        XCTAssertNil(controller.pendingDisconnectConfirmation)
        controller.deactivate()
    }

    func testDeactivatingCancelsAPendingConfirmation() async {
        let device = makeDevice(isConnected: true, name: "MX Keys", kind: .peripheral(.keyboard))
        let (controller, _) = makeController(
            device: device,
            performer: BluetoothActionPerformerStub(),
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: ManualEventSleeper()
        )
        controller.activate()
        await waitUntil { controller.availability == .available }
        controller.requestDisconnectConfirmation(for: device)

        controller.deactivate()

        XCTAssertNil(controller.pendingDisconnectConfirmation)
    }

    func testDeactivatingClearsEveryActionState() async {
        let device = makeDevice(isConnected: false)
        let performer = BluetoothActionPerformerStub()
        let (controller, _) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: ManualEventSleeper()
        )
        controller.activate()
        await waitUntil { controller.availability == .available }
        controller.performDeviceAction(for: device)

        controller.deactivate()

        XCTAssertTrue(controller.deviceActionStates.isEmpty)
    }

    func testOnlyDisconnectingAnInputDeviceNeedsConfirmation() {
        XCTAssertTrue(
            BluetoothDeviceActionPolicy.requiresConfirmation(
                for: makeDevice(isConnected: true, name: "MX Keys", kind: .peripheral(.keyboard))
            )
        )
        XCTAssertFalse(
            BluetoothDeviceActionPolicy.requiresConfirmation(
                for: makeDevice(isConnected: false, name: "MX Keys", kind: .peripheral(.keyboard))
            )
        )
        for kind in [BluetoothDeviceKind.audio, .computer(.unclassified), .mobile(.phone)] {
            XCTAssertFalse(
                BluetoothDeviceActionPolicy.requiresConfirmation(
                    for: makeDevice(isConnected: true, kind: kind)
                ),
                "\(kind) must disconnect without a confirmation"
            )
        }
        XCTAssertTrue(
            BluetoothDeviceActionPolicy.requiresConfirmation(
                for: makeDevice(isConnected: true, kind: .unknown)
            ),
            "unknown connected devices must disconnect with a confirmation"
        )
    }

    func testAmbiguousUnknownHIDDeviceRequiresDisconnectConfirmation() {
        let seeded = BluetoothInputIconSeed.apply(
            to: [makeDevice(isConnected: true, name: "Combo Input", kind: .unknown)],
            hidUsages: [
                BluetoothBatteryReader.normalizedAddress(airPodsAddress): [
                    BluetoothHIDUsage(usagePage: 1, usage: 2),
                    BluetoothHIDUsage(usagePage: 1, usage: 6),
                ]
            ]
        )

        // The class stays unknown; only the drawn glyph is refined. An unknown
        // connected device still confirms before disconnecting.
        XCTAssertEqual(seeded.first?.kind, .unknown)
        XCTAssertEqual(seeded.first?.inputIconClassification, .genericInput)
        XCTAssertTrue(BluetoothDeviceActionPolicy.requiresConfirmation(for: seeded[0]))
    }

    func testTheActionFollowsTheConnectionState() {
        XCTAssertEqual(BluetoothDeviceActionPolicy.action(for: makeDevice(isConnected: true)), .disconnect)
        XCTAssertEqual(BluetoothDeviceActionPolicy.action(for: makeDevice(isConnected: false)), .connect)
    }

    func testTheRowStatusFollowsTheActionState() {
        let device = makeDevice(isConnected: true)

        XCTAssertEqual(BluetoothDeviceActionPolicy.status(for: device, actionState: nil), .connected)
        XCTAssertEqual(
            BluetoothDeviceActionPolicy.status(for: makeDevice(isConnected: false), actionState: nil),
            .notConnected
        )
        XCTAssertEqual(
            BluetoothDeviceActionPolicy.status(for: device, actionState: .connecting),
            .connecting
        )
        XCTAssertEqual(
            BluetoothDeviceActionPolicy.status(for: device, actionState: .disconnecting),
            .disconnecting
        )
        XCTAssertEqual(
            BluetoothDeviceActionPolicy.status(for: device, actionState: .failed(.connect)),
            .connectFailed
        )
        XCTAssertEqual(
            BluetoothDeviceActionPolicy.status(for: device, actionState: .failed(.disconnect)),
            .disconnectFailed
        )
    }

    /// A connected device is drawn with a ringed icon, a semibold name and a
    /// checkmark, so the row does not also say "connected" in words — that space
    /// is for the battery level. Only what the appearance cannot say, an action in
    /// flight or a failure, is written out.
    func testOnlyATransientStateIsWrittenOut() {
        XCTAssertFalse(BluetoothDeviceRowStatus.connected.drawsText)
        XCTAssertFalse(BluetoothDeviceRowStatus.notConnected.drawsText)
        for transient in [
            BluetoothDeviceRowStatus.connecting,
            .disconnecting,
            .connectFailed,
            .disconnectFailed
        ] {
            XCTAssertTrue(transient.drawsText, "\(transient) has to be written out")
        }
    }
}

private final class BluetoothActionPerformerStub: BluetoothDeviceActionPerforming {
    private(set) var requests: [(connected: Bool, address: String)] = []
    var accepted = true

    func setConnected(
        _ connected: Bool,
        forAddress address: String,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        requests.append((connected, address))
        completion(accepted)
    }
}

private final class DeferredBluetoothActionPerformer: BluetoothDeviceActionPerforming {
    private(set) var requests: [(connected: Bool, address: String)] = []
    private var completions: [@Sendable (Bool) -> Void] = []

    func setConnected(
        _ connected: Bool,
        forAddress address: String,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        requests.append((connected, address))
        completions.append(completion)
    }

    func answerFirst(accepted: Bool) {
        completions.first?(accepted)
        if !completions.isEmpty {
            completions.removeFirst()
        }
    }
}

private final class MutableBluetoothDeviceReader: BluetoothPairedDeviceReading {
    var devices: [BluetoothDevice]
    private(set) var readCount = 0

    init(devices: [BluetoothDevice]) {
        self.devices = devices
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        readCount += 1
        completion(.success(devices))
    }
}

@MainActor
private final class ActionTestStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() {
        onStateChange?(authorization, .poweredOn)
    }

    func stop() {}
}

private final class SilentBluetoothBatteryReader: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        completion([:])
    }
}
