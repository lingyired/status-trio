import CoreAudio
import XCTest
@testable import StatusTrioCore

@MainActor
final class DDCVolumePresentationTests: XCTestCase {
    func testConfirmedDDCUpdateReplacesCoreAudioPlaceholderAndSelectedRowVolume() async {
        let row = AudioOutputDevice(id: 42, name: "XV272U", uid: "DISPLAY-A", isCurrent: true)
        let reader = FixedAudioStatusReader(reading: VolumeReading(
            scalar: nil, isMuted: false, deviceName: "XV272U", currentDevice: row,
            canSetVolume: false, canMute: false
        ), devices: [row])
        let monitor = VolumeMonitor(statusReader: reader, eventMonitor: PresentationVolumeEvents(),
                                   ddcTransport: PresentationDDCTransport())
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()
        let status = await iterator.next()

        XCTAssertEqual(status?.scalar, 0.75)
        XCTAssertTrue(status?.canSetVolume == true)
        XCTAssertFalse(status?.canMute == true)
        XCTAssertFalse(status?.isMuted == true)
        XCTAssertEqual(status?.outputDevices.first(where: { $0.isCurrent })?.volume, 0.75)
        monitor.stop()
    }

    func testSameOutputCoreAudioRefreshPreservesConfirmedDDCVolumeAndRow() async {
        let row = AudioOutputDevice(id: 42, name: "XV272U", uid: "DISPLAY-A", isCurrent: true)
        let reader = MutableAudioStatusReader(reading: VolumeReading(
            scalar: nil, isMuted: false, deviceName: "XV272U", currentDevice: row,
            canSetVolume: false, canMute: false
        ), devices: [row])
        let monitor = VolumeMonitor(statusReader: reader, eventMonitor: PresentationVolumeEvents(),
                                   ddcTransport: PresentationDDCTransport())
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()
        let confirmed = await iterator.next()
        XCTAssertEqual(confirmed?.scalar, 0.75)

        monitor.refresh()
        let refreshed = await iterator.next()

        XCTAssertEqual(refreshed?.scalar, 0.75)
        XCTAssertTrue(refreshed?.canSetVolume == true)
        XCTAssertFalse(refreshed?.canMute == true)
        XCTAssertEqual(refreshed?.outputDevices.first(where: { $0.isCurrent })?.volume, 0.75)

        monitor.setVolume(0.6)
        let optimistic = await iterator.next()
        XCTAssertEqual(optimistic?.scalar, 0.6)
        XCTAssertEqual(optimistic?.outputDevices.first(where: { $0.isCurrent })?.volume, 0.6)

        monitor.flushPendingVolume()
        let writeReadback = await iterator.next()
        XCTAssertEqual(writeReadback?.scalar, 0.75)
        XCTAssertEqual(writeReadback?.outputDevices.first(where: { $0.isCurrent })?.volume, 0.75)
        monitor.stop()
    }

    func testSameOutputRefreshKeepsDDCMuteDisabledWhenCoreAudioReportsMute() async {
        let row = AudioOutputDevice(id: 42, name: "XV272U", uid: "DISPLAY-A", isCurrent: true)
        let reader = MutableAudioStatusReader(reading: VolumeReading(
            scalar: nil, isMuted: false, deviceName: "XV272U", currentDevice: row,
            canSetVolume: false, canMute: false
        ), devices: [row])
        let commands = MuteCommandRecorder()
        let monitor = VolumeMonitor(statusReader: reader, eventMonitor: PresentationVolumeEvents(),
                                   outputController: commands, ddcTransport: PresentationDDCTransport())
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()
        let confirmed = await iterator.next()
        XCTAssertEqual(confirmed?.scalar, 0.75)

        reader.reading = VolumeReading(scalar: nil, isMuted: true, deviceName: "XV272U",
                                       currentDevice: row, canSetVolume: true, canMute: true)
        monitor.refresh()
        let refreshed = await iterator.next()

        XCTAssertEqual(refreshed?.scalar, 0.75)
        XCTAssertFalse(refreshed?.isMuted == true)
        XCTAssertFalse(refreshed?.canMute == true)
        monitor.toggleMute()
        XCTAssertEqual(commands.muteCount, 0)
        monitor.stop()
    }

    func testReadableWritableCoreAudioScalarKeepsPriorityOverDDC() async {
        let row = AudioOutputDevice(id: 42, name: "Speakers", uid: "DISPLAY-A", isCurrent: true, volume: 0.5)
        let reader = FixedAudioStatusReader(reading: VolumeReading(
            scalar: 0.5, isMuted: false, deviceName: "Speakers", currentDevice: row,
            canSetVolume: true, canMute: true
        ), devices: [row])
        let transport = TrackingPresentationDDCTransport()
        let monitor = VolumeMonitor(statusReader: reader, eventMonitor: PresentationVolumeEvents(),
                                   ddcTransport: transport)
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        let status = await iterator.next()

        XCTAssertEqual(status?.scalar, 0.5)
        XCTAssertEqual(transport.readCount, 0)
        monitor.stop()
    }

    func testReadableButUnsettableScalarFallsBackToDDC() async {
        let row = AudioOutputDevice(id: 42, name: "XV272U", uid: "DISPLAY-A", isCurrent: true)
        let reader = FixedAudioStatusReader(reading: VolumeReading(
            scalar: nil, isMuted: false, deviceName: "XV272U", currentDevice: row,
            canSetVolume: true, canMute: true
        ), devices: [row])
        let monitor = VolumeMonitor(statusReader: reader, eventMonitor: PresentationVolumeEvents(),
                                   ddcTransport: PresentationDDCTransport())
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()
        let status = await iterator.next()

        XCTAssertEqual(status?.scalar, 0.75)
        XCTAssertTrue(status?.canSetVolume == true)
        XCTAssertFalse(status?.canMute == true)
        monitor.stop()
    }

    func testDeviceDisappearanceCancelsPendingDDCWrite() async throws {
        let row = AudioOutputDevice(id: 42, name: "XV272U", uid: "DISPLAY-A", isCurrent: true)
        let reader = MutableAudioStatusReader(reading: VolumeReading(
            scalar: nil, isMuted: false, deviceName: "XV272U", currentDevice: row,
            canSetVolume: false, canMute: false
        ), devices: [row])
        let transport = TrackingPresentationDDCTransport()
        let monitor = VolumeMonitor(statusReader: reader, eventMonitor: PresentationVolumeEvents(),
                                   ddcTransport: transport)
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()
        _ = await iterator.next()
        monitor.setVolume(0.5)
        reader.reading = nil
        monitor.refresh()
        let disappeared = await iterator.next()
        try await Task.sleep(for: .milliseconds(250))

        XCTAssertNil(disappeared?.scalar)
        XCTAssertEqual(transport.writeCount, 0)
        monitor.stop()
    }

    func testFailedDDCWriteClearsPendingVolumeAndDisablesSlider() async {
        let row = AudioOutputDevice(id: 42, name: "XV272U", uid: "DISPLAY-A", isCurrent: true)
        let reader = FixedAudioStatusReader(reading: VolumeReading(
            scalar: nil, isMuted: false, deviceName: "XV272U", currentDevice: row,
            canSetVolume: false, canMute: false
        ), devices: [row])
        let monitor = VolumeMonitor(statusReader: reader, eventMonitor: PresentationVolumeEvents(),
                                   ddcTransport: FailingWritePresentationDDCTransport())
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()
        let confirmed = await iterator.next()
        XCTAssertEqual(confirmed?.scalar, 0.75)

        monitor.setVolume(0.4)
        let optimistic = await iterator.next()
        XCTAssertEqual(optimistic?.scalar, 0.4)
        XCTAssertTrue(optimistic?.canSetVolume == true)

        monitor.flushPendingVolume()
        let failed = await iterator.next()
        XCTAssertNil(failed?.scalar)
        XCTAssertFalse(failed?.canSetVolume == true)
        monitor.stop()
    }

    func testPendingDDCVolumeClearsOnSleepAndConfirmedVolumeReturnsAfterWake() async {
        let row = AudioOutputDevice(id: 42, name: "XV272U", uid: "DISPLAY-A", isCurrent: true)
        let reader = FixedAudioStatusReader(reading: VolumeReading(
            scalar: nil, isMuted: false, deviceName: "XV272U", currentDevice: row,
            canSetVolume: false, canMute: false
        ), devices: [row])
        let monitor = VolumeMonitor(statusReader: reader, eventMonitor: PresentationVolumeEvents(),
                                   ddcTransport: PresentationDDCTransport())
        let observation = PendingDDCVolumeObservation()
        let observer = Task { @MainActor in
            for await status in monitor.updates {
                observation.receive(status)
            }
        }

        monitor.start()
        await fulfillment(of: [observation.initialConfirmation], timeout: 1)
        monitor.setVolume(0.4)
        await fulfillment(of: [observation.optimisticTarget], timeout: 1)

        observation.expectSleep()
        monitor.setDisplayAsleep(true)
        await fulfillment(of: [observation.sleepClearsControl], timeout: 1)
        XCTAssertNil(observation.statusOnSleep?.scalar)
        XCTAssertFalse(observation.statusOnSleep?.canSetVolume == true)

        observation.expectWake()
        monitor.setDisplayAsleep(false)
        await fulfillment(of: [observation.wakeConfirmsVolume], timeout: 1)
        XCTAssertEqual(observation.statusAfterWake?.scalar, 0.75)
        XCTAssertTrue(observation.statusAfterWake?.canSetVolume == true)
        monitor.stop()
        observer.cancel()
    }

    func testProductionDDCReadWatchdogDefaultIsTwoSeconds() {
        XCTAssertEqual(VolumeMonitor.defaultDDCReadWatchdog, .seconds(2))
    }

    func testWatchdogAndLateReadCannotReplacePendingDDCTarget() async {
        let row = AudioOutputDevice(id: 42, name: "XV272U", uid: "DISPLAY-A", isCurrent: true)
        let reader = FixedAudioStatusReader(reading: VolumeReading(
            scalar: nil, isMuted: false, deviceName: "XV272U", currentDevice: row,
            canSetVolume: false, canMute: false
        ), devices: [row])
        let transport = GatedFirstReadPresentationDDCTransport()
        let watchdogGate = WatchdogSleepGate()
        let watchdogObservation = WatchdogTimeoutObservation()
        let monitor = VolumeMonitor(statusReader: reader, eventMonitor: PresentationVolumeEvents(),
                                   ddcTransport: transport, ddcReadWatchdog: .milliseconds(20),
                                   ddcWatchdogSleep: { try await watchdogGate.sleep($0) },
                                   onDDCWatchdogTimeout: { watchdogObservation.receive($0, $1) })
        let history = PendingDDCCommandHistory()
        let observer = Task { @MainActor in
            for await status in monitor.updates {
                history.receive(status)
            }
        }

        monitor.start()
        monitor.setVolume(0.4)
        await fulfillment(of: [
            history.optimisticTarget,
            transport.firstReadStarted,
            watchdogGate.sleepStarted
        ], timeout: 1)
        defer {
            transport.releaseFirstRead()
            watchdogGate.release()
        }

        watchdogGate.release()
        await fulfillment(of: [watchdogObservation.completed], timeout: 1)
        XCTAssertEqual(history.updatesDuringPending.map(\.scalar), [])
        XCTAssertEqual(transport.releaseSignalCount, 0, "The physical read must remain gated through the timeout")

        transport.releaseFirstRead()
        await fulfillment(of: [history.confirmedReadback], timeout: 1)

        XCTAssertEqual(history.updatesDuringPending.map(\.scalar), [])
        XCTAssertTrue(history.confirmedReadbackStatus?.canSetVolume == true)
        XCTAssertEqual(transport.gatedReadCount, 1)
        XCTAssertEqual(transport.releaseSignalCount, 1, "The first-read gate must be released exactly once")
        XCTAssertEqual(watchdogGate.releaseSignalCount, 1, "The watchdog gate must be released exactly once")
        XCTAssertEqual(watchdogObservation.count, 1)
        monitor.stop()
        observer.cancel()
    }

    func testTopologyChangeClearsConfirmedDDCVolumeAndSelectedRowImmediately() async {
        let row = AudioOutputDevice(id: 42, name: "XV272U", uid: "DISPLAY-A", isCurrent: true)
        let reader = FixedAudioStatusReader(reading: VolumeReading(
            scalar: nil, isMuted: false, deviceName: "XV272U", currentDevice: row,
            canSetVolume: false, canMute: false
        ), devices: [row])
        let transport = TopologyGatedPresentationDDCTransport()
        let monitor = VolumeMonitor(statusReader: reader, eventMonitor: PresentationVolumeEvents(),
                                   ddcTransport: transport)
        let observation = TopologyPresentationObservation()
        let observer = Task { @MainActor in
            for await status in monitor.updates {
                observation.receive(status)
            }
        }
        monitor.start()
        await fulfillment(of: [observation.confirmed], timeout: 1)
        XCTAssertEqual(observation.confirmedStatus?.scalar, 0.75)

        // The instant initial read can otherwise race the topology invalidation
        // into `bufferingNewest(1)`. Hold the later read so this test observes
        // the invalidation before a legitimate fresh confirmation.
        transport.blockNextRead()
        defer { transport.releaseBlockedRead() }
        monitor.setVolume(0.4)
        await fulfillment(of: [observation.pending], timeout: 1)
        XCTAssertEqual(observation.pendingStatus?.scalar, 0.4)
        XCTAssertTrue(observation.pendingStatus?.canSetVolume == true)

        monitor.topologyChanged()
        await fulfillment(of: [transport.blockedReadStarted], timeout: 1)
        await fulfillment(of: [observation.invalidated], timeout: 1)
        let invalidated = observation.invalidatedStatus

        XCTAssertEqual(observation.invalidationCount, 1)
        XCTAssertNil(invalidated?.scalar)
        XCTAssertNil(invalidated?.currentDevice?.volume)
        XCTAssertFalse(invalidated?.canSetVolume == true)
        XCTAssertNil(invalidated?.outputDevices.first(where: { $0.isCurrent })?.volume)

        transport.releaseBlockedRead()
        await fulfillment(of: [transport.blockedReadFinished], timeout: 1)
        await fulfillment(of: [observation.confirmedAgain], timeout: 1)
        XCTAssertEqual(observation.confirmedAgainStatus?.scalar, 0.75)
        XCTAssertTrue(observation.confirmedAgainStatus?.canSetVolume == true)
        monitor.stop()
        observer.cancel()
    }

    func testMuteCapabilityRemainsAvailableWithoutVolumeCapability() async {
        let volume = CapabilityFakeVolumeMonitor()
        let store = SystemStatusStore(
            batteryMonitor: CapabilityBatteryMonitor(), wifiMonitor: CapabilityWiFiMonitor(), volumeMonitor: volume
        )
        store.start()
        let status = VolumeStatus(scalar: nil, isMuted: false, deviceName: "Speakers",
                                  canSetVolume: false, canMute: true)
        volume.send(status)
        for _ in 0..<100 where store.liveVolume != status { await Task.yield() }

        XCTAssertTrue(store.isVolumeControllerAvailable)
        XCTAssertFalse(store.liveVolume.canSetVolume)
        XCTAssertTrue(store.liveVolume.canMute)
        store.stop()
    }

    func testDDCVolumeCanBePresentedWithoutMuteCapability() {
        let status = VolumeStatus(
            scalar: 0.75,
            isMuted: false,
            deviceName: "XV272U",
            canSetVolume: true,
            canMute: false
        )

        XCTAssertEqual(status.scalar, 0.75)
        XCTAssertTrue(status.canSetVolume)
        XCTAssertFalse(status.canMute)
        XCTAssertFalse(status.isMuted)
    }

    func testOutputDeviceCopyCanReplaceConfirmedVolume() {
        let device = AudioOutputDevice(id: 42, name: "XV272U", uid: "DISPLAY-A", isCurrent: true)
        let updated = device.replacingVolume(0.75)

        XCTAssertEqual(updated.volume, 0.75)
        XCTAssertEqual(updated.uid, "DISPLAY-A")
        XCTAssertTrue(updated.isCurrent)
    }

    func testZeroDDCScalarIsZeroPercentAndNotMuted() {
        let status = VolumeStatus(
            scalar: 0,
            isMuted: false,
            deviceName: "XV272U",
            canSetVolume: true,
            canMute: false
        )

        XCTAssertEqual(status.scalar, 0)
        XCTAssertFalse(status.isMuted)
        XCTAssertTrue(status.canSetVolume)
        XCTAssertFalse(status.canMute)
    }
}

@MainActor
private final class FixedAudioStatusReader: AudioStatusReadingProviding {
    private let reading: VolumeReading
    private let devices: [AudioOutputDevice]
    init(reading: VolumeReading, devices: [AudioOutputDevice]) { self.reading = reading; self.devices = devices }
    func read(includeOutputDevices: Bool, completion: @escaping @MainActor @Sendable (AudioStatusReading) -> Void) {
        completion(AudioStatusReading(volume: reading, outputDevices: includeOutputDevices ? devices : nil))
    }
}

@MainActor
private final class MutableAudioStatusReader: AudioStatusReadingProviding {
    var reading: VolumeReading?
    var devices: [AudioOutputDevice]
    init(reading: VolumeReading, devices: [AudioOutputDevice]) { self.reading = reading; self.devices = devices }
    func read(includeOutputDevices: Bool, completion: @escaping @MainActor @Sendable (AudioStatusReading) -> Void) {
        completion(AudioStatusReading(volume: reading, outputDevices: includeOutputDevices ? devices : nil))
    }
}

@MainActor
private final class CapabilityFakeVolumeMonitor: VolumeMonitoring, VolumeControlling {
    let updates: AsyncStream<VolumeStatus>
    private let continuation: AsyncStream<VolumeStatus>.Continuation
    private(set) var toggleMuteCount = 0
    init() { (updates, continuation) = MonitorStream.make(of: VolumeStatus.self) }
    func send(_ status: VolumeStatus) { continuation.yield(status) }
    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
    func setDetailsVisible(_ visible: Bool) {}
    func setDisplayAsleep(_ asleep: Bool) {}
    func topologyChanged() {}
    func setVolume(_ scalar: Double) {}
    func toggleMute() { toggleMuteCount += 1 }
    func selectOutputDevice(_ deviceID: AudioDeviceID) {}
}

@MainActor
private final class MuteCommandRecorder: AudioOutputControlling {
    private(set) var muteCount = 0
    func setVolume(_ scalar: Double) -> Bool { true }
    func toggleMute() -> Bool { muteCount += 1; return true }
    func selectOutputDevice(_ deviceID: AudioDeviceID) -> Bool { true }
}

@MainActor
private final class CapabilityBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    private let continuation: AsyncStream<BatteryStatus>.Continuation
    init() { (updates, continuation) = MonitorStream.make(of: BatteryStatus.self) }
    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
}

@MainActor
private final class CapabilityWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    private let continuation: AsyncStream<WiFiStatus>.Continuation
    init() { (updates, continuation) = MonitorStream.make(of: WiFiStatus.self) }
    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
    func setDetailsVisible(_ visible: Bool) {}
}

@MainActor
private final class PresentationVolumeEvents: VolumeEventMonitoring {
    func start(onDefaultDeviceChange: @escaping @MainActor @Sendable () -> Void,
               onVolumeChange: @escaping @MainActor @Sendable () -> Void,
               onDeviceListChange: @escaping @MainActor @Sendable () -> Void) {}
    func reconcile() {}
    func recover() {}
    func stop() {}
}

private final class PresentationDDCTransport: DDCVolumeTransport {
    func resolve(uid: String) -> DDCDisplayTarget? { DDCDisplayTarget(uid: uid, service: nil) }
    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult { .reply(DDCVolumeReply(current: 75, maximum: 100)) }
    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool { true }
}

private final class TopologyGatedPresentationDDCTransport: DDCVolumeTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let blockedRead = DispatchSemaphore(value: 0)
    private var gateNextRead = false
    private var didRelease = false
    let blockedReadStarted = XCTestExpectation(description: "topology DDC read starts")
    let blockedReadFinished = XCTestExpectation(description: "topology DDC read finishes")

    func blockNextRead() {
        lock.withLock { gateNextRead = true }
    }

    func releaseBlockedRead() {
        let shouldSignal = lock.withLock { () -> Bool in
            guard !didRelease else { return false }
            didRelease = true
            return true
        }
        if shouldSignal { blockedRead.signal() }
    }

    func resolve(uid: String) -> DDCDisplayTarget? { DDCDisplayTarget(uid: uid, service: nil) }

    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult {
        let shouldBlock = lock.withLock { () -> Bool in
            guard gateNextRead else { return false }
            gateNextRead = false
            return true
        }
        if shouldBlock {
            blockedReadStarted.fulfill()
            blockedRead.wait()
            blockedReadFinished.fulfill()
        }
        return .reply(DDCVolumeReply(current: 75, maximum: 100))
    }

    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool { true }
}

@MainActor
private final class PendingDDCVolumeObservation {
    let initialConfirmation = XCTestExpectation(description: "initial DDC volume is confirmed")
    let optimisticTarget = XCTestExpectation(description: "pending target is published")
    let sleepClearsControl = XCTestExpectation(description: "sleep clears pending volume")
    let wakeConfirmsVolume = XCTestExpectation(description: "wake reads DDC volume again")
    private var receivedInitialConfirmation = false
    private var didSleep = false
    private var didWake = false
    private(set) var statusOnSleep: VolumeStatus?
    private(set) var statusAfterWake: VolumeStatus?

    func expectSleep() { didSleep = true }
    func expectWake() { didWake = true }

    func receive(_ status: VolumeStatus) {
        if status.scalar == 0.75 {
            if !receivedInitialConfirmation {
                receivedInitialConfirmation = true
                initialConfirmation.fulfill()
            } else if didWake {
                statusAfterWake = status
                wakeConfirmsVolume.fulfill()
            }
        }
        if status.scalar == 0.4 { optimisticTarget.fulfill() }
        if didSleep, status.scalar == nil {
            statusOnSleep = status
            sleepClearsControl.fulfill()
        }
    }
}

@MainActor
private final class TopologyPresentationObservation {
    let confirmed = XCTestExpectation(description: "initial DDC volume is confirmed")
    let pending = XCTestExpectation(description: "optimistic DDC target is published")
    let invalidated = XCTestExpectation(description: "topology invalidation is published")
    let confirmedAgain = XCTestExpectation(description: "fresh DDC volume is confirmed")
    private var didConfirm = false
    private var didPend = false
    private var didInvalidate = false
    private(set) var confirmedStatus: VolumeStatus?
    private(set) var pendingStatus: VolumeStatus?
    private(set) var invalidatedStatus: VolumeStatus?
    private(set) var confirmedAgainStatus: VolumeStatus?
    private(set) var invalidationCount = 0

    func receive(_ status: VolumeStatus) {
        if status.scalar == 0.75, !didConfirm {
            didConfirm = true
            confirmedStatus = status
            confirmed.fulfill()
        } else if status.scalar == 0.4, !didPend {
            didPend = true
            pendingStatus = status
            pending.fulfill()
        } else if didConfirm, status.scalar == nil {
            invalidationCount += 1
            if !didInvalidate {
                didInvalidate = true
                invalidatedStatus = status
                invalidated.fulfill()
            }
        } else if didInvalidate, status.scalar == 0.75, confirmedAgainStatus == nil {
            confirmedAgainStatus = status
            confirmedAgain.fulfill()
        }
    }
}

@MainActor
private final class PendingDDCCommandHistory {
    let optimisticTarget = XCTestExpectation(description: "DDC target remains optimistic")
    let confirmedReadback = XCTestExpectation(description: "DDC write readback is confirmed")
    private var hasPendingTarget = false
    private var targetCount = 0
    private(set) var updatesDuringPending: [VolumeStatus] = []
    private(set) var confirmedReadbackStatus: VolumeStatus?

    func receive(_ status: VolumeStatus) {
        if hasPendingTarget, status.scalar != 0.4 {
            updatesDuringPending.append(status)
        }
        if status.scalar == 0.4 {
            targetCount += 1
            hasPendingTarget = true
            if targetCount == 1 {
                optimisticTarget.fulfill()
            } else {
                confirmedReadbackStatus = status
                confirmedReadback.fulfill()
                hasPendingTarget = false
            }
        }
    }
}

@MainActor
private final class WatchdogSleepGate {
    let sleepStarted = XCTestExpectation(description: "DDC watchdog sleep starts")
    private var continuation: CheckedContinuation<Void, any Error>?
    private var releaseRequested = false
    private var didGateFirstSleep = false
    private var releaseSignals = 0

    var releaseSignalCount: Int { releaseSignals }

    func sleep(_ duration: Duration) async throws {
        guard duration == .milliseconds(20) else {
            XCTFail("Unexpected watchdog duration: \(duration)")
            return
        }

        if didGateFirstSleep {
            try await waitForCancellation()
            return
        }

        didGateFirstSleep = true
        sleepStarted.fulfill()
        try await withTaskCancellationHandler(
            operation: { try await self.waitForRelease() },
            onCancel: {
                Task { @MainActor [weak self] in self?.cancel() }
            }
        )
    }

    func release() {
        guard releaseSignals == 0 else { return }
        releaseSignals = 1
        if let continuation {
            self.continuation = nil
            continuation.resume()
        } else {
            releaseRequested = true
        }
    }

    private func waitForCancellation() async throws {
        try await withTaskCancellationHandler(
            operation: { try await self.suspendUntilCancelled() },
            onCancel: {
                Task { @MainActor [weak self] in self?.cancel() }
            }
        )
    }

    private func waitForRelease() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            if Task.isCancelled {
                continuation.resume(throwing: CancellationError())
            } else if releaseRequested {
                releaseRequested = false
                continuation.resume()
            } else {
                self.continuation = continuation
            }
        }
    }

    private func suspendUntilCancelled() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            if Task.isCancelled {
                continuation.resume(throwing: CancellationError())
            } else {
                self.continuation = continuation
            }
        }
    }

    private func cancel() {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: CancellationError())
    }
}

@MainActor
private final class WatchdogTimeoutObservation {
    let completed = XCTestExpectation(description: "DDC watchdog timeout emit completes")
    private(set) var count = 0

    func receive(_ generation: UInt64, _ commandID: UInt64?) {
        _ = generation
        _ = commandID
        count += 1
        if count == 1 { completed.fulfill() }
    }
}

private final class FailingWritePresentationDDCTransport: DDCVolumeTransport {
    func resolve(uid: String) -> DDCDisplayTarget? { DDCDisplayTarget(uid: uid, service: nil) }
    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult { .reply(DDCVolumeReply(current: 75, maximum: 100)) }
    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool { false }
}

private final class GatedFirstReadPresentationDDCTransport: DDCVolumeTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let firstReadGate = DispatchSemaphore(value: 0)
    private var readCount = 0
    private var gatedReads = 0
    private var releaseSignals = 0
    private var currentValue: UInt16 = 75
    let firstReadStarted = XCTestExpectation(description: "first DDC read starts")

    var gatedReadCount: Int { lock.withLock { gatedReads } }
    var releaseSignalCount: Int { lock.withLock { releaseSignals } }

    func resolve(uid: String) -> DDCDisplayTarget? { DDCDisplayTarget(uid: uid, service: nil) }

    func releaseFirstRead() {
        let shouldSignal = lock.withLock { () -> Bool in
            guard releaseSignals == 0 else { return false }
            releaseSignals = 1
            return true
        }
        if shouldSignal { firstReadGate.signal() }
    }

    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult {
        let isFirstRead = lock.withLock { () -> Bool in
            readCount += 1
            guard readCount == 1 else { return false }
            gatedReads += 1
            return true
        }
        if isFirstRead {
            firstReadStarted.fulfill()
            firstReadGate.wait()
        }
        return .reply(DDCVolumeReply(current: currentValueSnapshot(), maximum: 100))
    }

    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool {
        lock.lock()
        currentValue = value
        lock.unlock()
        return true
    }

    private func currentValueSnapshot() -> UInt16 {
        lock.lock()
        defer { lock.unlock() }
        return currentValue
    }
}

private final class TrackingPresentationDDCTransport: DDCVolumeTransport {
    private let lock = NSLock()
    private var writes = 0
    private var reads = 0
    var writeCount: Int { lock.lock(); defer { lock.unlock() }; return writes }
    var readCount: Int { lock.lock(); defer { lock.unlock() }; return reads }
    func resolve(uid: String) -> DDCDisplayTarget? { DDCDisplayTarget(uid: uid, service: nil) }
    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult {
        lock.lock(); reads += 1; lock.unlock()
        return .reply(DDCVolumeReply(current: 75, maximum: 100))
    }
    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool {
        lock.lock(); writes += 1; lock.unlock()
        return true
    }
}
