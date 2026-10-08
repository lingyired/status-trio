enum RingLayout: Equatable, Hashable, Sendable {
    case standard
    case leftRight
}

enum RingSegmentPosition: Equatable, Hashable, Sendable {
    case left
    case right
}

enum RingGapStyle: Equatable, Hashable, Sendable {
    case closed
    case indicator
    case value
}

enum RingAccessoryState: Equatable, Hashable, Sendable {
    case symbol(IconSymbolState)
    case text(IconTextState)
}

struct RingSegmentState: Equatable, Hashable, Sendable {
    let progress: Double
    let color: IconColorRole
    let position: RingSegmentPosition?

    init(progress: Double, color: IconColorRole, position: RingSegmentPosition? = nil) {
        self.progress = Self.normalizedProgress(progress)
        self.color = color
        self.position = position
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
    let layout: RingLayout
    let isPartial: Bool
    let gap: RingGapStyle
    let accessory: RingAccessoryState?
    let effect: RingEffectState?
    let strokeScale: Double
    let inactiveColor: IconColorRole

    init(
        segments: [RingSegmentState],
        gap: RingGapStyle,
        layout: RingLayout = .standard,
        isPartial: Bool = false,
        accessory: RingAccessoryState? = nil,
        effect: RingEffectState? = nil,
        strokeScale: Double = 1.25,
        inactiveColor: IconColorRole = .inactive
    ) {
        self.segments = segments
        self.layout = layout
        self.isPartial = isPartial
        self.gap = gap
        self.accessory = accessory
        self.effect = effect
        self.strokeScale = Self.normalizedStrokeScale(strokeScale)
        self.inactiveColor = inactiveColor
    }

    static func normalizedStrokeScale(_ scale: Double) -> Double {
        guard scale.isFinite else { return 1.25 }
        return min(2.5, max(0.5, scale))
    }
}
