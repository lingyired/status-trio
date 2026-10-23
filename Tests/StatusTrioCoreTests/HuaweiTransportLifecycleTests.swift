import Foundation
import IOBluetooth
import XCTest

@testable import StatusTrioCore

@MainActor
final class HuaweiTransportLifecycleTests: XCTestCase {
    func testChannelFailureReleasesAnApplicationOpenedBluetoothConnection() async {
        let probe = ConnectionOwnershipProbe(channelOpenStatus: kIOReturnError)
        let transport = HuaweiRFCOMMTransport(hooks: probe.hooks)

        do {
            _ = try await transport.state(address: "AA:BB:CC:DD:EE:FF")
            XCTFail("Expected channel open failure")
        } catch {
            // Expected.
        }

        XCTAssertEqual(probe.openConnectionCallCount, 1)
        XCTAssertEqual(probe.openRFCOMMChannelCallCount, 2)
        XCTAssertEqual(probe.closeConnectionCallCount, 1)
    }

    func testFailedOpenDoesNotCloseAConnectionTheTransportDidNotAcquire() async {
        let probe = ConnectionOwnershipProbe(openConnectionStatus: kIOReturnError)
        let transport = HuaweiRFCOMMTransport(hooks: probe.hooks)

        do {
            _ = try await transport.state(address: "AA:BB:CC:DD:EE:FF")
            XCTFail("Expected Bluetooth connection failure")
        } catch {
            // Expected.
        }

        XCTAssertEqual(probe.openConnectionCallCount, 1)
        XCTAssertEqual(probe.sdpCallCount, 0)
        XCTAssertEqual(probe.closeConnectionCallCount, 0)
    }

    func testOpenThatNeverConnectsIsReleased() async {
        let probe = ConnectionOwnershipProbe(connectsAfterOpen: false)
        let transport = HuaweiRFCOMMTransport(hooks: probe.hooks)

        do {
            _ = try await transport.state(address: "AA:BB:CC:DD:EE:FF")
            XCTFail("Expected Bluetooth connection timeout")
        } catch HuaweiListeningModeError.timeout {
            // Expected.
        } catch {
            XCTFail("Expected Bluetooth connection timeout, got \(error)")
        }

        XCTAssertEqual(probe.openConnectionCallCount, 1)
        XCTAssertEqual(probe.sdpCallCount, 0)
        XCTAssertEqual(probe.closeConnectionCallCount, 1)
    }

    func testCloseAllDuringSDPReleasesAnApplicationOpenedBluetoothConnection() async {
        let sdpStarted = expectation(description: "SDP started")
        let probe = ConnectionOwnershipProbe(
            sdpStarted: sdpStarted,
            holdSDPUntilReleased: true
        )
        let transport = HuaweiRFCOMMTransport(hooks: probe.hooks)
        let read = Task.detached {
            try await transport.state(address: "AA:BB:CC:DD:EE:FF")
        }

        await fulfillment(of: [sdpStarted], timeout: 2)
        transport.closeAll()
        probe.releaseSDP.signal()
        _ = try? await read.value

        await fulfillment(of: [probe.sessionsClosed], timeout: 2)
        XCTAssertEqual(probe.sdpCallCount, 1)
        XCTAssertEqual(probe.openRFCOMMChannelCallCount, 0)
        XCTAssertFalse(probe.isDeviceConnected)
        XCTAssertEqual(probe.closeConnectionCallCount, 1)
    }

    func testCloseAllReleasesAnApplicationOpenedBluetoothConnection() async {
        let probe = ConnectionOwnershipProbe()
        let transport = HuaweiRFCOMMTransport(hooks: probe.hooks)
        do {
            _ = try await transport.state(address: "AA:BB:CC:DD:EE:FF")
        } catch {
            XCTFail("Expected state read to succeed, got \(error)")
        }

        transport.closeAll()

        await fulfillment(of: [probe.sessionsClosed], timeout: 2)
        XCTAssertEqual(probe.closeRFCOMMChannelCallCount, 1)
        XCTAssertFalse(probe.isDeviceConnected)
        XCTAssertEqual(probe.closeConnectionCallCount, 1)
    }

    func testCloseAllLeavesAPreExistingBluetoothConnectionOpen() async throws {
        let probe = ConnectionOwnershipProbe(initiallyConnected: true)
        let transport = HuaweiRFCOMMTransport(hooks: probe.hooks)
        _ = try await transport.state(address: "AA:BB:CC:DD:EE:FF")

        transport.closeAll()

        await fulfillment(of: [probe.sessionsClosed], timeout: 2)
        XCTAssertEqual(probe.openConnectionCallCount, 0)
        XCTAssertEqual(probe.closeRFCOMMChannelCallCount, 1)
        XCTAssertEqual(probe.closeConnectionCallCount, 0)
    }

    func testSDPFailureReleasesAnApplicationOpenedBluetoothConnection() async {
        let probe = ConnectionOwnershipProbe(
            sdpStatus: kIOReturnError
        )
        let transport = HuaweiRFCOMMTransport(hooks: probe.hooks)

        do {
            _ = try await transport.state(address: "AA:BB:CC:DD:EE:FF")
            XCTFail("Expected SDP query failure")
        } catch {
            // Expected.
        }

        XCTAssertEqual(probe.openConnectionCallCount, 1)
        XCTAssertEqual(probe.sdpCallCount, 1)
        XCTAssertEqual(probe.openRFCOMMChannelCallCount, 0)
        XCTAssertFalse(probe.isDeviceConnected)
        XCTAssertEqual(probe.closeConnectionCallCount, 1)
    }

    func testExchangeFailureReleasesAnApplicationOpenedBluetoothConnection() async {
        let probe = ConnectionOwnershipProbe(
            channelWriteStatus: kIOReturnError
        )
        let transport = HuaweiRFCOMMTransport(hooks: probe.hooks)

        do {
            _ = try await transport.state(address: "AA:BB:CC:DD:EE:FF")
            XCTFail("Expected channel write failure")
        } catch {
            // Expected.
        }

        XCTAssertEqual(probe.openConnectionCallCount, 1)
        XCTAssertEqual(probe.closeRFCOMMChannelCallCount, 1)
        XCTAssertFalse(probe.isDeviceConnected)
        XCTAssertEqual(probe.closeConnectionCallCount, 1)
    }

    func testExchangeFailureLeavesAPreExistingBluetoothConnectionOpen() async {
        let probe = ConnectionOwnershipProbe(
            initiallyConnected: true,
            channelWriteStatus: kIOReturnError
        )
        let transport = HuaweiRFCOMMTransport(hooks: probe.hooks)

        do {
            _ = try await transport.state(address: "AA:BB:CC:DD:EE:FF")
            XCTFail("Expected channel write failure")
        } catch {
            // Expected.
        }

        XCTAssertEqual(probe.openConnectionCallCount, 0)
        XCTAssertEqual(probe.closeRFCOMMChannelCallCount, 1)
        XCTAssertTrue(probe.isDeviceConnected)
        XCTAssertEqual(probe.closeConnectionCallCount, 0)
    }

    func testCancellationAfterChannelOpenReleasesBothOwnedResources() async {
        let channelOpened = expectation(description: "RFCOMM channel opened")
        let probe = ConnectionOwnershipProbe(
            channelOpened: channelOpened,
            holdChannelOpenUntilReleased: true
        )
        let transport = HuaweiRFCOMMTransport(hooks: probe.hooks)
        let read = Task.detached {
            try await transport.state(address: "AA:BB:CC:DD:EE:FF")
        }

        await fulfillment(of: [channelOpened], timeout: 3)
        transport.closeAll()
        probe.releaseChannel.signal()
        do {
            _ = try await read.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertEqual(probe.openRFCOMMChannelCallCount, 1)
        XCTAssertEqual(probe.closeRFCOMMChannelCallCount, 1)
        XCTAssertEqual(probe.closeConnectionCallCount, 1)
    }

    func testAlreadyCancelledOperationDoesNotStartTransport() async {
        let probe = LifecycleProbe()
        let transport = makeTransport(probe: probe)
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await transport.state(address: "AA:BB:CC:DD:EE:FF")
        }

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertEqual(probe.operationCount, 0)
        XCTAssertEqual(transport.transportThreadCount, 0)
    }

    func testCloseDuringRunningOperationCancelsBeforeSideEffect() async {
        let probe = LifecycleProbe()
        let operationStarted = expectation(description: "operation started")
        let closed = expectation(description: "sessions closed")
        let gate = DispatchSemaphore(value: 0)
        let transport = makeTransport(
            probe: probe,
            runOperation: { request, context in
                operationStarted.fulfill()
                guard gate.wait(timeout: .now() + 2) == .success else {
                    throw LifecycleProbeError.gateTimedOut
                }
                return try probe.execute(request, context: context)
            },
            didCloseSessions: { _ in closed.fulfill() }
        )
        let task = Task.detached {
            try await transport.setMode(.cancellation, address: "AA:BB:CC:DD:EE:FF")
        }

        await fulfillment(of: [operationStarted], timeout: 2)
        transport.closeAll()
        gate.signal()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        await fulfillment(of: [closed], timeout: 2)
        XCTAssertEqual(probe.operationCount, 0)
    }

    func testCloseDuringStartupInvalidatesOperation() async {
        let probe = LifecycleProbe()
        let startupEntered = expectation(description: "startup entered")
        let closed = expectation(description: "sessions closed")
        let gate = DispatchSemaphore(value: 0)
        let transport = makeTransport(
            probe: probe,
            didStartTransportThread: {
                startupEntered.fulfill()
                _ = gate.wait(timeout: .now() + 2)
            },
            didCloseSessions: { _ in closed.fulfill() }
        )
        let task = Task.detached {
            try await transport.state(address: "AA:BB:CC:DD:EE:FF")
        }

        await fulfillment(of: [startupEntered], timeout: 2)
        transport.closeAll()
        gate.signal()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        await fulfillment(of: [closed], timeout: 2)
        XCTAssertEqual(probe.operationCount, 0)
        XCTAssertEqual(transport.transportThreadCount, 1)
    }

    func testQueuedOperationsDoNotReenterTransportDrain() async throws {
        let probe = LifecycleProbe()
        let firstStarted = expectation(description: "first operation started")
        let secondQueued = expectation(description: "second operation queued")
        let gate = DispatchSemaphore(value: 0)
        let secondAddress = "11:22:33:44:55:66"
        let transport = makeTransport(
            probe: probe,
            didEnqueue: { request in
                if case .state(let address) = request, address == secondAddress {
                    secondQueued.fulfill()
                }
            },
            runOperation: { request, context in
                if probe.noteRunStarted() == 1 {
                    firstStarted.fulfill()
                    guard gate.wait(timeout: .now() + 2) == .success else {
                        throw LifecycleProbeError.gateTimedOut
                    }
                }
                return try probe.execute(request, context: context)
            }
        )
        let first = Task.detached {
            try await transport.state(address: "AA:BB:CC:DD:EE:FF")
        }

        await fulfillment(of: [firstStarted], timeout: 2)
        let second = Task.detached {
            try await transport.state(address: "11:22:33:44:55:66")
        }
        await fulfillment(of: [secondQueued], timeout: 2)
        gate.signal()

        let firstState = try await first.value
        let secondState = try await second.value
        XCTAssertEqual(firstState.mode, HuaweiNoiseMode.cancellation)
        XCTAssertEqual(secondState.mode, HuaweiNoiseMode.cancellation)
        XCTAssertEqual(probe.operationCount, 2)
        XCTAssertEqual(probe.maximumExecutionDepth, 1)
        XCTAssertEqual(transport.transportThreadCount, 1)
    }

    func testCloseAndReopenUsesFreshSessionOnSameTransportThread() async throws {
        let probe = LifecycleProbe()
        let closed = expectation(description: "sessions closed")
        let transport = makeTransport(
            probe: probe,
            didCloseSessions: { _ in closed.fulfill() }
        )

        _ = try await transport.state(address: "AA:BB:CC:DD:EE:FF")
        transport.closeAll()
        await fulfillment(of: [closed], timeout: 2)

        _ = try await transport.state(address: "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(probe.sessionGenerations, [0, 1])
        XCTAssertEqual(transport.transportThreadCount, 1)
    }

    private func makeTransport(
        probe: LifecycleProbe,
        didStartTransportThread: (@Sendable () -> Void)? = nil,
        didEnqueue: (@Sendable (HuaweiRFCOMMTransport.OperationRequest) -> Void)? = nil,
        runOperation: (
            @Sendable (HuaweiRFCOMMTransport.OperationRequest, HuaweiRFCOMMTransport.OperationContext) throws -> HuaweiNoiseState
        )? = nil,
        didCloseSessions: (@Sendable (UInt64) -> Void)? = nil
    ) -> HuaweiRFCOMMTransport {
        HuaweiRFCOMMTransport(hooks: .init(
            didStartTransportThread: didStartTransportThread,
            didEnqueue: didEnqueue,
            runOperation: runOperation ?? { request, context in
                try probe.execute(request, context: context)
            },
            didCloseSessions: didCloseSessions
        ))
    }
}

private final class LifecycleProbe: @unchecked Sendable {
    private struct State {
        var operations = 0
        var runStarts = 0
        var executionDepth = 0
        var maximumExecutionDepth = 0
        var sessionGenerations: [UInt64] = []
    }

    private let lock = NSLock()
    private var state = State()

    var operationCount: Int { lock.withLock { state.operations } }
    var maximumExecutionDepth: Int { lock.withLock { state.maximumExecutionDepth } }
    var sessionGenerations: [UInt64] { lock.withLock { state.sessionGenerations } }

    func noteRunStarted() -> Int {
        lock.withLock {
            state.runStarts += 1
            return state.runStarts
        }
    }

    func execute(
        _ request: HuaweiRFCOMMTransport.OperationRequest,
        context: HuaweiRFCOMMTransport.OperationContext
    ) throws -> HuaweiNoiseState {
        lock.withLock {
            state.executionDepth += 1
            state.maximumExecutionDepth = max(
                state.maximumExecutionDepth,
                state.executionDepth
            )
        }
        defer {
            lock.withLock { state.executionDepth -= 1 }
        }

        try context.checkpoint()
        lock.withLock {
            state.operations += 1
            state.sessionGenerations.append(context.sessionGeneration)
        }

        switch request {
        case .state:
            return HuaweiNoiseState(level: 0, mode: HuaweiNoiseMode.cancellation.rawValue)!
        case .setMode(let mode, _):
            return HuaweiNoiseState(level: 0, mode: mode.rawValue)!
        }
    }
}


private struct ConnectionOwnershipState {
    var openRFCOMMChannelCallCount = 0
    var openConnectionCallCount = 0
    var closeRFCOMMChannelCallCount = 0
    var closeConnectionCallCount = 0
    var sdpCallCount = 0
}

private final class LockedConnectionOwnershipState: @unchecked Sendable {
    private let lock = NSLock()
    private var state = ConnectionOwnershipState()

    var openRFCOMMChannelCallCount: Int { lock.withLock { state.openRFCOMMChannelCallCount } }
    var openConnectionCallCount: Int { lock.withLock { state.openConnectionCallCount } }
    var closeRFCOMMChannelCallCount: Int { lock.withLock { state.closeRFCOMMChannelCallCount } }
    var closeConnectionCallCount: Int { lock.withLock { state.closeConnectionCallCount } }
    var sdpCallCount: Int { lock.withLock { state.sdpCallCount } }

    func record(_ event: HuaweiBluetoothDeviceProbe.Event) {
        lock.withLock {
            switch event {
            case .openConnection: state.openConnectionCallCount += 1
            case .closeConnection: state.closeConnectionCallCount += 1
            case .sdp: state.sdpCallCount += 1
            case .openRFCOMMChannel: state.openRFCOMMChannelCallCount += 1
            case .closeRFCOMMChannel: state.closeRFCOMMChannelCallCount += 1
            }
        }
    }
}

private final class ConnectionOwnershipProbe: @unchecked Sendable {
    private let state: LockedConnectionOwnershipState
    let hooks: HuaweiRFCOMMTransport.Hooks
    let sessionsClosed: XCTestExpectation
    let releaseSDP = DispatchSemaphore(value: 0)
    let releaseChannel = DispatchSemaphore(value: 0)
    private let device: HuaweiBluetoothDeviceProbe

    var openRFCOMMChannelCallCount: Int { state.openRFCOMMChannelCallCount }
    var openConnectionCallCount: Int { state.openConnectionCallCount }
    var closeRFCOMMChannelCallCount: Int { state.closeRFCOMMChannelCallCount }
    var closeConnectionCallCount: Int { state.closeConnectionCallCount }
    var sdpCallCount: Int { state.sdpCallCount }
    var isDeviceConnected: Bool { device.isConnected() }

    init(
        initiallyConnected: Bool = false,
        openConnectionStatus: IOReturn = kIOReturnSuccess,
        connectsAfterOpen: Bool = true,
        channelOpenStatus: IOReturn = kIOReturnSuccess,
        channelWriteStatus: IOReturn = kIOReturnSuccess,
        sdpStatus: IOReturn = kIOReturnSuccess,
        sdpStarted: XCTestExpectation? = nil,
        holdSDPUntilReleased: Bool = false,
        channelOpened: XCTestExpectation? = nil,
        holdChannelOpenUntilReleased: Bool = false
    ) {
        let sessionsClosed = XCTestExpectation(description: "sessions closed")
        self.sessionsClosed = sessionsClosed
        let state = LockedConnectionOwnershipState()
        let device = HuaweiBluetoothDeviceProbe(
            initiallyConnected: initiallyConnected,
            openConnectionStatus: openConnectionStatus,
            connectsAfterOpen: connectsAfterOpen,
            channelOpenStatus: channelOpenStatus,
            channelWriteStatus: channelWriteStatus,
            sdpStatus: sdpStatus,
            sdpStarted: sdpStarted,
            holdSDPUntilReleased: holdSDPUntilReleased,
            releaseSDP: releaseSDP,
            channelOpened: channelOpened,
            holdChannelOpenUntilReleased: holdChannelOpenUntilReleased,
            releaseChannel: releaseChannel,
            eventHandler: { state.record($0) }
        )
        self.state = state
        self.device = device
        hooks = HuaweiRFCOMMTransport.Hooks(
            pairedDevices: { [device] },
            didCloseSessions: { _ in sessionsClosed.fulfill() }
        )
    }
}

private final class HuaweiBluetoothDeviceProbe: HuaweiBluetoothDevice, @unchecked Sendable {
    enum Event {
        case openConnection
        case closeConnection
        case sdp
        case openRFCOMMChannel
        case closeRFCOMMChannel
    }

    private let lock = NSLock()
    private var connected: Bool
    private let openConnectionStatus: IOReturn
    private let connectsAfterOpen: Bool
    private let channelOpenStatus: IOReturn
    private let channelWriteStatus: IOReturn
    private let sdpStatus: IOReturn
    private let sdpStarted: XCTestExpectation?
    private let holdSDPUntilReleased: Bool
    private let releaseSDP: DispatchSemaphore
    private let channelOpened: XCTestExpectation?
    private let holdChannelOpenUntilReleased: Bool
    private let releaseChannel: DispatchSemaphore
    private let eventHandler: @Sendable (Event) -> Void

    var addressString: String? { "AA:BB:CC:DD:EE:FF" }

    init(
        initiallyConnected: Bool,
        openConnectionStatus: IOReturn,
        connectsAfterOpen: Bool,
        channelOpenStatus: IOReturn,
        channelWriteStatus: IOReturn,
        sdpStatus: IOReturn,
        sdpStarted: XCTestExpectation?,
        holdSDPUntilReleased: Bool,
        releaseSDP: DispatchSemaphore,
        channelOpened: XCTestExpectation?,
        holdChannelOpenUntilReleased: Bool,
        releaseChannel: DispatchSemaphore,
        eventHandler: @escaping @Sendable (Event) -> Void
    ) {
        connected = initiallyConnected
        self.openConnectionStatus = openConnectionStatus
        self.connectsAfterOpen = connectsAfterOpen
        self.channelOpenStatus = channelOpenStatus
        self.channelWriteStatus = channelWriteStatus
        self.sdpStatus = sdpStatus
        self.sdpStarted = sdpStarted
        self.holdSDPUntilReleased = holdSDPUntilReleased
        self.releaseSDP = releaseSDP
        self.channelOpened = channelOpened
        self.holdChannelOpenUntilReleased = holdChannelOpenUntilReleased
        self.releaseChannel = releaseChannel
        self.eventHandler = eventHandler
    }

    func isConnected() -> Bool { lock.withLock { connected } }

    func openConnection() -> IOReturn {
        eventHandler(.openConnection)
        guard openConnectionStatus == kIOReturnSuccess else {
            return openConnectionStatus
        }
        if connectsAfterOpen {
            lock.withLock { connected = true }
        }
        return kIOReturnSuccess
    }

    func closeConnection() -> IOReturn {
        eventHandler(.closeConnection)
        lock.withLock { connected = false }
        return kIOReturnSuccess
    }

    func performSDPQuery() -> IOReturn {
        eventHandler(.sdp)
        sdpStarted?.fulfill()
        if holdSDPUntilReleased {
            _ = releaseSDP.wait(timeout: .now() + 2)
        }
        return sdpStatus
    }

    func serviceRFCOMMChannelID() -> BluetoothRFCOMMChannelID? { nil }

    func openRFCOMMChannel(
        channelID: BluetoothRFCOMMChannelID,
        delegate: IOBluetoothRFCOMMChannelDelegate
    ) -> (status: IOReturn, channel: (any HuaweiRFCOMMChannel)?) {
        eventHandler(.openRFCOMMChannel)
        guard channelOpenStatus == kIOReturnSuccess else {
            return (channelOpenStatus, nil)
        }
        let response = HuaweiSPPFrame(
            command: HuaweiSPPFrame.readANCCommand,
            parameters: [1: [2, HuaweiNoiseMode.cancellation.rawValue]]
        ).encoded()
        return (
            kIOReturnSuccess,
            HuaweiRFCOMMChannelProbe(
                delegate: delegate,
                response: response,
                writeStatus: channelWriteStatus,
                channelOpened: channelOpened,
                holdOpenUntilReleased: holdChannelOpenUntilReleased,
                releaseChannel: releaseChannel,
                didClose: { [eventHandler] in eventHandler(.closeRFCOMMChannel) }
            )
        )
    }
}

private final class HuaweiRFCOMMChannelProbe: HuaweiRFCOMMChannel, @unchecked Sendable {
    private let delegate: IOBluetoothRFCOMMChannelDelegate
    private let response: [UInt8]
    private let writeStatus: IOReturn
    private let channelOpened: XCTestExpectation?
    private let holdOpenUntilReleased: Bool
    private let releaseChannel: DispatchSemaphore
    private let didClose: @Sendable () -> Void
    private let lock = NSLock()
    private var open = true
    private var didCheckOpen = false

    init(
        delegate: IOBluetoothRFCOMMChannelDelegate,
        response: [UInt8],
        writeStatus: IOReturn,
        channelOpened: XCTestExpectation?,
        holdOpenUntilReleased: Bool,
        releaseChannel: DispatchSemaphore,
        didClose: @escaping @Sendable () -> Void
    ) {
        self.delegate = delegate
        self.response = response
        self.writeStatus = writeStatus
        self.channelOpened = channelOpened
        self.holdOpenUntilReleased = holdOpenUntilReleased
        self.releaseChannel = releaseChannel
        self.didClose = didClose
        delegate.rfcommChannelOpenComplete?(nil, status: kIOReturnSuccess)
    }

    func isOpen() -> Bool {
        let shouldPause = lock.withLock {
            defer { didCheckOpen = true }
            return holdOpenUntilReleased && !didCheckOpen
        }
        if shouldPause {
            channelOpened?.fulfill()
            _ = releaseChannel.wait(timeout: .now() + 2)
        }
        return lock.withLock { open }
    }

    func writeSync(_ data: UnsafeMutableRawPointer, length: UInt16) -> IOReturn {
        var response = response
        response.withUnsafeMutableBytes { bytes in
            delegate.rfcommChannelData?(
                nil,
                data: bytes.baseAddress,
                length: bytes.count
            )
        }
        return writeStatus
    }

    func close() {
        lock.withLock { open = false }
        didClose()
    }
}

private enum LifecycleProbeError: Error {
    case gateTimedOut
}
