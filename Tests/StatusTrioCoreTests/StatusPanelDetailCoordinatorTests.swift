import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct StatusPanelDetailCoordinatorTests {
    private let screen = StatusPanelScreen(
        frame: NSRect(x: 0, y: 0, width: 1000, height: 700),
        visibleFrame: NSRect(x: 0, y: 0, width: 1000, height: 700)
    )
    private func summary(x: CGFloat) -> NSRect {
        NSRect(x: x, y: 250, width: 330, height: 400)
    }

    private func side(_ decision: StatusPanelDetailCoordinator.Decision) -> StatusPanelDetailPlacement.Side? {
        if case let .alongside(placement) = decision { return placement.side }
        return nil
    }

    @Test func switchingRoutesKeepsSideUntilGeometryChanges() {
        var coordinator = StatusPanelDetailCoordinator()
        let start = summary(x: 600)

        let first = coordinator.update(route: .battery, enabled: true, summaryFrame: start, screens: [screen], dockInset: DockReveal.noInset)
        #expect(side(first) == .left)

        let nextRoute = coordinator.update(route: .wifi, enabled: true, summaryFrame: start, screens: [screen], dockInset: DockReveal.noInset)
        #expect(side(nextRoute) == .left)

        let moved = coordinator.update(route: .wifi, enabled: true, summaryFrame: summary(x: 0), screens: [screen], dockInset: DockReveal.noInset)
        #expect(side(moved) == .right)
    }

    @Test func fallbackReevaluatesOnScreenChange() {
        var coordinator = StatusPanelDetailCoordinator()
        let narrow = StatusPanelScreen(frame: NSRect(x: 0, y: 0, width: 660, height: 700), visibleFrame: NSRect(x: 0, y: 0, width: 660, height: 700))
        let start = summary(x: 160)

        let fallback = coordinator.update(route: .battery, enabled: true, summaryFrame: start, screens: [narrow], dockInset: DockReveal.noInset)
        #expect(fallback == .inline)

        let reappraised = coordinator.update(route: .battery, enabled: true, summaryFrame: start, screens: [screen], dockInset: DockReveal.noInset)
        #expect(side(reappraised) == .right)
    }

    @Test func noSideWindowWithoutActiveDetail() {
        var coordinator = StatusPanelDetailCoordinator()
        let start = summary(x: 0)

        #expect(coordinator.update(route: .summary, enabled: true, summaryFrame: start, screens: [screen], dockInset: DockReveal.noInset) == .hidden)
        #expect(coordinator.update(route: .battery, enabled: false, summaryFrame: start, screens: [screen], dockInset: DockReveal.noInset) == .hidden)
        #expect(coordinator.update(route: .battery, enabled: true, summaryFrame: start, screens: [screen], dockInset: DockReveal.noInset) != .hidden)
        #expect(coordinator.update(route: .summary, enabled: true, summaryFrame: start, screens: [screen], dockInset: DockReveal.noInset) == .hidden)
    }
}
