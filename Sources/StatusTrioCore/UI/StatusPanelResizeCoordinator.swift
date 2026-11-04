import AppKit
import QuartzCore

/// Owns the status panel's animated content-driven height changes.
///
/// This is the single place allowed to write an animated window frame for a
/// content measurement. It wraps `StatusPanelResizeAnimation` with a frame timer,
/// the clock and the callbacks the window needs, so the grow/collapse can be
/// driven in tests without a real timer or display.
///
/// Responsibilities (and the reason it exists):
/// - one animation in flight at a time: a new measurement only retargets the
///   current curve, it never starts a second timer that would fight the first;
/// - the anchored edge is locked for the whole run: the panel hands in a
///   `place(height:)` closure that pins the placement edge it chose when the
///   animation began, so intermediate heights cannot flip the side;
/// - phase reporting (`idle` / `expanding` / `collapsing` / `settling`) so the
///   panel and diagnostics can tell a settled panel from a moving one;
/// - full teardown on cancel, so a closed panel leaves no timer behind.
@MainActor
final class StatusPanelResizeCoordinator {
    enum Phase: String, Equatable {
        case idle
        case expanding
        case collapsing
        case settling
    }

    /// Wall clock used for the animation. Injectable for tests.
    var clock: () -> CFTimeInterval = { CACurrentMediaTime() }
    /// Starts a repeating frame tick and returns a closure that stops it.
    /// Injectable for tests. Defaults to the shared run-loop timer the panel
    /// used before this extraction.
    var scheduleTicks: (@escaping () -> Void) -> () -> Void = { tick in
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { _ in tick() }
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }

    /// The eased curve duration in seconds.
    var duration: CFTimeInterval = 0.22

    private(set) var phase: Phase = .idle
    private(set) var animation = StatusPanelResizeAnimation()
    /// Number of times a measurement retargeted the live curve. Diagnostics only.
    private(set) var retargetCount = 0

    private var stopTicks: (() -> Void)?
    /// The presented height the panel should show right now (whole points).
    private(set) var presentedHeight: CGFloat = 0
    private(set) var targetHeight: CGFloat = 0
    /// The height of the last frame this coordinator wrote, so the settle step
    /// never rewrites a frame the final tick already placed.
    private var lastWrittenHeight: CGFloat?

    /// Computes the placed window frame for a presented height. The panel's
    /// implementation pins the edge it locked when the animation began.
    var place: ((CGFloat) -> NSRect)?
    /// Writes the frame. `display` is true only on the final tick.
    var writeFrame: ((NSRect, Bool) -> Void)?
    /// Pins / unpins the SwiftUI content to a fixed height while the window
    /// animates. `nil` restores normal fill-the-window layout.
    var pinContent: ((CGFloat?) -> Void)?
    /// Called once the curve has settled and the final frame was written.
    var didSettle: (() -> Void)?

    var isAnimating: Bool { phase != .idle }

    /// Whether a measured height pixel-aligns to the current target, so a
    /// redundant measurement must not restart the curve.
    func isAtTarget(_ height: CGFloat) -> Bool {
        abs(height - targetHeight) < 0.5
    }

    /// Starts or retargets the animation to `targetHeight`.
    ///
    /// The presented height always begins at the window's actual current height,
    /// so a toggle during a running animation continues from the live position
    /// rather than jumping to a stale start. The direction picks the phase.
    func retarget(to targetHeight: CGFloat, fromHeight: CGFloat) {
        let direction: StatusPanelResizeAnimation.Direction
        if abs(targetHeight - fromHeight) < 0.5 {
            direction = .settling
        } else if targetHeight > fromHeight {
            direction = .expanding
        } else {
            direction = .collapsing
        }

        if animation.isAnimating {
            retargetCount += 1
        }
        self.targetHeight = targetHeight
        self.presentedHeight = fromHeight
        animation.retarget(
            to: targetHeight,
            from: fromHeight,
            time: clock(),
            direction: direction
        )
        switch direction {
        case .expanding: phase = .expanding
        case .collapsing: phase = .collapsing
        case .settling: phase = .settling
        }

        // Freeze the content at its final height: SwiftUI lays it out once and
        // the growing window reveals it, instead of re-flowing the page at every
        // intermediate height.
        pinContent?(targetHeight)

        startTicksIfNeeded()
    }

    private func startTicksIfNeeded() {
        guard stopTicks == nil else { return }
        stopTicks = scheduleTicks { [weak self] in
            self?.tick()
        }
    }

    private func stopTicking() {
        stopTicks?()
        stopTicks = nil
    }

    private func tick() {
        guard animation.isAnimating else {
            settle()
            return
        }
        let result = animation.presentedHeight(at: clock(), duration: duration)
        presentedHeight = result.height
        if let place {
            let target = place(presentedHeight)
            // Only the final tick forces a synchronous display; intermediate
            // frames ride the normal run-loop draw.
            lastWrittenHeight = presentedHeight
            writeFrame?(target, result.finished)
        }
        if result.finished {
            settle()
        }
    }

    private func settle() {
        stopTicking()
        phase = .settling
        targetHeight = presentedHeight
        animation.finish()
        // Let the content fill the window again; at this point the pinned height
        // and the window height are the same, so nothing moves.
        pinContent?(nil)
        // The final tick already wrote the target frame; only write again when
        // this settle did not come from a tick (presented height not yet on screen).
        if let place, lastWrittenHeight != presentedHeight {
            lastWrittenHeight = presentedHeight
            writeFrame?(place(presentedHeight), false)
        }
        phase = .idle
        didSettle?()
    }

    /// Stops any running animation and drops all callbacks, so a closed panel
    /// leaves no timer or retained closures behind.
    func cancel() {
        stopTicking()
        animation.finish()
        phase = .idle
    }

    /// Marks the coordinator settled at `height` without an animation (used when
    /// the panel writes an immediate frame instead of animating).
    func markSettled(at height: CGFloat) {
        stopTicking()
        animation.finish()
        phase = .idle
        presentedHeight = height
        targetHeight = height
    }
}