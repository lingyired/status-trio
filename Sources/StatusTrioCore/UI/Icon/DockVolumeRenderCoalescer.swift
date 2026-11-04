import Foundation

/// Rate-limits Dock repaints while the volume value is adjusted continuously
/// and merges changes that are too small to be visible.
///
/// The Dock is not the primary volume feedback surface — the panel and the
/// menu bar are — so a continuous volume adjustment may repaint it at a
/// bounded rate. The newest value always reaches the Dock: the coalescer keeps
/// the latest request as the trailing repaint. Every other scene change
/// bypasses this coalescer in `AppIconController`, so settings and non-volume
/// scene changes stay on the immediate path.
@MainActor
final class DockVolumeRenderCoalescer {
    /// At most ten volume-driven Dock repaints per second.
    static let defaultMinimumInterval: TimeInterval = 1.0 / 10
    /// Arc progress below this delta is visually indistinguishable at Dock
    /// size; it merges into the trailing repaint instead of repainting.
    static let defaultArcMergeThreshold: Double = 0.002

    private let minimumInterval: TimeInterval
    private let arcMergeThreshold: Double
    private let now: () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void

    private var lastRenderDate: Date?
    private var lastRenderedFooter: FooterState?
    private var pendingFooter: FooterState?
    private var pendingRender: (@MainActor () -> Void)?
    private var pendingTask: Task<Void, Never>?

    init(
        minimumInterval: TimeInterval = DockVolumeRenderCoalescer.defaultMinimumInterval,
        arcMergeThreshold: Double = DockVolumeRenderCoalescer.defaultArcMergeThreshold,
        now: @escaping () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.minimumInterval = minimumInterval
        self.arcMergeThreshold = arcMergeThreshold
        self.now = now
        self.sleep = sleep
    }

    /// Queues a volume-only repaint. The latest request wins.
    func submit(footer: FooterState?, render: @escaping @MainActor () -> Void) {
        let currentDate = now()
        let elapsed = lastRenderDate.map { currentDate.timeIntervalSince($0) }
            ?? .greatestFiniteMagnitude
        let merged = isMerged(footer, against: lastRenderedFooter)

        pendingFooter = footer
        pendingRender = render

        if elapsed >= minimumInterval, !merged {
            runPending(at: currentDate)
            return
        }

        guard pendingTask == nil else { return }
        scheduleTrailing(after: max(0, minimumInterval - elapsed))
    }

    /// Drops a scheduled volume repaint, for a controller that is stopping or
    /// for a scene change that takes the immediate path.
    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingRender = nil
        pendingFooter = nil
        lastRenderDate = nil
        lastRenderedFooter = nil
    }

    /// Runs queued volume presentation work at a deterministic drain boundary.
    func flushPending() {
        pendingTask?.cancel()
        pendingTask = nil
        guard pendingRender != nil else { return }
        runPending(at: now())
    }

    private func scheduleTrailing(after delay: TimeInterval) {
        let sleep = self.sleep
        pendingTask = Task { @MainActor [weak self] in
            do {
                try await sleep(.seconds(delay))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.pendingTask = nil
            self.runPending(at: self.now())
        }
    }

    private func runPending(at date: Date) {
        pendingTask?.cancel()
        pendingTask = nil
        guard let render = pendingRender else { return }
        let footer = pendingFooter
        pendingRender = nil
        pendingFooter = nil
        lastRenderDate = date
        lastRenderedFooter = footer
        render()
    }

    private func isMerged(_ footer: FooterState?, against lastRendered: FooterState?) -> Bool {
        guard case let .arc(new)? = footer, case let .arc(old)? = lastRendered else {
            return false
        }
        return new.color == old.color
            && new.strokeScale == old.strokeScale
            && abs(new.progress - old.progress) < arcMergeThreshold
    }
}
