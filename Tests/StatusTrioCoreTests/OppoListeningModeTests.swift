import CoreAudio
import IOBluetooth
import XCTest

@testable import StatusTrioCore

/// The OPO v1 wire format, the session state machine, and the per-model profile
/// table, held without IOBluetooth.
///
/// The protocol facts encoded here come from the public reverse-engineering
/// material for the HeyMelody family — the frame layout, the command words, the
/// `0x010C` sub-types and the "the buds always report the sub-index" rule. What
/// this suite pins is that the port keeps those facts, not that a specific model
/// answers them: real-device acceptance is a separate, manual step.
final class OppoListeningModeProtocolTests: XCTestCase {

    // MARK: - Framing

    func testWireFormatEncodesTheModeQuery() {
        let query = OppoFrame(command: OppoCommand.noiseQuery, sequence: 0, payload: [0x01, 0x01])
        XCTAssertEqual(query.bytes, [0xAA, 0x09, 0x00, 0x00, 0x0C, 0x01, 0x00, 0x02, 0x00, 0x01, 0x01])
    }

    func testVarintExpandsForPayloadsOverOneHundredTwentyBytes() {
        let payload = [UInt8](repeating: 0x11, count: 200)
        let frame = OppoFrame(command: OppoCommand.noiseQuery, sequence: 0, payload: payload)
        // LEN = link header (2) + CMD (2) + SEQ (1) + PLEN (2) + payload (200) = 207
        XCTAssertEqual(Array(frame.bytes.prefix(3)), [0xAA, 0xCF, 0x01])
        XCTAssertEqual(frame.bytes.count, 1 + 2 + 207)
    }

    func testDecodesAFragmentedFrameAtEverySplit() {
        let response = OppoFrame(command: 0x810C, sequence: 3, payload: [0x00, 0x01, 0x01, 0x02])
        for split in 0...response.bytes.count {
            var parser = OppoFrameDecoder()
            let first = parser.append(Array(response.bytes.prefix(split)))
            let rest = parser.append(Array(response.bytes.dropFirst(split)))
            XCTAssertEqual(first + rest, [response], "fragmented frame at \(split)")
        }
    }

    func testDecoderResynchronisesOnNoiseAndBadFrames() {
        let answer = OppoFrame(command: 0x810C, sequence: 3, payload: [0x00, 0x01, 0x01, 0x02])
        let handshake = OppoFrame(command: 0x8100, sequence: 0, payload: [0x00])

        var parser = OppoFrameDecoder()
        XCTAssertEqual(parser.append([0x11, 0x22, 0xAA, 0x33] + answer.bytes + handshake.bytes), [answer, handshake])

        // A payload length that disagrees with the frame length is a mis-parse,
        // not a frame: drop a byte and find the next real one.
        var malformed = answer.bytes
        malformed[8] = 0x7F
        XCTAssertEqual(parser.append(malformed + handshake.bytes), [handshake])
    }

    func testDecoderBuffersAnIncompleteFrameWithoutEmittingIt() {
        let answer = OppoFrame(command: 0x810C, sequence: 1, payload: [0x00, 0x01, 0x01, 0x01])
        var parser = OppoFrameDecoder()
        XCTAssertEqual(parser.append(Array(answer.bytes.dropLast())), [])
        XCTAssertEqual(parser.append([answer.bytes.last!]), [answer])
    }

    func testDecoderSurvivesMalformedStreams() {
        var parser = OppoFrameDecoder()
        var generator = SeededGenerator(seed: 0x0FF0_5EED)
        for _ in 0..<2000 {
            let length = Int.random(in: 0...64, using: &generator)
            let bytes = (0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) }
            _ = parser.append(bytes)
        }
        // The stream never crashes or hangs; a real frame still decodes after it.
        let answer = OppoFrame(command: 0x810C, sequence: 9, payload: [0x00, 0x01, 0x01, 0x04])
        XCTAssertEqual(parser.append(answer.bytes), [answer])
    }

    // MARK: - Session exchange

    private func engineWithProfile() -> OppoSessionEngine {
        var engine = OppoSessionEngine()
        _ = engine.handshake()
        _ = engine.receive(OppoFrame(command: OppoCommand.handshakeResponse, sequence: 0, payload: [0x00]))
        _ = engine.receive(OppoFrame(command: OppoCommand.productIDResponse, sequence: 1, payload: [0x00, 0x10, 0xEC, 0x06]))
        _ = engine.receive(OppoFrame(command: OppoCommand.noiseQueryResponse, sequence: 2, payload: [0x00, 0x02, 0x00, 0x06, 0x00]))
        return engine
    }

    func testHandshakeAsksForTheProductIDAndTheCycle() {
        var engine = OppoSessionEngine()
        let handshake = engine.handshake()
        XCTAssertEqual(handshake.command, OppoCommand.handshake)

        let replies = engine.receive(OppoFrame(command: 0x8100, sequence: 0, payload: [0x00]))
        XCTAssertEqual(replies.map(\.command), [OppoCommand.productID, OppoCommand.noiseQuery])
        XCTAssertEqual(replies.last?.payload, [0x02, 0x01])
    }

    func testProductIDIsLittleEndian() {
        XCTAssertEqual(OppoPayload.productID([0x00, 0x10, 0xEC, 0x06]), 0x06EC10)
        XCTAssertNil(OppoPayload.productID([0x01, 0x10, 0xEC, 0x06]))
    }

    func testCycleAnswerResolvesTheProfileAndSubscribes() {
        var engine = OppoSessionEngine()
        _ = engine.receive(OppoFrame(command: 0x8100, sequence: 0, payload: [0x00]))
        _ = engine.receive(OppoFrame(command: 0x8103, sequence: 1, payload: [0x00, 0x10, 0xEC, 0x06]))

        let replies = engine.receive(
            OppoFrame(command: 0x810C, sequence: 2, payload: [0x00, 0x02, 0x00, 0x06, 0x00])
        )

        XCTAssertNotNil(engine.profile)
        XCTAssertEqual(engine.cycleMask, 0x0006)
        XCTAssertEqual(replies.map(\.command), [OppoCommand.eventsSubscribe, OppoCommand.noiseQuery])
        XCTAssertTrue(engine.subscribed)
    }

    func testDeviceThatDeclaresNoNoiseCycleGetsNoProfile() {
        var engine = OppoSessionEngine()
        _ = engine.receive(OppoFrame(command: 0x8100, sequence: 0, payload: [0x00]))
        _ = engine.receive(OppoFrame(command: 0x8103, sequence: 1, payload: [0x00, 0x10, 0xEC, 0x06]))

        // Only "off" in the cycle: this model does not switch between cancellation
        // and transparency, so nothing may be drawn for it.
        let replies = engine.receive(
            OppoFrame(command: 0x810C, sequence: 2, payload: [0x00, 0x02, 0x00, 0x01, 0x00])
        )
        XCTAssertNil(engine.profile)
        XCTAssertTrue(replies.isEmpty)
    }

    func testSubIndexHighlightsTheParentMode() {
        var engine = engineWithProfile()
        // Index 7 is "smart cancellation" under the parent cancellation mode.
        _ = engine.receive(OppoFrame(command: 0x810C, sequence: 3, payload: [0x00, 0x01, 0x01, 0x80, 0x00]))
        XCTAssertEqual(engine.currentMode, .noiseCancellation)

        _ = engine.receive(OppoFrame(command: 0x810C, sequence: 4, payload: [0x00, 0x01, 0x01, 0x04, 0x00]))
        XCTAssertEqual(engine.currentMode, .transparency)

        // Index 0 and its alias 3 both mean off.
        _ = engine.receive(OppoFrame(command: 0x810C, sequence: 5, payload: [0x00, 0x01, 0x01, 0x08, 0x00]))
        XCTAssertEqual(engine.currentMode, .off)
    }

    func testAmbiguousMaskNamesNoMode() {
        XCTAssertNil(OppoPayload.modeIndex(fromMask: 0))
        XCTAssertNil(OppoPayload.modeIndex(fromMask: 0x0003))
        XCTAssertEqual(OppoPayload.modeIndex(fromMask: 0x0004), 2)
    }

    func testSetModeWritesTheSingleIndexBit() {
        var engine = engineWithProfile()
        XCTAssertEqual(engine.setMode(.noiseCancellation)?.payload, [0x01, 0x01, 0x02])
        XCTAssertEqual(engine.setMode(.transparency)?.payload, [0x01, 0x01, 0x04])
        XCTAssertEqual(engine.setMode(.off)?.payload, [0x01, 0x01, 0x01])
        // Adaptive is a mode this protocol family does not offer here.
        XCTAssertNil(engine.setMode(.adaptive))
    }

    func testSetModeUsesTwoMaskBytesForHighIndices() {
        var engine = OppoSessionEngine()
        engine.adoptProfile(OppoNoiseProfile(
            productID: 0x06EC10,
            indices: [.off: 0, .cancellation: 13, .transparency: 2],
            aliases: [:],
            isMeasured: true
        ))
        XCTAssertEqual(engine.setMode(.noiseCancellation)?.payload, [0x01, 0x01, 0x00, 0x20])
    }

    func testWriteAckIsNotTreatedAsConfirmation() {
        var engine = engineWithProfile()
        let replies = engine.receive(OppoFrame(command: 0x8404, sequence: 4, payload: [0x00]))
        // The ack only asks for a read-back; the mode moves when the device says so.
        XCTAssertEqual(replies.map(\.command), [OppoCommand.noiseQuery])
        XCTAssertNil(engine.currentMode)

        _ = engine.receive(OppoFrame(command: 0x810C, sequence: 5, payload: [0x00, 0x01, 0x01, 0x04, 0x00]))
        XCTAssertEqual(engine.currentMode, .transparency)
    }

    func testFailedWriteAckRequestsNoReadBack() {
        var engine = engineWithProfile()
        XCTAssertTrue(engine.receive(OppoFrame(command: 0x8404, sequence: 4, payload: [0x01])).isEmpty)
    }

    func testEventPushUpdatesTheMode() {
        var engine = engineWithProfile()
        _ = engine.receive(OppoFrame(command: 0x0204, sequence: 0xFF, payload: [0x03, 0x01, 0x01, 0x02]))
        XCTAssertEqual(engine.currentMode, .noiseCancellation)

        // A push naming two bits is ambiguous and must be ignored, not guessed.
        _ = engine.receive(OppoFrame(command: 0x0204, sequence: 0xFF, payload: [0x03, 0x03]))
        XCTAssertEqual(engine.currentMode, .noiseCancellation)
    }
}

// MARK: - Profile selection

final class OppoNoiseProfileTests: XCTestCase {
    func testGenericProfileRequiresTheDeviceToDeclareBothModes() {
        XCTAssertNotNil(OppoNoiseProfiles.profile(productID: 0x06EC10, cycleMask: 0x0006))
        XCTAssertNotNil(OppoNoiseProfiles.profile(productID: nil, cycleMask: 0x0007))
        XCTAssertNil(OppoNoiseProfiles.profile(productID: 0x06EC10, cycleMask: 0x0004))
        XCTAssertNil(OppoNoiseProfiles.profile(productID: 0x06EC10, cycleMask: nil))
        XCTAssertNil(OppoNoiseProfiles.profile(productID: 0x06EC10, cycleMask: 0x0000))
    }

    func testSelectableModesAreCancellationTransparencyOff() {
        let profile = OppoNoiseProfiles.generic
        XCTAssertEqual(profile.selectableModes, [.noiseCancellation, .transparency, .off])
        XCTAssertEqual(OppoNoiseState.selectableListeningModes, [.noiseCancellation, .transparency, .off])
    }

    func testAliasesMapBackToTheirParentMode() {
        let profile = OppoNoiseProfiles.generic
        XCTAssertEqual(profile.mode(reportedIndex: 7), .noiseCancellation)
        XCTAssertEqual(profile.mode(reportedIndex: 8), .transparency)
        XCTAssertEqual(profile.mode(reportedIndex: 2), .transparency)
        XCTAssertNil(profile.mode(reportedIndex: 11))
    }

    func testProfileWithoutOffCannotExpressIt() {
        let profile = OppoNoiseProfile(
            productID: 1,
            indices: [.cancellation: 1, .transparency: 2],
            aliases: [:],
            isMeasured: true
        )
        XCTAssertNil(profile.index(for: .off))
        XCTAssertNil(profile.setPayload(for: .off))
        XCTAssertEqual(profile.selectableModes, [.noiseCancellation, .transparency])
    }
}

// MARK: - Device classification

final class OppoAudioClassificationTests: XCTestCase {

    private func device(name: String, kind: BluetoothDeviceKind = .audio) -> BluetoothDevice {
        BluetoothDevice(
            id: "AA-BB-CC-DD-EE-FF",
            name: name,
            kind: kind,
            isConnected: true
        )
    }

    func testEncoFamilyIsRecognised() {
        XCTAssertTrue(device(name: "OPPO Enco X3").isOppoAudio)
        XCTAssertTrue(device(name: "OPPO Enco Air2 Pro").isOppoAudio)
        XCTAssertTrue(device(name: "Enco Free3").isOppoAudio)
    }

    func testSiblingBrandsRequireTheBudsWord() {
        XCTAssertTrue(device(name: "OnePlus Buds Pro 3").isOppoAudio)
        XCTAssertTrue(device(name: "realme Buds Air 6").isOppoAudio)
        // A OnePlus handset must not enter the noise-control branch.
        XCTAssertFalse(device(name: "OnePlus 13", kind: .mobile(.phone)).isOppoAudio)
    }

    func testOtherFamiliesAreNotMistakenForOppo() {
        XCTAssertFalse(device(name: "Redmi Buds 8").isOppoAudio)
        XCTAssertFalse(device(name: "HUAWEI FreeBuds 6i").isOppoAudio)
        XCTAssertFalse(device(name: "Galaxy Buds3 Pro").isOppoAudio)
        XCTAssertFalse(device(name: "Logitech Mouse").isOppoAudio)
        XCTAssertFalse(device(name: "OPPO Enco X3", kind: .unknown).isOppoAudio)
    }
}

// MARK: - Transport / controller integration

/// A scripted `OppoListeningModeTransporting` so the controller's OPPO branch can
/// be exercised without IOBluetooth.
private final class FakeOppoTransport: OppoListeningModeTransporting, @unchecked Sendable {
    private(set) var stateCalls: [String] = []
    private(set) var setModeCalls: [(BluetoothListeningMode, String)] = []
    private(set) var closeAllCount = 0
    private(set) var closedAddresses: [String] = []

    var stateResult: OppoNoiseState
    var setModeResult: OppoNoiseState?
    var stateError: (any Error)?
    var setModeError: (any Error)?

    init(stateResult: OppoNoiseState = OppoNoiseState(listeningMode: .noiseCancellation)) {
        self.stateResult = stateResult
    }

    func state(address: String) async throws -> OppoNoiseState {
        stateCalls.append(address)
        if let stateError { throw stateError }
        return stateResult
    }

    func setMode(_ mode: BluetoothListeningMode, address: String) async throws -> OppoNoiseState {
        setModeCalls.append((mode, address))
        if let setModeError { throw setModeError }
        return setModeResult ?? OppoNoiseState(listeningMode: mode)
    }

    func closeAll() { closeAllCount += 1 }

    func close(address: String) { closedAddresses.append(address) }
}

private struct EmptyOppoCoreAudioEndpoints: CoreAudioBluetoothEndpointProviding {
    func discoverEndpoints(using hal: BluetoothListeningModeHAL) -> [BluetoothListeningModeEndpoint] { [] }
}

private struct ScriptedOppoEndpointProvider: HuaweiAudioEndpointProviding {
    var endpointID: AudioDeviceID?
    func endpointID(for device: BluetoothDevice) -> AudioDeviceID? { endpointID }
}

@MainActor
final class OppoControllerTests: XCTestCase {
    private let address = "AA:BB:CC:DD:EE:01"
    private var key: String { BluetoothBatteryReader.normalizedAddress(address) }

    private func device(name: String = "OPPO Enco X3") -> BluetoothDevice {
        BluetoothDevice(id: address, name: name, kind: .audio, isConnected: true)
    }

    private func makeController(
        _ transport: FakeOppoTransport,
        endpoint: AudioDeviceID? = nil
    ) -> BluetoothListeningModeController {
        BluetoothListeningModeController(
            hal: BluetoothListeningModeHAL(
                backend: CoreAudioBluetoothListeningModeBackend(),
                sleeper: ImmediateListeningModeSleeper(),
                retryAttempts: 1,
                retryDelay: .milliseconds(1)
            ),
            endpointProvider: EmptyOppoCoreAudioEndpoints(),
            listenerBackend: CoreAudioBluetoothListeningModeListenerBackend(),
            oppoTransport: transport,
            oppoEndpointProvider: ScriptedOppoEndpointProvider(endpointID: endpoint),
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

    func testOppoDevicePublishesControlOnTheBluetoothRow() async {
        let transport = FakeOppoTransport()
        let controller = makeController(transport)
        controller.refresh(devices: [device()])

        await waitUntil { controller.control(forBluetoothAddress: self.address) != nil }

        let control = controller.control(forBluetoothAddress: address)
        XCTAssertEqual(control?.selectedMode, .noiseCancellation)
        XCTAssertEqual(Set(control?.availableModes ?? []), Set([.noiseCancellation, .transparency, .off]))
        XCTAssertEqual(controller.huaweiBluetoothRowPresentations[key]?.selectedMode, .noiseCancellation)
        XCTAssertEqual(transport.stateCalls, [key])
    }

    func testOppoControlRendersOnVolumeRowWhenEndpointResolves() async {
        let transport = FakeOppoTransport()
        let controller = makeController(transport, endpoint: 77)
        controller.refresh(devices: [device()])

        await waitUntil { controller.control(forEndpoint: 77) != nil }

        XCTAssertEqual(controller.control(forEndpoint: 77)?.address, key)
        XCTAssertNil(controller.control(forBluetoothAddress: address))
        XCTAssertTrue(controller.huaweiBluetoothRowPresentations.isEmpty)
    }

    func testOppoSetModeRoutesThroughTransportAndConfirms() async {
        let transport = FakeOppoTransport()
        transport.setModeResult = OppoNoiseState(listeningMode: .transparency)
        let controller = makeController(transport)
        controller.refresh(devices: [device()])
        await waitUntil { controller.control(forBluetoothAddress: self.address) != nil }

        controller.setMode(.transparency, forAddress: key)

        await waitUntil { controller.control(forBluetoothAddress: self.address)?.selectedMode == .transparency }
        XCTAssertEqual(transport.setModeCalls.count, 1)
        XCTAssertEqual(transport.setModeCalls.first?.0, .transparency)
        XCTAssertEqual(controller.control(forBluetoothAddress: address)?.selectedMode, .transparency)
    }

    func testOppoFailedWriteRollsBackToReportedMode() async {
        let transport = FakeOppoTransport()
        // The device kept the mode it had: the write must not be shown as a success.
        transport.setModeResult = OppoNoiseState(listeningMode: .noiseCancellation)
        let controller = makeController(transport)
        controller.refresh(devices: [device()])
        await waitUntil { controller.control(forBluetoothAddress: self.address) != nil }

        controller.setMode(.transparency, forAddress: key)

        await waitUntil { controller.control(forBluetoothAddress: self.address)?.isChanging == false }
        XCTAssertEqual(controller.control(forBluetoothAddress: address)?.selectedMode, .noiseCancellation)
    }

    func testOppoVanishesWhenTheModelIsUnsupported() async {
        let transport = FakeOppoTransport()
        transport.stateError = OppoListeningModeError.unsupportedModel
        let controller = makeController(transport)
        controller.refresh(devices: [device()])

        await waitUntil { !transport.stateCalls.isEmpty }
        XCTAssertNil(controller.control(forBluetoothAddress: address))
        XCTAssertTrue(controller.huaweiBluetoothRowPresentations.isEmpty)
    }

    func testOppoDeviceIsNotOfferedWhenTheListeningModeSwitchIsOff() {
        // Nothing in this controller reads the master switch; the panel simply
        // stops calling `refresh`. Guarding the classification here keeps the
        // contract visible: a non-OPPO name never enters this branch.
        XCTAssertFalse(BluetoothDevice(id: address, name: "Galaxy Buds3", kind: .audio, isConnected: true).isOppoAudio)
    }

    func testStopKeepsPersistentSessionsAndShutdownReleasesThem() async {
        let transport = FakeOppoTransport()
        let controller = makeController(transport)
        controller.refresh(devices: [device()])
        await waitUntil { controller.control(forBluetoothAddress: self.address) != nil }

        controller.stop()
        XCTAssertEqual(transport.closeAllCount, 0)
        XCTAssertNil(controller.control(forBluetoothAddress: address))

        controller.shutdown()
        XCTAssertEqual(transport.closeAllCount, 1)
    }

    func testDeviceLeavingTheEligibleSetClosesItsSession() async {
        let transport = FakeOppoTransport()
        let controller = makeController(transport)
        controller.refresh(devices: [device()])
        await waitUntil { controller.control(forBluetoothAddress: self.address) != nil }

        let offline = BluetoothDevice(id: address, name: "OPPO Enco X3", kind: .audio, isConnected: false)
        controller.refresh(devices: [offline])

        XCTAssertEqual(transport.closedAddresses, [key])
        XCTAssertNil(controller.control(forBluetoothAddress: address))
    }
}

/// A fixed-seed generator so the malformed-stream test is reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
