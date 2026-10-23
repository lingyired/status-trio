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

    func testWatchdogAndLateReadCannotReplacePendingDDCTarget() async {
        let row = AudioOutputDevice(id: 42, name: "XV272U", uid: "DISPLAY-A", isCurrent: true)
        let reader = FixedAudioStatusReader(reading: VolumeReading(
            scalar: nil, isMuted: false, deviceName: "XV272U", currentDevice: row,
            canSetVolume: false, canMute: false
        ), devices: [row])
        let transport = SlowFirstReadPresentationDDCTransport()
        let monitor = VolumeMonitor(statusReader: reader, eventMonitor: PresentationVolumeEvents(),
                                   ddcTransport: transport)
        let history = PendingDDCCommandHistory()
        let observer = Task { @MainActor in
            for await status in monitor.updates {
                history.receive(status)
            }
        }

        monitor.start()
        monitor.setVolume(0.4)
        await fulfillment(of: [history.optimisticTarget, history.confirmedReadback], timeout: 4)

        XCTAssertEqual(history.updatesDuringPending.map(\.scalar), [])
        XCTAssertTrue(history.confirmedReadbackStatus?.canSetVolume == true)
        monitor.stop()
        observer.cancel()
    }

    func testTopologyChangeClearsConfirmedDDCVolumeAndSelectedRowImmediately() async {
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
        let confirmed = await iterator.next()
        XCTAssertEqual(confirmed?.scalar, 0.75)

        monitor.setVolume(0.4)
        let pending = await iterator.next()
        XCTAssertEqual(pending?.scalar, 0.4)
        XCTAssertTrue(pending?.canSetVolume == true)

        monitor.topologyChanged()
        let invalidated = await iterator.next()

        XCTAssertNil(invalidated?.scalar)
        XCTAssertNil(invalidated?.currentDevice?.volume)
        XCTAssertFalse(invalidated?.canSetVolume == true)
        XCTAssertNil(invalidated?.outputDevices.first(where: { $0.isCurrent })?.volume)
        monitor.stop()
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
               onVolumeChange: @escaping @MainActor @Sendable () -> Void) {}
    func reconcile() {}
    func recover() {}
    func stop() {}
}

private final class PresentationDDCTransport: DDCVolumeTransport {
    func resolve(uid: String) -> DDCDisplayTarget? { DDCDisplayTarget(uid: uid, service: nil) }
    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult { .reply(DDCVolumeReply(current: 75, maximum: 100)) }
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

private final class FailingWritePresentationDDCTransport: DDCVolumeTransport {
    func resolve(uid: String) -> DDCDisplayTarget? { DDCDisplayTarget(uid: uid, service: nil) }
    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult { .reply(DDCVolumeReply(current: 75, maximum: 100)) }
    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool { false }
}

private final class SlowFirstReadPresentationDDCTransport: DDCVolumeTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var readCount = 0
    private var currentValue: UInt16 = 75

    func resolve(uid: String) -> DDCDisplayTarget? { DDCDisplayTarget(uid: uid, service: nil) }

    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult {
        lock.lock()
        readCount += 1
        let isFirstRead = readCount == 1
        let initialValue = currentValue
        lock.unlock()

        if isFirstRead { Thread.sleep(forTimeInterval: 2.2) }
        return .reply(DDCVolumeReply(current: isFirstRead ? initialValue : currentValueSnapshot(), maximum: 100))
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
