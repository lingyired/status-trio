import QuartzCore

/// The pure, AppKit-free math behind the status panel's height resize animation.
///
/// The window owner drives the animation through this value type so the easing,
/// retarget and settle rules can be unit-tested without a window. The panel keeps
/// one `Snapshot` for the grow/collapse that is currently in flight and recomputes
/// the presented height on every tick from the elapsed time alone.
///
/// Retargeting never jumps: replacing the snapshot uses the live presented height
/// and the current time as the origin of a fresh curve, so a second toggle while
/// the first is mid-flight continues smoothly from where the panel actually is.
@MainActor
struct StatusPanelResizeAnimation {
    enum Direction: Equatable {
        case expanding
        case collapsing
        case settling
    }

    struct Snapshot: Equatable {
        var startHeight: CGFloat
        var targetHeight: CGFloat
        var startTime: CFTimeInterval
        var direction: Direction

        var delta: CGFloat { targetHeight - startHeight }
    }

    /// The curve currently in flight. `nil` means no animation is running.
    private(set) var snapshot: Snapshot?

    /// Starts or retargets the animation towards `targetHeight`, taking the
    /// current presented height `fromHeight` and wall-clock `time` as the new
    /// origin so the curve continues from the live position.
    ///
    /// `direction` only describes intent (expand vs collapse vs settle); it does
    /// not change the eased path, which always runs from `fromHeight` to
    /// `targetHeight`.
    mutating func retarget(
        to targetHeight: CGFloat,
        from fromHeight: CGFloat,
        time: CFTimeInterval,
        direction: Direction
    ) {
        snapshot = Snapshot(
            startHeight: fromHeight,
            targetHeight: targetHeight,
            startTime: time,
            direction: direction
        )
    }

    /// Ends any animation, keeping the presented height where it currently sits.
    mutating func finish() {
        snapshot = nil
    }

    /// Whether an animation is currently advancing towards a target.
    var isAnimating: Bool { snapshot != nil }

    /// The presented height at `time` for a curve of `duration`, plus whether the
    /// curve has reached its end.
    ///
    /// Heights snap to whole points every tick: a fractional window height makes
    /// AppKit round the window's origin and size independently, so the anchored
    /// edge wobbles by up to a point while the panel grows. The final height is
    /// exactly the target, never the eased value a few ticks short of it.
    func presentedHeight(at time: CFTimeInterval, duration: CFTimeInterval) -> (height: CGFloat, finished: Bool) {
        guard let snapshot else {
            return (0, true)
        }
        let progress = min(1, (time - snapshot.startTime) / max(duration, 0.001))
        let finished = progress >= 1
        let eased = 1 - pow(1 - progress, 3)
        let delta = snapshot.delta
        let height = (snapshot.startHeight + delta * CGFloat(eased)).rounded()
        return (finished ? snapshot.targetHeight : height, finished)
    }
}