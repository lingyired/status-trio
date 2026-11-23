import Foundation
import Testing
@testable import StatusTrioCore

/// A main queue the test drains by hand, so the coalescing behaviour is
/// deterministic and no window or run loop is involved.
@MainActor
private final class ManualSchedule {
    private var callbacks: [StatusPanelLayoutUpdateScheduler.Operation] = []

    func schedule(_ operation: @escaping StatusPanelLayoutUpdateScheduler.Operation) {
        callbacks.append(operation)
    }

    var scheduledCount: Int { callbacks.count }

    func drain() {
        while !callbacks.isEmpty {
            callbacks.removeFirst()()
        }
    }
}

@MainActor
struct StatusPanelLayoutUpdateSchedulerTests {
    @Test func aBurstOfRequestsRunsOnlyTheLatestOperationOnce() {
        let manual = ManualSchedule()
        let scheduler = StatusPanelLayoutUpdateScheduler { manual.schedule($0) }
        var seen: [Int] = []

        for value in 0..<100 {
            scheduler.enqueue { seen.append(value) }
        }

        #expect(manual.scheduledCount == 1, "one burst must schedule one callback")
        #expect(scheduler.hasPendingOperation)
        manual.drain()

        #expect(seen == [99], "only the latest operation of a burst may run")
        #expect(!scheduler.hasPendingOperation)
    }

    @Test func invalidateDropsPendingWorkAndResumesAfterwards() {
        let manual = ManualSchedule()
        let scheduler = StatusPanelLayoutUpdateScheduler { manual.schedule($0) }
        var runs = 0

        scheduler.enqueue { runs += 1 }
        scheduler.invalidate()
        manual.drain()
        #expect(runs == 0, "invalidated work must not run")

        scheduler.enqueue { runs += 1 }
        manual.drain()
        #expect(runs == 1, "the scheduler must accept work again after invalidate")
    }

    @Test func anOperationMayEnqueueTheNextTurn() {
        let manual = ManualSchedule()
        let scheduler = StatusPanelLayoutUpdateScheduler { manual.schedule($0) }
        var seen: [String] = []

        scheduler.enqueue {
            seen.append("first")
            scheduler.enqueue { seen.append("second") }
        }
        manual.drain()

        #expect(seen == ["first", "second"], "work queued during a turn runs next turn")
    }

    @Test func aReleasedSchedulerDoesNotRunScheduledCallbacks() {
        let manual = ManualSchedule()
        var runs = 0
        do {
            let scheduler = StatusPanelLayoutUpdateScheduler { manual.schedule($0) }
            scheduler.enqueue { runs += 1 }
        }

        manual.drain()
        #expect(runs == 0, "a scheduled callback must not keep a released scheduler alive")
    }
}
