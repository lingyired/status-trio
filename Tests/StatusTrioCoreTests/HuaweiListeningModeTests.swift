import CoreAudio
import os
import XCTest

@testable import StatusTrioCore

/// The HUAWEI SPP wire format and its mode map, held without IOBluetooth.
final class HuaweiListeningModeProtocolTests: XCTestCase {
    func testDecodesFramesCapturedFromAFreeBuds6i() {
        // Idle notification emitted as soon as the SPP channel opens.
        let idle = HuaweiSPPFrame.decode([0x5A, 0x00, 0x03, 0x00, 0x01, 0x06, 0x3E, 0xBD])
        XCTAssertEqual(idle?.command, [0x01, 0x06])
        XCTAssertEqual(idle?.parameters, [:])

        // Device-info notification the earbuds send unprompted.
        let info: [UInt8] = [
            0x5A, 0x00, 0x1B, 0x00, 0x2B, 0xAC,
            0x01, 0x01, 0x01, 0x02, 0x01, 0x01, 0x03, 0x01, 0x00,
            0x04, 0x01, 0x00, 0x05, 0x01, 0x00, 0x06, 0x01, 0x00,
            0x07, 0x01, 0x00, 0x08, 0x01, 0x00,
            0xCB, 0x6A
        ]
        let frame = HuaweiSPPFrame.decode(info)
        XCTAssertEqual(frame?.command, [0x2B, 0xAC])
        XCTAssertEqual(frame?.parameters[1], [0x01])
        XCTAssertEqual(frame?.parameters[8], [0x00])
    }

    func testEncodesTheANCReadRequest() {
        let packet = HuaweiSPPFrame(
            command: HuaweiSPPFrame.readANCCommand,
            parameters: [1: [], 2: []]
        ).encoded()
        XCTAssertEqual(packet, [0x5A, 0x00, 0x07, 0x00, 0x2B, 0x2A, 0x01, 0x00, 0x02, 0x00, 0x1D, 0x33])
    }

    func testRejectsPartialAndChecksumMismatchedFrames() {
        let valid: [UInt8] = [0x5A, 0x00, 0x03, 0x00, 0x01, 0x06, 0x3E, 0xBD]
        XCTAssertNil(HuaweiSPPFrame.decode(Array(valid.dropLast())))
        var corrupt = valid
        corrupt[corrupt.count - 1] ^= 0xFF
        XCTAssertNil(HuaweiSPPFrame.decode(corrupt))
    }

    func testHuaweiAudioDetectionUsesVendorOrKnownFamilyName() {
        func device(name: String, vendorID: Int? = nil) -> BluetoothDevice {
            BluetoothDevice(
                id: "A8:37:59:F1:77:3D",
                name: name,
                kind: .audio,
                isConnected: true,
                vendorID: vendorID
            )
        }
        XCTAssertTrue(device(name: "Anything", vendorID: 0x027D).isHuaweiAudio)
        XCTAssertTrue(device(name: "HUAWEI FreeBuds 6i").isHuaweiAudio)
        XCTAssertTrue(device(name: "FreeLace Pro 2").isHuaweiAudio)
        XCTAssertFalse(device(name: "AirPods Pro").isHuaweiAudio)
        XCTAssertFalse(
            device(name: "FreeBuds 6i", vendorID: 0x1234).isHuaweiAudio,
            "An explicit non-HUAWEI vendor ID must override the family-name fallback"
        )
        XCTAssertFalse(
            BluetoothDevice(
                id: "A8:37:59:F1:77:3D",
                name: "FreeBuds 6i",
                kind: .peripheral(.keyboard),
                isConnected: true,
                vendorID: 0x027D
            ).isHuaweiAudio
        )
    }

    func testModeRoundTripAndWritePayload() {
        XCTAssertEqual(HuaweiNoiseState(level: 0, mode: 0)?.listeningMode, .off)
        XCTAssertEqual(HuaweiNoiseState(level: 2, mode: 1)?.listeningMode, .noiseCancellation)
        XCTAssertEqual(HuaweiNoiseState(level: 1, mode: 2)?.listeningMode, .transparency)
        XCTAssertNil(HuaweiNoiseState(level: 0, mode: 9))

        XCTAssertEqual(HuaweiNoiseState.noiseMode(for: .off), .normal)
        XCTAssertEqual(HuaweiNoiseState.noiseMode(for: .noiseCancellation), .cancellation)
        XCTAssertEqual(HuaweiNoiseState.noiseMode(for: .transparency), .awareness)
        XCTAssertNil(HuaweiNoiseState.noiseMode(for: .adaptive))

        XCTAssertEqual(HuaweiNoiseMode.normal.writePayload, [0x00, 0x00])
        XCTAssertEqual(HuaweiNoiseMode.cancellation.writePayload, [0x01, 0xFF])
        XCTAssertEqual(HuaweiNoiseMode.awareness.writePayload, [0x02, 0xFF])
        XCTAssertEqual(
            HuaweiNoiseState.selectableListeningModes,
            [.noiseCancellation, .transparency, .off]
        )
    }
}

/// The transport's own first-use startup, with the device lookup stubbed out.
///
/// Nothing here touches a real `IOBluetoothDevice`. Asking the live stack for
/// paired devices makes TCC require an `NSBluetoothAlwaysUsageDescription` in
/// the test bundle, and a bundle without one is SIGABRTed inside the TCC reply
/// callback (`__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__`), which takes the whole
/// XCTest target down with 0 tests executed (#132). The startup under test runs
/// before any device lookup, so an empty paired-device list keeps the
/// concurrency and the assertion intact while staying inside the fixture.
final class HuaweiRFCOMMTransportStartupTests: XCTestCase {
    /// Two HUAWEI devices are read at once, and `state` is a nonisolated `async`
    /// method, so the calls reach the transport's first-use startup on different
    /// cooperative-pool threads. That startup has to be serialized: a second
    /// thread would leave the transport with two run loops and two owners of the
    /// connection map, and the losing thread would run for the process lifetime.
    func testConcurrentFirstUseStartsExactlyOneTransportThread() async throws {
        let transport = HuaweiRFCOMMTransport(hooks: .init(pairedDevices: { [] }))
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<8 {
                group.addTask {
                    _ = try? await transport.state(address: "AA:BB:CC:DD:EE:0\(index)")
                }
            }
        }
        XCTAssertEqual(transport.transportThreadCount, 1)
    }
}

final class HuaweiAudioEndpointMatcherTests: XCTestCase {
    private let address = "A8:37:59:F1:77:3D"

    func testDuplicateAddressMatchesFailClosed() {
        let endpoints = [
            HuaweiAudioEndpoint(id: 7, uid: "A8-37-59-F1-77-3D:input", name: "HUAWEI FreeBuds 6i"),
            HuaweiAudioEndpoint(id: 9, uid: "A8-37-59-F1-77-3D:output", name: "HUAWEI FreeBuds 6i")
        ]
        // Both endpoints carry the address, so the address rule alone is ambiguous;
        // the caller only ever enumerates output endpoints, and this pins that an
        // input endpoint cannot be selected when both are offered.
        XCTAssertNil(
            HuaweiAudioEndpointMatcher.endpointID(
                forAddress: address,
                deviceName: "HUAWEI FreeBuds 6i",
                in: endpoints
            )
        )
    }

    func testMatchesSingleOutputByAddress() {
        let endpoints = [
            HuaweiAudioEndpoint(id: 9, uid: "A8-37-59-F1-77-3D:output", name: "renamed")
        ]
        XCTAssertEqual(
            HuaweiAudioEndpointMatcher.endpointID(
                forAddress: address,
                deviceName: "HUAWEI FreeBuds 6i",
                in: endpoints
            ),
            9
        )
    }

    func testMatchesColonDelimitedAddressWhenNameDoesNotMatch() {
        let endpoints = [
            HuaweiAudioEndpoint(id: 9, uid: "A8:37:59:F1:77:3D:output", name: "renamed")
        ]
        XCTAssertEqual(
            HuaweiAudioEndpointMatcher.endpointID(
                forAddress: address,
                deviceName: "HUAWEI FreeBuds 6i",
                in: endpoints
            ),
            9
        )
    }

    func testRequiresWellFormedAddressEvidenceInUID() {
        let endpoints = [
            HuaweiAudioEndpoint(id: 9, uid: "A83759F1773D:output", name: "renamed")
        ]
        XCTAssertNil(
            HuaweiAudioEndpointMatcher.endpointID(
                forAddress: address,
                deviceName: "HUAWEI FreeBuds 6i",
                in: endpoints
            )
        )
    }

    func testReviewPR124ConflictingAddressCannotMatchByName() {
        let endpoint = HuaweiAudioEndpoint(id: 9, uid: "11-22-33-44-55-66:output", name: "HUAWEI FreeBuds 6i")
        XCTAssertNil(HuaweiAudioEndpointMatcher.endpointID(
            forAddress: address,
            deviceName: "HUAWEI FreeBuds 6i",
            in: [endpoint]
        ), "An endpoint with a different known address must not match by name")
    }

    func testDuplicateOpaqueNameMatchesFailClosed() {
        let endpoints = [
            HuaweiAudioEndpoint(id: 7, uid: "OpaqueInput", name: "HUAWEI FreeBuds 6i"),
            HuaweiAudioEndpoint(id: 9, uid: "OpaqueOutput", name: "HUAWEI FreeBuds 6i")
        ]
        XCTAssertNil(
            HuaweiAudioEndpointMatcher.endpointID(
                forAddress: address,
                deviceName: "HUAWEI FreeBuds 6i",
                in: endpoints
            )
        )
    }

    func testFallsBackToExactNameOnly() {
        let endpoints = [
            HuaweiAudioEndpoint(id: 9, uid: "SomeOtherUID", name: "HUAWEI FreeBuds 6i")
        ]
        XCTAssertEqual(
            HuaweiAudioEndpointMatcher.endpointID(
                forAddress: address,
                deviceName: "HUAWEI FreeBuds 6i",
                in: endpoints
            ),
            9
        )
        XCTAssertNil(
            HuaweiAudioEndpointMatcher.endpointID(
                forAddress: address,
                deviceName: "HUAWEI",
                in: endpoints
            )
        )
    }
}

/// The controller's HUAWEI branch: discovery publishes three capsules, a tap
/// writes the vendor mode and settles on the state read back, a failure rolls
/// back, and closing the panel closes the transport.
private final class FakeTransport: HuaweiListeningModeTransporting, @unchecked Sendable {
    private struct State {
        var mode: HuaweiNoiseMode = .cancellation
        var stateCalls = 0
        var stateCallsStarted = 0
        var stateCallsFinished = 0
        var setCalls = 0
        var closed = false
        var failuresBeforeSuccess = 0
        var failure: HuaweiListeningModeError?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var mode: HuaweiNoiseMode { state.withLock { $0.mode } }
    var stateCalls: Int { state.withLock { $0.stateCalls } }
    var stateCallsFinished: Int { state.withLock { $0.stateCallsFinished } }
    var setCalls: Int { state.withLock { $0.setCalls } }
    var closed: Bool { state.withLock { $0.closed } }
    var failuresBeforeSuccess: Int {
        get { state.withLock { $0.failuresBeforeSuccess } }
        set { state.withLock { $0.failuresBeforeSuccess = newValue } }
    }
    var failure: HuaweiListeningModeError? {
        get { state.withLock { $0.failure } }
        set { state.withLock { $0.failure = newValue } }
    }

    func state(address: String) async throws -> HuaweiNoiseState {
        let result: Result<HuaweiNoiseState, HuaweiListeningModeError> = state.withLock { state in
            state.stateCalls += 1
            state.stateCallsStarted += 1
            if state.failuresBeforeSuccess > 0 {
                state.failuresBeforeSuccess -= 1
                return .failure(.timeout)
            }
            if let failure = state.failure { return .failure(failure) }
            return .success(HuaweiNoiseState(level: 2, mode: state.mode.rawValue)!)
        }
        state.withLock { $0.stateCallsFinished += 1 }
        return try result.get()
    }

    func setMode(_ mode: HuaweiNoiseMode, address: String) async throws -> HuaweiNoiseState {
        try state.withLock { state in
            state.setCalls += 1
            if let failure = state.failure { throw failure }
            state.mode = mode
            return HuaweiNoiseState(level: 2, mode: mode.rawValue)!
        }
    }

    func closeAll() { state.withLock { $0.closed = true } }
}

private struct FakeHuaweiEndpointProvider: HuaweiAudioEndpointProviding {
    let endpointID: AudioDeviceID?
    func endpointID(for device: BluetoothDevice) -> AudioDeviceID? { endpointID }
}

private struct EmptyCoreAudioEndpoints: CoreAudioBluetoothEndpointProviding {
    func discoverEndpoints(using hal: BluetoothListeningModeHAL) -> [BluetoothListeningModeEndpoint] { [] }
}


@MainActor
final class HuaweiListeningModeControllerTests: XCTestCase {
    private let address = "A8:37:59:F1:77:3D"
    private var key: String { BluetoothBatteryReader.normalizedAddress(address) }
    private let endpointID: AudioDeviceID = 42

    private func device() -> BluetoothDevice {
        BluetoothDevice(
            id: address,
            name: "HUAWEI FreeBuds 6i",
            kind: .audio,
            isConnected: true,
            vendorID: 0x027D
        )
    }

    private func makeController(
        _ transport: FakeTransport,
        endpoint: AudioDeviceID? = 42,
        retryDelay: Duration = .milliseconds(1)
    ) -> BluetoothListeningModeController {
        BluetoothListeningModeController(
            hal: BluetoothListeningModeHAL(
                backend: CoreAudioBluetoothListeningModeBackend(),
                sleeper: ImmediateListeningModeSleeper(),
                retryAttempts: 1,
                retryDelay: .milliseconds(1)
            ),
            endpointProvider: EmptyCoreAudioEndpoints(),
            listenerBackend: CoreAudioBluetoothListeningModeListenerBackend(),
            huaweiTransport: transport,
            huaweiEndpointProvider: FakeHuaweiEndpointProvider(endpointID: endpoint),
            huaweiReadRetryDelays: [retryDelay],
            failureClearDelay: .milliseconds(20),
            previewSettleDelay: .milliseconds(1)
        )
    }

    func testHuaweiSwitchesWithoutAnAudioEndpointEvenWhilePreviewIsEnabled() async {
        for preview in [false, true] {
            let transport = FakeTransport()
            let controller = makeController(transport, endpoint: nil)
            controller.previewMode = preview
            controller.refresh(devices: [device()])
            await waitUntil { controller.presentations[self.key] != nil }
            XCTAssertEqual(controller.control(forBluetoothAddress: address)?.selectedMode, .noiseCancellation)

            controller.setMode(.transparency, forAddress: key)
            controller.refresh(devices: [device()])
            await waitUntil { controller.presentations[self.key]?.selectedMode == .transparency }
            XCTAssertEqual(transport.mode, .awareness)
            XCTAssertEqual(controller.control(forBluetoothAddress: address)?.selectedMode, .transparency)
            XCTAssertEqual(transport.setCalls, 1)

            controller.refresh(devices: [])
            XCTAssertNil(controller.control(forBluetoothAddress: address))
            XCTAssertTrue(controller.huaweiBluetoothRowPresentations.isEmpty)
            controller.stop()
        }
    }

    func testRefreshPublishesThreeHuaweiModesAndSelectedState() async {
        let transport = FakeTransport()
        let controller = makeController(transport)
        controller.refresh(devices: [device()])

        await waitUntil { controller.control(forEndpoint: self.endpointID) != nil }
        let control = controller.control(forEndpoint: endpointID)
        XCTAssertEqual(control?.presentation.availableModes ?? [], [.noiseCancellation, .transparency, .off])
        XCTAssertEqual(control?.presentation.selectedMode, .noiseCancellation)
        XCTAssertEqual(control?.address, key)
    }

    func testInitialReadFailureRetriesUntilTheHuaweiControlIsAvailable() async {
        let transport = FakeTransport()
        transport.failuresBeforeSuccess = 1
        let controller = makeController(transport)

        controller.refresh(devices: [device()])

        await waitUntil { controller.control(forEndpoint: self.endpointID) != nil }
        XCTAssertEqual(transport.stateCalls, 2)
        XCTAssertEqual(
            controller.control(forEndpoint: endpointID)?.presentation.selectedMode,
            .noiseCancellation
        )
    }

    func testInitialReadRetryBudgetIsBounded() async {
        let transport = FakeTransport()
        transport.failure = .timeout
        let controller = makeController(transport)

        controller.refresh(devices: [device()])

        await waitUntil { transport.stateCallsFinished == 2 }
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(transport.stateCalls, 2)
        XCTAssertNil(controller.control(forEndpoint: endpointID))
    }

    func testStopCancelsTheInitialReadRetryWindow() async {
        let transport = FakeTransport()
        transport.failure = .timeout
        let controller = makeController(transport, retryDelay: .milliseconds(100))

        controller.refresh(devices: [device()])
        await waitUntil { transport.stateCallsFinished == 1 }
        controller.stop()
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(transport.stateCalls, 1)
        XCTAssertNil(controller.control(forEndpoint: endpointID))
    }

    func testLaterReadFailurePreservesTheLastConfirmedHuaweiMode() async {
        let transport = FakeTransport()
        let controller = makeController(transport)
        controller.refresh(devices: [device()])
        await waitUntil { controller.control(forEndpoint: self.endpointID) != nil }

        transport.failure = .timeout
        controller.refresh(devices: [device()])
        await waitUntil { transport.stateCallsFinished == 2 }
        await Task.yield()

        XCTAssertEqual(
            controller.control(forEndpoint: endpointID)?.presentation.selectedMode,
            .noiseCancellation
        )
        XCTAssertEqual(transport.stateCalls, 2, "a confirmed state does not trigger first-use retries")
    }

    func testSetModeWritesAndSettlesOnReadBack() async {
        let transport = FakeTransport()
        let controller = makeController(transport)
        controller.refresh(devices: [device()])
        await waitUntil { controller.control(forEndpoint: self.endpointID) != nil }

        controller.setMode(.transparency, forAddress: key)
        await waitUntil {
            controller.control(forEndpoint: self.endpointID)?.presentation.selectedMode == .transparency
        }
        XCTAssertEqual(transport.setCalls, 1)
        XCTAssertEqual(transport.mode, .awareness)
    }

    func testFailedWriteRollsBackToObservedMode() async {
        let transport = FakeTransport()
        let controller = makeController(transport)
        controller.refresh(devices: [device()])
        await waitUntil { controller.control(forEndpoint: self.endpointID) != nil }
        transport.failure = .timeout

        controller.setMode(.transparency, forAddress: key)
        await waitUntil { controller.control(forEndpoint: self.endpointID)?.presentation.isFailed == true }
        XCTAssertEqual(
            controller.control(forEndpoint: self.endpointID)?.presentation.selectedMode,
            .noiseCancellation
        )
        await waitUntil(timeout: .milliseconds(200)) {
            controller.control(forEndpoint: self.endpointID)?.presentation.isFailed == false
        }
    }

    func testStopClosesTransport() {
        let transport = FakeTransport()
        let controller = makeController(transport)
        controller.refresh(devices: [device()])
        controller.stop()
        XCTAssertTrue(transport.closed)
        XCTAssertNil(controller.control(forEndpoint: endpointID))
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline && !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
