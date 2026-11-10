import XCTest
@testable import StatusTrioCore

final class BatteryHealthSystemReaderTests: XCTestCase {
    private func json(health: String? = nil, maximumCapacity: String? = nil) -> Data {
        var info: [String: Any] = [:]
        if let health { info["sppower_battery_health"] = health }
        if let maximumCapacity { info["sppower_battery_health_maximum_capacity"] = maximumCapacity }
        let root: [String: Any] = [
            "SPPowerDataType": [["_name": "spbattery_information", "sppower_battery_health_info": info]]
        ]
        return try! JSONSerialization.data(withJSONObject: root)
    }

    override func setUp() {
        super.setUp()
        BatteryHealthSystemReader.resetCache()
    }

    override func tearDown() {
        BatteryHealthSystemReader.resetCache()
        super.tearDown()
    }

    func testSuccessIsCachedForTTLThenReRun() {
        var calls = 0
        let start = Date()
        let run: BatteryHealthSystemReader.Runner = { _ in
            calls += 1
            return .exited(self.json(health: "Good", maximumCapacity: "94%"))
        }
        let first = BatteryHealthSystemReader.read(now: start, run: run)
        XCTAssertEqual(first?.condition, .normal)
        XCTAssertEqual(first?.maximumCapacityPercent, 94)
        XCTAssertEqual(calls, 1)
        // Within ttl the cached answer is reused without launching a process.
        let cached = BatteryHealthSystemReader.read(now: start.addingTimeInterval(100), run: run)
        XCTAssertEqual(cached?.condition, .normal)
        XCTAssertEqual(cached?.maximumCapacityPercent, 94)
        XCTAssertEqual(calls, 1, "within ttl the cached answer is reused")
        // After ttl the process runs again.
        XCTAssertEqual(
            BatteryHealthSystemReader.read(now: start.addingTimeInterval(601), run: run)?.condition,
            .normal)
        XCTAssertEqual(calls, 2, "after ttl it re-runs")
    }

    func testFailureIsRetriedAfterShortFailureTTL() {
        var calls = 0
        let start = Date()
        let run: BatteryHealthSystemReader.Runner = { _ in
            calls += 1
            return .timedOut
        }
        XCTAssertNil(BatteryHealthSystemReader.read(now: start, run: run))
        XCTAssertEqual(calls, 1)
        XCTAssertNil(
            BatteryHealthSystemReader.read(now: start.addingTimeInterval(30), run: run))
        XCTAssertEqual(calls, 1, "a failure is cached for the short failureTTL")
        XCTAssertNil(
            BatteryHealthSystemReader.read(now: start.addingTimeInterval(61), run: run))
        XCTAssertEqual(calls, 2, "after failureTTL it retries")
    }

    func testUnknownFieldsAreCachedLikeAnAnswer() {
        var calls = 0
        let start = Date()
        let run: BatteryHealthSystemReader.Runner = { _ in
            calls += 1
            return .exited(self.json())
        }
        let reading = BatteryHealthSystemReader.read(now: start, run: run)
        XCTAssertNil(reading?.condition)
        XCTAssertNil(reading?.maximumCapacityPercent)
        XCTAssertNil(BatteryHealthSystemReader.read(now: start.addingTimeInterval(100), run: run)?.condition)
        XCTAssertEqual(calls, 1, "a clean exit caches its answer even when both values are unknown")
    }

    func testMaximumCapacityPercentParsesReportedPercentage() {
        XCTAssertEqual(
            BatteryHealthParser.maximumCapacityPercent(
                systemProfilerJSON: json(maximumCapacity: "94%")), 94)
        XCTAssertEqual(
            BatteryHealthParser.maximumCapacityPercent(
                systemProfilerJSON: json(maximumCapacity: " 100 % ")), 100)
        XCTAssertNil(
            BatteryHealthParser.maximumCapacityPercent(
                systemProfilerJSON: json(maximumCapacity: "94")), "no % is not a health percentage")
        XCTAssertNil(
            BatteryHealthParser.maximumCapacityPercent(
                systemProfilerJSON: json(maximumCapacity: "0%")), "zero is not a real maximum")
        XCTAssertNil(
            BatteryHealthParser.maximumCapacityPercent(
                systemProfilerJSON: json(maximumCapacity: "200%")), "out of credible range")
        XCTAssertNil(
            BatteryHealthParser.maximumCapacityPercent(
                systemProfilerJSON: Data("not json".utf8)))
    }
}
