import XCTest
@testable import StatusTrioCore

@MainActor
final class ReadWatchdogTests: XCTestCase {
    func testTimeoutStartsAtTheBaseAndDoublesUpToTheCap() async {
        let sleeper = ManualEventSleeper()
        let watchdog = ReadWatchdog(
            baseTimeout: .seconds(1),
            maxTimeout: .seconds(8),
            sleep: { duration in await sleeper.sleep(duration) }
        )

        for index in 0..<5 {
            let fired = expectation(description: "watchdog \(index) fired")
            watchdog.arm { fired.fulfill() }
            await sleeper.waitForCallCount(index + 1, timeout: .seconds(5))
            sleeper.releaseAll()
            await fulfillment(of: [fired], timeout: 5)
        }

        XCTAssertEqual(
            sleeper.durations,
            [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(8)],
            "Consecutive timeouts must back off and then stay at the cap"
        )
    }

    func testRecordSuccessResetsTheBackoff() async {
        let sleeper = ManualEventSleeper()
        let watchdog = ReadWatchdog(
            baseTimeout: .seconds(1),
            maxTimeout: .seconds(8),
            sleep: { duration in await sleeper.sleep(duration) }
        )

        for index in 0..<3 {
            let fired = expectation(description: "watchdog \(index) fired")
            watchdog.arm { fired.fulfill() }
            await sleeper.waitForCallCount(index + 1, timeout: .seconds(5))
            sleeper.releaseAll()
            await fulfillment(of: [fired], timeout: 5)
        }

        watchdog.recordSuccess()

        let afterReset = expectation(description: "watchdog after reset fired")
        watchdog.arm { afterReset.fulfill() }
        await sleeper.waitForCallCount(4, timeout: .seconds(5))
        sleeper.releaseAll()
        await fulfillment(of: [afterReset], timeout: 5)

        XCTAssertEqual(
            sleeper.durations,
            [.seconds(1), .seconds(2), .seconds(4), .seconds(1)],
            "A returned read means the system is responsive again"
        )
    }

    func testCancelledWatchdogDoesNotReportATimeout() async {
        let sleeper = ManualEventSleeper()
        let watchdog = ReadWatchdog(
            baseTimeout: .seconds(1),
            maxTimeout: .seconds(8),
            sleep: { duration in await sleeper.sleep(duration) }
        )
        let notFired = expectation(description: "a cancelled watchdog never fires")
        notFired.isInverted = true

        watchdog.arm { notFired.fulfill() }
        await sleeper.waitForCallCount(1, timeout: .seconds(5))
        watchdog.cancel()
        sleeper.releaseAll()

        await fulfillment(of: [notFired], timeout: 0.2)
    }
}
