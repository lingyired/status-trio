import XCTest
@testable import StatusTrioCore

final class BatteryConditionSystemReaderTests: XCTestCase {
    private func json(_ health: String) -> Data {
        Data("""
        {"SPPowerDataType":[{"_name":"spbattery_information",
          "sppower_battery_health_info":{"sppower_battery_health":"\(health)"}}]}
        """.utf8)
    }

    override func setUp() {
        super.setUp()
        BatteryConditionSystemReader.resetCache()
    }

    override func tearDown() {
        BatteryConditionSystemReader.resetCache()
        super.tearDown()
    }

    func testSuccessIsCachedForTTLThenReRun() {
        var calls = 0
        let start = Date()
        let run: BatteryConditionSystemReader.Runner = { _ in
            calls += 1
            return .exited(self.json("Good"))
        }
        XCTAssertEqual(BatteryConditionSystemReader.read(now: start, run: run), .normal)
        XCTAssertEqual(calls, 1)
        // Within ttl the cached answer is reused without launching a process.
        XCTAssertEqual(
            BatteryConditionSystemReader.read(now: start.addingTimeInterval(100), run: run), .normal)
        XCTAssertEqual(calls, 1, "within ttl the cached answer is reused")
        // After ttl the process runs again.
        XCTAssertEqual(
            BatteryConditionSystemReader.read(now: start.addingTimeInterval(601), run: run), .normal)
        XCTAssertEqual(calls, 2, "after ttl it re-runs")
    }

    func testFailureIsRetriedAfterShortFailureTTL() {
        var calls = 0
        let start = Date()
        let run: BatteryConditionSystemReader.Runner = { _ in
            calls += 1
            return .timedOut
        }
        XCTAssertNil(BatteryConditionSystemReader.read(now: start, run: run))
        XCTAssertEqual(calls, 1)
        XCTAssertNil(
            BatteryConditionSystemReader.read(now: start.addingTimeInterval(30), run: run))
        XCTAssertEqual(calls, 1, "a failure is cached for the short failureTTL")
        XCTAssertNil(
            BatteryConditionSystemReader.read(now: start.addingTimeInterval(61), run: run))
        XCTAssertEqual(calls, 2, "after failureTTL it retries")
    }

    func testUnknownConditionIsCachedLikeAnAnswer() {
        var calls = 0
        let start = Date()
        let run: BatteryConditionSystemReader.Runner = { _ in
            calls += 1
            return .exited(self.json("Unknown"))
        }
        XCTAssertNil(BatteryConditionSystemReader.read(now: start, run: run))
        XCTAssertNil(
            BatteryConditionSystemReader.read(now: start.addingTimeInterval(100), run: run))
        XCTAssertEqual(calls, 1, "a clean exit caches its answer even when unknown")
    }
}
