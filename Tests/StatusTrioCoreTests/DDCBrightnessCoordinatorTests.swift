import XCTest
@testable import StatusTrioCore

/// Behavioural tests for the VCP `0x10` brightness backend using a mock
/// transport. No IOAVService / I2C hardware is touched, so the real on-device
/// effect stays NOT RUN; these cover resolve → read → write → read-back, fail
/// closed, generation and watchdog.
@MainActor
final class DDCBrightnessCoordinatorTests: XCTestCase {
    func testSelectionReadsBrightnessAndEmitsScalar() async {
        let transport = FakeBrightnessTransport()
        transport.enqueue(DDCVolumeReply(current: 40, maximum: 100))
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(transport: transport) { updates.append($0) }

        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("initial brightness read") { updates.contains { $0.scalar == 0.4 } }

        let update = try? XCTUnwrap(updates.last)
        XCTAssertEqual(update?.displayID, "DISPLAY-A")
        XCTAssertEqual(update?.source, .directDDC)
        XCTAssertEqual(update?.canAdjust, true)
        XCTAssertEqual(update?.generation, coordinator.generation)
        XCTAssertEqual(transport.readFeatures, [DDCPacket.brightnessVCP])
        coordinator.stop()
    }

    func testWriteReadsBackAndConfirmsOnExactMatch() async {
        let transport = FakeBrightnessTransport()
        transport.enqueue(DDCVolumeReply(current: 30, maximum: 100)) // initial read
        transport.enqueue(DDCVolumeReply(current: 70, maximum: 100)) // read-back
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(
            transport: transport,
            debounce: .milliseconds(10),
            pollInterval: .seconds(600)
        ) { updates.append($0) }

        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("initial read") { updates.contains { $0.scalar == 0.3 } }

        let commandID = coordinator.setBrightness(0.7)
        await waitUntil("confirmed write update") {
            updates.contains { $0.commandID == commandID && $0.scalar == 0.7 }
        }

        XCTAssertEqual(transport.writeCalls.map(\.value), [70])
        XCTAssertEqual(transport.writeCalls.map(\.feature), [DDCPacket.brightnessVCP])
        XCTAssertEqual(updates.last?.source, .directDDC, "A verified read-back is a success")
        coordinator.stop()
    }

    func testWriteReadBackMismatchFailsClosed() async {
        let transport = FakeBrightnessTransport()
        transport.enqueue(DDCVolumeReply(current: 30, maximum: 100)) // initial read
        transport.enqueue(DDCVolumeReply(current: 30, maximum: 100)) // read-back did NOT move
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(
            transport: transport,
            debounce: .milliseconds(10),
            pollInterval: .seconds(600)
        ) { updates.append($0) }

        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("initial read") { updates.contains { $0.scalar == 0.3 } }

        let commandID = coordinator.setBrightness(0.7)
        await waitUntil("mismatched read-back update") {
            updates.contains { $0.commandID == commandID }
        }

        let update = try? XCTUnwrap(updates.last { $0.commandID == commandID })
        XCTAssertNil(update?.scalar, "A failed confirmation must not publish an optimistic value")
        XCTAssertEqual(update?.source, .unavailable(.writeNotConfirmed))
        XCTAssertEqual(update?.canAdjust, false,
                       "An unconfirmed write must not keep the slider enabled while the error text is hidden")
        coordinator.stop()
    }

    func testReadFailureMapsRefusedVCPToUnsupportedReason() async {
        let transport = FakeBrightnessTransport()
        transport.failNextReads(1, with: .replyRejected(.vcpRefused))
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(
            transport: transport,
            pollInterval: .seconds(600)
        ) { updates.append($0) }

        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("unavailable update") { updates.contains { $0.source == .unavailable(.unsupportedVCP) } }

        XCTAssertEqual(updates.last?.scalar, nil)
        XCTAssertEqual(updates.last?.canAdjust, false)
        coordinator.stop()
    }

    func testResolveFailureIsFailClosedWithNoWrite() async {
        let transport = FakeBrightnessTransport()
        transport.resolveSucceeds = false
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(
            transport: transport,
            debounce: .milliseconds(10),
            pollInterval: .seconds(600)
        ) { updates.append($0) }

        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("resolve failure update") { updates.contains { $0.source == .unavailable(.resolveFailed) } }

        coordinator.setBrightness(0.5)
        coordinator.flushPendingBrightness()
        await coordinator.waitForWorkerIdle()
        XCTAssertTrue(transport.writeCalls.isEmpty, "An unresolved display must never be written")
        coordinator.stop()
    }

    func testStalledReadWatchdogEmitsTimeout() async {
        let transport = FakeBrightnessTransport()
        let box = TimeoutBox()
        let coordinator = DDCBrightnessCoordinator(
            transport: transport,
            readWatchdog: .milliseconds(40),
            pollInterval: .seconds(600),
            onWatchdogTimeout: { _, _ in box.fired = true }
        ) { updates in box.updates.append(updates) }

        transport.blockNextRead()
        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("read enters blocking state") { transport.hasBlockedRead }
        await waitUntil("watchdog timeout update") {
            box.updates.contains { $0.source == .unavailable(.timeout) }
        }
        XCTAssertTrue(box.fired, "Watchdog handler must fire once")

        transport.releaseBlockedRead()
        await coordinator.waitForWorkerIdle()
        coordinator.stop()
    }

    func testTopologyChangeBumpsGenerationAndRepublishes() async {
        let transport = FakeBrightnessTransport()
        transport.enqueue(DDCVolumeReply(current: 20, maximum: 100))
        transport.enqueue(DDCVolumeReply(current: 60, maximum: 100))
        var updates: [DDCBrightnessUpdate] = []
        let coordinator = DDCBrightnessCoordinator(
            transport: transport,
            pollInterval: .seconds(600)
        ) { updates.append($0) }

        coordinator.select(displayID: "DISPLAY-A")
        await waitUntil("initial read") { updates.contains { $0.scalar == 0.2 } }
        let firstGeneration = coordinator.generation

        coordinator.topologyChanged()
        await waitUntil("post-topology read") { updates.contains { $0.scalar == 0.6 } }

        XCTAssertGreaterThan(coordinator.generation, firstGeneration)
        XCTAssertEqual(updates.last?.generation, coordinator.generation)
        coordinator.stop()
    }

    // MARK: - Helpers

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(5),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for \(description)", file: file, line: line)
    }
}

@MainActor
private final class TimeoutBox {
    var fired = false
    var updates: [DDCBrightnessUpdate] = []
}

/// Mock DDC transport. It only models resolve / read / write; there is no I2C.
private final class FakeBrightnessTransport: DDCFeatureTransport, @unchecked Sendable {
    private struct WriteCall {
        let value: UInt16
        let feature: UInt8
    }

    private let lock = NSLock()
    private var replyQueue: [DDCVolumeReply] = []
    private var pendingReadFailures: [DDCReadFailure] = []
    private var storedReadFeatures: [UInt8] = []
    private var storedWriteCalls: [WriteCall] = []
    private var storedResolveCount = 0
    private var storedResolveSucceeds = true
    private var storedWriteAcknowledged = true
    private var blockNextReadFlag = false
    private var blockedReadEntered = false
    private let blockedReadSemaphore = DispatchSemaphore(value: 0)

    var resolveSucceeds: Bool {
        get { lock.withLock { storedResolveSucceeds } }
        set { lock.withLock { storedResolveSucceeds = newValue } }
    }
    var readFeatures: [UInt8] { lock.withLock { storedReadFeatures } }
    var writeCalls: [(value: UInt16, feature: UInt8)] {
        lock.withLock { storedWriteCalls.map { ($0.value, $0.feature) } }
    }
    var resolveCount: Int { lock.withLock { storedResolveCount } }
    var hasBlockedRead: Bool { lock.withLock { blockedReadEntered } }

    func enqueue(_ reply: DDCVolumeReply) {
        lock.withLock { replyQueue.append(reply) }
    }

    func failNextReads(_ count: Int, with failure: DDCReadFailure) {
        lock.withLock {
            for _ in 0..<count { pendingReadFailures.append(failure) }
        }
    }

    func blockNextRead() {
        lock.withLock { blockNextReadFlag = true }
    }

    func releaseBlockedRead() {
        blockedReadSemaphore.signal()
    }

    // MARK: DDCVolumeTransport

    func resolve(uid: String) -> DDCDisplayTarget? {
        lock.withLock { storedResolveCount += 1; return storedResolveSucceeds ? DDCDisplayTarget(uid: uid, service: nil) : nil }
    }

    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult {
        read(target, feature: DDCPacket.volumeVCP)
    }

    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool {
        write(target, value: value, feature: DDCPacket.volumeVCP)
    }

    // MARK: DDCFeatureTransport

    func read(_ target: DDCDisplayTarget, feature: UInt8) -> DDCVolumeReadResult {
        let shouldBlock: Bool = lock.withLock {
            let flag = blockNextReadFlag
            if flag { blockNextReadFlag = false; blockedReadEntered = true }
            return flag
        }
        if shouldBlock { blockedReadSemaphore.wait() }

        return lock.withLock {
            storedReadFeatures.append(feature)
            if !pendingReadFailures.isEmpty {
                return .failure(pendingReadFailures.removeFirst())
            }
            guard !replyQueue.isEmpty else { return .failure(.replyReadFailed) }
            return .reply(replyQueue.removeFirst())
        }
    }

    func write(_ target: DDCDisplayTarget, value: UInt16, feature: UInt8) -> Bool {
        lock.withLock {
            storedWriteCalls.append(WriteCall(value: value, feature: feature))
            return storedWriteAcknowledged
        }
    }
}
