import Foundation

struct ChargingEffectFrame: Equatable, Sendable {
    let tailRange: ClosedRange<Double>?
    let headProgress: Double
    let headIsVisible: Bool
    let tailAlpha: Double
    let beadAlpha: Double
    let heartbeatAlpha: Double
    let heartbeatScale: Double
    let boltScale: Double
    let boltArcColorAmount: Double
}

enum ChargingEffectPolicy {
    static let tailRatio = 0.32
    static let maximumTailToFillRatio = 0.78
    static let minimumVisibleFillRatio = 0.25
    static let heartbeatDuration: TimeInterval = 0.25

    static func shouldAnimate(
        battery: BatteryStatus,
        enabled: Bool,
        reduceMotion: Bool,
        displayAsleep: Bool
    ) -> Bool {
        battery.isPresent
            && battery.isCharging
            && !battery.isCharged
            && enabled
            && !reduceMotion
            && !displayAsleep
    }

    static func frame(
        progress: Double,
        phase: ChargingEffectPhase,
        hasTopGap: Bool,
        topGapWidth: CGFloat = StatusIconGeometry.batteryChargingBoltTopGapWidth
    ) -> ChargingEffectFrame? {
        guard progress.isFinite,
              phase.stepsPerCycle > 0,
              phase.step >= 0,
              phase.step < phase.stepsPerCycle,
              phase.heartbeatMultiplier.isFinite,
              phase.heartbeatMultiplier >= 0 else {
            return nil
        }

        let batteryProgress = min(1, max(0, progress))
        let visibleArcLength = StatusIconGeometry.visibleFraction(
            forProgress: 1,
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        )
        let visibleFill = StatusIconGeometry.visibleFraction(
            forProgress: batteryProgress,
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        )
        let endpoint = StatusIconGeometry.lastVisibleProgress(
            forProgress: batteryProgress,
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        )

        let heartbeatSteps = min(
            phase.stepsPerCycle,
            max(1, Int((heartbeatDuration * Double(ChargingEffectTimeline.framesPerSecond)).rounded()))
        )
        let travelSteps = max(1, phase.stepsPerCycle - heartbeatSteps)
        let travelFraction = min(1, Double(phase.step) / Double(travelSteps))
        let head = endpoint * travelFraction
        let heartbeatProgress: Double
        if phase.step >= travelSteps {
            let pulseStep = phase.step - travelSteps
            heartbeatProgress = heartbeatSteps <= 1
                ? 0
                : Double(pulseStep) / Double(heartbeatSteps - 1)
        } else {
            heartbeatProgress = 0
        }

        let boundedHeartbeatProgress = min(1, max(0, heartbeatProgress))
        let pulse = boundedHeartbeatProgress == 0 || boundedHeartbeatProgress == 1
            ? 0
            : sin(.pi * boundedHeartbeatProgress)
        let multiplier = min(1.35, phase.heartbeatMultiplier)
        let heartbeatAlpha = pulse * multiplier
        let isHeartbeatStep = phase.step >= travelSteps
        let heartbeatScale = isHeartbeatStep
            ? (1 + 0.55 * (1 - pulse)) * multiplier
            : 1
        let headVisible = abs(
            StatusIconGeometry.lastVisibleProgress(
                forProgress: head,
                hasTopGap: hasTopGap,
                topGapWidth: topGapWidth
            ) - head
        ) < 1e-9

        // The top gap occupies the progress range [topGapStart, topGapEnd]
        // (the two are symmetric around 0.5). Both the bolt-pulse transition and
        // the tail clamp below refer to these bounds.
        let topGapStart = hasTopGap
            ? StatusIconGeometry.lastVisibleProgress(
                forProgress: 0.5,
                hasTopGap: true,
                topGapWidth: topGapWidth
            )
            : 0
        let topGapEnd = hasTopGap ? 1 - topGapStart : 0

        let boltScale: Double
        let boltArcColorAmount: Double
        if hasTopGap {
            if endpoint >= topGapEnd, head > topGapStart, head < topGapEnd {
                let pulse = boltGapPulse(at: (head - topGapStart) / (topGapEnd - topGapStart))
                boltScale = 1 + 0.2 * pulse
                boltArcColorAmount = pulse
            } else {
                boltScale = 1
                boltArcColorAmount = 0
            }
        } else {
            boltScale = 1
            boltArcColorAmount = 0
        }

        let minimumTailFill = minimumVisibleFillRatio * visibleArcLength
        let tailLength = min(
            tailRatio * visibleArcLength,
            maximumTailToFillRatio * visibleFill
        )
        // The tail must only ever draw the visible side the head currently
        // sits on. When the head has advanced past the top gap, the unwrapped
        // tail range would reach back across the gap into the left arc; that
        // left sliver lingers as a flickering residue (#254). Clamp the tail to
        // the head's own visible side so it never spans the gap, and hide it
        // entirely while the head is inside the gap.
        let tailRange: ClosedRange<Double>?
        if visibleFill >= minimumTailFill, head > 0, tailLength > 0,
           !hasTopGap || head <= topGapStart || head >= topGapEnd {
            let visibleHead = StatusIconGeometry.visibleFraction(
                forProgress: head,
                hasTopGap: hasTopGap,
                topGapWidth: topGapWidth
            )
            let visibleTailStart = max(0, visibleHead - tailLength)
            let tailStart = StatusIconGeometry.progress(
                forVisibleFraction: visibleTailStart,
                hasTopGap: hasTopGap,
                topGapWidth: topGapWidth
            )
            let tailEnd = StatusIconGeometry.progress(
                forVisibleFraction: visibleHead,
                hasTopGap: hasTopGap,
                topGapWidth: topGapWidth
            )
            let sideStart = hasTopGap && head >= topGapEnd
                ? max(tailStart, topGapEnd) : tailStart
            // At the gap's exact right edge the inverse visible mapping selects
            // its left edge. No right-side tail has grown yet; never construct
            // a descending ClosedRange at this boundary.
            tailRange = tailEnd > sideStart ? sideStart...tailEnd : nil
        } else {
            tailRange = nil
        }

        return ChargingEffectFrame(
            tailRange: tailRange,
            headProgress: head,
            headIsVisible: headVisible,
            tailAlpha: tailRange == nil ? 0 : 1,
            beadAlpha: headVisible
                ? (isHeartbeatStep ? max(0, 1 - boundedHeartbeatProgress) : 1)
                : 0,
            heartbeatAlpha: heartbeatAlpha,
            heartbeatScale: heartbeatScale,
            boltScale: boltScale,
            boltArcColorAmount: boltArcColorAmount
        )
    }

    private static func boltGapPulse(at progress: Double) -> Double {
        sin(.pi * min(1, max(0, progress)))
    }
}
