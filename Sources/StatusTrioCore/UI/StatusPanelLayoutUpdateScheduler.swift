import Foundation

/// Coalesces panel layout work into one main-actor turn (issue #259).
///
/// A window resize, a screen change and a content measurement can all arrive
/// inside the same layout pass. Running each one immediately re-enters layout
/// and produces the next notification, so the main thread never settles. This
/// scheduler keeps at most one pending operation and always runs the latest
/// one: a burst collapses into a single turn, and an owner that is going away
/// can drop anything still in flight.
@MainActor
final class StatusPanelLayoutUpdateScheduler {
    typealias Operation = @Sendable @MainActor () -> Void
    typealias Schedule = (@escaping Operation) -> Void

    private let schedule: Schedule
    private var pendingOperation: Operation?
    private var scheduledGeneration: Int?
    private var generation = 0

    init(schedule: @escaping Schedule) {
        self.schedule = schedule
    }

    /// Whether an operation is waiting to run.
    var hasPendingOperation: Bool { pendingOperation != nil }

    /// Queues the latest operation. A burst of calls runs only the last one.
    func enqueue(_ operation: @escaping Operation) {
        pendingOperation = operation
        guard scheduledGeneration == nil else { return }
        let scheduled = generation
        scheduledGeneration = scheduled
        schedule { [weak self] in
            guard let self, self.generation == scheduled else { return }
            self.scheduledGeneration = nil
            let operation = self.pendingOperation
            self.pendingOperation = nil
            operation?()
        }
    }

    /// Drops the pending operation and any callback already scheduled.
    func invalidate() {
        pendingOperation = nil
        generation += 1
        scheduledGeneration = nil
    }
}
