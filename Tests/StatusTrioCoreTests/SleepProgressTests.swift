import XCTest
@testable import StatusTrioCore

final class SleepProgressTests: XCTestCase {
    func testFractionUsesTheConfiguredTotal() {
        XCTAssertEqual(SleepProgress.fraction(remaining: 3600, total: 3600), 1, accuracy: 0.0001)
        XCTAssertEqual(SleepProgress.fraction(remaining: 1800, total: 3600), 0.5, accuracy: 0.0001)
        XCTAssertEqual(SleepProgress.fraction(remaining: 1260, total: 3600), 0.35, accuracy: 0.0001)
        XCTAssertEqual(SleepProgress.fraction(remaining: 600, total: 3600), 1.0 / 6.0, accuracy: 0.001)
    }

    func testFractionClampsToZeroAndOne() {
        XCTAssertEqual(SleepProgress.fraction(remaining: 7200, total: 3600), 1, accuracy: 0.0001)
        XCTAssertEqual(SleepProgress.fraction(remaining: -30, total: 3600), 0, accuracy: 0.0001)
        XCTAssertEqual(SleepProgress.fraction(remaining: 0, total: 3600), 0, accuracy: 0.0001)
    }

    func testUnlimitedStaysFull() {
        XCTAssertEqual(SleepProgress.fraction(remaining: 0, total: nil), 1, accuracy: 0.0001)
    }

    func testDisplayMinutesNeverReadsZeroWhileRunning() {
        XCTAssertEqual(SleepProgress.displayMinutes(remaining: 0), 1)
        XCTAssertEqual(SleepProgress.displayMinutes(remaining: 20), 1)
        XCTAssertEqual(SleepProgress.displayMinutes(remaining: 60), 1)
        XCTAssertEqual(SleepProgress.displayMinutes(remaining: 61), 2)
        XCTAssertEqual(SleepProgress.displayMinutes(remaining: 3600), 60)
    }

    func testRemainingIsNeverNegative() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(SleepProgress.remaining(until: now.addingTimeInterval(90), now: now), 90)
        XCTAssertEqual(SleepProgress.remaining(until: now.addingTimeInterval(-90), now: now), 0)
    }

    func testEveryTimerDurationIntervalAndShortLabel() {
        XCTAssertEqual(SleepTimerDuration.thirtyMinutes.timeInterval, 30 * 60)
        XCTAssertEqual(SleepTimerDuration.oneHour.timeInterval, 60 * 60)
        XCTAssertEqual(SleepTimerDuration.twoHours.timeInterval, 2 * 60 * 60)
        XCTAssertEqual(SleepTimerDuration.fourHours.timeInterval, 4 * 60 * 60)
        XCTAssertNil(SleepTimerDuration.unlimited.timeInterval)

        XCTAssertEqual(SleepTimerDuration.thirtyMinutes.shortLabel, "30m")
        XCTAssertEqual(SleepTimerDuration.oneHour.shortLabel, "1h")
        XCTAssertEqual(SleepTimerDuration.twoHours.shortLabel, "2h")
        XCTAssertEqual(SleepTimerDuration.fourHours.shortLabel, "4h")
        XCTAssertEqual(SleepTimerDuration.unlimited.shortLabel, "∞")
    }
}
