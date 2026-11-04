import AppKit
import QuartzCore
import XCTest
@testable import StatusTrioCore

/// End-to-end coverage for the panel's animated content resize, driven headlessly
/// through `StatusPanelResizeCoordinator` and the real placement maths.
///
/// The existing `AirPodsInlineControlsSizingTests` only proves the expanded view
/// reports a stable height. These tests prove the *window transition* keeps its
/// anchored edge fixed, moves monotonically, never exceeds the screen budget and
/// writes no frame after it settles.
@MainActor
final class AirPodsInlineWindowTransitionTests: XCTestCase {
    // A 1440x900 screen with a 875pt visible frame, like the other placement tests.
    private let screen = StatusPanelScreen(
        frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 875)
    )
    private let anchor = StatusPanelAnchor(
        screenRect: NSRect(x: 708, y: 880, width: 24, height: 18),
        preferredEdge: .minY
    )
    private let width: CGFloat = 330

    private final class TickDriver {
        private(set) var tick: (() -> Void)?
        private(set) var startCount = 0
        private var running = false
        var isRunning: Bool { running }

        func schedule(_ block: @escaping () -> Void) -> () -> Void {
            startCount += 1
            tick = block
            running = true
            return { [weak self] in
                self?.tick = nil
                self?.running = false
            }
        }

        func stop() { tick = nil; running = false }
        func fire() { tick?() }
    }

    /// Reference box so the test observes writes recorded inside the closures.
    private final class Recorder {
        var frames: [NSRect] = []
        var writesAfterSettle = 0
        var settled = false
        var now: CFTimeInterval = 1000
    }

    private final class Harness {
        let coordinator: StatusPanelResizeCoordinator
        let driver: TickDriver
        let recorder: Recorder

        init(coordinator: StatusPanelResizeCoordinator, driver: TickDriver, recorder: Recorder) {
            self.coordinator = coordinator
            self.driver = driver
            self.recorder = recorder
        }

        var now: CFTimeInterval {
            get { recorder.now }
            set { recorder.now = newValue }
        }
        var frames: [NSRect] { recorder.frames }
        var writesAfterSettle: Int { recorder.writesAfterSettle }
    }

    /// Builds a coordinator whose `place` closure mirrors the panel: the anchor
    /// is locked for the run, so intermediate heights cannot flip the side.
    private func makeHarness(
        startingHeight: CGFloat,
        anchor: StatusPanelAnchor? = nil
    ) -> Harness {
        let driver = TickDriver()
        let recorder = Recorder()
        let coordinator = StatusPanelResizeCoordinator()
        let width = self.width
        let screenList = [screen]
        let anchorValue = anchor ?? self.anchor

        coordinator.clock = { recorder.now }
        coordinator.scheduleTicks = { [weak driver] block in
            driver?.schedule(block) ?? {}
        }
        coordinator.place = { height in
            StatusPanelPlacement.frame(
                contentSize: NSSize(width: width, height: height),
                anchor: anchorValue,
                screens: screenList
            )
        }
        coordinator.writeFrame = { rect, _ in
            recorder.frames.append(rect)
            if recorder.settled { recorder.writesAfterSettle += 1 }
        }
        coordinator.didSettle = { recorder.settled = true }

        return Harness(coordinator: coordinator, driver: driver, recorder: recorder)
    }

    private func runToSettle(_ h: Harness) {
        for _ in 0..<60 {
            h.now += 0.01
            h.driver.fire()
            if h.coordinator.phase == .idle { break }
        }
    }

    // MARK: - 4.1 Static expansion

    func testExpandKeepsTheMenuBarEdgeFixedAndNeverOvershoots() {
        var h = makeHarness(startingHeight: 400)
        let originalTop = StatusPanelPlacement.frame(
            contentSize: NSSize(width: width, height: 400),
            anchor: anchor,
            screens: [screen]
        ).maxY

        h.coordinator.retarget(to: 640, fromHeight: 400)
        XCTAssertEqual(h.coordinator.phase, .expanding)

        var heights: [CGFloat] = []
        for _ in 0..<60 {
            h.now += 0.01
            h.driver.fire()
            if let last = h.frames.last { heights.append(last.height) }
            if h.coordinator.phase == .idle { break }
        }

        XCTAssertEqual(h.coordinator.phase, .idle)
        XCTAssertEqual(h.coordinator.presentedHeight, 640)
        for frame in h.frames {
            XCTAssertEqual(frame.maxY, originalTop, accuracy: 0.5,
                           "the menu-bar edge must not move while growing")
            XCTAssertEqual(frame.width, width, accuracy: 0.5,
                           "the panel width must not change for a height-only resize")
            XCTAssertEqual(frame.minX, h.frames.first?.minX ?? frame.minX, accuracy: 0.5)
        }
        for pair in zip(heights, heights.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1, pair.0, "growth must be monotonic")
        }
        XCTAssertEqual(h.writesAfterSettle, 0)
        XCTAssertFalse(h.driver.isRunning, "no timer may survive a settle")
    }

    // MARK: - 4.2 Progressive data load

    func testSeveralMeasurementsDuringOneGrowRetargetWithoutExtraDrivers() {
        var h = makeHarness(startingHeight: 300)
        h.coordinator.retarget(to: 520, fromHeight: 300)
        h.now += 0.05
        h.driver.fire()

        h.coordinator.retarget(to: 600, fromHeight: h.coordinator.presentedHeight)
        h.now += 0.04
        h.driver.fire()
        h.coordinator.retarget(to: 640, fromHeight: h.coordinator.presentedHeight)

        XCTAssertEqual(h.driver.startCount, 1,
                       "progressive publishes must not start a second driver")
        XCTAssertEqual(h.coordinator.retargetCount, 2)

        runToSettle(h)
        XCTAssertEqual(h.coordinator.presentedHeight, 640)
        XCTAssertEqual(h.writesAfterSettle, 0)
    }

    func testPixelAlignedMeasurementIsRecognisedAsAtTarget() {
        var h = makeHarness(startingHeight: 400)
        h.coordinator.retarget(to: 520, fromHeight: 400)
        h.now += 0.03
        h.driver.fire()

        XCTAssertTrue(h.coordinator.isAtTarget(520.4))
        XCTAssertFalse(h.coordinator.isAtTarget(522))
        XCTAssertGreaterThan(h.coordinator.presentedHeight, 400)
        XCTAssertLessThan(h.coordinator.presentedHeight, 520)
    }

    // MARK: - 4.3 Rapid repeated toggling

    func testTwentyRapidTogglesLeaveNoTimerAndConvergeOnTheLastTarget() {
        var h = makeHarness(startingHeight: 400)
        var expected: CGFloat = 400
        for i in 0..<20 {
            expected = (i % 2 == 0) ? 640 : 400
            h.coordinator.retarget(to: expected, fromHeight: h.coordinator.presentedHeight)
            h.now += 0.012
            h.driver.fire()
        }
        runToSettle(h)
        XCTAssertEqual(h.coordinator.presentedHeight, expected)
        XCTAssertFalse(h.driver.isRunning)
        XCTAssertEqual(h.writesAfterSettle, 0)
    }

    func testCancellingDuringFlightStopsTheDriverAndLeavesNoWrites() {
        var h = makeHarness(startingHeight: 400)
        h.coordinator.retarget(to: 640, fromHeight: 400)
        h.now += 0.05
        h.driver.fire()
        XCTAssertTrue(h.driver.isRunning)
        h.coordinator.cancel()
        XCTAssertFalse(h.driver.isRunning)
        XCTAssertEqual(h.coordinator.phase, .idle)
        let afterCancel = h.frames.count
        h.now += 0.5
        h.driver.stop()
        XCTAssertEqual(h.frames.count, afterCancel)
    }

    // MARK: - 4.4 Geometry acceptance

    func testResizeNeverExceedsTheMaximumPanelHeight() {
        let maximum = StatusPanelPlacement.maximumPanelHeight(
            anchor: anchor,
            screens: [screen]
        )!
        var h = makeHarness(startingHeight: 400)
        h.coordinator.retarget(to: maximum + 300, fromHeight: 400)
        runToSettle(h)
        for frame in h.frames {
            XCTAssertLessThanOrEqual(frame.height, maximum + 0.5,
                                     "the panel must never exceed its screen budget")
        }
    }

    func testBottomDockAnchorKeepsTheBottomEdgeFixedAndGrowsUpward() {
        let dockAnchor = StatusPanelAnchor(
            screenRect: NSRect(x: 700, y: 0, width: 40, height: 40),
            preferredEdge: .maxY
        )
        var h = makeHarness(startingHeight: 300, anchor: dockAnchor)
        let originalBottom = StatusPanelPlacement.frame(
            contentSize: NSSize(width: width, height: 300),
            anchor: dockAnchor,
            screens: [screen]
        ).minY
        h.coordinator.retarget(to: 520, fromHeight: 300)
        runToSettle(h)
        for frame in h.frames {
            XCTAssertEqual(frame.minY, originalBottom, accuracy: 0.5,
                           "a Dock-anchored panel must keep its bottom edge fixed")
        }
        XCTAssertEqual(h.coordinator.presentedHeight, 520)
    }

    func testCollapseReturnsMonotonicallyToTheOriginalHeight() {
        var h = makeHarness(startingHeight: 640)
        h.coordinator.retarget(to: 400, fromHeight: 640)
        XCTAssertEqual(h.coordinator.phase, .collapsing)
        var heights: [CGFloat] = []
        for _ in 0..<60 {
            h.now += 0.01
            h.driver.fire()
            if let last = h.frames.last { heights.append(last.height) }
            if h.coordinator.phase == .idle { break }
        }
        for pair in zip(heights, heights.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.1, pair.0, "collapse must be monotonic")
        }
        XCTAssertEqual(h.coordinator.presentedHeight, 400)
        XCTAssertEqual(h.frames.last?.height, 400)
        XCTAssertEqual(h.writesAfterSettle, 0)
    }
}