import Foundation

enum MemoryPressureFooterMapper {
    static func state(reading: MemoryPressureReading?, now: Date,
                      style: VolumeDisplayStyle, strokeScale: Double) -> FooterState {
        let level = reading.flatMap { $0.isFresh(at: now) ? $0.level : nil } ?? .unknown
        return state(level: level, style: style, strokeScale: strokeScale)
    }

    static func state(level: MemoryPressureLevel, style: VolumeDisplayStyle,
                      strokeScale: Double) -> FooterState {
        let count: Int
        switch level {
        case .normal: count = 2
        case .warning: count = 3
        case .critical: count = 4
        case .unknown: count = 0
        }
        let color = color(for: level).map(IconColorRole.custom) ?? .inactive
        switch style {
        case .dots:
            return .dots(DotsState(count: 4, activeCount: count, color: color, strokeScale: strokeScale))
        case .arc:
            return .arc(ArcState(progress: Double(count) / 4, color: color, strokeScale: strokeScale))
        }
    }

    static func color(for level: MemoryPressureLevel) -> IconRGBA? {
        switch level {
        case .normal: IconRGBA(red: 52.0 / 255, green: 199.0 / 255, blue: 89.0 / 255, alpha: 1)
        case .warning: HardwareRingColorConfiguration.warningColor
        case .critical: HardwareRingColorConfiguration.criticalColor
        case .unknown: nil
        }
    }
}
