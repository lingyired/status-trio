import Combine
import XCTest
@testable import StatusTrioCore

/// Deterministic coverage for the reusable disclosure height driver. Real
/// button/layout/window coverage lives in StatusPanelLayoutIntegrationTests.
@MainActor
final class StatusPanelResizeCoordinatorTests: XCTestCase {
    @MainActor
    private final class TickDriver {
        var tick: (@MainActor @Sendable () -> Void)?
        var startCount = 0
        func schedule(_ block: @escaping @MainActor @Sendable () -> Void) -> () -> Void {
            startCount += 1
            tick = block
            return { [weak self] in self?.tick = nil }
        }
        func fire() { tick?() }
    }

    private func makeCoordinator(clock: @escaping () -> CFTimeInterval) -> (StatusPanelResizeCoordinator, TickDriver) {
        let driver = TickDriver()
        let coordinator = StatusPanelResizeCoordinator()
        coordinator.clock = clock
        coordinator.scheduleTicks = { [weak driver] in driver?.schedule($0) ?? {} }
        return (coordinator, driver)
    }

    func testExpandPresentsIntermediateHeightsAndStopsAtTheExactTarget() {
        var now: CFTimeInterval = 1000
        let (c, driver) = makeCoordinator(clock: { now })
        c.retarget(to: 200, fromHeight: 0)
        XCTAssertEqual(c.phase, .expanding)
        XCTAssertNotNil(driver.tick)
        now += 0.05
        driver.fire()
        XCTAssertGreaterThan(c.presentedHeight, 0)
        XCTAssertLessThan(c.presentedHeight, 200)
        now += 0.4
        driver.fire()
        XCTAssertEqual(c.presentedHeight, 200)
        XCTAssertEqual(c.phase, .idle)
        XCTAssertNil(driver.tick)
        XCTAssertNil(c.animation.snapshot)
    }

    func testReversalCarriesVelocityAndKeepsOneTickSource() {
        var now: CFTimeInterval = 1000
        let (c, driver) = makeCoordinator(clock: { now })
        c.retarget(to: 200, fromHeight: 0)
        now += 0.05
        driver.fire()
        let live = c.presentedHeight
        c.retarget(to: 0, fromHeight: live)
        XCTAssertEqual(c.presentedHeight, live)
        XCTAssertGreaterThan(c.animation.snapshot?.startVelocity ?? 0, 0)
        XCTAssertEqual(c.phase, .collapsing)
        XCTAssertEqual(driver.startCount, 1)
        now += 0.4
        driver.fire()
        XCTAssertEqual(c.presentedHeight, 0)
        XCTAssertNil(driver.tick)
    }

    func testReversalToTheCurrentHeightCancelsBeforeTheFirstTick() {
        var now: CFTimeInterval = 1000
        let (c, driver) = makeCoordinator(clock: { now })
        c.retarget(to: 200, fromHeight: 0)
        let staleTick = driver.tick
        c.retarget(to: 0, fromHeight: 0)
        XCTAssertEqual(c.phase, .idle)
        XCTAssertNil(driver.tick)
        now += 0.5
        staleTick?()
        XCTAssertEqual(c.presentedHeight, 0)
        XCTAssertEqual(c.targetHeight, 0)
    }

    func testRepeatedTargetsDoNotRestartTheCurve() {
        var now: CFTimeInterval = 1000
        let (c, driver) = makeCoordinator(clock: { now })
        c.retarget(to: 200, fromHeight: 0)
        now += 0.05
        driver.fire()
        let snapshot = c.animation.snapshot
        c.retarget(to: 200, fromHeight: c.presentedHeight)
        XCTAssertEqual(c.animation.snapshot, snapshot)
        XCTAssertEqual(c.retargetCount, 0)
        XCTAssertEqual(driver.startCount, 1)
        c.cancel()
    }

    func testDelayedRetargetUsesVelocityFromTheSamePresentedPosition() {
        var now: CFTimeInterval = 1000
        let (c, driver) = makeCoordinator(clock: { now })
        c.retarget(to: 200, fromHeight: 0)
        now += 0.004
        driver.fire()
        let velocity = c.animation.velocity(at: now)
        let position = c.presentedHeight
        now += 0.04 // no displayed tick during this main-thread interval
        c.retarget(to: 0, fromHeight: position)
        XCTAssertEqual(c.animation.snapshot?.startVelocity, velocity)
        XCTAssertEqual(c.animation.snapshot?.startHeight, position)
        c.cancel()
    }

    func testThirtyRapidTargetsConvergeOnTheLastIntentWithoutOvershooting() {
        var now: CFTimeInterval = 1000
        let (c, driver) = makeCoordinator(clock: { now })
        for index in 0..<30 {
            c.retarget(to: index % 2 == 0 ? 200 : 0, fromHeight: c.presentedHeight)
            for _ in 0..<(index % 4 + 2) {
                now += 0.01
                driver.fire()
                XCTAssertGreaterThanOrEqual(c.presentedHeight, 0)
                XCTAssertLessThanOrEqual(c.presentedHeight, 200)
            }
        }
        now += 0.5
        driver.fire()
        XCTAssertEqual(c.presentedHeight, 0)
        XCTAssertEqual(c.targetHeight, 0)
        XCTAssertNil(driver.tick)
    }

    func testDisplayPixelHeightsAreDeduplicatedAndUseHalfPoints() {
        var now: CFTimeInterval = 1000
        let (c, driver) = makeCoordinator(clock: { now })
        c.pixelScale = 2
        var heights: [CGFloat] = []
        let subscription = c.$presentedHeight.sink { heights.append($0) }
        defer { subscription.cancel() }
        c.retarget(to: 200.5, fromHeight: 0)
        for _ in 0..<1000 {
            now += 0.0005
            driver.fire()
        }
        XCTAssertTrue(heights.contains { $0 != $0.rounded() })
        XCTAssertTrue(heights.allSatisfy { $0 * 2 == ($0 * 2).rounded() })
        XCTAssertFalse(zip(heights, heights.dropFirst()).contains { $0 == $1 })
        XCTAssertEqual(heights.last, 200.5)
        XCTAssertNil(driver.tick)
    }

    func testChangingPixelScaleRealignsAnInFlightAndSettledTarget() {
        var now: CFTimeInterval = 1000
        let (c, driver) = makeCoordinator(clock: { now })
        c.pixelScale = 2
        c.retarget(to: 200.5, fromHeight: 0)
        now += 0.05
        driver.fire()
        c.pixelScale = 1
        XCTAssertEqual(c.targetHeight, 201)
        now += 0.4
        driver.fire()
        XCTAssertEqual(c.presentedHeight, 201)
        XCTAssertNil(driver.tick)
        c.pixelScale = 2
        c.markSettled(at: 100.5)
        c.pixelScale = 1
        XCTAssertEqual(c.presentedHeight, 101)
        XCTAssertEqual(c.targetHeight, 101)
    }

    func testCancelAndImmediateSettlementClearEveryTransientState() {
        let (c, driver) = makeCoordinator(clock: { 1000 })
        c.retarget(to: 200, fromHeight: 0)
        c.cancel()
        XCTAssertNil(driver.tick)
        XCTAssertNil(c.animation.snapshot)
        XCTAssertEqual(c.phase, .idle)
        XCTAssertEqual(c.targetHeight, c.presentedHeight)
        c.retarget(to: 200, fromHeight: 0)
        let staleTick = driver.tick
        c.markSettled(at: 120.5)
        let settled = c.presentedHeight
        staleTick?()
        XCTAssertEqual(c.presentedHeight, settled, "an invalidated tick cannot replay movement")
        XCTAssertNil(driver.tick)
        XCTAssertNil(c.animation.snapshot)
        XCTAssertEqual(c.phase, .idle)
        XCTAssertEqual(c.presentedHeight, c.targetHeight)
    }
}
