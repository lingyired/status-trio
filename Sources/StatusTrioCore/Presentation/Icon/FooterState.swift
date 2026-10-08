struct DotsState: Equatable, Hashable, Sendable {
    let count: Int
    let activeCount: Int
    let color: IconColorRole
    let strokeScale: Double

    init(count: Int, activeCount: Int, color: IconColorRole, strokeScale: Double = 1.25) {
        let normalizedCount = max(0, count)
        self.count = normalizedCount
        self.activeCount = min(normalizedCount, max(0, activeCount))
        self.color = color
        self.strokeScale = OuterRingState.normalizedStrokeScale(strokeScale)
    }
}

struct ArcState: Equatable, Hashable, Sendable {
    let progress: Double
    let color: IconColorRole
    let strokeScale: Double

    init(progress: Double, color: IconColorRole, strokeScale: Double = 1.25) {
        self.progress = RingSegmentState.normalizedProgress(progress)
        self.color = color
        self.strokeScale = OuterRingState.normalizedStrokeScale(strokeScale)
    }
}

enum FooterState: Equatable, Hashable, Sendable {
    case dots(DotsState)
    case arc(ArcState)
}
