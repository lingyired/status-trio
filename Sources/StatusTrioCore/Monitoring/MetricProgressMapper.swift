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
        guard let value = displayableValue(sample) else { return nil }
        return clamp(value / 100.0)
    }

    static func temperature(_ sample: HardwareMetricSample,
                            range: ClosedRange<Double> = temperatureRange) -> Double? {
        guard let value = displayableValue(sample) else { return nil }
        let span = max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude)
        return clamp((value - range.lowerBound) / span)
    }

    static func rpm(_ sample: HardwareMetricSample) -> Double? {
        guard let value = displayableValue(sample),
              let maximum = sample.metadata.maximum,
              maximum > 0, maximum.isFinite else { return nil }
        return clamp(value / maximum)
    }

    static func progress(for id: HardwareMetricID, sample: HardwareMetricSample) -> Double? {
        switch id {
        case .cpuUsage, .gpuUsage, .memoryUsage: percent(sample)
        case .cpuTemperature: temperature(sample)
        case .batteryTemperature: temperature(sample, range: 20...60)
        case .gpuTemperature: nil
        case .fanRPM: rpm(sample)
        // Network needs a configured cap, so it is mapped via `speed(capMbps:)`.
        case .networkDownload, .networkUpload: nil
        }
    }

    /// Draws a throughput sample as a fraction of the configured broadband cap.
    /// `capMbps <= 0` (unset) yields `nil` so the UI shows the value only.
    static func speed(_ sample: HardwareMetricSample, capMbps: Double) -> Double? {
        guard capMbps > 0, capMbps.isFinite, let value = displayableValue(sample), value >= 0 else { return nil }
        let megabitsPerSecond = value * 8.0 / 1_000_000.0
        return clamp(megabitsPerSecond / capMbps)
    }

    /// Value eligible for display: a measured, fresh number, or the cached
    /// last value of a stale sample (the UI dims it and marks it expired).
    static func displayableValue(_ sample: HardwareMetricSample) -> Double? {
        guard sample.availability == .measured || sample.availability == .stale,
              let value = sample.value,
              value.isFinite else { return nil }
        return value
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}