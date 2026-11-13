import Foundation

struct PopupVolumeScrollAdjustment {
    private static let preciseVolumePerPoint = 0.002
    static let defaultWheelStep = 0.10
    private var pendingLines = 0.0
    private var lastTimestamp: TimeInterval?
    private var lastContext: String?
    private var lastWheelStep: Double?

    /// Shared entry for all three panel sliders; keeps their preferences and
    /// partial wheel packets on the same path without requiring a live NSEvent.
    @MainActor
    mutating func levelDelta(
        deltaY: Double,
        isPrecise: Bool,
        isDirectionInverted: Bool,
        timestamp: TimeInterval,
        target: PanelLevelScrollTarget,
        settings: SettingsStore
    ) -> Double? {
        let context: String
        switch target {
        case .volume: context = "volume"
        case .audioInput: context = "audioInput"
        case .brightness(let displayID): context = "brightness.\(displayID)"
        }
        return volumeDelta(
            deltaY: deltaY, isPrecise: isPrecise,
            isDirectionInverted: isDirectionInverted,
            usesNaturalScrolling: settings.popupVolumeNaturalScrolling,
            wheelStep: settings.popupScrollWheelStepPercent / 100,
            timestamp: timestamp, context: context
        )
    }

    mutating func volumeDelta(
        deltaY: Double,
        isPrecise: Bool,
        isDirectionInverted: Bool,
        usesNaturalScrolling: Bool,
        wheelStep: Double = PopupVolumeScrollAdjustment.defaultWheelStep,
        timestamp: TimeInterval = 0,
        context: String = "volume"
    ) -> Double? {
        guard deltaY.isFinite, deltaY != 0 else { return nil }
        let scrollUpDelta = usesNaturalScrolling
            ? (isDirectionInverted ? -deltaY : deltaY)
            : deltaY
        if isPrecise {
            pendingLines = 0
            lastTimestamp = nil
            return scrollUpDelta * Self.preciseVolumePerPoint
        }
        guard wheelStep.isFinite, wheelStep > 0 else { return nil }
        if lastContext != context || lastWheelStep != wheelStep
            || lastTimestamp.map({ timestamp < $0 || timestamp - $0 > PopupVolumeScrollSession.timeout }) == true
            || pendingLines * scrollUpDelta < 0 {
            pendingLines = 0
        }
        lastContext = context
        lastWheelStep = wheelStep
        lastTimestamp = timestamp
        // AppKit reports lines, not physical notches (commonly 1 or 3 per
        // event). Normalize a full packet to one step; retain sub-line packets
        // until they form a step. Coalesced hardware notches are not exposed.
        pendingLines += min(abs(scrollUpDelta), 1) * (scrollUpDelta > 0 ? 1 : -1)
        guard abs(pendingLines) >= 1 - 1e-9 else { return nil }
        let direction = pendingLines > 0 ? 1.0 : -1.0
        pendingLines -= direction
        if abs(pendingLines) < 1e-9 { pendingLines = 0 }
        return direction * wheelStep
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
