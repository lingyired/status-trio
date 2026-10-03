import XCTest
@testable import StatusTrioCore

@MainActor
final class MobileBatteryControllerTests: XCTestCase {
    func testClaimsAndSurfaceMustBothBeActiveToRead() async {
        let reader = ControlledMobileBatteryReader()
        let controller = MobileBatteryController(reader: reader)

        controller.setSurfaceVisible(true)
        await settle()
        let countWithoutClaims = await reader.readCount
        XCTAssertEqual(countWithoutClaims, 0)

        controller.setSurfaceVisible(false)
        controller.request("summary")
        await settle()
        let countWithClaimsButClosed = await reader.readCount
        XCTAssertEqual(countWithClaimsButClosed, 0)

        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }
        controller.stop()
        await reader.finishAll()
    }

    func testRapidDisableAndReenableClearsCacheAndStartsANewReadForTheExistingClaim() async {
        let reader = ControlledMobileBatteryReader()
        let controller = MobileBatteryController(reader: reader)
        controller.setSurfaceVisible(true)
        controller.request("summary")
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: result(level: 71))
        await waitUntil { controller.snapshots.count == 1 }

        controller.setReadingEnabled(false)
        XCTAssertTrue(controller.snapshots.isEmpty)
        controller.setReadingEnabled(true)
        await waitUntil { await reader.readCount == 2 }
        XCTAssertTrue(controller.snapshots.isEmpty)
        controller.stop()
        await reader.finishAll()
    }

    func testReenablingWithNoClaimAndClosedSurfaceDoesNotRead() async {
        let reader = ControlledMobileBatteryReader()
        let controller = MobileBatteryController(reader: reader)
        controller.setReadingEnabled(false)
        controller.setReadingEnabled(true)
        controller.setSurfaceVisible(false)
        await settle()

        let readCount = await reader.readCount
        XCTAssertEqual(readCount, 0)
        controller.stop()
        await reader.finishAll()
    }

    func testClaimsShareWorkAndLastReleaseClearsSnapshots() async {
        let reader = ControlledMobileBatteryReader()
        let controller = MobileBatteryController(reader: reader)
        controller.setSurfaceVisible(true)
        controller.request("summary")
        await waitUntil { await reader.readCount == 1 }

        controller.request("bluetooth")
        controller.release("summary")
        await settle()
        let cancellationsAfterFirstRelease = await reader.cancellationCount
        XCTAssertEqual(cancellationsAfterFirstRelease, 0)

        await reader.complete(0, with: result(level: 71))
        await waitUntil { controller.snapshots.map(\.batteryLevel) == [71] }
        controller.release("bluetooth")
        XCTAssertTrue(controller.snapshots.isEmpty)
        let cancellationsAfterLastRelease = await reader.cancellationCount
        XCTAssertEqual(cancellationsAfterLastRelease, 0)
        XCTAssertFalse(controller.isRefreshing)
        XCTAssertTrue(controller.failures.isEmpty)
        controller.stop()
        await reader.finishAll()
    }

    func testClosingPopoverCancelsReadAndReopenRejectsLateGeneration() async {
        let reader = ControlledMobileBatteryReader()
        let controller = MobileBatteryController(reader: reader)
        controller.request("summary")
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }

        controller.setSurfaceVisible(false)
        await waitUntil { await reader.cancellationCount == 1 }
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 2 }

        await reader.complete(1, with: result(level: 38))
        await waitUntil { controller.snapshots.map(\.batteryLevel) == [38] }
        await reader.complete(0, with: result(level: 92))
        await settle()
        XCTAssertEqual(controller.snapshots.map(\.batteryLevel), [38])
        controller.stop()
        await reader.finishAll()
    }

    func testManualRefreshSupersedesReadAndStartsImmediately() async {
        let reader = ControlledMobileBatteryReader()
        let controller = MobileBatteryController(reader: reader)
        controller.request("summary")
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }

        controller.refresh()
        await waitUntil { await reader.readCount == 2 }
        let cancellations = await reader.cancellationCount
        XCTAssertEqual(cancellations, 1)
        await reader.complete(1, with: result(level: 52))
        await waitUntil { controller.snapshots.map(\.batteryLevel) == [52] }
        await reader.complete(0, with: result(level: 12))
        await settle()
        XCTAssertEqual(controller.snapshots.map(\.batteryLevel), [52])
        controller.stop()
        await reader.finishAll()
    }

    func testFailureRetainsTimestampAndPartialSuccessMergesByIdentity() async {
        let reader = ControlledMobileBatteryReader()
        let now = MutableDate(Date(timeIntervalSince1970: 10_000))
        let controller = MobileBatteryController(reader: reader, clock: { now.value })
        controller.request("summary")
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: result(level: 80, id: "phone-a"))
        await waitUntil { controller.snapshots.count == 1 }
        let initialTimestamp = controller.snapshots[0].observedAt

        now.value.addTimeInterval(60)
        controller.refresh()
        await waitUntil { await reader.readCount == 2 }
        await reader.complete(1, with: MobileBatteryReadResult(
            snapshots: [snapshot(id: "phone-b", level: 44, at: now.value)],
            failures: [MobileBatteryReadFailure(category: "unavailable", deviceID: "phone-a")]
        ))
        await waitUntil { controller.snapshots.count == 2 }
        XCTAssertEqual(controller.failures.map(\.category), ["unavailable"])
        XCTAssertEqual(controller.snapshots.first(where: { $0.id == "phone-a" })?.observedAt, initialTimestamp)
        XCTAssertEqual(controller.snapshots.first(where: { $0.id == "phone-a" })?.batteryLevel, 80)
        XCTAssertEqual(controller.snapshots.first(where: { $0.id == "phone-b" })?.batteryLevel, 44)
        controller.stop()
        await reader.finishAll()
    }

    func testExpiredCacheIsPrunedWhilePopoverIsClosed() async {
        let reader = ControlledMobileBatteryReader()
        let now = MutableDate(Date(timeIntervalSince1970: 20_000))
        let sleeper = ControlledMobileBatterySleeper()
        let controller = MobileBatteryController(
            reader: reader,
            clock: { now.value },
            sleep: { duration in try await sleeper.sleep(duration) }
        )
        controller.request("summary")
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: result(level: 63, at: now.value))
        await waitUntil { controller.snapshots.count == 1 }
        await sleeper.waitForDuration(.seconds(1_800))

        controller.setSurfaceVisible(false)
        now.value.addTimeInterval(1_800)
        await sleeper.fire(duration: .seconds(1_800))
        await waitUntil { controller.snapshots.isEmpty }
        controller.stop()
        await reader.finishAll()
    }

    func testRefreshesEverySixtySecondsWithoutOverlappingCycles() async {
        let reader = ControlledMobileBatteryReader()
        let sleeper = ControlledMobileBatterySleeper()
        let controller = MobileBatteryController(
            reader: reader,
            sleep: { duration in try await sleeper.sleep(duration) }
        )
        controller.request("summary")
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: result(level: 42))
        await waitUntil { !controller.isRefreshing }
        await sleeper.waitForDuration(.seconds(60))

        let countBeforeRefresh = await reader.readCount
        XCTAssertEqual(countBeforeRefresh, 1)
        await sleeper.fire(duration: .seconds(60))
        await waitUntil { await reader.readCount == 2 }
        controller.stop()
        await reader.finishAll()
    }

    func testDeallocationCancelsAReaderThatNeverReturns() async {
        let reader = ControlledMobileBatteryReader()
        weak var weakController: MobileBatteryController?
        do {
            let controller = MobileBatteryController(reader: reader)
            weakController = controller
            controller.request("summary")
            controller.setSurfaceVisible(true)
            await waitUntil { await reader.readCount == 1 }
        }
        await waitUntil { weakController == nil }
        await waitUntil { await reader.cancellationCount == 1 }
        await reader.finishAll()
    }

    func testSameIdentitySnapshotIsReplacedByLatestReading() async {
        let reader = ControlledMobileBatteryReader()
        let now = MutableDate(Date(timeIntervalSince1970: 30_000))
        let controller = MobileBatteryController(reader: reader, clock: { now.value })
        controller.request("summary")
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: result(level: 71, at: now.value))
        await waitUntil { controller.snapshots.count == 1 }

        now.value.addTimeInterval(60)
        controller.refresh()
        await waitUntil { await reader.readCount == 2 }
        await reader.complete(1, with: result(level: 82, at: now.value))
        await waitUntil { controller.snapshots.first?.batteryLevel == 82 }

        XCTAssertEqual(controller.snapshots.count, 1)
        XCTAssertEqual(controller.snapshots.first?.observedAt, now.value)
        controller.stop()
        await reader.finishAll()
    }

    func testEmptySuccessPreservesCachedReadingAndTimestamp() async {
        let reader = ControlledMobileBatteryReader()
        let now = MutableDate(Date(timeIntervalSince1970: 40_000))
        let controller = MobileBatteryController(reader: reader, clock: { now.value })
        controller.request("summary")
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: result(level: 73, at: now.value))
        await waitUntil { controller.snapshots.count == 1 }
        let originalTimestamp = controller.snapshots[0].observedAt

        now.value.addTimeInterval(300)
        controller.refresh()
        await waitUntil { await reader.readCount == 2 }
        await reader.complete(1, with: MobileBatteryReadResult())
        await waitUntil { !controller.isRefreshing }

        XCTAssertEqual(controller.snapshots.map(\.batteryLevel), [73])
        XCTAssertEqual(controller.snapshots.first?.observedAt, originalTimestamp)
        controller.stop()
        await reader.finishAll()
    }

    func testCacheExpiresAfterFinalClaimReleasesWhileKeepingResults() async {
        let reader = ControlledMobileBatteryReader()
        let now = MutableDate(Date(timeIntervalSince1970: 50_000))
        let sleeper = ControlledMobileBatterySleeper()
        let controller = MobileBatteryController(
            reader: reader,
            clock: { now.value },
            sleep: { duration in try await sleeper.sleep(duration) }
        )
        controller.request("summary")
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: result(level: 64, at: now.value))
        await waitUntil { controller.snapshots.count == 1 }
        await sleeper.waitForDuration(.seconds(1_800))

        controller.release("summary", keepingResults: true)
        XCTAssertEqual(controller.snapshots.map(\.batteryLevel), [64])
        now.value.addTimeInterval(1_800)
        await sleeper.fire(duration: .seconds(1_800))
        await waitUntil { controller.snapshots.isEmpty }

        controller.stop()
        await reader.finishAll()
    }

    private func snapshot(id: String = "phone-a", level: Int, at date: Date) -> MobileBatterySnapshot {
        MobileBatterySnapshot(
            id: id,
            parentID: nil,
            name: "Phone",
            model: "iPhone",
            batteryLevel: level,
            isCharging: nil,
            transport: .usb,
            observedAt: date
        )
    }

    private func result(level: Int, id: String = "phone-a", at date: Date = Date()) -> MobileBatteryReadResult {
        MobileBatteryReadResult(snapshots: [snapshot(id: id, level: level, at: date)])
    }

    private func settle() async {
        for _ in 0..<8 { await Task.yield() }
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping () async -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !(await condition()), ContinuousClock.now < deadline {
            await Task.yield()
        }
        let didBecomeTrue = await condition()
        XCTAssertTrue(didBecomeTrue, "condition did not become true before timeout")
    }
}

private final class MutableDate: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Date

    init(_ value: Date) { storage = value }

    var value: Date {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}

actor ControlledMobileBatteryReader: MobileBatteryReading {
    private var continuations: [Int: CheckedContinuation<MobileBatteryReadResult, any Error>] = [:]
    private(set) var readCount = 0
    private(set) var cancellationCount = 0

    func read() async throws -> MobileBatteryReadResult {
        let index = readCount
        readCount += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuations[index] = $0 }
        } onCancel: {
            Task { await self.recordCancellation() }
        }
    }

    func complete(_ index: Int, with result: MobileBatteryReadResult) {
        continuations.removeValue(forKey: index)?.resume(returning: result)
    }

    func finishAll() {
        let pending = continuations.values
        continuations.removeAll()
        for continuation in pending { continuation.resume(throwing: CancellationError()) }
    }

    private func recordCancellation() { cancellationCount += 1 }
}

private actor ControlledMobileBatterySleeper {
    private struct Waiter {
        let duration: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }
    private var nextID = 0
    private var continuations: [Int: Waiter] = [:]

    func sleep(_ duration: Duration) async throws {
        let id = nextID
        nextID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                continuations[id] = Waiter(duration: duration, continuation: $0)
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func waitForDuration(_ duration: Duration) async {
        for _ in 0..<1_000 {
            if continuations.values.contains(where: { $0.duration == duration }) { return }
            await Task.yield()
        }
    }

    func fire(duration: Duration) {
        guard let id = continuations.first(where: { $0.value.duration == duration })?.key,
              let waiter = continuations.removeValue(forKey: id) else { return }
        waiter.continuation.resume()
    }

    private func cancel(_ id: Int) {
        continuations.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }
}
