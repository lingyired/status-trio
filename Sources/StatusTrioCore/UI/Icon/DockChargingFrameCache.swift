import CoreGraphics

/// Pre-renders the Dock charging animation's frames once per icon state and
/// reuses the bitmaps for every 20-Hz tick.
///
/// A frame is the effect's own raster — the slice of the tile that holds the
/// charging comet, heartbeat halo and bolt — so everything that does not
/// animate stays in the presenter's static base. A set is keyed by the
/// phase-free icon state plus the heartbeat variant, and at most
/// `maximumVariants` sets stay resident inside `maximumResidentBytes`: the
/// normal `1` and the boosted `1.35` heartbeat cycle both fit at the tile sizes
/// the Dock actually uses, while a scene, theme or tile-size change replaces
/// the set instead of accumulating one.
@MainActor
final class DockChargingFrameCache {
    struct VariantKey: Equatable {
        /// Phase-free, so a 20-Hz tick can never invalidate a set.
        let renderKey: DockChargingEffectKey
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
    /// Two sets at a 256-px tile are about 11 MiB together. The ceiling is what
    /// stops a much larger tile from holding two full-resolution sets.
    static let maximumResidentBytes = 24 * 1024 * 1024

    /// Most recently used first.
    private var variants: [Variant] = []
    /// A set that failed to rasterize is not retried on every 20-Hz tick.
    /// `reset()` (a new base key) clears this so the next state retries.
    private var failedKey: VariantKey?

    /// Cumulative work counters: a steady tick must not move them.
    private(set) var rebuildCount = 0
    private(set) var rasterizedFrameCount = 0
    /// Cache-owned pixel buffers plus the group currently being constructed.
    /// Does not include the presenter's current overlay or renderer scratch.
    private(set) var peakResidentByteCount = 0

    func needsFrames(for phase: ChargingEffectPhase, key renderKey: DockIconRenderKey) -> Bool {
        guard isSupported(phase, key: renderKey) else { return false }
        let nextKey = variantKey(for: phase, key: renderKey)
        return failedKey != nextKey && index(of: nextKey) == nil
    }

    func image(
        for phase: ChargingEffectPhase,
        key renderKey: DockIconRenderKey,
        renderFrame: (ChargingEffectPhase) -> CGImage?
    ) -> CGImage? {
        guard isSupported(phase, key: renderKey) else { return nil }

        let nextKey = variantKey(for: phase, key: renderKey)
        guard failedKey != nextKey else { return nil }
        if let index = index(of: nextKey) {
            let variant = variants.remove(at: index)
            variants.insert(variant, at: 0)
            noteSuccessfulIdentity(nextKey)
            return variant.frames[phase.step]
        }

        var frames: [CGImage] = []
        frames.reserveCapacity(Self.steadyFrameCount)
        // Retire obsolete scenes before building; the presenter keeps the
        // current frame alive until a replacement or static fallback is ready.
        variants.removeAll { $0.key.renderKey != nextKey.renderKey }
        var buildingBytes = 0
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
            let frameBytes = frame.bytesPerRow * frame.height
            peakResidentByteCount = max(peakResidentByteCount, residentByteCount + buildingBytes + frameBytes)
            if step == 0 {
                // One probe raster gives the actual row stride. Make room for
                // the remaining 35 BEFORE retaining two complete large groups.
                let projectedBytes = frameBytes * Self.steadyFrameCount
                while !variants.isEmpty && (
                    variants.count >= Self.maximumVariants
                        || residentByteCount + projectedBytes > Self.maximumResidentBytes
                ) {
                    variants.removeLast()
                }
            }
            frames.append(frame)
            buildingBytes += frameBytes
            peakResidentByteCount = max(peakResidentByteCount, residentByteCount + buildingBytes)
        }

        variants.insert(Variant(key: nextKey, frames: frames), at: 0)
        noteSuccessfulIdentity(nextKey)
        trim()
        rebuildCount += 1
        rasterizedFrameCount += frames.count
        return frames[phase.step]
    }

    /// Frames in the most recently used set, which is what the caller draws.
    var frameCount: Int { variants.first?.frames.count ?? 0 }

    /// How many frame sets are resident, bounded by `maximumVariants`.
    var variantCount: Int { variants.count }

    /// What the resident sets cost as raw pixels.
    var residentByteCount: Int {
        variants.reduce(0) { total, variant in
            total + Self.byteCount(of: variant.frames)
        }
    }

    func reset() {
        variants.removeAll(keepingCapacity: false)
        failedKey = nil
    }

    /// Keep the current group so pressure cannot trigger a 20-Hz rebuild loop.
    func trimForMemoryPressure() {
        if variants.count > 1 { variants.removeLast(variants.count - 1) }
    }

    private static func byteCount(of frames: [CGImage]) -> Int {
        frames.reduce(0) { $0 + $1.bytesPerRow * $1.height }
    }

    private func trim() {
        // One set is always kept: a set is indivisible, so the ceiling decides
        // how many stay resident — one for a 512-px tile, two at the 128-256 px
        // tiles the Dock actually draws.
        while variants.count > Self.maximumVariants
            || (variants.count > 1 && residentByteCount > Self.maximumResidentBytes) {
            variants.removeLast()
        }
    }

    private func variantKey(
        for phase: ChargingEffectPhase,
        key renderKey: DockIconRenderKey
    ) -> VariantKey {
        VariantKey(renderKey: DockChargingEffectKey(renderKey), heartbeatMultiplier: phase.heartbeatMultiplier)
    }

    private func index(of key: VariantKey) -> Int? {
        variants.firstIndex { $0.key == key && $0.frames.count == Self.steadyFrameCount }
    }

    private func noteSuccessfulIdentity(_ successfulKey: VariantKey) {
        guard let failedKey,
              failedKey.renderKey != successfulKey.renderKey
        else { return }
        self.failedKey = nil
    }

    private func isSupported(_ phase: ChargingEffectPhase, key renderKey: DockIconRenderKey) -> Bool {
        renderKey.scene.outerRing?.effect != nil
            && phase.kind == .steady
            && phase.stepsPerCycle == Self.steadyFrameCount
            && (0..<Self.steadyFrameCount).contains(phase.step)
            && phase.heartbeatMultiplier.isFinite
            && phase.heartbeatMultiplier >= 0
    }
}
