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
    let boltUsesArcColor: Bool
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

        let boltScale: Double
        let boltUsesArcColor: Bool
        if hasTopGap {
            let gapStart = StatusIconGeometry.lastVisibleProgress(
                forProgress: 0.5,
                hasTopGap: true,
                topGapWidth: topGapWidth
            )
            let gapEnd = 1 - gapStart
            if endpoint >= gapEnd, head > gapStart, head < gapEnd {
                let pulse = boltHeartbeatPulse(at: (head - gapStart) / (gapEnd - gapStart))
                boltScale = 1 + 0.3 * pulse
                boltUsesArcColor = pulse >= 0.75
            } else {
                boltScale = 1
                boltUsesArcColor = false
            }
        } else {
            boltScale = 1
            boltUsesArcColor = false
        }

        let minimumTailFill = minimumVisibleFillRatio * visibleArcLength
        let tailLength = min(
            tailRatio * visibleArcLength,
            maximumTailToFillRatio * visibleFill
        )
        let tailRange: ClosedRange<Double>?
        if visibleFill >= minimumTailFill, head > 0, tailLength > 0 {
            let visibleHead = StatusIconGeometry.visibleFraction(
                forProgress: head,
                hasTopGap: hasTopGap,
                topGapWidth: topGapWidth
            )
            let tailStart = StatusIconGeometry.progress(
                forVisibleFraction: max(0, visibleHead - tailLength),
                hasTopGap: hasTopGap,
                topGapWidth: topGapWidth
            )
            let tailEnd = StatusIconGeometry.progress(
                forVisibleFraction: visibleHead,
                hasTopGap: hasTopGap,
                topGapWidth: topGapWidth
            )
            tailRange = tailStart...tailEnd
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
            boltUsesArcColor: boltUsesArcColor
        )
    }

    private static func boltHeartbeatPulse(at progress: Double) -> Double {
        // Two peaks follow Animate.css heartBeat's 14/28/42/70% rhythm.
        if progress < 0.14 { return progress / 0.14 }
        if progress < 0.28 { return (0.28 - progress) / 0.14 }
        if progress < 0.42 { return (progress - 0.28) / 0.14 }
        if progress < 0.70 { return (0.70 - progress) / 0.28 }
        return 0
    }
}
