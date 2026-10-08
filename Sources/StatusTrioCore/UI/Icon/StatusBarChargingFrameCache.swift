import AppKit

/// Eagerly renders steady menu-bar frames once per icon state, then reuses the
/// resulting bitmap-backed images for each clock tick.
@MainActor
final class StatusBarChargingFrameCache {
    private struct FrameSetKey: Equatable {
        let renderKey: StatusBarRenderKey
        let backingScale: CGFloat
        let heartbeatMultiplier: Double

        init(
            renderKey: StatusBarRenderKey,
            backingScale: CGFloat,
            heartbeatMultiplier: Double
        ) {
            self.renderKey = StatusBarRenderKey(
                scene: renderKey.scene,
                iconSize: renderKey.iconSize,
                backingScale: renderKey.backingScale,
                appearanceName: renderKey.appearanceName,
                phase: nil
            )
            self.backingScale = backingScale
            self.heartbeatMultiplier = heartbeatMultiplier
        }
    }

    private static let steadyFrameCount = Int(
        (ChargingEffectTimeline.steadyCycleDuration
            * Double(ChargingEffectTimeline.framesPerSecond)).rounded()
    )

    private var key: FrameSetKey?
    private var frames: [NSImage] = []

    func needsFrames(
        for phase: ChargingEffectPhase,
        key renderKey: StatusBarRenderKey,
        backingScale: CGFloat
    ) -> Bool {
        guard isSupported(phase, backingScale: backingScale) else { return false }
        let nextKey = FrameSetKey(
            renderKey: renderKey,
            backingScale: backingScale,
            heartbeatMultiplier: phase.heartbeatMultiplier
        )
        return key != nextKey || frames.count != Self.steadyFrameCount
    }

    func image(
        for phase: ChargingEffectPhase,
        key renderKey: StatusBarRenderKey,
        backingScale: CGFloat,
        renderFrame: (ChargingEffectPhase) -> NSImage?
    ) -> NSImage? {
        guard isSupported(phase, backingScale: backingScale) else { return nil }

        let nextKey = FrameSetKey(
            renderKey: renderKey,
            backingScale: backingScale,
            heartbeatMultiplier: phase.heartbeatMultiplier
        )
        if key != nextKey || frames.count != Self.steadyFrameCount {
            var newFrames: [NSImage] = []
            newFrames.reserveCapacity(Self.steadyFrameCount)
            for step in 0..<Self.steadyFrameCount {
                let framePhase = ChargingEffectPhase(
                    step: step,
                    stepsPerCycle: Self.steadyFrameCount,
                    kind: .steady,
                    heartbeatMultiplier: phase.heartbeatMultiplier
                )
                guard let image = renderFrame(framePhase) else {
                    reset()
                    return nil
                }
                newFrames.append(image)
            }
            key = nextKey
            frames = newFrames
        }

        return frames[phase.step]
    }

    var frameCount: Int { frames.count }

    func reset() {
        key = nil
        frames.removeAll(keepingCapacity: false)
    }

    private func isSupported(_ phase: ChargingEffectPhase, backingScale: CGFloat) -> Bool {
        phase.kind == .steady
            && phase.stepsPerCycle == Self.steadyFrameCount
            && (0..<Self.steadyFrameCount).contains(phase.step)
            && phase.heartbeatMultiplier.isFinite
            && phase.heartbeatMultiplier >= 0
            && backingScale.isFinite
            && backingScale > 0
    }
}
