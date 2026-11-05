import AppKit
import Combine
import QuartzCore

/// The disclosure container's sole height driver. SwiftUI lays out this height;
/// the panel follows those measurements without another geometry animation.
@MainActor
final class StatusPanelResizeCoordinator: ObservableObject {
    enum Phase: String, Equatable {
        case idle, expanding, collapsing, settling
    }

    var clock: () -> CFTimeInterval = { CACurrentMediaTime() }
    var scheduleTicks: (@escaping @MainActor @Sendable () -> Void) -> () -> Void = { tick in
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }

    var duration: CFTimeInterval = 0.22
    var pixelScale: CGFloat = 1 {
        didSet {
            guard pixelScale != oldValue else { return }
            if isAnimating {
                retarget(to: targetHeight, fromHeight: presentedHeight)
            } else {
                markSettled(at: presentedHeight)
            }
        }
    }
    private(set) var phase: Phase = .idle
    private(set) var animation = StatusPanelResizeAnimation()
    private(set) var retargetCount = 0
    @Published private(set) var presentedHeight: CGFloat = 0
    private(set) var targetHeight: CGFloat = 0
    private var stopTicks: (() -> Void)?
    private var presentedTime: CFTimeInterval?

    var isAnimating: Bool { phase != .idle }

    func isAtTarget(_ height: CGFloat) -> Bool {
        pixelAligned(height) == targetHeight
    }

    private func pixelAligned(_ height: CGFloat) -> CGFloat {
        let scale = max(pixelScale, 1)
        return (height * scale).rounded() / scale
    }

    func retarget(to height: CGFloat, fromHeight: CGFloat) {
        let target = pixelAligned(height)
        guard target != targetHeight || !isAnimating else { return }
        if animation.isAnimating { retargetCount += 1 }
        targetHeight = target
        publish(fromHeight)
        // A reversal back to the displayed height cancels pending movement,
        // even if no new frame would otherwise be needed.
        guard target != fromHeight else {
            markSettled(at: target)
            return
        }
        let direction: StatusPanelResizeAnimation.Direction = target > fromHeight ? .expanding : .collapsing
        let now = clock()
        // Keep position and velocity from the same displayed sample. A delayed
        // run-loop tick must not combine an old position with a future velocity.
        let velocity = animation.velocity(at: presentedTime ?? now)
        animation.retarget(to: target, from: fromHeight, time: now,
                           direction: direction, duration: duration, velocity: velocity)
        presentedTime = now
        phase = target > fromHeight ? .expanding : .collapsing
        if stopTicks == nil {
            stopTicks = scheduleTicks { [weak self] in self?.tick() }
        }
    }

    private func tick() {
        guard animation.isAnimating else { return }
        let now = clock()
        let result = animation.presentedHeight(at: now)
        presentedTime = now
        publish(pixelAligned(result.height))
        if result.finished { markSettled(at: targetHeight) }
    }

    private func publish(_ height: CGFloat) {
        guard height != presentedHeight else { return }
        presentedHeight = height
    }

    /// Stop on disappearance; there is no content pin or deferred unload to
    /// release. The retained view can restart from its actual displayed height.
    func cancel() {
        stopTicks?()
        stopTicks = nil
        animation.finish()
        presentedTime = nil
        targetHeight = presentedHeight
        phase = .idle
    }

    func markSettled(at height: CGFloat) {
        cancel()
        let height = pixelAligned(height)
        targetHeight = height
        publish(height)
    }
}
