import Foundation

struct VolumeControlInteractionIdentity: Equatable, Sendable {
    let output: PanelAudioDeviceID?
    let configuration: ExternalVolumeConfiguration
    let transitionGeneration: UInt64

    init(
        output: PanelAudioDeviceID?,
        configuration: ExternalVolumeConfiguration,
        transitionGeneration: UInt64 = 0
    ) {
        self.output = output
        self.configuration = configuration
        self.transitionGeneration = transitionGeneration
    }
}

/// Owns the slider draft while keeping programmatic system reads separate from
/// user actions. The same production action closures serve both paths; only the
/// slider setter and a completed edit can emit.
struct VolumeControlInteraction {
    private(set) var value = 0.0
    private(set) var isEditing = false

    private let setVolume: (Double) -> Void
    private let finishVolume: () -> Void
    private var identity: VolumeControlInteractionIdentity?
    private var isInvalidated = true
    private var hasPendingUnmanagedWrite = false
    private var requiresFreshGesture = false
    private var hasReceivedValidState = false

    init(
        setVolume: @escaping (Double) -> Void,
        finishVolume: @escaping () -> Void
    ) {
        self.setVolume = setVolume
        self.finishVolume = finishVolume
    }

    mutating func receiveSystemState(
        identity: VolumeControlInteractionIdentity,
        scalar: Double?,
        canAdjust: Bool
    ) {
        let readableScalar = normalized(scalar)
        let canUseScalar = canAdjust && readableScalar != nil
        let identityChanged = self.identity != identity
        let wasPointerEditing = isEditing

        if identityChanged {
            self.identity = identity
            value = readableScalar ?? 0
            isEditing = false
            isInvalidated = !canUseScalar
            hasPendingUnmanagedWrite = false
            if wasPointerEditing && hasReceivedValidState {
                requiresFreshGesture = true
            }
            if canUseScalar {
                hasReceivedValidState = true
            }
            return
        }

        if !canUseScalar {
            value = readableScalar ?? 0
            isEditing = false
            isInvalidated = true
            hasPendingUnmanagedWrite = false
            if wasPointerEditing && hasReceivedValidState {
                requiresFreshGesture = true
            }
            return
        }

        self.identity = identity
        isInvalidated = false
        hasReceivedValidState = true
        if !isEditing, let readableScalar {
            value = readableScalar
            hasPendingUnmanagedWrite = false
        }
    }

    mutating func beginEditing() {
        guard !isInvalidated else { return }
        requiresFreshGesture = false
        isEditing = true
    }

    mutating func setSliderValue(
        _ newValue: Double,
        identity: VolumeControlInteractionIdentity,
        canAdjust: Bool
    ) {
        guard canAdjust,
              self.identity == identity,
              !requiresFreshGesture,
              newValue.isFinite
        else { return }

        let nextValue = min(1, max(0, newValue))
        isInvalidated = false
        if !isEditing {
            hasPendingUnmanagedWrite = true
        }
        guard nextValue != value else { return }
        value = nextValue
        setVolume(nextValue)
    }

    mutating func endEditing(identity: VolumeControlInteractionIdentity) {
        guard self.identity == identity else { return }
        if requiresFreshGesture {
            // Mouseup reports the current output identity after a transition.
            // Consume the stale pointer transaction without flushing its draft.
            requiresFreshGesture = false
            isEditing = false
            hasPendingUnmanagedWrite = false
            return
        }
        guard isEditing || hasPendingUnmanagedWrite,
              !isInvalidated
        else { return }
        isEditing = false
        hasPendingUnmanagedWrite = false
        finishVolume()
    }

    private func normalized(_ scalar: Double?) -> Double? {
        guard let scalar, scalar.isFinite else { return nil }
        return min(1, max(0, scalar))
    }
}
