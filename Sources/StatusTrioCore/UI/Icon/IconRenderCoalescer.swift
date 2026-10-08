import Foundation

/// Rate-limits status icon redraws.
///
/// A setting change has to reach the menu bar immediately, but a slider drag
/// publishes a value per frame and every one of those values used to redraw the
/// bitmap. `submit(_:)` runs the first request of a quiet period straight away
/// and keeps the newest request of a burst as the trailing redraw, so a drag
/// repaints at most once per `minimumInterval` while a single toggle or picker
/// change is still applied within the same run loop turn.
@MainActor
final class IconRenderCoalescer {
    /// 20 redraws per second: fast enough that a drag looks continuous, slow
    /// enough that one bitmap render does not follow every frame.
    static let defaultMinimumInterval: TimeInterval = 1.0 / 20

    private let minimumInterval: TimeInterval
    private let now: () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void

    private var lastRunDate: Date?
    private var pendingRender: (() -> Void)?
    private var pendingTask: Task<Void, Never>?

    init(
        minimumInterval: TimeInterval = IconRenderCoalescer.defaultMinimumInterval,
        now: @escaping () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.minimumInterval = minimumInterval
        self.now = now
        self.sleep = sleep
    }

    /// Runs `render` now when the last redraw is old enough, otherwise keeps it
    /// as the trailing redraw for the burst in progress.
    func submit(_ render: @escaping @MainActor () -> Void) {
        let currentDate = now()
        let elapsed = lastRunDate.map { currentDate.timeIntervalSince($0) }
            ?? .greatestFiniteMagnitude

        guard elapsed < minimumInterval else {
            lastRunDate = currentDate
            render()
            return
        }

        pendingRender = render
        guard pendingTask == nil else { return }

        let delay = max(0, minimumInterval - elapsed)
        let sleep = self.sleep
        pendingTask = Task { @MainActor [weak self] in
            do {
                try await sleep(.seconds(delay))
            } catch {
                return
            }
            guard let self else { return }
            self.pendingTask = nil
            guard let render = self.pendingRender else { return }
            self.pendingRender = nil
            self.lastRunDate = self.now()
            render()
        }
    }

    /// Drops a scheduled trailing redraw, for a controller that is shutting down.
    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingRender = nil
        lastRunDate = nil
    }

    /// Runs queued presentation work at a deterministic drain boundary.
    func flushPending() {
        pendingTask?.cancel()
        pendingTask = nil
        guard let render = pendingRender else { return }
        pendingRender = nil
        lastRunDate = now()
        render()
    }
}
