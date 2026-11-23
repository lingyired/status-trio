import CoreAudio
import IOBluetooth
import XCTest

@testable import StatusTrioCore

/// The Redmi vendor SPP wire format, authentication, and mode map, held without
/// IOBluetooth. Mirrors the reference implementation's protocol test suite so the
/// port keeps parity with the values verified against real Buds 8 hardware.
final class RedmiListeningModeProtocolTests: XCTestCase {

    /// Expected values produced by the pinned upstream Rust `auth.rs`. These are
    /// the same four vectors the reference implementation checks.
    private let authVectors: [([UInt8], [UInt8])] = [
        ([UInt8](repeating: 0, count: 16),
         [0x6b, 0x9e, 0x57, 0x8c, 0x32, 0xd0, 0x4d, 0x24, 0xb6, 0x25, 0x06, 0xff, 0x08, 0x0c, 0xca, 0xc6]),
        ([UInt8](repeating: 1, count: 16),
         [0xd7, 0xcd, 0xd2, 0x80, 0x4c, 0x5b, 0xed, 0x14, 0xe7, 0xc8, 0xa4, 0x7a, 0x6c, 0x93, 0x71, 0x1c]),
        ([UInt8](repeating: 255, count: 16),
         [0x71, 0xe5, 0x22, 0x35, 0xd7, 0xee, 0x32, 0x27, 0xb6, 0x76, 0x3f, 0xf0, 0xef, 0x1f, 0xc9, 0xef]),
        ((0..<16).map(UInt8.init),
         [0xfe, 0x6c, 0x34, 0xc4, 0xa7, 0xcf, 0x72, 0x0a, 0x06, 0x6b, 0x2b, 0x45, 0xb5, 0xba, 0xf4, 0x7d]),
    ]

    func testAuthenticationVectorsMatchUpstream() {
        for (challenge, expected) in authVectors {
            XCTAssertEqual(RedmiBudsAuthentication.response(to: challenge), expected)
        }
    }

    func testWireFormatEncodesTheModeCommand() {
        let command = RedmiBudsFrame(opcode: 8, sequence: 7, payload: [2, 4, 1])
        XCTAssertEqual(command.bytes, [0xFE, 0xDC, 0xBA, 0xC4, 8, 0, 4, 7, 2, 4, 1, 0xEF])
    }

    func testDecodesAFragmentedFrameAtEverySplit() {
        let response = RedmiBudsFrame(type: 4, opcode: 0x50, sequence: 2, payload: [0xFE, 0xDC, 0xBA, 0xEF])
        for split in 0...response.bytes.count {
            var parser = RedmiBudsFrameDecoder()
            let first = parser.append(Array(response.bytes.prefix(split)))
            let rest = parser.append(Array(response.bytes.dropFirst(split)))
            XCTAssertEqual(first + rest, [response], "fragmented frame at \(split)")
        }
    }

    func testDecoderResynchronizesOnNoiseAndBadFrames() {
        let command = RedmiBudsFrame(opcode: 8, sequence: 7, payload: [2, 4, 1])
        let response = RedmiBudsFrame(type: 4, opcode: 0x50, sequence: 2, payload: [])

        var parser = RedmiBudsFrameDecoder()
        XCTAssertEqual(parser.append([7, 8, 9] + command.bytes + response.bytes), [command, response])

        var malformed = command.bytes
        malformed[malformed.count - 1] = 0
        XCTAssertEqual(parser.append(malformed + response.bytes), [response])

        XCTAssertEqual(
            parser.append([0xFE, 0xDC, 0xBA, 0xC4, 8, 0xFF, 0xFF] + command.bytes),
            [command]
        )
    }

    func testAuthenticationHandshakeSequence() {
        var engine = RedmiBudsProtocol()

        _ = engine.receive(RedmiBudsFrame(type: 4, opcode: 0x51, sequence: 0))
        XCTAssertFalse(engine.authenticated, "reject unsolicited authentication confirmation")

        let start = engine.begin()
        XCTAssertEqual(start.payload.count, 17)
        XCTAssertEqual(start.payload.first, 1)

        let challengeReply = engine.receive(
            RedmiBudsFrame(type: 0xC0, opcode: 0x50, sequence: 90, payload: [1] + authVectors[0].0)
        )
        XCTAssertEqual(challengeReply.first?.payload, [1] + authVectors[0].1)
        XCTAssertEqual(challengeReply.first?.sequence, 90)

        let confirm = engine.receive(RedmiBudsFrame(type: 4, opcode: 0x50, sequence: start.sequence))
        XCTAssertEqual(confirm.count, 1)
        XCTAssertEqual(confirm.first?.opcode, 0x51)

        _ = engine.receive(RedmiBudsFrame(type: 4, opcode: 0x51, sequence: 88))
        XCTAssertFalse(engine.authenticated, "reject confirmation with wrong sequence")

        _ = engine.receive(RedmiBudsFrame(type: 4, opcode: 0x51, sequence: confirm[0].sequence, status: 1))
        XCTAssertFalse(engine.authenticated, "reject failed authentication status")

        let ready = engine.receive(RedmiBudsFrame(type: 4, opcode: 0x51, sequence: confirm[0].sequence))
        XCTAssertTrue(engine.authenticated)
        XCTAssertEqual(ready.map(\.opcode), [0x51, 2, 9])

        let lateChallenge = engine.receive(
            RedmiBudsFrame(type: 0xC4, opcode: 0x50, sequence: 6, payload: [1] + authVectors[0].0)
        )
        XCTAssertTrue(engine.authenticated)
        XCTAssertEqual(lateChallenge.first?.payload, [1] + authVectors[0].1)
        XCTAssertEqual(lateChallenge.first?.sequence, 6)
    }

    func testModeCommandsAndReadback() {
        var engine = RedmiBudsProtocol()
        let start = engine.begin()
        _ = engine.receive(RedmiBudsFrame(type: 4, opcode: 0x50, sequence: start.sequence))
        _ = engine.receive(RedmiBudsFrame(type: 4, opcode: 0x51, sequence: 1))
        // After authentication the engine is ready for mode writes/reads.

        for mode in RedmiNoiseMode.allCases {
            let request = engine.setMode(mode)
            XCTAssertEqual(request.payload, [2, 4, mode.rawValue], "mode command \(mode)")
        }
        XCTAssertNil(engine.state.mode, "writes do not invent confirmed mode")

        let ack = engine.receive(RedmiBudsFrame(type: 0xC0, opcode: 0x0E, sequence: 45, payload: [2, 4, 2]))
        XCTAssertEqual(engine.state.mode, .transparency)
        XCTAssertEqual(ack.first?.sequence, 45)
        XCTAssertEqual(ack.first?.type, 4)

        let revision = engine.state.modeRevision
        _ = engine.receive(RedmiBudsFrame(type: 4, opcode: 8, sequence: 5))
        XCTAssertEqual(engine.state.modeRevision, revision, "command ACK cannot confirm a pending mode")

        _ = engine.receive(RedmiBudsFrame(type: 4, opcode: 9, sequence: 7, payload: [2, 9, 1]))
        XCTAssertEqual(engine.state.mode, .cancellation)
        XCTAssertGreaterThan(engine.state.modeRevision, revision)

        _ = engine.receive(RedmiBudsFrame(type: 0xC7, opcode: 0xF4, sequence: 46, payload: [4, 0, 0x0B, 0, 1]))
        XCTAssertEqual(engine.state.mode, .off, "configuration notify mode")
    }

    func testBatteryParsingAndFailedResponseIgnored() {
        var engine = RedmiBudsProtocol()
        let start = engine.begin()
        _ = engine.receive(RedmiBudsFrame(type: 4, opcode: 0x50, sequence: start.sequence))
        _ = engine.receive(RedmiBudsFrame(type: 4, opcode: 0x51, sequence: 1))

        _ = engine.receive(RedmiBudsFrame(type: 4, opcode: 2, sequence: 8, payload: [4, 7, 100, 255, 178]))
        XCTAssertEqual(engine.state.left, 100)
        XCTAssertNil(engine.state.right)
        XCTAssertEqual(engine.state.caseBattery, 50, "charging bit masked, 0xFF is unknown")

        _ = engine.receive(RedmiBudsFrame(type: 0xC7, opcode: 0xF4, sequence: 46, payload: [4, 0, 0x0B, 0, 1]))
        _ = engine.receive(RedmiBudsFrame(type: 4, opcode: 9, sequence: 9, payload: [2, 9, 2], status: 1))
        XCTAssertEqual(engine.state.mode, .off, "failed response must not update state")

        _ = engine.receive(RedmiBudsFrame(type: 4, opcode: 0xF4, sequence: 47, payload: [0]))
        _ = engine.receive(RedmiBudsFrame(type: 4, opcode: 9, sequence: 10, payload: [9, 9, 2]))
        XCTAssertEqual(engine.state.mode, .off, "truncated TLV ignored")
    }

    func testSurvivesMalformedStreams() {
        var parser = RedmiBudsFrameDecoder()
        var engine = RedmiBudsProtocol()
        var seed: UInt64 = 1234
        for _ in 0..<2000 {
            var bytes: [UInt8] = []
            for _ in 0..<32 {
                seed = seed &* 6364136223846793005 &+ 1
                bytes.append(UInt8(truncatingIfNeeded: seed >> 32))
            }
            for frame in parser.append(bytes) { _ = engine.receive(frame) }
        }
        // Reaching here without a crash or hang is the assertion.
    }

    // MARK: - Mode mapping

    func testListeningModeMapping() {
        XCTAssertEqual(redmiMode(for: .off), .off)
        XCTAssertEqual(redmiMode(for: .noiseCancellation), .cancellation)
        XCTAssertEqual(redmiMode(for: .transparency), .transparency)
        XCTAssertNil(redmiMode(for: .adaptive))

        XCTAssertEqual(RedmiNoiseState(mode: .off).listeningMode, .off)
        XCTAssertEqual(RedmiNoiseState(mode: .cancellation).listeningMode, .noiseCancellation)
        XCTAssertEqual(RedmiNoiseState(mode: .transparency).listeningMode, .transparency)
    }

    func testSelectableModesIncludeOff() {
        XCTAssertEqual(
            RedmiNoiseState.selectableListeningModes,
            [.noiseCancellation, .transparency, .off]
        )
    }
}

/// Isolated tests for the Redmi device-classification rule.
final class RedmiAudioClassificationTests: XCTestCase {

    private func device(name: String, kind: BluetoothDeviceKind = .audio, vendorID: Int? = nil) -> BluetoothDevice {
        BluetoothDevice(
            id: "AA-BB-CC-DD-EE-FF",
            name: name,
            kind: kind,
            isConnected: true,
            vendorID: vendorID
        )
    }

    func testCompanyIDIdentifiesXiaomiDevice() {
        let dev = device(name: "My Earbuds", vendorID: 0x2717)
        XCTAssertTrue(dev.isRedmiAudio)
    }

    func testNameFallbackCoversReportsWithoutCompanyID() {
        XCTAssertTrue(device(name: "Redmi Buds 8").isRedmiAudio)
        XCTAssertTrue(device(name: "Xiaomi Buds 5").isRedmiAudio)
    }

    func testNonAudioAndUnrelatedNamesDoNotMatch() {
        XCTAssertFalse(device(name: "Redmi Buds 8", kind: .unknown).isRedmiAudio)
        XCTAssertFalse(device(name: "Logitech Mouse").isRedmiAudio)
    }

    func testHuaweiDeviceIsNotMistakenForRedmi() {
        let dev = device(name: "HUAWEI FreeBuds 6i", vendorID: 0x027D)
        XCTAssertTrue(dev.isHuaweiAudio)
        XCTAssertFalse(dev.isRedmiAudio)
    }
}
// MARK: - Transport / controller integration

/// A scripted `RedmiListeningModeTransporting` so the controller's Redmi branch
/// can be exercised without IOBluetooth. Mirrors the fake used by the HUAWEI
/// controller tests, but for the Redmi seam.
private final class FakeRedmiTransport: RedmiListeningModeTransporting, @unchecked Sendable {
    private(set) var stateCalls: [String] = []
    private(set) var setModeCalls: [(RedmiNoiseMode, String)] = []
    private(set) var closeAllCount = 0
    private(set) var closedAddresses: [String] = []

    var stateResult: RedmiNoiseState
    var setModeResult: RedmiNoiseState?
    var stateError: (any Error)?
    var setModeError: (any Error)?

    init(stateResult: RedmiNoiseState = RedmiNoiseState(mode: .cancellation)) {
        self.stateResult = stateResult
    }

    func state(address: String) async throws -> RedmiNoiseState {
        stateCalls.append(address)
        if let stateError { throw stateError }
        return stateResult
    }

    func setMode(_ mode: RedmiNoiseMode, address: String) async throws -> RedmiNoiseState {
        setModeCalls.append((mode, address))
        if let setModeError { throw setModeError }
        return setModeResult ?? RedmiNoiseState(mode: mode)
    }

    func closeAll() {
        closeAllCount += 1
    }

    func close(address: String) {
        closedAddresses.append(address)
    }
}

private struct EmptyRedmiCoreAudioEndpoints: CoreAudioBluetoothEndpointProviding {
    func discoverEndpoints(using hal: BluetoothListeningModeHAL) -> [BluetoothListeningModeEndpoint] { [] }
}

/// A scripted CoreAudio output endpoint resolver for the Redmi family.
private struct ScriptedRedmiEndpointProvider: HuaweiAudioEndpointProviding {
    var endpointID: AudioDeviceID?
    func endpointID(for device: BluetoothDevice) -> AudioDeviceID? { endpointID }
}

@MainActor
final class RedmiControllerTests: XCTestCase {
    private let address = "AA:BB:CC:DD:EE:FF"
    private var key: String { BluetoothBatteryReader.normalizedAddress(address) }

    private func device(name: String = "Redmi Buds 8") -> BluetoothDevice {
        BluetoothDevice(
            id: address,
            name: name,
            kind: .audio,
            isConnected: true,
            vendorID: 0x2717
        )
    }

    private func makeController(
        _ transport: FakeRedmiTransport,
        endpoint: AudioDeviceID? = nil
    ) -> BluetoothListeningModeController {
        BluetoothListeningModeController(
            hal: BluetoothListeningModeHAL(
                backend: CoreAudioBluetoothListeningModeBackend(),
                sleeper: ImmediateListeningModeSleeper(),
                retryAttempts: 1,
                retryDelay: .milliseconds(1)
            ),
            endpointProvider: EmptyRedmiCoreAudioEndpoints(),
            listenerBackend: CoreAudioBluetoothListeningModeListenerBackend(),
            redmiTransport: transport,
            redmiEndpointProvider: ScriptedRedmiEndpointProvider(endpointID: endpoint),
            airPodsDiscoveryRetryDelays: [],
            failureClearDelay: .milliseconds(1),
            previewSettleDelay: .milliseconds(1)
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @escaping () async -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testRedmiDevicePublishesControlOnTheBluetoothRow() async {
        let transport = FakeRedmiTransport(stateResult: RedmiNoiseState(mode: .cancellation))
        let controller = makeController(transport)
        controller.refresh(devices: [device()])

        await waitUntil { controller.control(forBluetoothAddress: self.address) != nil }

        let control = controller.control(forBluetoothAddress: address)
        XCTAssertNotNil(control)
        XCTAssertEqual(control?.selectedMode, .noiseCancellation)
        XCTAssertEqual(Set(control?.availableModes ?? []), Set([.noiseCancellation, .transparency, .off]))
        XCTAssertEqual(controller.huaweiBluetoothRowPresentations[key]?.selectedMode, .noiseCancellation)
        XCTAssertEqual(transport.stateCalls, [key])
    }

    func testRedmiControlRendersOnVolumeRowWhenEndpointResolves() async {
        let transport = FakeRedmiTransport(stateResult: RedmiNoiseState(mode: .cancellation))
        let controller = makeController(transport, endpoint: 42)
        controller.refresh(devices: [device()])

        await waitUntil { controller.control(forEndpoint: 42)?.presentation != nil }

        // With an endpoint resolved, the volume row owns the control and the
        // Bluetooth row must not draw a duplicate.
        let rowControl = controller.control(forEndpoint: 42)
        XCTAssertNotNil(rowControl)
        XCTAssertEqual(rowControl?.address, key)
        XCTAssertEqual(rowControl?.presentation.selectedMode, .noiseCancellation)
        XCTAssertNil(controller.control(forBluetoothAddress: address))
        XCTAssertTrue(controller.huaweiBluetoothRowPresentations.isEmpty)
    }

    func testRedmiSetModeRoutesThroughTransportAndConfirms() async {
        let transport = FakeRedmiTransport(stateResult: RedmiNoiseState(mode: .cancellation))
        transport.setModeResult = RedmiNoiseState(mode: .transparency)
        let controller = makeController(transport)
        controller.refresh(devices: [device()])
        await waitUntil { controller.control(forBluetoothAddress: self.address) != nil }

        controller.setMode(.transparency, forAddress: key)

        await waitUntil { controller.control(forBluetoothAddress: self.address)?.selectedMode == .transparency }
        XCTAssertEqual(transport.setModeCalls.count, 1)
        XCTAssertEqual(transport.setModeCalls.first?.0, .transparency)
        XCTAssertEqual(controller.control(forBluetoothAddress: address)?.selectedMode, .transparency)
    }

    func testRedmiFailedWriteRollsBackToReportedMode() async {
        let transport = FakeRedmiTransport(stateResult: RedmiNoiseState(mode: .cancellation))
        transport.setModeResult = RedmiNoiseState(mode: .cancellation) // did not confirm target
        let controller = makeController(transport)
        controller.refresh(devices: [device()])
        await waitUntil { controller.control(forBluetoothAddress: self.address) != nil }

        controller.setMode(.transparency, forAddress: key)
        await waitUntil { controller.control(forBluetoothAddress: self.address)?.isChanging == false }
        XCTAssertEqual(controller.control(forBluetoothAddress: address)?.selectedMode, .noiseCancellation)
    }

    func testRedmiVanishesWhenTransportFailsClosed() async {
        let transport = FakeRedmiTransport()
        transport.stateError = RedmiListeningModeError.controlServiceNotFound
        let controller = makeController(transport)
        controller.refresh(devices: [device()])
        // Give the failed read a chance to run; no control should appear.
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertNil(controller.control(forBluetoothAddress: address))
        XCTAssertTrue(controller.huaweiBluetoothRowPresentations.isEmpty)
    }

    func testStopClearsSurfaceButKeepsPersistentSessions() async {
        let transport = FakeRedmiTransport()
        let controller = makeController(transport)
        controller.refresh(devices: [device()])
        await waitUntil { controller.control(forBluetoothAddress: self.address) != nil }

        controller.stop()
        // The panel surface is cleared...
        XCTAssertNil(controller.control(forBluetoothAddress: address))
        XCTAssertTrue(controller.huaweiBluetoothRowPresentations.isEmpty)
        // ...but the long-lived Redmi control session is kept so a phone cannot
        // steal the channel between panel visits.
        XCTAssertEqual(transport.closeAllCount, 0)
    }

    func testDeviceLeavingEligibleSetClosesItsSession() async {
        let transport = FakeRedmiTransport()
        let controller = makeController(transport)
        controller.refresh(devices: [device()])
        await waitUntil { controller.control(forBluetoothAddress: self.address) != nil }
        XCTAssertTrue(transport.closedAddresses.isEmpty)

        // Simulate the buds going back into the case: they disappear from the
        // connected list. The next refresh must drop that device's session.
        controller.refresh(devices: [])
        XCTAssertEqual(transport.closedAddresses, [key])
    }

    func testShutdownReleasesPersistentSessions() async {
        let transport = FakeRedmiTransport()
        let controller = makeController(transport)
        controller.refresh(devices: [device()])
        await waitUntil { controller.control(forBluetoothAddress: self.address) != nil }

        controller.shutdown()
        XCTAssertNil(controller.control(forBluetoothAddress: address))
        XCTAssertGreaterThanOrEqual(transport.closeAllCount, 1)
    }
}

/// Verifies the real transport fails closed for an address it cannot resolve,
/// without touching IOBluetooth.
final class RedmiTransportFailClosedTests: XCTestCase {
    func testUnknownAddressThrowsControlServiceNotFound() async {
        let transport = RedmiRFCOMMTransport(
            resolveDevice: { _ in nil },
            sessionFactory: { device, address in RedmiControlSession(device: device, address: address) }
        )
        do {
            _ = try await transport.state(address: "000000000000")
            XCTFail("expected controlServiceNotFound")
        } catch let error as RedmiListeningModeError {
            XCTAssertEqual(error, .controlServiceNotFound)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testCloseAllIsIdempotent() {
        let transport = RedmiRFCOMMTransport(resolveDevice: { _ in nil }, sessionFactory: {
            RedmiControlSession(device: $0, address: $1)
        })
        transport.closeAll()
        transport.closeAll()
    }
}

// MARK: - Persistent-session transport

private final class CountingRedmiSessionFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var creations = 0
    func bump() { lock.lock(); creations += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return creations }
}

/// A device whose control service can never be resolved, so a session connect
/// fails fast without IOBluetooth or real hardware.
private final class UnresolvableRedmiDevice: RedmiBluetoothDevice, @unchecked Sendable {
    var addressString: String? { "AA:BB:CC:DD:EE:FF" }
    func isConnected() -> Bool { true }
    func cachedControlService() -> IOBluetoothSDPServiceRecord? { nil }
    func queryForControlService() -> Bool { false }
    func openControlChannel(
        id: BluetoothRFCOMMChannelID,
        delegate: IOBluetoothRFCOMMChannelDelegate
    ) -> IOReturn { kIOReturnError }
}

/// The transport must hold one persistent session per device across requests and
/// only re-create it after an explicit close — this is the behaviour that keeps
/// the control channel held (so a connecting phone cannot take it over).
final class RedmiPersistentTransportTests: XCTestCase {
    func testSessionIsReusedAcrossRequestsAndRecreatedAfterClose() async {
        let factory = CountingRedmiSessionFactory()
        let device = UnresolvableRedmiDevice()
        let transport = RedmiRFCOMMTransport(
            resolveDevice: { _ in device },
            sessionFactory: { d, a in
                factory.bump()
                return RedmiControlSession(device: d, address: a, connectTimeoutSeconds: 0.1)
            }
        )
        let address = "AA:BB:CC:DD:EE:FF"

        _ = try? await transport.state(address: address)
        _ = try? await transport.state(address: address)
        XCTAssertEqual(factory.count, 1, "the same session must back repeated requests")

        transport.close(address: address)
        _ = try? await transport.state(address: address)
        XCTAssertEqual(factory.count, 2, "closing drops the session so the next request reconnects")

        transport.closeAll()
    }

    func testCloseAllDropsEverySession() async {
        let factory = CountingRedmiSessionFactory()
        let device = UnresolvableRedmiDevice()
        let transport = RedmiRFCOMMTransport(
            resolveDevice: { _ in device },
            sessionFactory: { d, a in
                factory.bump()
                return RedmiControlSession(device: d, address: a, connectTimeoutSeconds: 0.1)
            }
        )
        _ = try? await transport.state(address: "AA:BB:CC:DD:EE:FF")
        transport.closeAll()
        _ = try? await transport.state(address: "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(factory.count, 2)
        transport.closeAll()
    }
}
