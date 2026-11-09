import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class BatteryMonitorTests: XCTestCase {
    func testParserConvertsValidInternalBatteryDescription() {
        let description: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: 73,
            kIOPSMaxCapacityKey: 100,
            kIOPSIsChargingKey: true,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
            kIOPSIsPresentKey: true
        ]

        XCTAssertEqual(
            IOPSBatteryReader.parse(description),
            BatteryReading(
                currentCapacity: 73,
                maxCapacity: 100,
                isCharging: true,
                isConnectedToPower: true,
                isPresent: true
            )
        )
    }

    func testParserReadsChargedStateAndTimeToFullCharge() {
        let description: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: 68,
            kIOPSMaxCapacityKey: 100,
            kIOPSIsChargingKey: true,
            kIOPSIsChargedKey: false,
            kIOPSTimeToFullChargeKey: 85,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
            kIOPSIsPresentKey: true
        ]

        XCTAssertEqual(
            IOPSBatteryReader.parse(description),
            BatteryReading(
                currentCapacity: 68,
                maxCapacity: 100,
                isCharging: true,
                isCharged: false,
                timeToFullChargeMinutes: 85,
                isConnectedToPower: true,
                isPresent: true
            )
        )
    }

    func testParserTreatsMissingAndNonPositiveTimeToFullAsUnknown() {
        for time in [nil, 0, -1] as [Int?] {
            var description: [String: Any] = [
                kIOPSTypeKey: kIOPSInternalBatteryType,
                kIOPSCurrentCapacityKey: 68,
                kIOPSMaxCapacityKey: 100,
                kIOPSIsChargingKey: true,
                kIOPSIsChargedKey: false,
                kIOPSPowerSourceStateKey: kIOPSACPowerValue,
                kIOPSIsPresentKey: true
            ]
            description[kIOPSTimeToFullChargeKey] = time

            XCTAssertNil(IOPSBatteryReader.parse(description)?.timeToFullChargeMinutes)
        }
    }

    func testMonitorOnlyEmitsTimeWhileCharging() async {
        let reader = FakeBatteryReader(result: BatteryReading(
            currentCapacity: 68,
            maxCapacity: 100,
            isCharging: false,
            isCharged: true,
            timeToFullChargeMinutes: 85,
            isConnectedToPower: true,
            isPresent: true
        ))
        let monitor = BatteryMonitor(
            reader: reader,
            lowPowerModeProvider: { false }
        )

        monitor.refresh()
        var iterator = monitor.updates.makeAsyncIterator()
        let value = await iterator.next()

        XCTAssertTrue(value?.isCharged == true)
        XCTAssertNil(value?.timeToFullChargeMinutes)
        monitor.stop()
    }

    func testParserReadsPositiveTimeToEmptyAndRejectsUnknownEstimates() {
        for time in [nil, 0, -1, -20, 1, 85] as [Int?] {
            var description: [String: Any] = [
                kIOPSTypeKey: kIOPSInternalBatteryType,
                kIOPSCurrentCapacityKey: 68,
                kIOPSMaxCapacityKey: 100,
                kIOPSIsChargingKey: false,
                kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue
            ]
            description[kIOPSTimeToEmptyKey] = time.map { NSNumber(value: $0) }

            XCTAssertEqual(
                IOPSBatteryReader.parse(description)?.timeToEmptyMinutes,
                time.flatMap { $0 > 0 ? $0 : nil }
            )
        }
    }

    func testMonitorUpdatesRuntimeWithoutPercentageChangeAndClearsItOnPowerTransitions() async {
        let reader = FakeBatteryReader(result: makeReading(percentage: 68))
        let monitor = BatteryMonitor(
            reader: reader,
            lowPowerModeProvider: { false },
            iopsRunLoopSourceFactory: { _, _ in nil }
        )
        defer { monitor.stop() }
        var iterator = monitor.updates.makeAsyncIterator()

        // Every transition has the same percentage, including fresh estimates,
        // external power, inconsistent charging flags, and battery removal.
        let cases: [(Int?, Bool, Bool, Bool, Int?)] = [
            (85, false, false, true, 85),
            (80, false, false, true, 80),
            (nil, false, false, true, nil),
            (0, false, false, true, nil),
            (-1, false, false, true, nil),
            (80, true, false, true, nil),
            (80, true, true, true, nil),
            (80, false, true, true, nil),
            (80, false, false, false, nil),
            (70, false, false, true, 70)
        ]
        for (minutes, connected, charging, present, expected) in cases {
            var reading = makeReading(percentage: 68)
            reading.timeToEmptyMinutes = minutes
            reading.isConnectedToPower = connected
            reading.isCharging = charging
            reading.isPresent = present
            reader.result = reading
            monitor.refresh()
            let status = await iterator.next()
            XCTAssertEqual(status?.timeToEmptyMinutes, expected)
        }
        reader.result = nil
        monitor.refresh()
        let unavailable = await iterator.next()
        XCTAssertNil(unavailable?.timeToEmptyMinutes)
    }

    func testParserRejectsInvalidInternalBatteryDescription() {
        let description: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: "73",
            kIOPSMaxCapacityKey: 100
        ]

        XCTAssertNil(IOPSBatteryReader.parse(description))
    }

    func testParserRejectsNonBatteryDescription() {
        let description: [String: Any] = [
            kIOPSTypeKey: "UPS",
            kIOPSCurrentCapacityKey: 73,
            kIOPSMaxCapacityKey: 100
        ]

        XCTAssertNil(IOPSBatteryReader.parse(description))
    }

    func testMonitorConvertsReaderOutput() async {
        let reader = FakeBatteryReader(result: BatteryReading(
            currentCapacity: 2,
            maxCapacity: 3,
            isCharging: true,
            isConnectedToPower: true,
            isPresent: true
        ))
        let monitor = BatteryMonitor(
            reader: reader,
            lowPowerModeProvider: { true }
        )

        monitor.refresh()
        var iterator = monitor.updates.makeAsyncIterator()
        let value = await iterator.next()

        XCTAssertEqual(value?.percentage, 67)
        XCTAssertTrue(value?.isCharging == true)
        XCTAssertTrue(value?.isConnectedToPower == true)
        XCTAssertTrue(value?.isLowPowerMode == true)
        monitor.stop()
    }

    func testMissingReaderResultUsesFullValue() async {
        let monitor = BatteryMonitor(
            reader: FakeBatteryReader(result: nil),
            lowPowerModeProvider: { false }
        )

        monitor.refresh()
        var iterator = monitor.updates.makeAsyncIterator()
        let value = await iterator.next()

        XCTAssertTrue(value?.isPresent == false)
        XCTAssertEqual(value?.percentage, 100)
        XCTAssertFalse(value?.isCharging == true)
        XCTAssertFalse(value?.isConnectedToPower == true)
        monitor.stop()
    }

    func testNonPresentReadingUsesFullValue() async {
        let monitor = BatteryMonitor(
            reader: FakeBatteryReader(result: BatteryReading(
                currentCapacity: 42,
                maxCapacity: 100,
                isCharging: true,
                isConnectedToPower: true,
                isPresent: false
            )),
            lowPowerModeProvider: { false }
        )

        monitor.refresh()
        var iterator = monitor.updates.makeAsyncIterator()
        let value = await iterator.next()

        XCTAssertTrue(value?.isPresent == false)
        XCTAssertEqual(value?.percentage, 100)
        XCTAssertFalse(value?.isCharging == true)
        XCTAssertFalse(value?.isConnectedToPower == true)
        monitor.stop()
    }

    func testZeroMaxCapacityFallsBackToCurrentCapacity() async {
        let monitor = BatteryMonitor(
            reader: FakeBatteryReader(result: BatteryReading(
                currentCapacity: 73,
                maxCapacity: 0,
                isCharging: false,
                isConnectedToPower: false,
                isPresent: true
            )),
            lowPowerModeProvider: { false }
        )

        monitor.refresh()
        var iterator = monitor.updates.makeAsyncIterator()
        let value = await iterator.next()

        XCTAssertEqual(value?.percentage, 73)
        monitor.stop()
    }

    func testStartImmediatelyEmitsCurrentReading() async {
        let monitor = BatteryMonitor(
            reader: FakeBatteryReader(result: BatteryReading(
                currentCapacity: 81,
                maxCapacity: 100,
                isCharging: false,
                isConnectedToPower: false,
                isPresent: true
            )),
            lowPowerModeProvider: { false },
            iopsRunLoopSourceFactory: { _, _ in nil }
        )

        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        let value = await iterator.next()

        XCTAssertEqual(value?.percentage, 81)
        monitor.stop()
    }

    func testNilIOPSNotificationSourceStillRefreshesAndStops() async {
        let reader = FakeBatteryReader(result: makeReading(percentage: 64))
        let monitor = BatteryMonitor(
            reader: reader,
            lowPowerModeProvider: { false },
            iopsRunLoopSourceFactory: { _, _ in nil }
        )

        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        let value = await iterator.next()

        XCTAssertEqual(value?.percentage, 64)
        XCTAssertEqual(reader.readCount, 1)

        monitor.stop()
        let stoppedValue = await iterator.next()

        XCTAssertNil(stoppedValue)
        XCTAssertEqual(reader.readCount, 1)
    }

    func testRecoverReinstallsNotificationsAndKeepsStreamAlive() async {
        let reader = FakeBatteryReader(result: makeReading(percentage: 50))
        let harness = IOPSNotificationSourceHarness()
        defer { harness.releaseRetainedContexts() }
        let monitor = BatteryMonitor(
            reader: reader,
            lowPowerModeProvider: { false },
            iopsRunLoopSourceFactory: harness.factory
        )

        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        monitor.recover()

        XCTAssertEqual(harness.factoryInvocationCount, 2)
        XCTAssertNotNil(harness.contextPointer)
        XCTAssertNotNil(harness.callback)
        XCTAssertTrue(CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode))

        reader.result = makeReading(percentage: 60)
        harness.invokeCallback()
        let callbackValue = await iterator.next()
        XCTAssertEqual(callbackValue?.percentage, 60)

        let lowPowerStateRead = expectation(description: "low power state read")
        lowPowerStateRead.assertForOverFulfill = true
        reader.onReadCount = { count in
            if count == 3 {
                lowPowerStateRead.fulfill()
            }
        }
        NotificationCenter.default.post(
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        await fulfillment(of: [lowPowerStateRead], timeout: 1)

        XCTAssertEqual(reader.readCount, 3)
        monitor.stop()
    }

    func testStartAndStopAreIdempotent() {
        let reader = FakeBatteryReader(result: makeReading(percentage: 50))
        let harness = IOPSNotificationSourceHarness()
        defer { harness.releaseRetainedContexts() }
        let monitor = BatteryMonitor(
            reader: reader,
            lowPowerModeProvider: { false },
            iopsRunLoopSourceFactory: harness.factory
        )

        monitor.start()
        monitor.start()

        XCTAssertEqual(harness.factoryInvocationCount, 1)
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertTrue(CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode))

        monitor.stop()
        monitor.stop()

        XCTAssertFalse(CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode))
        XCTAssertEqual(reader.readCount, 1)
    }

    func testIOPSNotificationCallbackRefreshesUntilStopped() async {
        let reader = FakeBatteryReader(result: makeReading(percentage: 50))
        let harness = IOPSNotificationSourceHarness()
        defer { harness.releaseRetainedContexts() }
        let monitor = BatteryMonitor(
            reader: reader,
            lowPowerModeProvider: { false },
            iopsRunLoopSourceFactory: harness.factory
        )

        var iterator = monitor.updates.makeAsyncIterator()
        monitor.start()

        XCTAssertNotNil(harness.contextPointer)
        XCTAssertNotNil(harness.callback)
        XCTAssertTrue(CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode))
        let immediateValue = await iterator.next()
        XCTAssertEqual(immediateValue?.percentage, 50)
        XCTAssertEqual(reader.readCount, 1)

        reader.result = makeReading(percentage: 60)
        harness.invokeCallback()
        let callbackValue = await iterator.next()
        XCTAssertEqual(callbackValue?.percentage, 60)
        XCTAssertEqual(reader.readCount, 2)

        monitor.stop()

        XCTAssertFalse(CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode))
        let stoppedValue = await iterator.next()
        XCTAssertNil(stoppedValue)

        reader.result = makeReading(percentage: 70)
        harness.invokeCallback()
        await drainMainActorTasks()

        XCTAssertEqual(reader.readCount, 2)
        let postStopValue = await iterator.next()
        XCTAssertNil(postStopValue)
    }

    func testPowerStateNotificationRefreshesUntilStopped() async {
        let reader = FakeBatteryReader(result: makeReading(percentage: 50))
        let monitor = BatteryMonitor(
            reader: reader,
            lowPowerModeProvider: { false },
            iopsRunLoopSourceFactory: { _, _ in nil }
        )

        monitor.start()
        XCTAssertEqual(reader.readCount, 1)

        let powerStateRead = expectation(description: "power state read")
        powerStateRead.assertForOverFulfill = true
        reader.onReadCount = { count in
            if count == 2 {
                powerStateRead.fulfill()
            }
        }
        NotificationCenter.default.post(
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        await fulfillment(of: [powerStateRead], timeout: 1)

        monitor.stop()
        NotificationCenter.default.post(
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        await drainMainActorTasks()

        XCTAssertEqual(reader.readCount, 2)
    }

    func testRefreshAfterStopDoesNotReadOrEmitAnotherUpdate() async {
        let reader = FakeBatteryReader(result: makeReading(percentage: 50))
        let monitor = BatteryMonitor(
            reader: reader,
            lowPowerModeProvider: { false },
            iopsRunLoopSourceFactory: { _, _ in nil }
        )

        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        monitor.stop()
        monitor.refresh()

        let stoppedValue = await iterator.next()
        XCTAssertNil(stoppedValue)
        XCTAssertEqual(reader.readCount, 1)
    }

    func testStartAfterStopDoesNotRestart() {
        let reader = FakeBatteryReader(result: makeReading(percentage: 50))
        let harness = IOPSNotificationSourceHarness()
        defer { harness.releaseRetainedContexts() }
        let monitor = BatteryMonitor(
            reader: reader,
            lowPowerModeProvider: { false },
            iopsRunLoopSourceFactory: harness.factory
        )

        monitor.stop()
        monitor.start()

        XCTAssertEqual(harness.factoryInvocationCount, 0)
        XCTAssertEqual(reader.readCount, 0)
    }

    func testRecoverAfterStopDoesNotReinstallOrEmit() async {
        let reader = FakeBatteryReader(result: makeReading(percentage: 50))
        let harness = IOPSNotificationSourceHarness()
        defer { harness.releaseRetainedContexts() }
        let monitor = BatteryMonitor(
            reader: reader,
            lowPowerModeProvider: { false },
            iopsRunLoopSourceFactory: harness.factory
        )

        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()
        monitor.stop()

        monitor.recover()

        XCTAssertEqual(harness.factoryInvocationCount, 1)
        XCTAssertFalse(CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode))
        XCTAssertEqual(reader.readCount, 1)
        let finalValue = await iterator.next()
        XCTAssertNil(finalValue)
    }

    func testDeinitRemovesSourceWhenStopWasNotCalled() {
        let harness = IOPSNotificationSourceHarness()
        defer { harness.releaseRetainedContexts() }
        weak var weakMonitor: BatteryMonitor?

        do {
            let monitor = BatteryMonitor(
                reader: FakeBatteryReader(result: makeReading(percentage: 50)),
                lowPowerModeProvider: { false },
                iopsRunLoopSourceFactory: harness.factory
            )
            weakMonitor = monitor

            monitor.start()
            XCTAssertTrue(CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode))
        }

        XCTAssertNil(weakMonitor)
        XCTAssertFalse(CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode))
    }

    private func makeReading(percentage: Int) -> BatteryReading {
        BatteryReading(
            currentCapacity: percentage,
            maxCapacity: 100,
            isCharging: false,
            isConnectedToPower: false,
            isPresent: true
        )
    }

    private func drainMainActorTasks() async {
        await Task { @MainActor in }.value
    }
}

private final class FakeBatteryReader: BatteryReadingProviding {
    var result: BatteryReading?
    private(set) var readCount = 0
    var onReadCount: ((Int) -> Void)?

    init(result: BatteryReading?) {
        self.result = result
    }

    func read() -> BatteryReading? {
        readCount += 1
        onReadCount?(readCount)
        return result
    }
}

private final class IOPSNotificationSourceHarness {
    let source: CFRunLoopSource
    private(set) var callback: IOPSNotificationCallback?
    private(set) var contextPointer: UnsafeMutableRawPointer?
    private(set) var factoryInvocationCount = 0
    private var retainedContexts: [Unmanaged<AnyObject>] = []

    init() {
        var sourceContext = CFRunLoopSourceContext(
            version: 0,
            info: nil,
            retain: nil,
            release: nil,
            copyDescription: nil,
            equal: nil,
            hash: nil,
            schedule: nil,
            cancel: nil,
            perform: nil
        )
        source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &sourceContext)!
    }

    var factory: IOPSRunLoopSourceFactory {
        { [self] contextPointer, callback in
            factoryInvocationCount += 1
            self.contextPointer = contextPointer
            self.callback = callback
            if let contextPointer {
                retainedContexts.append(
                    Unmanaged<AnyObject>
                        .fromOpaque(contextPointer)
                        .retain()
                )
            }
            return source
        }
    }

    func invokeCallback() {
        callback?(contextPointer)
    }

    func releaseRetainedContexts() {
        retainedContexts.forEach { $0.release() }
        retainedContexts.removeAll()
    }
}
