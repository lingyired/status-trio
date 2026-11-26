import Foundation

/// Maps the system memory-pressure level to the footer dots/arc and to the
/// shared three-level colours (#398).
///
/// The colours live in `HardwareRingColorConfiguration` so the bottom indicator
/// and the top marker always draw the same level in the same colour. `unknown`
/// has no colour: callers draw the inactive track instead of inventing a level.
enum MemoryPressureFooterMapper {
    static func state(reading: MemoryPressureReading?, now: Date,
                      style: VolumeDisplayStyle, strokeScale: Double,
                      colors: HardwareRingColorConfiguration = HardwareRingColorConfiguration()) -> FooterState {
        let level = reading.flatMap { $0.isFresh(at: now) ? $0.level : nil } ?? .unknown
        return state(level: level, style: style, strokeScale: strokeScale,
                     colors: colors)
    }

    static func state(level: MemoryPressureLevel, style: VolumeDisplayStyle,
                      strokeScale: Double,
                      colors: HardwareRingColorConfiguration = HardwareRingColorConfiguration()) -> FooterState {
        let count: Int
        switch level {
        case .normal: count = 2
        case .warning: count = 3
        case .critical: count = 4
        case .unknown: count = 0
        }
        let color = color(for: level, colors: colors).map(IconColorRole.custom) ?? .inactive
        switch style {
        case .dots:
            return .dots(DotsState(count: 4, activeCount: count, color: color, strokeScale: strokeScale))
        case .arc:
            return .arc(ArcState(progress: Double(count) / 4, color: color, strokeScale: strokeScale))
        }
    }

    /// The configured colour for a pressure level, or `nil` for `unknown`.
    static func color(for level: MemoryPressureLevel,
                      colors: HardwareRingColorConfiguration = HardwareRingColorConfiguration()) -> IconRGBA? {
        switch level {
        case .normal: return colors.memoryPressureNormalColor
        case .warning: return colors.memoryPressureWarningColor
        case .critical: return colors.memoryPressureCriticalColor
        case .unknown: return nil
        }
    }
}
