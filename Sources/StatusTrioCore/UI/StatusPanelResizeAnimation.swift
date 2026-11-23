import QuartzCore

/// One critically damped position/velocity trajectory. Retargeting carries
/// momentum; pixel alignment belongs to the window writer, not this state.
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
        var startVelocity: CGFloat
        var response: CFTimeInterval

        var delta: CGFloat { targetHeight - startHeight }
    }

    private(set) var snapshot: Snapshot?
    var isAnimating: Bool { snapshot != nil }

    mutating func retarget(
        to targetHeight: CGFloat,
        from fromHeight: CGFloat,
        time: CFTimeInterval,
        direction: Direction,
        duration: CFTimeInterval = 0.22,
        velocity: CGFloat? = nil
    ) {
        let velocity = velocity ?? state(at: time).velocity
        snapshot = Snapshot(
            startHeight: fromHeight, targetHeight: targetHeight,
            startTime: time, direction: direction,
            startVelocity: velocity, response: max(duration, 0.001)
        )
    }

    mutating func finish() { snapshot = nil }

    private func state(at time: CFTimeInterval) -> (height: CGFloat, velocity: CGFloat, finished: Bool) {
        guard let snapshot else { return (0, 0, true) }
        let elapsed = CGFloat(max(0, time - snapshot.startTime))
        let omega = CGFloat(10 / snapshot.response)
        let offset = snapshot.startHeight - snapshot.targetHeight
        let coefficient = snapshot.startVelocity + omega * offset
        // If a nearby new target lies inside the old momentum's stopping
        // distance, stop on first arrival rather than crossing and ringing.
        if offset * coefficient < 0, elapsed >= -offset / coefficient {
            return (snapshot.targetHeight, 0, true)
        }
        let decay = exp(-omega * elapsed)
        let displacement = (offset + coefficient * elapsed) * decay
        let velocity = (snapshot.startVelocity - omega * coefficient * elapsed) * decay
        let finished = abs(displacement) < 0.01 && abs(velocity) < 0.5
        return (finished ? snapshot.targetHeight : snapshot.targetHeight + displacement,
                finished ? 0 : velocity, finished)
    }

    func velocity(at time: CFTimeInterval) -> CGFloat { state(at: time).velocity }

    func presentedHeight(at time: CFTimeInterval) -> (height: CGFloat, finished: Bool) {
        let value = state(at: time)
        return (value.height, value.finished)
    }
}
