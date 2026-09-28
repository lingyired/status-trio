import Foundation

struct BatteryIconOptions: Equatable, Hashable, Sendable {
    let showsPercentage: Bool
    let showsChargingIndicator: Bool
    let showsChargingEffect: Bool
    let showsChargingBoltHeartbeat: Bool
    let usesStatusColors: Bool
    let showsPercentageWhenConnected: Bool
    let criticalThreshold: Int
    let textScale: Double
    let ringStrokeScale: Double

    static let defaultTextScale = 1.8
    /// Kept in step with the stroke-style default so tuning the enum cannot
    /// silently desynchronise `.standard`, the previews, and the icon guide.
    static let defaultRingStrokeScale = RingStrokeStyle.regular.scale

    static let standard = BatteryIconOptions(
        showsPercentage: true,
        showsChargingIndicator: true,
        showsChargingEffect: true,
        showsChargingBoltHeartbeat: true,
        usesStatusColors: true,
        criticalThreshold: 20,
        showsPercentageWhenConnected: false,
        textScale: defaultTextScale,
        ringStrokeScale: defaultRingStrokeScale
    )

    init(
        showsPercentage: Bool = true,
        showsChargingIndicator: Bool = true,
        showsChargingEffect: Bool = true,
        showsChargingBoltHeartbeat: Bool = true,
        usesStatusColors: Bool = true,
        criticalThreshold: Int = 20,
        showsPercentageWhenConnected: Bool = false,
        textScale: Double = defaultTextScale,
        ringStrokeScale: Double = defaultRingStrokeScale
    ) {
        self.showsPercentage = showsPercentage
        self.showsChargingIndicator = showsChargingIndicator
        self.showsChargingEffect = showsChargingEffect
        self.showsChargingBoltHeartbeat = showsChargingBoltHeartbeat
        self.usesStatusColors = usesStatusColors
        self.showsPercentageWhenConnected = showsPercentageWhenConnected
        self.criticalThreshold = min(100, max(0, criticalThreshold))
        self.textScale = textScale.isFinite ? min(3, max(1, textScale)) : Self.defaultTextScale
        self.ringStrokeScale = ringStrokeScale.isFinite ? min(2.5, max(0.5, ringStrokeScale)) : Self.defaultRingStrokeScale
    }
}
