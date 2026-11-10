import Foundation

struct BatteryIconOptions: Equatable, Hashable, Sendable {
    /// What the top gap shows while on battery (not on power) — the level
    /// percentage or nothing (#315).
    let onBatteryMarker: BatteryTopMarker
    /// What the top gap shows while charging — percentage / bolt / plug / nothing.
    let chargingMarker: BatteryTopMarker
    /// What the top gap shows while connected to power without charging.
    let connectedMarker: BatteryTopMarker
    /// The decorative marker on a battery-less Mac (plug / bolt / nothing).
    let noBatteryMarker: BatteryTopMarker
    let showsChargingEffect: Bool
    let showsChargingBoltHeartbeat: Bool
    /// When the top gap shows content (bolt, plug or percentage), draw the arc so
    /// the left visible half carries 0–50% and the right visible half carries
    /// 50–100%, instead of letting the gap absorb progress (#205). Off by
    /// default so the historical "gap consumes progress" look is preserved.
    let splitGapProgress: Bool
    let usesStatusColors: Bool
    let criticalThreshold: Int
    /// The level at which the ring counts as full (#105).
    ///
    /// macOS caps a charging battery below 100% when charge limiting is on, so a
    /// ring drawn against a fixed 100% never closes and reads as "still not
    /// full" no matter how long the cable stays in. This threshold rescales the
    /// arc so the configured level is the closed ring; the default keeps the
    /// raw percentage and therefore the previous behaviour.
    let fullThreshold: Int
    let textScale: Double
    let ringStrokeScale: Double
    /// The user's per-role colour overrides. `.standard` selects the system
    /// semantic colours (the #188 baseline, which itself changed those colours).
    let batteryStatusColors: BatteryStatusColors

    static let defaultTextScale = 1.8
    /// Kept in step with the stroke-style default so tuning the enum cannot
    /// silently desynchronise `.standard`, the previews, and the icon guide.
    static let defaultRingStrokeScale = RingStrokeStyle.regular.scale
    /// Raw percentage: the ring only closes at a genuine 100%.
    static let defaultFullThreshold = 100

    static let standard = BatteryIconOptions(
        showsPercentage: true,
        showsChargingIndicator: true,
        showsChargingEffect: true,
        showsChargingBoltHeartbeat: true,
        splitGapProgress: false,
        usesStatusColors: true,
        criticalThreshold: 20,
        connectedIndicator: .plug,
        fullThreshold: defaultFullThreshold,
        textScale: defaultTextScale,
        ringStrokeScale: defaultRingStrokeScale
    )

    /// Legacy-shaped initializer. The #315 redesign stores the three power states
    /// separately, but older call sites (renderers, previews, tests) still speak
    /// in terms of the two booleans plus the connected-indicator choice. Passing
    /// only the legacy arguments reproduces their previous behaviour exactly:
    /// `showsPercentage` is the on-battery marker, `showsChargingIndicator`
    /// decides whether charging shows the bolt, and the connected state follows
    /// `connectedIndicator`. New call sites pass the marker arguments directly.
    init(
        showsPercentage: Bool = true,
        showsChargingIndicator: Bool = true,
        showsChargingEffect: Bool = true,
        showsChargingBoltHeartbeat: Bool = true,
        splitGapProgress: Bool = false,
        usesStatusColors: Bool = true,
        criticalThreshold: Int = 20,
        connectedIndicator: BatteryConnectedIndicator = .plug,
        fullThreshold: Int = defaultFullThreshold,
        textScale: Double = defaultTextScale,
        ringStrokeScale: Double = defaultRingStrokeScale,
        batteryStatusColors: BatteryStatusColors = .standard,
        onBatteryMarker: BatteryTopMarker? = nil,
        chargingMarker: BatteryTopMarker? = nil,
        connectedMarker: BatteryTopMarker? = nil,
        noBatteryMarker: BatteryTopMarker? = nil
    ) {
        let legacyOnBattery: BatteryTopMarker = showsPercentage ? .percentage : .hidden
        self.onBatteryMarker = onBatteryMarker ?? legacyOnBattery
        self.chargingMarker = chargingMarker
            ?? (showsChargingIndicator ? .bolt : legacyOnBattery)
        self.connectedMarker = connectedMarker
            ?? (
                showsChargingIndicator
                    ? Self.legacyMarker(for: connectedIndicator, showsPercentage: showsPercentage)
                    : legacyOnBattery
            )
        self.noBatteryMarker = noBatteryMarker
            ?? (showsChargingIndicator ? (connectedIndicator == .bolt ? .bolt : .plug) : .hidden)
        self.showsChargingEffect = showsChargingEffect
        self.showsChargingBoltHeartbeat = showsChargingBoltHeartbeat
        self.splitGapProgress = splitGapProgress
        self.usesStatusColors = usesStatusColors
        self.criticalThreshold = min(100, max(0, criticalThreshold))
        self.fullThreshold = min(100, max(1, fullThreshold))
        self.textScale = textScale.isFinite ? min(3, max(1, textScale)) : Self.defaultTextScale
        self.ringStrokeScale = ringStrokeScale.isFinite ? min(2.5, max(0.5, ringStrokeScale)) : Self.defaultRingStrokeScale
        self.batteryStatusColors = batteryStatusColors
    }

    private static func legacyMarker(
        for connected: BatteryConnectedIndicator,
        showsPercentage: Bool
    ) -> BatteryTopMarker {
        switch connected {
        case .plug: return .plug
        case .bolt: return .bolt
        case .percentage: return showsPercentage ? .percentage : .plug
        }
    }
}
