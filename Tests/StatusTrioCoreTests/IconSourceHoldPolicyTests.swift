import XCTest
@testable import StatusTrioCore

final class IconSourceHoldPolicyTests: XCTestCase {
    func testUnknownUsesLastGoodForLessThanTwoSecondsThenExpires() {
        let start = Date(timeIntervalSince1970: 100)
        var policy = IconSourceHoldPolicy<Int>(holdDuration: 2)

        XCTAssertEqual(policy.update(.available(0), sourceID: "network", at: start), .available(0))
        XCTAssertEqual(policy.update(.unavailable(.unknown), sourceID: "network", at: start), .available(0))
        XCTAssertEqual(policy.update(.unavailable(.unknown), sourceID: "network", at: start.addingTimeInterval(1)), .available(0))
        XCTAssertEqual(policy.update(.unavailable(.unknown), sourceID: "network", at: start.addingTimeInterval(2)),
                       .unavailable(.temporarilyStale))
    }

    func testUnknownWithoutHistoryIsImmediatelyUnavailable() {
        var policy = IconSourceHoldPolicy<Int>()

        XCTAssertEqual(policy.update(.unavailable(.unknown), sourceID: "network", at: Date()),
                       .unavailable(.unknown))
    }

    func testDisconnectAndPermissionDenialClearLastGoodImmediately() {
        let start = Date(timeIntervalSince1970: 100)
        var policy = IconSourceHoldPolicy<Int>()
        _ = policy.update(.available(42), sourceID: "bluetooth", at: start)

        XCTAssertEqual(policy.update(.unavailable(.disconnected), sourceID: "bluetooth", at: start),
                       .unavailable(.disconnected))
        XCTAssertEqual(policy.update(.unavailable(.unknown), sourceID: "bluetooth", at: start),
                       .unavailable(.unknown))
        _ = policy.update(.available(99), sourceID: "bluetooth", at: start)
        XCTAssertEqual(policy.update(.unavailable(.permissionDenied), sourceID: "bluetooth", at: start),
                       .unavailable(.permissionDenied))
    }

    func testChangingSourceAndResettingPolicyDoNotReuseOldValues() {
        let now = Date(timeIntervalSince1970: 100)
        var policy = IconSourceHoldPolicy<Int>()
        _ = policy.update(.available(42), sourceID: "first-device", at: now)

        XCTAssertEqual(policy.update(.unavailable(.unknown), sourceID: "second-device", at: now),
                       .unavailable(.unknown))
        _ = policy.update(.available(99), sourceID: "second-device", at: now)
        policy.reset()
        XCTAssertEqual(policy.update(.unavailable(.unknown), sourceID: "second-device", at: now),
                       .unavailable(.unknown))
    }

    func testRepeatedTemporaryStalenessDoesNotExtendOriginalTwoSecondHold() {
        let start = Date(timeIntervalSince1970: 100)
        var policy = IconSourceHoldPolicy<Int>(holdDuration: 2)
        _ = policy.update(.available(7), sourceID: "network", at: start)

        XCTAssertEqual(policy.update(.unavailable(.temporarilyStale), sourceID: "network", at: start.addingTimeInterval(1.5)),
                       .available(7))
        XCTAssertEqual(policy.expirationDate, start.addingTimeInterval(2))
        XCTAssertEqual(policy.update(.unavailable(.temporarilyStale), sourceID: "network", at: start.addingTimeInterval(2)),
                       .unavailable(.temporarilyStale))
        XCTAssertNil(policy.expirationDate)
    }

    func testExpiryDeadlineIsCreatedOnlyAfterUnknownBeginsAHold() {
        let now = Date(timeIntervalSince1970: 100)
        var policy = IconSourceHoldPolicy<Int>()
        XCTAssertNil(policy.expirationDate)
        _ = policy.update(.available(5), sourceID: "network", at: now)
        XCTAssertNil(policy.expirationDate, "Healthy values must not schedule a hold-expiry wake.")
        _ = policy.update(.unavailable(.unknown), sourceID: "network", at: now.addingTimeInterval(0.5))
        XCTAssertEqual(policy.expirationDate, now.addingTimeInterval(2))
    }
}
