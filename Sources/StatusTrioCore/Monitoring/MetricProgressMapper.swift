import Foundation

/// Pure mapping from a metric sample to a drawn 0–1 progress.
///
/// Deliberately free of SwiftUI, colors and localized strings so the future
/// menu-bar arc / Dock rendering can reuse it. It never invents a proportion
/// from an unavailable or unsupported sample, and it clamps only the drawn
/// progress — the raw number shown stays honest.
enum MetricProgressMapper {
    /// Temperature track range. This is a documented visual tick interval, not
    /// a safety percentage and not a danger threshold.
    static let temperatureRange: ClosedRange<Double> = 30...100

    static func percent(_ sample: HardwareMetricSample) -> Double? {
        guard let value = measuredValue(sample) else { return nil }
        return clamp(value / 100.0)
    }

    static func temperature(_ sample: HardwareMetricSample,
                            range: ClosedRange<Double> = temperatureRange) -> Double? {
        guard let value = measuredValue(sample) else { return nil }
        let span = max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude)
        return clamp((value - range.lowerBound) / span)
    }

    static func rpm(_ sample: HardwareMetricSample) -> Double? {
        guard let value = measuredValue(sample),
              let maximum = sample.metadata.maximum,
              maximum > 0, maximum.isFinite else { return nil }
        return clamp(value / maximum)
    }

    static func progress(for id: HardwareMetricID, sample: HardwareMetricSample) -> Double? {
        switch id {
        case .cpuUsage, .gpuUsage: percent(sample)
        case .cpuTemperature: temperature(sample)
        case .gpuTemperature: nil
        case .fanRPM: rpm(sample)
        }
    }

    /// Value eligible for display: only a measured, fresh, finite number.
    static func measuredValue(_ sample: HardwareMetricSample) -> Double? {
        guard sample.availability == .measured,
              let value = sample.value,
              value.isFinite else { return nil }
        return value
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}