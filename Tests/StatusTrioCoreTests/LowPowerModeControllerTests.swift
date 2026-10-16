import XCTest
@testable import StatusTrioCore

@MainActor
final class LowPowerModeControllerTests: XCTestCase {
    func testOptOutBeforeAQueuedReadPreventsHelperContact() async {
        let client = FakeLowPowerModeClient(reads: true)
        let controller = LowPowerModeController(client: client, initialIsLowPowerMode: false)
        controller.setEnabled(true)
        controller.refresh()
        controller.setEnabled(false)
        await settle()
        XCTAssertEqual(client.readCallCount, 0)
        XCTAssertNil(controller.lastError)
    }

    func testOptOutBeforeAQueuedWritePreventsHelperContact() async {
        let client = FakeLowPowerModeClient(reads: false)
        let controller = LowPowerModeController(client: client, initialIsLowPowerMode: false)
        controller.setEnabled(true)
        controller.setLowPowerMode(true)
        controller.setEnabled(false)
        await settle()
        XCTAssertEqual(client.setCallCount, 0)
        XCTAssertFalse(controller.isApplying)
        XCTAssertNil(controller.lastError)
    }

    func testRefreshDoesNotSupersedeAQueuedPowerModeWrite() async {
        let client = FakeLowPowerModeClient(reads: false)
        let controller = LowPowerModeController(client: client, initialIsLowPowerMode: false)
        controller.setEnabled(true)
        controller.setLowPowerMode(true)
        controller.refresh()
        await waitUntil { !controller.isApplying }
        XCTAssertEqual(client.setCallCount, 1)
        XCTAssertEqual(client.readCallCount, 0)
        XCTAssertTrue(controller.isLowPowerMode)
        XCTAssertFalse(controller.isApplying)
    }

    func testDoesNotContactTheHelperWhileDisabled() async {
        let client = FakeLowPowerModeClient(reads: true)
        let controller = LowPowerModeController(client: client, initialIsLowPowerMode: false)

        controller.refresh()
        controller.setLowPowerMode(true)
        await settle()

        XCTAssertEqual(client.readCallCount, 0)
        XCTAssertEqual(client.setCallCount, 0)
        XCTAssertFalse(controller.isLowPowerMode)
    }

    func testEnablingAllowsRefreshToReadThroughTheHelper() async {
        let client = FakeLowPowerModeClient(reads: true)
        let controller = LowPowerModeController(client: client, initialIsLowPowerMode: false)

        controller.setEnabled(true)
        controller.refresh()
        await waitUntil { client.readCallCount == 1 }

        XCTAssertEqual(client.readCallCount, 1)
        XCTAssertTrue(controller.isLowPowerMode)
    }

    func testSetPublishesTheObservedValue() async {
        let client = FakeLowPowerModeClient(reads: false)
        client.setResult = true
        let controller = LowPowerModeController(client: client, initialIsLowPowerMode: false)
        controller.setEnabled(true)

        controller.setLowPowerMode(true)
        await waitUntil { !controller.isApplying && client.setCallCount == 1 }

        XCTAssertEqual(client.setCallCount, 1)
        XCTAssertEqual(client.lastSetValue, true)
        XCTAssertTrue(controller.isLowPowerMode)
        XCTAssertFalse(controller.isApplying)
        XCTAssertNil(controller.lastError)
    }

    func testSetRevertsOptimisticValueOnFailure() async {
        let client = FakeLowPowerModeClient(reads: false)
        client.setError = FakeError.denied
        let controller = LowPowerModeController(client: client, initialIsLowPowerMode: false)
        controller.setEnabled(true)

        controller.setLowPowerMode(true)
        await waitUntil { controller.lastError != nil }

        XCTAssertFalse(controller.isLowPowerMode)
        XCTAssertNotNil(controller.lastError)
        XCTAssertFalse(controller.isApplying)
    }

    func testSystemReadSeedsTheDisplayedValueWhenIdle() {
        let controller = LowPowerModeController(
            client: FakeLowPowerModeClient(reads: false),
            initialIsLowPowerMode: false
        )

        controller.updateFromSystemRead(true)

        XCTAssertTrue(controller.isLowPowerMode)
    }

    func testHelperReadingWinsOverTheLaggingProcessInfoSeed() async {
        // `ProcessInfo.isLowPowerModeEnabled` is cached per process and can lag
        // the real state; once the helper has answered, its value must stand or
        // the toggle would send the wrong direction.
        let client = FakeLowPowerModeClient(reads: true)
        let controller = LowPowerModeController(client: client, initialIsLowPowerMode: false)
        controller.setEnabled(true)
        controller.refresh()
        await waitUntil { controller.isLowPowerMode }
        XCTAssertTrue(controller.isLowPowerMode)

        controller.updateFromSystemRead(false)

        XCTAssertTrue(controller.isLowPowerMode)
    }

    func testDisablingClearsErrorAndStopsContact() async {
        let client = FakeLowPowerModeClient(reads: false)
        client.setError = FakeError.denied
        let controller = LowPowerModeController(client: client, initialIsLowPowerMode: false)
        controller.setEnabled(true)
        controller.setLowPowerMode(true)
        await waitUntil { controller.lastError != nil }
        XCTAssertNotNil(controller.lastError)

        controller.setEnabled(false)
        controller.refresh()
        await settle()

        XCTAssertNil(controller.lastError)
        XCTAssertEqual(client.readCallCount, 0)
    }

    /// Waits until `condition` holds, giving the controller's detached MainActor
    /// tasks real time to finish.
    ///
    /// Counting `Task.yield()`s is not a synchronization guarantee: the write
    /// path suspends on a nonisolated `await` and resumes back on the main actor,
    /// and on a loaded CI runner ten yields did not cover that round trip, which
    /// flaked `testDisablingClearsErrorAndStopsContact` (runs 38262423399 and
    /// 38278475902). The deadline makes a genuine regression fail instead of hang.
    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() {
            if ContinuousClock.now >= deadline {
                XCTFail("Timed out waiting for the low power mode controller to settle.")
                return
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    /// Drains the main actor for a bounded moment when a test asserts that *no*
    /// asynchronous work happened and therefore has no condition to wait on.
    private func settle() async {
        for _ in 0..<25 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    private enum FakeError: Error {
        case denied
    }
}

private final class FakeLowPowerModeClient: LowPowerModeClienting, @unchecked Sendable {
    var reads: Bool
    var setResult: Bool?
    var setError: Error?
    private(set) var readCallCount = 0
    private(set) var setCallCount = 0
    private(set) var lastSetValue: Bool?

    init(reads: Bool) {
        self.reads = reads
    }

    func readLowPowerMode() async throws -> Bool {
        readCallCount += 1
        return reads
    }

    func setLowPowerMode(_ enabled: Bool) async throws -> Bool {
        setCallCount += 1
        lastSetValue = enabled
        if let setError {
            throw setError
        }
        return setResult ?? enabled
    }
}
