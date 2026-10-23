import CoreGraphics

/// Eagerly renders steady menu-bar frames once per icon state, then reuses the
/// resulting bitmaps for each clock tick.
///
/// The frames are stored as `CGImage`, which is exactly what the overlay layer
/// wants, so a tick never round-trips through `NSImage`. A set is keyed by the
/// phase-free icon state plus the heartbeat variant, and at most
/// `maximumVariants` sets stay resident: the normal `1` and the boosted `1.35`
/// heartbeat cycle both fit, while a scene change can never accumulate frame
/// sets. The clock only ever emits those two multipliers; anything else evicts
/// the least recently used set instead of growing the cache.
@MainActor
final class StatusBarChargingFrameCache {
    struct VariantKey: Equatable {
        let renderKey: StatusBarRenderKey
        let backingScale: CGFloat
        let heartbeatMultiplier: Double
    }

    private struct Variant {
        let key: VariantKey
        let frames: [CGImage]
    }

    static let steadyFrameCount = Int(
        (ChargingEffectTimeline.steadyCycleDuration
            * Double(ChargingEffectTimeline.framesPerSecond)).rounded()
    )
    static let maximumVariants = 2

    /// Most recently used first.
    private var variants: [Variant] = []
    /// A full set that failed to rasterize is not retried on every 20-Hz tick.
    /// `reset()` (a new static key) clears this so the next state retries.
    /// Compared linearly: there is at most one failed set at a time, and the
    /// render key is not `Hashable`.
    private var failedKey: VariantKey?

    /// Cumulative work counters: a steady tick must not move them.
    private(set) var rebuildCount = 0
    private(set) var rasterizedFrameCount = 0

    func needsFrames(
        for phase: ChargingEffectPhase,
        key renderKey: StatusBarRenderKey,
        backingScale: CGFloat
    ) -> Bool {
        guard isSupported(phase, backingScale: backingScale) else { return false }
        let nextKey = variantKey(for: phase, key: renderKey, backingScale: backingScale)
        return failedKey != nextKey && index(of: nextKey) == nil
    }

    func image(
        for phase: ChargingEffectPhase,
        key renderKey: StatusBarRenderKey,
        backingScale: CGFloat,
        renderFrame: (ChargingEffectPhase) -> CGImage?
    ) -> CGImage? {
        guard isSupported(phase, backingScale: backingScale) else { return nil }

        let nextKey = variantKey(for: phase, key: renderKey, backingScale: backingScale)
        guard failedKey != nextKey else { return nil }
        if let index = index(of: nextKey) {
            let variant = variants.remove(at: index)
            variants.insert(variant, at: 0)
            return variant.frames[phase.step]
        }

        var frames: [CGImage] = []
        frames.reserveCapacity(Self.steadyFrameCount)
        for step in 0..<Self.steadyFrameCount {
            let framePhase = ChargingEffectPhase(
                step: step,
                stepsPerCycle: Self.steadyFrameCount,
                kind: .steady,
                heartbeatMultiplier: phase.heartbeatMultiplier
            )
            guard let frame = renderFrame(framePhase) else {
                failedKey = nextKey
                return nil
            }
            frames.append(frame)
        }

        variants.insert(Variant(key: nextKey, frames: frames), at: 0)
        if variants.count > Self.maximumVariants {
            variants.removeLast(variants.count - Self.maximumVariants)
        }
        rebuildCount += 1
        rasterizedFrameCount += frames.count
        return frames[phase.step]
    }

    /// Frames in the most recently used set, which is what the caller is drawing.
    var frameCount: Int { variants.first?.frames.count ?? 0 }

    /// How many frame sets are resident, bounded by `maximumVariants`.
    var variantCount: Int { variants.count }

    func reset() {
        variants.removeAll(keepingCapacity: false)
        failedKey = nil
    }

    func trimForMemoryPressure() {
        if variants.count > 1 { variants.removeLast(variants.count - 1) }
    }

    private func variantKey(
        for phase: ChargingEffectPhase,
        key renderKey: StatusBarRenderKey,
        backingScale: CGFloat
    ) -> VariantKey {
        VariantKey(
            renderKey: StatusBarRenderKey(
                scene: renderKey.scene,
                iconSize: renderKey.iconSize,
                backingScale: renderKey.backingScale,
                appearanceName: renderKey.appearanceName,
                phase: nil
            ),
            backingScale: backingScale,
            heartbeatMultiplier: phase.heartbeatMultiplier
        )
    }

    private func index(of key: VariantKey) -> Int? {
        variants.firstIndex { $0.key == key && $0.frames.count == Self.steadyFrameCount }
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
