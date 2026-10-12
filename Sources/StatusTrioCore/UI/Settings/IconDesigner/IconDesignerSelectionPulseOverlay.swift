import SwiftUI

enum IconDesignerSelectionHighlight {
    static func part(for slot: IconSlot) -> IconGuidePart {
        switch slot {
        case .outerRing: .battery
        case .center: .network
        case .footer: .volume
        }
    }
}

struct IconDesignerSelectionPulseTiming {
    static let period: TimeInterval = 4
    static let fadeDuration: TimeInterval = 0.3
    static let holdDuration: TimeInterval = 0.2
    static let interPulseDelay: TimeInterval = 0.2
    static let fadeOutStartsAt = fadeDuration + holdDuration
    static let visibleDuration = fadeOutStartsAt + fadeDuration
    static let pulseStartOffsets: [TimeInterval] = [0, visibleDuration + interPulseDelay]
    static let secondFadeOutStartsAt = pulseStartOffsets[1] + fadeOutStartsAt
    static let cycleVisibleDuration = pulseStartOffsets[1] + visibleDuration
    /// Delay after the second pulse fully fades until the next four-second cycle.
    static let remainingPeriod = period - cycleVisibleDuration
    static let peakOpacity = 0.24
    static let reducedMotionOpacity = 0.12

    static func isVisible(at elapsed: TimeInterval) -> Bool {
        guard elapsed >= 0 else { return false }
        let position = elapsed.truncatingRemainder(dividingBy: period)
        return pulseStartOffsets.contains { start in
            position >= start && position < start + visibleDuration
        }
    }
}

struct IconDesignerSelectionPulseTaskKey: Hashable {
    let slot: IconSlot?
    let reduceMotion: Bool
}

struct IconDesignerSelectionPulseOverlay: View {
    let slot: IconSlot
    let volumeDisplayStyle: VolumeDisplayStyle
    let size: CGFloat
    let lineWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    private var taskKey: IconDesignerSelectionPulseTaskKey {
        IconDesignerSelectionPulseTaskKey(slot: slot, reduceMotion: reduceMotion)
    }

    var body: some View {
        StatusIconPartHighlight(
            part: IconDesignerSelectionHighlight.part(for: slot),
            volumeDisplayStyle: volumeDisplayStyle,
            lineWidth: lineWidth,
            tint: .blue
        )
        .frame(width: size, height: size)
        .opacity(
            reduceMotion
                ? IconDesignerSelectionPulseTiming.reducedMotionOpacity
                : (isPulsing ? IconDesignerSelectionPulseTiming.peakOpacity : 0)
        )
        .animation(
            reduceMotion ? .linear(duration: 0.1) : .easeInOut(duration: IconDesignerSelectionPulseTiming.fadeDuration),
            value: isPulsing
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: taskKey) {
            isPulsing = false
            guard !reduceMotion else { return }

            while !Task.isCancelled {
                var previousPulseEnd: TimeInterval = 0
                for (index, pulseStart) in IconDesignerSelectionPulseTiming.pulseStartOffsets.enumerated() {
                    do {
                        if index > 0 {
                            let delayUntilPulse = pulseStart - previousPulseEnd
                            try await Task.sleep(for: .seconds(delayUntilPulse))
                            guard !Task.isCancelled else { return }
                        }
                        isPulsing = true
                        try await Task.sleep(for: .seconds(IconDesignerSelectionPulseTiming.fadeOutStartsAt))
                        guard !Task.isCancelled else { return }
                        isPulsing = false
                        try await Task.sleep(for: .seconds(IconDesignerSelectionPulseTiming.fadeDuration))
                        guard !Task.isCancelled else { return }
                        previousPulseEnd = pulseStart + IconDesignerSelectionPulseTiming.visibleDuration
                    } catch {
                        // Slot changes and view disappearance cancel this task.
                        return
                    }
                }

                do {
                    try await Task.sleep(for: .seconds(IconDesignerSelectionPulseTiming.remainingPeriod))
                    guard !Task.isCancelled else { return }
                } catch {
                    // Slot changes and view disappearance cancel this task.
                    return
                }
            }
        }
        .onDisappear {
            isPulsing = false
        }
        .id(taskKey)
    }
}
