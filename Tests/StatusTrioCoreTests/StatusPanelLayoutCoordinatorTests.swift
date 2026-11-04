import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
private final class ManualSchedule {
    private var callbacks: [StatusPanelLayoutUpdateScheduler.Operation] = []

    func schedule(_ operation: @escaping StatusPanelLayoutUpdateScheduler.Operation) {
        callbacks.append(operation)
    }

    func drain() {
        while !callbacks.isEmpty {
            callbacks.removeFirst()()
        }
    }
}

@MainActor
private final class CoordinatorProbe {
    var appliedSizes: [NSSize] = []
    var repositionCount = 0
    var remeasureCount = 0
}

@MainActor
struct StatusPanelLayoutCoordinatorTests {
    private func makeCoordinator() -> (StatusPanelLayoutCoordinator, CoordinatorProbe, ManualSchedule) {
        let manual = ManualSchedule()
        let probe = CoordinatorProbe()
        let scheduler = StatusPanelLayoutUpdateScheduler { manual.schedule($0) }
        let coordinator = StatusPanelLayoutCoordinator(
            scheduler: scheduler,
            applyContentSize: { probe.appliedSizes.append($0) },
            reposition: { probe.repositionCount += 1 },
            remeasure: { probe.remeasureCount += 1 }
        )
        return (coordinator, probe, manual)
    }

    @Test func contentSizeIsAppliedOncePerTurn() {
        let (coordinator, probe, manual) = makeCoordinator()

        coordinator.requestContentSize(NSSize(width: 330, height: 400))
        #expect(probe.appliedSizes.isEmpty, "nothing may resize before the turn runs")
        manual.drain()

        #expect(probe.appliedSizes.map(\.height) == [400])
        #expect(probe.repositionCount == 0)
    }

    @Test func aBurstOfMeasurementsAppliesOnlyTheLatest() {
        let (coordinator, probe, manual) = makeCoordinator()

        for height in stride(from: 100.0, through: 400.0, by: 10.0) {
            coordinator.requestContentSize(NSSize(width: 330, height: height))
        }
        manual.drain()

        #expect(probe.appliedSizes.map(\.height) == [400])
    }

    @Test func windowResizeRepositionsWithoutReapplyingStaleContent() {
        let (coordinator, probe, manual) = makeCoordinator()

        coordinator.requestContentSize(NSSize(width: 330, height: 400))
        manual.drain()
        #expect(probe.appliedSizes.count == 1)

        coordinator.windowDidResize()
        manual.drain()

        #expect(probe.repositionCount == 1, "a resize must only re-place the window")
        #expect(probe.appliedSizes.count == 1, "a resize must not replay the old measurement")
    }

    @Test func windowResizeBeforeAnyMeasurementOnlyRepositions() {
        let (coordinator, probe, manual) = makeCoordinator()

        coordinator.windowDidResize()
        manual.drain()

        #expect(probe.repositionCount == 1)
        #expect(probe.appliedSizes.isEmpty)
    }

    @Test func environmentChangeRemeasuresAndDropsThePendingMeasurement() {
        let (coordinator, probe, manual) = makeCoordinator()

        coordinator.placementEnvironmentChanged()
        // A measurement taken before the new budget was known must not decide
        // the frame once the re-measure is requested.
        coordinator.requestContentSize(NSSize(width: 330, height: 400))
        manual.drain()

        #expect(probe.remeasureCount == 1)
        #expect(probe.repositionCount == 1)
        #expect(probe.appliedSizes.isEmpty, "the pre-change measurement is stale")
    }

    @Test func aFreshMeasurementAfterTheRemeasureStillApplies() {
        let (coordinator, probe, manual) = makeCoordinator()

        coordinator.placementEnvironmentChanged()
        manual.drain()
        coordinator.requestContentSize(NSSize(width: 330, height: 260))
        manual.drain()

        #expect(probe.appliedSizes.map(\.height) == [260])
    }

    @Test func invalidateDropsPendingContentAndResumes() {
        let (coordinator, probe, manual) = makeCoordinator()

        coordinator.requestContentSize(NSSize(width: 330, height: 400))
        coordinator.invalidate()
        manual.drain()
        #expect(probe.appliedSizes.isEmpty)

        coordinator.requestContentSize(NSSize(width: 330, height: 200))
        manual.drain()
        #expect(probe.appliedSizes.map(\.height) == [200])
    }

    @Test func aSettledCoordinatorDoesNothingOnExtraTurns() {
        let (coordinator, probe, manual) = makeCoordinator()

        coordinator.requestContentSize(NSSize(width: 330, height: 200))
        manual.drain()
        coordinator.windowDidResize()
        manual.drain()

        #expect(probe.repositionCount == 1)
        #expect(probe.appliedSizes.map(\.height) == [200], "settled state must stay put")
    }
}
