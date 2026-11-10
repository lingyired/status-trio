import Foundation

struct PopupVolumeScrollAdjustment {
    private static let preciseVolumePerPoint = 0.002
    static let discreteVolumePerLine = 0.02

    /// Volume step for one mouse-wheel notch. A physical wheel loses the
    /// trackpad's continuous feel and only fires discrete lines, so the
    /// per-point trackpad constant leaves it moving ~2% a notch — many turns
    /// to cross the slider. Matching the system volume keys' 1/16 increment
    /// (~6%) keeps the wheel snappy without changing the smooth trackpad mapping.
    static let volumeWheelStep = 1.0 / 16.0

    func volumeDelta(
        deltaY: Double,
        isPrecise: Bool,
        isDirectionInverted: Bool,
        usesNaturalScrolling: Bool,
        wheelStep: Double = PopupVolumeScrollAdjustment.discreteVolumePerLine
    ) -> Double? {
        guard deltaY.isFinite, deltaY != 0 else { return nil }

        let volumePerUnit = isPrecise
            ? Self.preciseVolumePerPoint
            : wheelStep
        let scrollUpDelta = usesNaturalScrolling
            ? (isDirectionInverted ? -deltaY : deltaY)
            : deltaY
        return scrollUpDelta * volumePerUnit
    }
}

struct PopupVolumeScrollSession {
    static let timeout: TimeInterval = 0.75

    private var identity: VolumeControlInteractionIdentity?
    private var targetScalar: Double?
    private var lastTimestamp: TimeInterval?
    private var requestedUnmute = false

    mutating func scalar(
        at timestamp: TimeInterval,
        identity: VolumeControlInteractionIdentity,
        fallback: Double?
    ) -> Double? {
        if self.identity != identity {
            reset()
            self.identity = identity
        }
        if let lastTimestamp,
           timestamp < lastTimestamp
            || timestamp - lastTimestamp > Self.timeout {
            reset()
        }
        self.lastTimestamp = timestamp

        if let targetScalar {
            return targetScalar
        }
        guard let fallback, fallback.isFinite else { return nil }

        let clampedScalar = Self.clamp(fallback)
        targetScalar = clampedScalar
        return clampedScalar
    }

    mutating func applying(delta: Double, to scalar: Double) -> Double {
        let adjustedScalar = Self.clamp(scalar + delta)
        targetScalar = adjustedScalar
        return adjustedScalar
    }

    mutating func shouldUnmute(
        in state: VolumePanelState,
        isIncreasing: Bool
    ) -> Bool {
        guard identity == state.interactionIdentity,
              state.canMute,
              state.muted,
              isIncreasing,
              !requestedUnmute else {
            return false
        }
        requestedUnmute = true
        return true
    }

    mutating func reset() {
        identity = nil
        targetScalar = nil
        lastTimestamp = nil
        requestedUnmute = false
    }

    private static func clamp(_ scalar: Double) -> Double {
        min(1, max(0, scalar))
    }
}

/// Accumulates wheel deltas for one display's brightness slider so a burst of
/// scroll events moves a stable target instead of re-rounding from a stale
/// system echo on every event.
struct PopupLevelScrollSession {
    static let timeout: TimeInterval = 0.75

    private var displayID: String?
    private var targetScalar: Double?
    private var lastTimestamp: TimeInterval?

    mutating func scalar(
        at timestamp: TimeInterval,
        displayID: String,
        fallback: Double?
    ) -> Double? {
        if self.displayID != displayID {
            reset()
            self.displayID = displayID
        }
        if let lastTimestamp,
           timestamp < lastTimestamp
            || timestamp - lastTimestamp > Self.timeout {
            reset()
        }
        self.lastTimestamp = timestamp

        if let targetScalar {
            return targetScalar
        }
        guard let fallback, fallback.isFinite else { return nil }

        let clamped = Self.clamp(fallback)
        targetScalar = clamped
        return clamped
    }

    mutating func applying(delta: Double, to scalar: Double) -> Double {
        let adjustedScalar = Self.clamp(scalar + delta)
        targetScalar = adjustedScalar
        return adjustedScalar
    }

    mutating func reset() {
        displayID = nil
        targetScalar = nil
        lastTimestamp = nil
    }

    private static func clamp(_ scalar: Double) -> Double {
        min(1, max(0, scalar))
    }
}
