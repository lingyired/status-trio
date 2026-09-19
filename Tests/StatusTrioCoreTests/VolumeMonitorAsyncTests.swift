import CoreAudio
import XCTest
@testable import StatusTrioCore

@MainActor
final class VolumeMonitorAsyncTests: XCTestCase {
    func testRefreshBurstRetainsOneFollowUpAndUpgradesToDeviceEnumeration() async {
        let reader = DeferredAudioStatusReader()
        let events = AsyncVolumeEvents()
        let monitor = makeMonitor(reader: reader, events: events)
        monitor.setDetailsVisible(false)
        monitor.start()
        monitor.setDetailsVisible(true)
        for _ in 0..<100 { monitor.refresh() }
        XCTAssertEqual(reader.requests, [false])
        XCTAssertEqual(events.reconcileCount, 1, "The first read reconciles listener registration")

        // The visibility change invalidated the in-flight read. This test pins the
        // coalescing and the enumeration upgrade; the stale-reading discard itself
        // is guarded by the tests below that stop before the follow-up completes.
        reader.complete(reading(scalar: 0.2))
        XCTAssertEqual(reader.requests, [false, true])
        XCTAssertEqual(
            events.reconcileCount, 2,
            "The coalesced follow-up must still reconcile listeners, not only the first read"
        )
        reader.complete(reading(scalar: 0.7, devices: [device]))
        monitor.stop()

        var iterator = monitor.updates.makeAsyncIterator()
        let status = await iterator.next()
        let end = await iterator.next()
        XCTAssertEqual(status?.scalar, 0.7)
        XCTAssertEqual(status?.outputDevices, [device])
        XCTAssertNil(end)
        XCTAssertEqual(reader.requests, [false, true])
    }

    func testOrdinaryRefreshBurstPublishesBothCompletedReadings() async {
        // `refresh()` passes `detailsVisible`, which defaults to true, so this
        // burst enumerates devices and is not a level-only refresh.
        let reader = DeferredAudioStatusReader()
        let monitor = makeMonitor(reader: reader)
        monitor.start()
        for _ in 0..<100 { monitor.refresh() }
        XCTAssertEqual(reader.requests, [true])

        reader.complete(reading(scalar: 0.2, devices: [device]))
        var iterator = monitor.updates.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first?.scalar, 0.2)
        XCTAssertEqual(reader.requests, [true, true])

        reader.complete(reading(scalar: 0.7, devices: [device]))
        let second = await iterator.next()
        XCTAssertEqual(second?.scalar, 0.7)
        XCTAssertEqual(reader.requests, [true, true])
        monitor.stop()
    }

    func testStopDiscardsOutstandingReadAndPendingRefresh() async {
        let reader = DeferredAudioStatusReader()
        let monitor = makeMonitor(reader: reader)
        monitor.start()
        monitor.refresh()
        monitor.stop()
        reader.complete(reading(scalar: 0.2, devices: [device]))

        var iterator = monitor.updates.makeAsyncIterator()
        let end = await iterator.next()
        XCTAssertNil(end)
        XCTAssertEqual(reader.requests, [true])
    }

    func testOutstandingReadDoesNotRetainMonitor() async {
        let reader = DeferredAudioStatusReader()
        let events = AsyncVolumeEvents()
        var monitor: VolumeMonitor? = makeMonitor(reader: reader, events: events)
        weak var weakMonitor = monitor
        let updates = monitor!.updates
        monitor?.start()
        monitor = nil

        XCTAssertNil(weakMonitor)
        XCTAssertEqual(events.stopCount, 1)
        reader.complete(reading(scalar: 0.2, devices: [device]))
        var iterator = updates.makeAsyncIterator()
        let end = await iterator.next()
        XCTAssertNil(end)
    }

    func testCloseDuringReadCannotRepopulateDeviceListAndReopenFetchesFreshDevices() async {
        let reader = DeferredAudioStatusReader()
        let monitor = makeMonitor(reader: reader)
        monitor.start()
        monitor.setDetailsVisible(false)
        reader.complete(reading(scalar: 0.2, devices: [device]))
        XCTAssertEqual(reader.requests, [true, false])
        reader.complete(reading(scalar: 0.4))

        var iterator = monitor.updates.makeAsyncIterator()
        let hidden = await iterator.next()
        XCTAssertEqual(hidden?.scalar, 0.4)
        XCTAssertEqual(hidden?.outputDevices, [])
        XCTAssertEqual(hidden?.currentDevice, device, "Current device metadata remains available for icons")

        let newDevice = AudioOutputDevice(id: 84, name: "USB", isCurrent: true)
        monitor.setDetailsVisible(true)
        monitor.refresh()
        XCTAssertEqual(reader.requests, [true, false, true])
        reader.complete(reading(scalar: 0.6, devices: [newDevice]))
        let reopened = await iterator.next()
        XCTAssertEqual(reopened?.outputDevices, [newDevice])
        monitor.stop()
    }

    func testCloseThenReopenWhileReadIsOutstandingDiscardsObsoleteEnumeration() async {
        let reader = DeferredAudioStatusReader()
        let monitor = makeMonitor(reader: reader)
        monitor.start()
        monitor.setDetailsVisible(false)
        monitor.setDetailsVisible(true)
        monitor.refresh()
        reader.complete(reading(scalar: 0.2, devices: [device]))
        XCTAssertEqual(reader.requests, [true, true])
        monitor.stop()

        var iterator = monitor.updates.makeAsyncIterator()
        let end = await iterator.next()
        XCTAssertNil(end, "The enumeration started before close must not seed the reopened list")
    }

    func testRecoveryDiscardsOutstandingReadAndRequestsFreshDevices() async {
        let reader = DeferredAudioStatusReader()
        let events = AsyncVolumeEvents()
        let monitor = makeMonitor(reader: reader, events: events)
        monitor.start()
        monitor.recover()
        reader.complete(reading(scalar: 0.2, devices: [device]))
        XCTAssertEqual(events.recoverCount, 1)
        XCTAssertEqual(reader.requests, [true, true])
        monitor.stop()

        var iterator = monitor.updates.makeAsyncIterator()
        let end = await iterator.next()
        XCTAssertNil(end, "The result from before recovery must not be published")
    }

    func testDefaultDeviceChangeAcrossCloseAndReopenKeepsOneFreshEnumeration() async {
        let reader = DeferredAudioStatusReader()
        let events = AsyncVolumeEvents()
        let sleeper = ManualEventSleeper()
        let monitor = makeMonitor(reader: reader, events: events, sleeper: sleeper)
        monitor.start()
        events.defaultDeviceChanged?()
        let debounceStarted = await sleeper.waitForCallCount(1, timeout: .seconds(5))
        XCTAssertTrue(debounceStarted, "The device change must schedule a debounced refresh")
        monitor.setDetailsVisible(false)
        monitor.setDetailsVisible(true)
        monitor.refresh()
        reader.complete(reading(scalar: 0.2, devices: [device]))
        XCTAssertEqual(reader.requests, [true])

        let followUp = expectation(description: "fresh enumeration starts")
        reader.onRead = { followUp.fulfill() }
        sleeper.releaseAll()
        await fulfillment(of: [followUp], timeout: 5)
        reader.onRead = nil
        XCTAssertEqual(reader.requests, [true, true])
        monitor.stop()
        var iterator = monitor.updates.makeAsyncIterator()
        let end = await iterator.next()
        XCTAssertNil(end, "No result from before the device and visibility changes is published")
    }

    func testCommandsDiscardOlderReadAndDebounceOwnsSingleFollowUp() async {
        for command in AudioCommand.allCases {
            let reader = DeferredAudioStatusReader()
            let controller = RecordingAudioCommands()
            let sleeper = ManualEventSleeper()
            let monitor = makeMonitor(reader: reader, controller: controller, sleeper: sleeper)
            monitor.start()
            switch command {
            case .setVolume: monitor.setVolume(0.8)
            case .toggleMute: monitor.toggleMute()
            case .selectDevice: monitor.selectOutputDevice(84)
            }
            let debounceStarted = await sleeper.waitForCallCount(1, timeout: .seconds(5))
            XCTAssertTrue(debounceStarted, "The command must schedule a debounced refresh")
            reader.complete(reading(scalar: 0.2, devices: [device]))
            XCTAssertEqual(reader.requests, [true], "The debounce timer owns the follow-up")
            XCTAssertEqual(controller.commands, [command])

            let followUp = expectation(description: "command follow-up starts")
            reader.onRead = { followUp.fulfill() }
            sleeper.releaseAll()
            await fulfillment(of: [followUp], timeout: 5)
            reader.onRead = nil
            XCTAssertEqual(reader.requests, [true, true])
            monitor.stop()
            reader.complete(reading(scalar: 0.8, devices: [device]))
            var iterator = monitor.updates.makeAsyncIterator()
            let end = await iterator.next()
            XCTAssertNil(end, "A read from before the command must never be published")
        }
    }

    func testPendingEnumerationUpgradeSurvivesADebouncedLevelRefresh() async {
        let reader = DeferredAudioStatusReader()
        let events = AsyncVolumeEvents()
        let sleeper = ManualEventSleeper()
        let monitor = makeMonitor(reader: reader, events: events, sleeper: sleeper)
        monitor.start()
        reader.complete(reading(scalar: 0.2, devices: [device]))
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        events.volumeChanged?()
        let levelDebounce = await sleeper.waitForCallCount(1, timeout: .seconds(5))
        XCTAssertTrue(levelDebounce, "The level event must schedule a debounced refresh")
        let levelRead = expectation(description: "level read starts")
        reader.onRead = { levelRead.fulfill() }
        sleeper.releaseAll()
        await fulfillment(of: [levelRead], timeout: 5)
        reader.onRead = nil
        XCTAssertEqual(reader.requests, [true, false], "Level updates reuse the cached list")

        events.volumeChanged?()
        let upgradeDebounce = await sleeper.waitForCallCount(2, timeout: .seconds(5))
        XCTAssertTrue(upgradeDebounce, "The second level event must schedule a debounced refresh")
        monitor.refresh()
        XCTAssertEqual(reader.requests, [true, false])
        // The second volume event bumped the read generation, so the level read
        // that was already in flight is discarded. `bufferingNewest(1)` would hide
        // a wrongly published value behind the final 0.8, so the discard itself is
        // guarded by the tests that stop before the follow-up completes; this test
        // pins the pending enumeration upgrade the debounce timer must carry over.
        reader.complete(reading(scalar: 0.3))
        XCTAssertEqual(reader.requests, [true, false], "The debounce timer owns the follow-up")
        let enumeration = expectation(description: "upgraded enumeration starts")
        reader.onRead = { enumeration.fulfill() }
        sleeper.releaseAll()
        await fulfillment(of: [enumeration], timeout: 5)
        reader.onRead = nil
        XCTAssertEqual(reader.requests, [true, false, true])
        reader.complete(reading(scalar: 0.8, devices: [device]))
        let updated = await iterator.next()
        XCTAssertEqual(updated?.scalar, 0.8)
        XCTAssertEqual(updated?.outputDevices, [device])
        XCTAssertEqual(reader.requests, [true, false, true])
        monitor.stop()
    }

    func testAStuckReadIsAbandonedAndTheNextAttemptPublishes() async {
        let reader = DeferredAudioStatusReader()
        let timeoutSleeper = ManualEventSleeper()
        let monitor = makeMonitor(reader: reader, timeoutSleeper: timeoutSleeper)
        monitor.start()
        XCTAssertEqual(reader.requests, [true])

        // The first read never returns. The watchdog must abandon it and retry,
        // otherwise the monitor stays latched and never publishes again.
        let retry = expectation(description: "retry read starts")
        reader.onRead = { retry.fulfill() }
        let watchdogArmed = await timeoutSleeper.waitForCallCount(1, timeout: .seconds(5))
        XCTAssertTrue(watchdogArmed, "The monitor must arm the read watchdog")
        timeoutSleeper.releaseAll()
        await fulfillment(of: [retry], timeout: 5)
        reader.onRead = nil
        XCTAssertEqual(reader.requests, [true, true], "A stuck read must be retried")

        reader.completeNewest(reading(scalar: 0.42))
        var iterator = monitor.updates.makeAsyncIterator()
        let status = await iterator.next()
        XCTAssertEqual(status?.scalar, 0.42, "The retry must publish after the stuck read was abandoned")
        monitor.stop()
    }

    func testLateCompletionFromAnAbandonedReadDoesNotReleaseTheNewReadLatch() async {
        let reader = DeferredAudioStatusReader()
        let timeoutSleeper = ManualEventSleeper()
        let monitor = makeMonitor(reader: reader, timeoutSleeper: timeoutSleeper)
        monitor.start()
        XCTAssertEqual(reader.requests, [true])

        let retry = expectation(description: "retry read starts")
        reader.onRead = { retry.fulfill() }
        let watchdogArmed = await timeoutSleeper.waitForCallCount(1, timeout: .seconds(5))
        XCTAssertTrue(watchdogArmed, "The monitor must arm the read watchdog")
        timeoutSleeper.releaseAll()
        await fulfillment(of: [retry], timeout: 5)
        reader.onRead = nil
        XCTAssertEqual(reader.requests, [true, true])

        // The abandoned read finally returns while the retry is still outstanding.
        reader.complete(reading(scalar: 0.2))

        // A refresh must not start a third read: one read is still in flight.
        monitor.refresh()
        XCTAssertEqual(
            reader.requests, [true, true],
            "A late completion from an abandoned read must not release the newer read's latch"
        )

        reader.completeNewest(reading(scalar: 0.7))
        var iterator = monitor.updates.makeAsyncIterator()
        let status = await iterator.next()
        XCTAssertEqual(status?.scalar, 0.7)
        monitor.stop()
    }

    private var device: AudioOutputDevice {
        AudioOutputDevice(id: 42, name: "AirPods Pro", uid: "airpods", isCurrent: true, transport: .bluetooth)
    }

    private func reading(scalar: Double, devices: [AudioOutputDevice]? = nil) -> AudioStatusReading {
        AudioStatusReading(
            volume: VolumeReading(scalar: scalar, isMuted: false, deviceName: device.name, currentDevice: device),
            outputDevices: devices
        )
    }

    private func makeMonitor(
        reader: DeferredAudioStatusReader,
        events: AsyncVolumeEvents = AsyncVolumeEvents(),
        controller: RecordingAudioCommands? = nil,
        sleeper: ManualEventSleeper = ManualEventSleeper(),
        timeoutSleeper: ManualEventSleeper = ManualEventSleeper(),
        readTimeout: Duration = .seconds(5)
    ) -> VolumeMonitor {
        VolumeMonitor(
            statusReader: reader,
            eventMonitor: events,
            outputController: controller,
            refreshDebounceSleep: { duration in await sleeper.sleep(duration) },
            readTimeout: readTimeout,
            readTimeoutSleep: { duration in await timeoutSleeper.sleep(duration) }
        )
    }
}

@MainActor
private final class DeferredAudioStatusReader: AudioStatusReadingProviding {
    private(set) var requests: [Bool] = []
    private var completions: [@MainActor @Sendable (AudioStatusReading) -> Void] = []
    var onRead: (() -> Void)?

    func read(
        includeOutputDevices: Bool,
        completion: @escaping @MainActor @Sendable (AudioStatusReading) -> Void
    ) {
        requests.append(includeOutputDevices)
        completions.append(completion)
        onRead?()
    }

    func complete(_ reading: AudioStatusReading) {
        guard !completions.isEmpty else {
            XCTFail("complete() called with no read in flight")
            return
        }
        completions.removeFirst()(reading)
    }

    /// Completes the newest outstanding read, leaving older ones pending. Used
    /// when an abandoned read is still outstanding next to its retry.
    func completeNewest(_ reading: AudioStatusReading) {
        guard let completion = completions.last else {
            XCTFail("completeNewest() called with no read in flight")
            return
        }
        completion(reading)
    }
}

@MainActor
private final class AsyncVolumeEvents: VolumeEventMonitoring {
    var defaultDeviceChanged: (@MainActor @Sendable () -> Void)?
    var volumeChanged: (@MainActor @Sendable () -> Void)?
    private(set) var stopCount = 0
    private(set) var reconcileCount = 0
    private(set) var recoverCount = 0

    func start(
        onDefaultDeviceChange: @escaping @MainActor @Sendable () -> Void,
        onVolumeChange: @escaping @MainActor @Sendable () -> Void
    ) {
        defaultDeviceChanged = onDefaultDeviceChange
        volumeChanged = onVolumeChange
    }

    func reconcile() { reconcileCount += 1 }
    func recover() { recoverCount += 1 }
    func stop() { stopCount += 1 }
}

private enum AudioCommand: CaseIterable { case setVolume, toggleMute, selectDevice }

@MainActor
private final class RecordingAudioCommands: AudioOutputControlling {
    private(set) var commands: [AudioCommand] = []
    func setVolume(_ scalar: Double) -> Bool {
        XCTAssertEqual(scalar, 0.8)
        commands.append(.setVolume)
        return true
    }
    func toggleMute() -> Bool {
        commands.append(.toggleMute)
        return true
    }
    func selectOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        XCTAssertEqual(deviceID, 84)
        commands.append(.selectDevice)
        return true
    }
}
