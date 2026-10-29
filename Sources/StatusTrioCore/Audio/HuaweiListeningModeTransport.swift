import CoreFoundation
import Foundation
import IOBluetooth

protocol HuaweiBluetoothDevice: AnyObject, Sendable {
    var addressString: String? { get }
    func isConnected() -> Bool
    func openConnection() -> IOReturn
    func closeConnection() -> IOReturn
    func performSDPQuery() -> IOReturn
    func serviceRFCOMMChannelID() -> BluetoothRFCOMMChannelID?
    func openRFCOMMChannel(
        channelID: BluetoothRFCOMMChannelID,
        delegate: IOBluetoothRFCOMMChannelDelegate
    ) -> (status: IOReturn, channel: (any HuaweiRFCOMMChannel)?)
}

protocol HuaweiRFCOMMChannel: AnyObject, Sendable {
    func isOpen() -> Bool
    func writeSync(_ data: UnsafeMutableRawPointer, length: UInt16) -> IOReturn
    func close()
}

private final class IOBluetoothHuaweiRFCOMMChannel: HuaweiRFCOMMChannel, @unchecked Sendable {
    private let channel: IOBluetoothRFCOMMChannel

    init(_ channel: IOBluetoothRFCOMMChannel) {
        self.channel = channel
    }

    func isOpen() -> Bool { channel.isOpen() }

    func writeSync(_ data: UnsafeMutableRawPointer, length: UInt16) -> IOReturn {
        channel.writeSync(data, length: length)
    }

    func close() { channel.close() }
}

private final class IOBluetoothHuaweiDevice: HuaweiBluetoothDevice, @unchecked Sendable {
    private let device: IOBluetoothDevice

    init(_ device: IOBluetoothDevice) {
        self.device = device
    }

    var addressString: String? { device.addressString }
    func isConnected() -> Bool { device.isConnected() }
    func openConnection() -> IOReturn { device.openConnection() }
    func closeConnection() -> IOReturn { device.closeConnection() }
    func performSDPQuery() -> IOReturn { device.performSDPQuery(nil) }

    func serviceRFCOMMChannelID() -> BluetoothRFCOMMChannelID? {
        for item in device.services ?? [] {
            guard let record = item as? IOBluetoothSDPServiceRecord,
                  record.matchesUUID16(0x1101) else {
                continue
            }
            var channel: BluetoothRFCOMMChannelID = 0
            if record.getRFCOMMChannelID(&channel) == kIOReturnSuccess {
                return channel
            }
        }
        return nil
    }

    func openRFCOMMChannel(
        channelID: BluetoothRFCOMMChannelID,
        delegate: IOBluetoothRFCOMMChannelDelegate
    ) -> (status: IOReturn, channel: (any HuaweiRFCOMMChannel)?) {
        var channel: IOBluetoothRFCOMMChannel?
        let status = device.openRFCOMMChannelSync(
            &channel,
            withChannelID: channelID,
            delegate: delegate
        )
        return (status, channel.map(IOBluetoothHuaweiRFCOMMChannel.init))
    }
}

/// IOBluetooth-backed HUAWEI SPP transport.
///
/// Opens channels and serializes blocking exchanges on a dedicated run-loop
/// thread, leaving the main run loop free for UI and IOBluetooth callbacks.
/// Callbacks may arrive on the main thread even when the channel was opened on
/// the transport thread; the delegate synchronizes its receive state separately.
///
/// `@unchecked Sendable` is safe because connection ownership is confined to the
/// transport thread. The transport lock guards run-loop and queue state, while
/// each delegate lock guards its receive buffer, decoded frames, and open status.
final class HuaweiRFCOMMTransport: HuaweiListeningModeTransporting, @unchecked Sendable {
    /// Injection points for deterministic lifecycle tests. Production uses no
    /// hooks, so queueing, thread startup, and session cleanup stay in this type.
    struct Hooks: Sendable {
        var connectionReadyTimeout: TimeInterval = 5
        var sdpSettlingDuration: TimeInterval = 1
        var sdpServiceWaitTimeout: TimeInterval = 1
        var channelOpenTimeout: TimeInterval = 2
        var didStartTransportThread: (@Sendable () -> Void)?
        var didAcquireRunLoop: (@Sendable () -> Void)?
        var didEnqueue: (@Sendable (OperationRequest) -> Void)?
        var pairedDevices: @Sendable () -> [any HuaweiBluetoothDevice]
        var runOperation: (
            @Sendable (OperationRequest, OperationContext) throws -> HuaweiNoiseState
        )?
        var didCloseSessions: (@Sendable (UInt64) -> Void)?

        init(
            connectionReadyTimeout: TimeInterval = 5,
            sdpSettlingDuration: TimeInterval = 1,
            sdpServiceWaitTimeout: TimeInterval = 1,
            channelOpenTimeout: TimeInterval = 2,
            didStartTransportThread: (@Sendable () -> Void)? = nil,
            didAcquireRunLoop: (@Sendable () -> Void)? = nil,
            didEnqueue: (@Sendable (OperationRequest) -> Void)? = nil,
            pairedDevices: @escaping @Sendable () -> [any HuaweiBluetoothDevice] = {
                (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
                    .map(IOBluetoothHuaweiDevice.init)
            },
            runOperation: (
                @Sendable (OperationRequest, OperationContext) throws -> HuaweiNoiseState
            )? = nil,
            didCloseSessions: (@Sendable (UInt64) -> Void)? = nil
        ) {
            self.connectionReadyTimeout = connectionReadyTimeout
            self.sdpSettlingDuration = sdpSettlingDuration
            self.sdpServiceWaitTimeout = sdpServiceWaitTimeout
            self.channelOpenTimeout = channelOpenTimeout
            self.didStartTransportThread = didStartTransportThread
            self.didAcquireRunLoop = didAcquireRunLoop
            self.didEnqueue = didEnqueue
            self.pairedDevices = pairedDevices
            self.runOperation = runOperation
            self.didCloseSessions = didCloseSessions
        }
    }

    enum OperationRequest: Equatable, Sendable {
        case state(address: String)
        case setMode(mode: HuaweiNoiseMode, address: String)
    }

    struct OperationContext: Sendable {
        let sessionGeneration: UInt64
        private let checkOperation: @Sendable () throws -> Void

        init(
            sessionGeneration: UInt64,
            checkOperation: @escaping @Sendable () throws -> Void
        ) {
            self.sessionGeneration = sessionGeneration
            self.checkOperation = checkOperation
        }

        func checkpoint() throws {
            try checkOperation()
        }
    }

    private final class Delegate: NSObject, IOBluetoothRFCOMMChannelDelegate {
        // IOBluetooth can deliver data on the main thread even when the channel
        // was opened by the transport thread. Never expose mutable buffers to
        // exchange(); reset and dequeue operations must be atomic with callbacks.
        private let lock = NSLock()
        private var buffer: [UInt8] = []
        private var frames: [HuaweiSPPFrame] = []
        private var status: IOReturn?

        var openStatus: IOReturn? {
            lock.lock()
            defer { lock.unlock() }
            return status
        }

        func resetReplies() {
            lock.lock()
            defer { lock.unlock() }
            frames.removeAll(keepingCapacity: true)
            buffer.removeAll(keepingCapacity: true)
        }

        func takeFrame(command: [UInt8]) -> HuaweiSPPFrame? {
            lock.lock()
            defer { lock.unlock() }
            guard let index = frames.firstIndex(where: { $0.command == command }) else { return nil }
            return frames.remove(at: index)
        }

        func rfcommChannelOpenComplete(
            _ rfcommChannel: IOBluetoothRFCOMMChannel!,
            status error: IOReturn
        ) {
            lock.lock()
            defer { lock.unlock() }
            status = error
        }

        func rfcommChannelData(
            _ rfcommChannel: IOBluetoothRFCOMMChannel!,
            data dataPointer: UnsafeMutableRawPointer!,
            length dataLength: Int
        ) {
            guard let dataPointer, dataLength > 0 else { return }
            lock.lock()
            defer { lock.unlock() }
            buffer.append(contentsOf: UnsafeBufferPointer(
                start: dataPointer.assumingMemoryBound(to: UInt8.self),
                count: dataLength
            ))
            while buffer.count >= 4 {
                guard buffer[0] == HuaweiSPPFrame.magic else {
                    buffer.removeFirst()
                    continue
                }
                let frameLength = 4 + (Int(buffer[1]) << 8 | Int(buffer[2])) + 1
                guard frameLength <= 4096 else {
                    buffer.removeFirst()
                    continue
                }
                guard buffer.count >= frameLength else { break }
                if let frame = HuaweiSPPFrame.decode(Array(buffer[0..<frameLength])) {
                    frames.append(frame)
                }
                buffer.removeFirst(frameLength)
            }
        }

        func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
            lock.lock()
            defer { lock.unlock() }
            status = kIOReturnNotOpen
        }
    }

    private final class Connection {
        let device: any HuaweiBluetoothDevice
        let channel: any HuaweiRFCOMMChannel
        let delegate: Delegate
        let sessionGeneration: UInt64
        let openedConnection: Bool

        init(
            device: any HuaweiBluetoothDevice,
            channel: any HuaweiRFCOMMChannel,
            delegate: Delegate,
            sessionGeneration: UInt64,
            openedConnection: Bool
        ) {
            self.device = device
            self.channel = channel
            self.delegate = delegate
            self.sessionGeneration = sessionGeneration
            self.openedConnection = openedConnection
        }
    }

    /// The cancellation/completion state for one queued operation.
    ///
    /// A continuation can register after cancellation has already arrived, so
    /// cancellation is latched separately from the continuation. All terminal
    /// paths take the continuation exactly once.
    private final class OperationState: @unchecked Sendable {
        private enum Phase {
            case queued
            case running
            case completed
        }

        private let lock = NSLock()
        private var phase = Phase.queued
        private var cancellationRequested = false
        private var continuation: CheckedContinuation<HuaweiNoiseState, any Error>?

        var isCompleted: Bool {
            lock.withLock { phase == .completed }
        }

        func install(
            _ continuation: CheckedContinuation<HuaweiNoiseState, any Error>
        ) -> Bool {
            let result: (Bool, Bool) = lock.withLock {
                guard phase == .queued, !cancellationRequested else {
                    phase = .completed
                    return (false, true)
                }
                self.continuation = continuation
                return (true, false)
            }
            if result.1 {
                continuation.resume(throwing: CancellationError())
            }
            return result.0
        }

        func begin() -> Bool {
            let result: (Bool, CheckedContinuation<HuaweiNoiseState, any Error>?) = lock.withLock {
                guard phase == .queued else { return (false, nil) }
                if cancellationRequested {
                    phase = .completed
                    let continuation = self.continuation
                    self.continuation = nil
                    return (false, continuation)
                }
                phase = .running
                return (true, nil)
            }
            result.1?.resume(throwing: CancellationError())
            return result.0
        }

        func cancel() {
            let continuation: CheckedContinuation<HuaweiNoiseState, any Error>? = lock.withLock {
                guard phase != .completed else { return nil }
                cancellationRequested = true
                guard phase == .queued else { return nil }
                phase = .completed
                let continuation = self.continuation
                self.continuation = nil
                return continuation
            }
            continuation?.resume(throwing: CancellationError())
        }

        func checkpoint() throws {
            if lock.withLock({ cancellationRequested }) {
                throw CancellationError()
            }
        }

        func resume(returning value: HuaweiNoiseState) {
            let result: (
                CheckedContinuation<HuaweiNoiseState, any Error>?,
                Bool
            ) = lock.withLock {
                guard phase == .running else { return (nil, false) }
                phase = .completed
                let continuation = self.continuation
                self.continuation = nil
                return (continuation, cancellationRequested)
            }
            if result.1 {
                result.0?.resume(throwing: CancellationError())
            } else {
                result.0?.resume(returning: value)
            }
        }

        func resume(throwing error: any Error) {
            let continuation: CheckedContinuation<HuaweiNoiseState, any Error>? = lock.withLock {
                guard phase == .running else { return nil }
                phase = .completed
                let continuation = self.continuation
                self.continuation = nil
                return continuation
            }
            continuation?.resume(throwing: error)
        }
    }

    private struct PendingOperation: Sendable {
        let run: @Sendable () -> Void
    }

    private let lock = NSLock()
    /// Serializes the first-use startup of the transport thread.
    ///
    /// `transportRunLoop` is published by the new thread itself, so two callers
    /// that both observe `nil` would both create and start a thread. `state` and
    /// `setMode` are nonisolated `async` methods, so they run on the cooperative
    /// pool: two HUAWEI devices read at once really do reach `ensureRunLoop`
    /// concurrently. Two threads would break the "all access to `connections`
    /// happens on the transport thread" invariant this class documents, and the
    /// losing thread would run forever.
    private let startupLock = NSLock()
    private var transportThread: Thread?
    private var transportRunLoop: CFRunLoop?
    private var pending: [PendingOperation] = []
    private var activeOperationCancellations: [UUID: @Sendable () -> Void] = [:]
    /// One queued run-loop callback owns the entire drain chain.
    ///
    /// The active operation may pump its run loop while awaiting a response.
    /// Enqueue and close paths must not schedule another drain in that window.
    private var isDrainScheduled = false
    private var keepAlivePort: Port?
    private var startedThreadCount = 0
    private var currentSessionGeneration: UInt64 = 0
    private var deferredCloseGeneration: UInt64?
    private let hooks: Hooks

    init(hooks: Hooks = Hooks()) {
        self.hooks = hooks
    }

    /// How many transport threads this instance has started.
    ///
    /// One instance owns one thread. A second one would mean the first-use
    /// startup was not serialized, and the connection map would end up with two
    /// owners — the invariant this class documents.
    var transportThreadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return startedThreadCount
    }

    /// All access to `connections` happens on the transport thread.
    private var connections: [String: Connection] = [:]

    func state(address: String) async throws -> HuaweiNoiseState {
        try await perform(.state(address: address))
    }

    func setMode(_ mode: HuaweiNoiseMode, address: String) async throws -> HuaweiNoiseState {
        try await perform(.setMode(mode: mode, address: address))
    }

    func closeAll() {
        var cancellations: [@Sendable () -> Void] = []
        var runLoop: CFRunLoop?
        var shouldSchedule = false
        lock.lock()
        let closingGeneration = currentSessionGeneration
        currentSessionGeneration &+= 1
        cancellations = Array(activeOperationCancellations.values)
        runLoop = transportRunLoop
        if runLoop != nil {
            pending.append(PendingOperation { [weak self] in
                self?.closeAllOnTransportThread(through: closingGeneration)
            })
            if !isDrainScheduled {
                isDrainScheduled = true
                shouldSchedule = true
            }
        } else {
            deferredCloseGeneration = max(deferredCloseGeneration ?? 0, closingGeneration)
        }
        lock.unlock()
        for cancel in cancellations {
            cancel()
        }
        if shouldSchedule, let runLoop {
            scheduleDrain(on: runLoop)
        }
    }

    // MARK: - Async → transport thread

    private func perform(_ request: OperationRequest) async throws -> HuaweiNoiseState {
        let operation = OperationState()
        return try await withTaskCancellationHandler {
            if Task.isCancelled {
                operation.cancel()
            }
            return try await withCheckedThrowingContinuation { continuation in
                guard operation.install(continuation) else { return }
                enqueue(request, operation: operation)
            }
        } onCancel: {
            operation.cancel()
        }
    }

    private func enqueue(_ request: OperationRequest, operation: OperationState) {
        let id = UUID()
        let generation: UInt64
        lock.lock()
        generation = currentSessionGeneration
        activeOperationCancellations[id] = { operation.cancel() }
        lock.unlock()

        guard !operation.isCompleted else {
            removeActiveOperation(id)
            operation.cancel()
            return
        }

        let runLoop = ensureRunLoop()
        hooks.didAcquireRunLoop?()
        let pendingOperation = PendingOperation { [weak self, weak operation] in
            guard let self else { return }
            guard let operation else {
                self.removeActiveOperation(id)
                return
            }
            guard operation.begin() else {
                self.removeActiveOperation(id)
                return
            }
            let context = OperationContext(sessionGeneration: generation) {
                try operation.checkpoint()
                try self.checkSession(generation)
            }
            do {
                let result = try self.execute(request, context: context)
                operation.resume(returning: result)
            } catch {
                operation.resume(throwing: error)
            }
            self.removeActiveOperation(id)
        }

        var shouldCancel = false
        var shouldSchedule = false
        lock.lock()
        if generation == currentSessionGeneration, !operation.isCompleted {
            pending.append(pendingOperation)
            shouldSchedule = !isDrainScheduled
            if shouldSchedule { isDrainScheduled = true }
        } else {
            activeOperationCancellations.removeValue(forKey: id)
            shouldCancel = true
        }
        lock.unlock()

        if shouldCancel {
            operation.cancel()
            return
        }
        if shouldSchedule {
            scheduleDrain(on: runLoop)
        }
        hooks.didEnqueue?(request)
    }

    private func removeActiveOperation(_ id: UUID) {
        lock.withLock {
            _ = activeOperationCancellations.removeValue(forKey: id)
        }
    }

    private func checkSession(_ generation: UInt64) throws {
        let isCurrent = lock.withLock {
            generation == currentSessionGeneration
        }
        if !isCurrent {
            throw CancellationError()
        }
    }

    private func scheduleDrain(on runLoop: CFRunLoop) {
        CFRunLoopPerformBlock(runLoop, "kCFRunLoopCommonModes" as CFString) { [weak self] in
            self?.drain()
        }
        CFRunLoopWakeUp(runLoop)
    }

    /// Runs one queued operation. A request pumps a nested run loop while it
    /// waits for the reply, so the drain block must not be rescheduled until the
    /// operation returns; otherwise a second request would run re-entrantly.
    private func drain() {
        lock.lock()
        guard !pending.isEmpty else {
            isDrainScheduled = false
            lock.unlock()
            return
        }
        let pendingOperation = pending.removeFirst()
        lock.unlock()

        pendingOperation.run()

        var hasMore = false
        var runLoop: CFRunLoop?
        lock.lock()
        hasMore = !pending.isEmpty
        if !hasMore {
            isDrainScheduled = false
        } else {
            runLoop = transportRunLoop
        }
        lock.unlock()
        if let runLoop {
            scheduleDrain(on: runLoop)
        }
    }

    /// Returns the transport's run loop, starting the transport thread on first
    /// use.
    ///
    /// The whole body is serialized by `startupLock`: the run loop is published
    /// by the new thread, so without it two concurrent callers would each start
    /// a thread and the transport would own two. `closeAll()` never takes this
    /// lock, so invalidation remains nonblocking while startup is paused.
    private func ensureRunLoop() -> CFRunLoop {
        startupLock.lock()
        defer { startupLock.unlock() }

        lock.lock()
        if let runLoop = transportRunLoop {
            lock.unlock()
            return runLoop
        }
        lock.unlock()

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else { return }
            let runLoop = CFRunLoopGetCurrent()
            let keepAlivePort = Port()
            RunLoop.current.add(keepAlivePort, forMode: .default)
            self.lock.withLock {
                self.keepAlivePort = keepAlivePort
            }
            self.hooks.didStartTransportThread?()
            var shouldScheduleDrain = false
            self.lock.withLock {
                self.transportRunLoop = runLoop
                if let closeGeneration = self.deferredCloseGeneration {
                    self.deferredCloseGeneration = nil
                    self.pending.append(PendingOperation {
                        self.closeAllOnTransportThread(through: closeGeneration)
                    })
                }
                if !self.pending.isEmpty, !self.isDrainScheduled {
                    self.isDrainScheduled = true
                    shouldScheduleDrain = true
                }
            }
            ready.signal()
            if shouldScheduleDrain {
                self.scheduleDrain(on: CFRunLoopGetCurrent())
            }
            while true {
                RunLoop.current.run(mode: .default, before: .distantFuture)
            }
        }
        thread.name = "StatusTrio.HuaweiRFCOMM"
        thread.qualityOfService = .userInitiated

        lock.lock()
        transportThread = thread
        startedThreadCount += 1
        lock.unlock()

        thread.start()
        ready.wait()
        lock.lock()
        let runLoop = transportRunLoop ?? CFRunLoopGetMain()!
        lock.unlock()
        return runLoop
    }

    // MARK: - Transport-thread operations

    private func execute(
        _ request: OperationRequest,
        context: OperationContext
    ) throws -> HuaweiNoiseState {
        if let runOperation = hooks.runOperation {
            return try runOperation(request, context)
        }
        switch request {
        case .state(let address):
            return try readState(address: address, context: context)
        case .setMode(let mode, let address):
            return try writeMode(mode, address: address, context: context)
        }
    }

    private func readState(
        address: String,
        context: OperationContext
    ) throws -> HuaweiNoiseState {
        do {
            try context.checkpoint()
            let connection = try connection(for: address, context: context)
            let response = try exchange(
                connection,
                frame: HuaweiSPPFrame(
                    command: HuaweiSPPFrame.readANCCommand,
                    parameters: [1: [], 2: []]
                ),
                expecting: HuaweiSPPFrame.readANCCommand,
                context: context
            )
            try context.checkpoint()
            guard let value = response.parameters[1], value.count >= 2,
                  let state = HuaweiNoiseState(level: value[0], mode: value[1]) else {
                throw HuaweiListeningModeError.malformedResponse
            }
            return state
        } catch {
            discardConnection(for: address)
            throw error
        }
    }

    private func writeMode(
        _ mode: HuaweiNoiseMode,
        address: String,
        context: OperationContext
    ) throws -> HuaweiNoiseState {
        do {
            try context.checkpoint()
            let connection = try connection(for: address, context: context)
            let acknowledgement = try exchange(
                connection,
                frame: HuaweiSPPFrame(
                    command: HuaweiSPPFrame.writeANCCommand,
                    parameters: [1: mode.writePayload]
                ),
                expecting: HuaweiSPPFrame.writeANCCommand,
                context: context,
                timeout: 1.5
            )
            try context.checkpoint()
            if let status = acknowledgement.parameters[2]?.first, status != 0 {
                throw HuaweiListeningModeError.rejected(status)
            }
            return try readState(address: address, context: context)
        } catch HuaweiListeningModeError.timeout {
            // Some firmware applies the mode without an ACK. The read-back below
            // is the authority; a missing ACK alone is not a failed write.
            return try readState(address: address, context: context)
        } catch {
            discardConnection(for: address)
            throw error
        }
    }

    private func connection(
        for address: String,
        context: OperationContext
    ) throws -> Connection {
        try context.checkpoint()
        let key = BluetoothBatteryReader.normalizedAddress(address)
        guard !key.isEmpty else { throw HuaweiListeningModeError.deviceUnavailable }

        if let connection = connections[key],
           connection.sessionGeneration == context.sessionGeneration,
           connection.channel.isOpen() {
            return connection
        }
        if let stale = connections.removeValue(forKey: key) {
            close(stale)
        }

        try context.checkpoint()
        let devices = hooks.pairedDevices()
        guard let device = devices.first(where: {
            BluetoothBatteryReader.normalizedAddress($0.addressString ?? "") == key
        }) else {
            throw HuaweiListeningModeError.deviceUnavailable
        }

        var openedConnection = false
        if !device.isConnected() {
            try context.checkpoint()
            let status = device.openConnection()
            guard status == kIOReturnSuccess else {
                throw HuaweiListeningModeError.connectionFailed(status)
            }
            openedConnection = true
        }

        do {
            try context.checkpoint()
            if openedConnection {
                guard try waitUntil(
                    timeout: hooks.connectionReadyTimeout,
                    context: context,
                    { device.isConnected() }
                ) else {
                    throw HuaweiListeningModeError.timeout
                }
            }
            let sdpStatus = device.performSDPQuery()
            guard sdpStatus == kIOReturnSuccess else {
                throw HuaweiListeningModeError.sdpFailed(sdpStatus)
            }
            // `performSDPQuery` is asynchronous even though it returns a status. The
            // cached service list can already contain SPP, so waiting for the service
            // to appear is not enough; give the query a fixed window before opening,
            // the same sequence that works from PyObjC.
            try pump(hooks.sdpSettlingDuration, context: context)
            _ = try waitUntil(timeout: hooks.sdpServiceWaitTimeout, context: context) {
                self.sppChannel(for: device) != nil
            }
            // A resolved SDP record is authoritative. Without one, try the two channel
            // numbers the FreeBuds family uses (6i uses 1, 4i/5i use 16).
            let resolvedChannel = sppChannel(for: device)
            let candidates: [BluetoothRFCOMMChannelID] = resolvedChannel.map { [$0] } ?? [1, 16]

            var opened: (channel: any HuaweiRFCOMMChannel, delegate: Delegate)?
            var lastStatus: IOReturn = kIOReturnError
            for channelID in candidates {
                try context.checkpoint()
                let delegate = Delegate()
                let result = device.openRFCOMMChannel(
                    channelID: BluetoothRFCOMMChannelID(channelID),
                    delegate: delegate
                )
                lastStatus = result.status
                guard result.status == kIOReturnSuccess, let channel = result.channel else {
                    result.channel?.close()
                    continue
                }
                do {
                    _ = try waitUntil(timeout: hooks.channelOpenTimeout, context: context) {
                        delegate.openStatus != nil
                    }
                    if let openStatus = delegate.openStatus, openStatus != kIOReturnSuccess {
                        lastStatus = openStatus
                        channel.close()
                        continue
                    }
                    guard channel.isOpen() else {
                        lastStatus = kIOReturnNotOpen
                        channel.close()
                        continue
                    }
                    opened = (channel, delegate)
                    break
                } catch {
                    channel.close()
                    throw error
                }
            }
            guard let opened else {
                throw HuaweiListeningModeError.channelOpenFailed(lastStatus)
            }
            do {
                try context.checkpoint()
            } catch {
                opened.channel.close()
                throw error
            }
            let connection = Connection(
                device: device,
                channel: opened.channel,
                delegate: opened.delegate,
                sessionGeneration: context.sessionGeneration,
                openedConnection: openedConnection
            )
            connections[key] = connection
            return connection
        } catch {
            if openedConnection {
                _ = device.closeConnection()
            }
            throw error
        }
    }

    private func exchange(
        _ connection: Connection,
        frame: HuaweiSPPFrame,
        expecting command: [UInt8],
        context: OperationContext,
        timeout: TimeInterval = 3
    ) throws -> HuaweiSPPFrame {
        try context.checkpoint()
        guard connection.channel.isOpen() else { throw HuaweiListeningModeError.notOpen }
        connection.delegate.resetReplies()

        let packet = frame.encoded()
        let status = packet.withUnsafeBytes { bytes -> IOReturn in
            guard let baseAddress = bytes.baseAddress else { return kIOReturnError }
            return connection.channel.writeSync(
                UnsafeMutableRawPointer(mutating: baseAddress),
                length: UInt16(packet.count)
            )
        }
        guard status == kIOReturnSuccess else {
            throw HuaweiListeningModeError.writeFailed(status)
        }
        try context.checkpoint()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try context.checkpoint()
            if let response = connection.delegate.takeFrame(command: command) {
                return response
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        throw HuaweiListeningModeError.timeout
    }

    private func closeAllOnTransportThread(through generation: UInt64) {
        for connection in connections.values where connection.sessionGeneration <= generation {
            close(connection)
        }
        connections = connections.filter { $0.value.sessionGeneration > generation }
        hooks.didCloseSessions?(generation)
    }

    private func close(_ connection: Connection) {
        connection.channel.close()
        if connection.openedConnection {
            _ = connection.device.closeConnection()
        }
    }

    private func discardConnection(for address: String) {
        let key = BluetoothBatteryReader.normalizedAddress(address)
        if let connection = connections.removeValue(forKey: key) {
            close(connection)
        }
    }

    private func pump(
        _ duration: TimeInterval,
        context: OperationContext
    ) throws {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            try context.checkpoint()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func waitUntil(
        timeout: TimeInterval,
        context: OperationContext,
        _ condition: () -> Bool
    ) throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try context.checkpoint()
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    private func sppChannel(for device: any HuaweiBluetoothDevice) -> BluetoothRFCOMMChannelID? {
        device.serviceRFCOMMChannelID()
    }
}
