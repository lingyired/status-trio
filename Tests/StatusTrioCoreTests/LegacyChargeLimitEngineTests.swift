import XCTest
@testable import StatusTrioCore

/// Phase 4-6 shared engine logic: the hysteresis/boundary behaviour the plan's
/// `ChargeLimitEngineTests` matrix calls for. Pure, no hardware.
final class LegacyChargeLimitEngineTests: XCTestCase {
    private func engine(_ limit: Int = 80) -> LegacyChargeLimitEngine {
        LegacyChargeLimitEngine(limit: limit, hysteresis: 2)
    }

    // MARK: Boundary: 78 / 79 / 80 / 81 at limit 80

    func testAtCeilingInhibits() {
        let action = engine().decide(batteryLevel: 80, isOnAC: true, currentlyAllowing: true)
        XCTAssertEqual(action, .inhibitCharging)
    }

    func testAboveCeilingInhibits() {
        let action = engine().decide(batteryLevel: 81, isOnAC: true, currentlyAllowing: true)
        XCTAssertEqual(action, .inhibitCharging)
    }

    func testInsideHysteresisHoldsCurrentGate() {
        // 79 is above limit-hysteresis (78) but below 80 → hold the current gate.
        XCTAssertEqual(
            engine().decide(batteryLevel: 79, isOnAC: true, currentlyAllowing: true),
            .none
        )
        XCTAssertEqual(
            engine().decide(batteryLevel: 79, isOnAC: true, currentlyAllowing: false),
            .none
        )
    }

    func testAtLowerBandEdgeAllows() {
        // 78 == limit - hysteresis → allow charging.
        let action = engine().decide(batteryLevel: 78, isOnAC: true, currentlyAllowing: false)
        XCTAssertEqual(action, .allowCharging)
    }

    func testWellBelowAllows() {
        let action = engine().decide(batteryLevel: 50, isOnAC: true, currentlyAllowing: false)
        XCTAssertEqual(action, .allowCharging)
    }

    // MARK: No flapping inside the band

    func testNoFlapWhenLevelWobblesInsideBand() {
        var reducer = LegacyChargeLimitReducer()
        // Start allowing, reach 78 (allow), drift to 79 (hold), back to 78 (hold).
        XCTAssertEqual(reducer.apply(engine(), batteryLevel: 78, isOnAC: true), .allowCharging)
        XCTAssertEqual(reducer.apply(engine(), batteryLevel: 79, isOnAC: true), .none)
        XCTAssertEqual(reducer.apply(engine(), batteryLevel: 78, isOnAC: true), .none)
        // Only at the ceiling does it inhibit.
        XCTAssertEqual(reducer.apply(engine(), batteryLevel: 80, isOnAC: true), .inhibitCharging)
    }

    // MARK: Unplug / replug

    func testUnpluggedDoesNotInhibit() {
        // No AC: don't write a charge-gate change while on battery.
        XCTAssertEqual(
            engine().decide(batteryLevel: 85, isOnAC: false, currentlyAllowing: true),
            .none
        )
        // If we had inhibited before unplug, allow again so the battery can run.
        XCTAssertEqual(
            engine().decide(batteryLevel: 85, isOnAC: false, currentlyAllowing: false),
            .allowCharging
        )
    }

    func testReplugReevaluates() {
        var reducer = LegacyChargeLimitReducer()
        _ = reducer.apply(engine(), batteryLevel: 80, isOnAC: true)
        reducer.replug()
        XCTAssertNil(reducer.lastAllowed)
        // Fresh evaluate above ceiling → inhibit again.
        XCTAssertEqual(reducer.apply(engine(), batteryLevel: 85, isOnAC: true), .inhibitCharging)
    }

    // MARK: Sleep / wake

    func testWakeResetsGateThenReapplies() {
        var reducer = LegacyChargeLimitReducer()
        _ = reducer.apply(engine(), batteryLevel: 80, isOnAC: true) // inhibit
        reducer.resetForWake()
        XCTAssertNil(reducer.lastAllowed)
        // Above ceiling after wake → inhibit.
        XCTAssertEqual(reducer.apply(engine(), batteryLevel: 80, isOnAC: true), .inhibitCharging)
    }

    // MARK: Temporary charge-to-full (100%)

    func testTemporaryFullKeepsChargingUntilFull() {
        XCTAssertTrue(LegacyChargeLimitEngine.temporaryFullShouldContinue(batteryLevel: 99))
        XCTAssertTrue(LegacyChargeLimitEngine.temporaryFullShouldContinue(batteryLevel: 80))
        XCTAssertFalse(LegacyChargeLimitEngine.temporaryFullShouldContinue(batteryLevel: 100))
    }

    func testLimit100NeverInhibitsByCeiling() {
        // A 100% ceiling means "no cap": at 99 we allow, at 100 we would still
        // inhibit (>= limit) but the caller treats 100 as stock. Verify the
        // engine's raw decision remains coherent.
        let e = LegacyChargeLimitEngine(limit: 100)
        XCTAssertEqual(e.decide(batteryLevel: 99, isOnAC: true, currentlyAllowing: true), .none)
        XCTAssertEqual(e.decide(batteryLevel: 100, isOnAC: true, currentlyAllowing: true), .inhibitCharging)
    }

    func testCustomHysteresis() {
        let e = LegacyChargeLimitEngine(limit: 90, hysteresis: 5)
        // 86 inside band (90-5=85), hold.
        XCTAssertEqual(e.decide(batteryLevel: 86, isOnAC: true, currentlyAllowing: true), .none)
        // 85 at edge, allow.
        XCTAssertEqual(e.decide(batteryLevel: 85, isOnAC: true, currentlyAllowing: false), .allowCharging)
    }
}