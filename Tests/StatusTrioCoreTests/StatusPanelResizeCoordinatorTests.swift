import AppKit
import XCTest
@testable import StatusTrioCore

/// Headless tests for the resize coordinator: the single driver behind the
/// panel's animated grow/collapse. A fake clock and a manual tick driver replace
/// the real timer so the tests never touch a display.
@MainActor
final class StatusPanelResizeCoordinatorTests: XCTestCase {
    /// A manually driven tick source.
    private final class TickDriver {
        private(set) var tick: (() -> Void)?
        private(set) var startCount = 0
        var isRunning: Bool { tick != nil }

        func schedule(_ block: @escaping () -> Void) -> () -> Void {
            startCount += 1
            tick = block
            return { [weak self] in self?.tick = nil }
        }

        func fire() { tick?() }
        func stop() { tick = nil }
    }

    private func makeCoordinator(
        clock: @escaping () -> CFTimeInterval
    ) -> (StatusPanelResizeCoordinator, TickDriver) {
        let driver = TickDriver()
        let coordinator = StatusPanelResizeCoordinator()
        coordinator.clock = clock
        coordinator.scheduleTicks = { [weak driver] block in
            driver?.schedule(block) ?? {}
        }
        return (coordinator, driver)
    }

    func testExpandAnimatesFromTheLiveHeightAndSettlesAtTarget() {
        var now: CFTimeInterval = 1000
        let (coordinator, driver) = makeCoordinator(clock: { now })
        var frames: [(CGFloat, Bool)] = []
        coordinator.place = { NSRect(x: 0, y: 0, width: 300, height: $0) }
        coordinator.writeFrame = { rect, display in frames.append((rect.height, display)) }

        coordinator.retarget(to: 400, fromHeight: 200)
        XCTAssertEqual(coordinator.phase, .expanding)
        XCTAssertTrue(coordinator.isAnimating)
        XCTAssertTrue(driver.isRunning, "an expand must start exactly one tick source")

        // Mid-flight.
        now += 0.10
        driver.fire()
        XCTAssertTrue(coordinator.phase == .expanding)
        XCTAssertGreaterThan(coordinator.presentedHeight, 200)
        XCTAssertLessThan(coordinator.presentedHeight, 400)

        // Past the duration: settle at exactly the target.
        now += 0.30
        driver.fire()
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(coordinator.presentedHeight, 400)
        XCTAssertFalse(driver.isRunning, "the tick source must be torn down once settled")
        XCTAssertEqual(frames.last?.0, 400)
        XCTAssertEqual(frames.last?.1, true, "only the settling tick forces a display")
    }

    func testRetargetDuringAnimationContinuesFromTheLiveHeight() {
        var now: CFTimeInterval = 1000
        let (coordinator, driver) = makeCoordinator(clock: { now })
        coordinator.place = { NSRect(x: 0, y: 0, width: 300, height: $0) }
        coordinator.writeFrame = { _, _ in }

        coordinator.retarget(to: 400, fromHeight: 200)
        now += 0.10
        driver.fire()
        let live = coordinator.presentedHeight
        XCTAssertGreaterThan(live, 200)

        // Reverse mid-flight. The new curve starts at the live height.
        coordinator.retarget(to: 200, fromHeight: live)
        XCTAssertEqual(coordinator.phase, .collapsing)
        XCTAssertEqual(coordinator.retargetCount, 1)
        XCTAssertEqual(coordinator.animation.snapshot?.startHeight, live)
        XCTAssertEqual(coordinator.animation.snapshot?.targetHeight, 200)

        // It still uses a single tick source across the retarget.
        XCTAssertEqual(driver.startCount, 1, "retargeting must not start a second driver")

        now += 0.30
        driver.fire()
        XCTAssertEqual(coordinator.presentedHeight, 200)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testPinIsAppliedOnStartAndReleasedOnSettle() {
        var now: CFTimeInterval = 1000
        let (coordinator, driver) = makeCoordinator(clock: { now })
        coordinator.place = { NSRect(x: 0, y: 0, width: 300, height: $0) }
        coordinator.writeFrame = { _, _ in }
        var pins: [CGFloat?] = []
        coordinator.pinContent = { pins.append($0) }

        coordinator.retarget(to: 400, fromHeight: 200)
        XCTAssertEqual(pins, [400], "the content is pinned to the target height while growing")

        now += 0.30
        driver.fire()
        XCTAssertEqual(pins, [400, nil], "settling must release the pin")
    }

    func testCancelStopsTheTickSourceAndLeavesThePhaseIdle() {
        var now: CFTimeInterval = 1000
        let (coordinator, driver) = makeCoordinator(clock: { now })
        coordinator.place = { NSRect(x: 0, y: 0, width: 300, height: $0) }
        coordinator.writeFrame = { _, _ in }
        coordinator.pinContent = { _ in }

        coordinator.retarget(to: 400, fromHeight: 200)
        XCTAssertTrue(driver.isRunning)
        coordinator.cancel()
        XCTAssertFalse(driver.isRunning, "cancel must tear down the tick source")
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertFalse(coordinator.isAnimating)
    }

    func testNoTickSourceIsStartedForAnImmediateSettle() {
        var now: CFTimeInterval = 1000
        let (coordinator, driver) = makeCoordinator(clock: { now })
        coordinator.place = { NSRect(x: 0, y: 0, width: 300, height: $0) }
        coordinator.writeFrame = { _, _ in }

        coordinator.markSettled(at: 222)
        XCTAssertFalse(driver.isRunning)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(coordinator.presentedHeight, 222)
    }
}