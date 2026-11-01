enum RingGapStyle: Equatable, Hashable, Sendable {
    case closed
    case indicator
    case value
}

/// How a top gap with content treats progress (#205).
enum GapProgressMode: Equatable, Hashable, Sendable {
    /// The historical look: the gap occupies its share of the ring, so progress
    /// falling inside it collapses onto the gap's leading edge.
    case absorbed
    /// The visible arc carries the whole 0–100% scale: the left visible half is
    /// 0–50% and the right visible half is 50–100%, so the gap no longer hides
    /// any progress.
    case split
}

enum RingAccessoryState: Equatable, Hashable, Sendable {
    case symbol(IconSymbolState)
    case text(IconTextState)
}

struct RingSegmentState: Equatable, Hashable, Sendable {
    let progress: Double
    let color: IconColorRole

    init(progress: Double, color: IconColorRole) {
        self.progress = Self.normalizedProgress(progress)
        self.color = color
    }

    static func normalizedProgress(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(1, max(0, progress))
    }
}

struct RingEffectState: Equatable, Hashable, Sendable {
    let pulsesAccessory: Bool
    let tintsAccessory: Bool
}

struct OuterRingState: Equatable, Hashable, Sendable {
    let segments: [RingSegmentState]
    let gap: RingGapStyle
    let accessory: RingAccessoryState?
    let effect: RingEffectState?
    let strokeScale: Double
    /// Whether a top gap absorbs progress or the visible arc is split across it.
    let gapProgressMode: GapProgressMode

    init(
        segments: [RingSegmentState],
        gap: RingGapStyle,
        accessory: RingAccessoryState? = nil,
        effect: RingEffectState? = nil,
        strokeScale: Double = 1.25,
        gapProgressMode: GapProgressMode = .absorbed
    ) {
        self.segments = segments
        self.gap = gap
        self.accessory = accessory
        self.effect = effect
        self.strokeScale = Self.normalizedStrokeScale(strokeScale)
        self.gapProgressMode = gapProgressMode
    }

    static func normalizedStrokeScale(_ scale: Double) -> Double {
        guard scale.isFinite else { return 1.25 }
        return min(2.5, max(0.5, scale))
    }
}
