import Foundation

struct IconPreviewCenterIdentity: Equatable, Hashable {
    let source: String
    let target: String
    let style: String

    static func make(configuration: IconConfigurationV1, selectedBluetoothAddress: String?) -> Self {
        let selection = configuration.composition.center
        let sources = [selection.primary.rawValue, selection.fallback?.rawValue ?? "none"].joined(separator: "→")
        let usesSelectedDevice = [selection.primary, selection.fallback].compactMap { $0 }
            .contains(.connectedBluetoothDevice)
        let target = usesSelectedDevice
            ? (selectedBluetoothAddress.map { BluetoothBatteryReader.normalizedAddress($0) } ?? "current-audio-output")
            : "configured-source"
        let symbolOverride = configuration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride ?? "automatic"
        // Color, size, network state, battery digits, and live system symbol choices update directly.
        return Self(source: sources, target: target, style: "bluetooth-symbol:\(symbolOverride)")
    }
}

struct IconPreviewTransitionState {
    static let duration: TimeInterval = 0.22
    static let reduceMotionDuration: TimeInterval = 0.08

    private(set) var outgoingCenter: CenterState?
    private(set) var startedAt: Date?
    private(set) var generation: UInt64 = 0
    private(set) var usesReduceMotion = false

    var activeDuration: TimeInterval {
        usesReduceMotion ? Self.reduceMotionDuration : Self.duration
    }

    mutating func begin(
        from old: CenterState?,
        oldIdentity: IconPreviewCenterIdentity?,
        to newIdentity: IconPreviewCenterIdentity?,
        reduceMotion: Bool,
        now: Date
    ) {
        guard let old, let oldIdentity, let newIdentity, oldIdentity != newIdentity else {
            reset()
            return
        }
        generation &+= 1
        outgoingCenter = old
        startedAt = now
        usesReduceMotion = reduceMotion
    }

    func progress(at date: Date) -> Double {
        guard let startedAt else { return 1 }
        return min(1, max(0, date.timeIntervalSince(startedAt) / activeDuration))
    }

    func isActive(at date: Date) -> Bool {
        guard outgoingCenter != nil, let startedAt else { return false }
        return date.timeIntervalSince(startedAt) < activeDuration
    }

    mutating func restartAsReduceMotionFade(now: Date) {
        guard outgoingCenter != nil else { return }
        generation &+= 1
        startedAt = now
        usesReduceMotion = true
    }

    mutating func clear(generation expected: UInt64) {
        guard generation == expected else { return }
        reset()
    }

    mutating func reset() {
        outgoingCenter = nil
        startedAt = nil
        usesReduceMotion = false
        generation &+= 1
    }
}

struct IconPreviewTransitionDriver {
    private(set) var transition = IconPreviewTransitionState()
    private(set) var latestCenter: CenterState?
    private(set) var identity: IconPreviewCenterIdentity?

    mutating func setInitial(center: CenterState?, identity: IconPreviewCenterIdentity) {
        latestCenter = center
        self.identity = identity
    }

    mutating func update(center: CenterState?, identity newIdentity: IconPreviewCenterIdentity,
                         reduceMotion: Bool, now: Date) {
        if let identity, identity != newIdentity {
            transition.begin(from: latestCenter, oldIdentity: identity, to: newIdentity,
                             reduceMotion: reduceMotion, now: now)
        } else if identity == nil {
            transition.reset()
        }
        latestCenter = center
        identity = newIdentity
    }

    mutating func setReduceMotion(_ reduceMotion: Bool, now: Date) {
        if reduceMotion { transition.restartAsReduceMotionFade(now: now) }
    }

    mutating func clear(generation: UInt64) {
        transition.clear(generation: generation)
    }

    mutating func reset() {
        transition.reset()
        latestCenter = nil
        identity = nil
    }
}
