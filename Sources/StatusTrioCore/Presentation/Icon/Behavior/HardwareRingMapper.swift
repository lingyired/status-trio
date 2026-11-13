import Foundation

/// Pure mapping from the hardware-monitor configuration + a metrics snapshot to
/// the `OuterRingState` the shared renderer draws.
///
/// The mapper never starts sampling, reads defaults or touches the store: the
/// plugin supplies the configuration and the already-produced snapshot and
/// debounced levels. It returns a track-only ring (progress 0, inactive colour)
/// when a metric is unsupported/stale/unavailable, so the slot keeps its shape
/// instead of inventing a 0% "live" reading.
enum HardwareRingMapper {
    /// Vertical scale of the top value text, chosen per unit so the string fits
    /// the top gap at menu-bar size. Percentage values use the battery
    /// percentage's own scale (1.8) and are drawn as a plain number, exactly like
    /// the battery percentage — that is why that case is as crisp as the battery.
    /// Values carrying a wider suffix (degree, thousands) get a slightly smaller
    /// scale so they do not overflow the gap.
    static func topValueTextScale(for unit: HardwareMetricUnit) -> Double {
        switch unit {
        case .percent: return 1.8
        case .celsius: return 1.4
        case .rpm: return 1.2
        case .bytesPerSecond: return 1.2
        case .none: return 1.4
        }
    }
    /// Top glyph scale for a dual ring (drawn by the compact top-marker path).
    static let topSymbolScale: Double = 2.0
    /// Top glyph scale for a single ring. The standard-ring accessory path sizes
    /// symbols from the centre-symbol base point size, so it needs a smaller
    /// multiplier than the dual path to match the percentage numerals' height.
    static let singleTopSymbolScale: Double = 0.95
    /// Generic monitoring glyph used for automatic top content on a dual ring.
    /// A solid single-layer bar-chart reads clearly at menu-bar size (the
    /// hierarchical "gauge" rendered its dial ring in a washed-out secondary
    /// tint and was hard to make out).
    static let genericMonitorSymbol = "chart.bar.fill"

    static func resolve(
        snapshot: HardwareMetricsSnapshot,
        configuration rawConfiguration: HardwareRingConfiguration,
        levels: [HardwareMonitorMetric: HardwareLoadLevel] = [:],
        metricColors: [HardwareMonitorMetric: IconRGBA] = [:],
        speedCapsMbps: [HardwareMonitorMetric: Double] = [:],
        now: Date = .now
    ) -> OuterRingState {
        let configuration = rawConfiguration.normalized()
        let accessory = topAccessory(configuration: configuration, snapshot: snapshot, now: now)

        switch configuration.layout {
        case .single:
            let metric = configuration.primaryMetric
            let segment = segment(metric: metric, position: nil, snapshot: snapshot,
                                  configuration: configuration, levels: levels,
                                  metricColors: metricColors, speedCapsMbps: speedCapsMbps, now: now)
            return OuterRingState(
                segments: [segment],
                gap: singleGapStyle(for: accessory),
                layout: .standard,
                accessory: accessory
            )
        case .dual:
            let left = configuration.primaryMetric
            let right = configuration.normalizedSecondaryMetric
                ?? HardwareMonitorMetric.allCases.first { $0 != left } ?? .gpuUsage
            let leftSegment = segment(metric: left, position: .left, snapshot: snapshot,
                                      configuration: configuration, levels: levels,
                                      metricColors: metricColors, speedCapsMbps: speedCapsMbps, now: now)
            let rightSegment = segment(metric: right, position: .right, snapshot: snapshot,
                                       configuration: configuration, levels: levels,
                                       metricColors: metricColors, speedCapsMbps: speedCapsMbps, now: now)
            return OuterRingState(
                segments: [leftSegment, rightSegment],
                gap: .closed,
                layout: .leftRight,
                accessory: accessory
            )
        }
    }

    // MARK: - Segments

    private static func segment(
        metric: HardwareMonitorMetric,
        position: RingSegmentPosition?,
        snapshot: HardwareMetricsSnapshot,
        configuration: HardwareRingConfiguration,
        levels: [HardwareMonitorMetric: HardwareLoadLevel],
        metricColors: [HardwareMonitorMetric: IconRGBA],
        speedCapsMbps: [HardwareMonitorMetric: Double],
        now: Date
    ) -> RingSegmentState {
        let options = configuration.options(for: metric)
        let sample = sample(for: metric, in: snapshot)
        let capMbps = speedCapsMbps[metric]
        guard let progress = progress(metric: metric, sample: sample, options: options, capMbps: capMbps, now: now) else {
            return RingSegmentState(progress: 0, color: .inactive, position: position)
        }
        let level = levels[metric] ?? HardwareRingThresholdEngine.immediateLevel(value: sample.value ?? 0, options: options)
        let baseColor = metricColors[metric]
            ?? HardwareRingColorConfiguration.recommendedBaseColor(for: metric)
        let color = segmentColor(level: level,
                                 monochrome: configuration.color.monochrome,
                                 thresholdColors: configuration.color.thresholdColors,
                                 baseColor: baseColor)
        return RingSegmentState(progress: progress, color: color, position: position)
    }

    private static func segmentColor(
        level: HardwareLoadLevel,
        monochrome: Bool,
        thresholdColors: Bool,
        baseColor: IconRGBA
    ) -> IconColorRole {
        if monochrome { return .primary }
        guard thresholdColors else { return .custom(baseColor) }
        switch level {
        case .critical:
            return .custom(HardwareRingColorConfiguration.criticalColor)
        case .warning:
            return .custom(HardwareRingColorConfiguration.warningColor)
        case .normal:
            return .custom(baseColor)
        }
    }

    // MARK: - Progress

    static func progress(
        metric: HardwareMonitorMetric,
        sample: HardwareMetricSample,
        options: HardwareMetricRingOptions,
        capMbps: Double? = nil,
        now: Date
    ) -> Double? {
        guard sample.availability == .measured, sample.isFresh(at: now) else { return nil }
        guard let value = sample.value, value.isFinite else { return nil }

        // Share the base progress math with the panel card; the ring only adds
        // its configured display range / RPM cap on top.
        if metric.isPercentageMetric {
            return MetricProgressMapper.percent(sample)
        }
        if metric.isSpeedMetric {
            guard let capMbps, capMbps > 0, capMbps.isFinite else { return nil }
            return MetricProgressMapper.speed(sample, capMbps: capMbps)
        }
        if metric == .fan {
            let maximum = options.displayMaximum > options.displayMinimum
                ? options.displayMaximum
                : sample.metadata.maximum
            return MetricProgressMapper.rpm(sample, maximum: maximum)
        }
        let range = options.displayMinimum...options.displayMaximum
        guard options.displayMaximum > options.displayMinimum else { return nil }
        return MetricProgressMapper.temperature(sample, range: range)
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    // MARK: - Top marker

    private static func topAccessory(
        configuration: HardwareRingConfiguration,
        snapshot: HardwareMetricsSnapshot,
        now: Date
    ) -> RingAccessoryState? {
        switch configuration.topContent {
        case .hidden:
            return nil
        case .automatic:
            switch configuration.layout {
            case .single:
                return .symbol(symbolState(name: topMarkerSymbol(for: configuration.primaryMetric),
                                           scale: Self.singleTopSymbolScale * configuration.topMarkerScale))
            case .dual:
                return .symbol(symbolState(name: Self.genericMonitorSymbol,
                                           scale: Self.topSymbolScale * configuration.topMarkerScale))
            }
        case let .symbol(metric):
            let base = configuration.layout == .single ? Self.singleTopSymbolScale : Self.topSymbolScale
            return .symbol(symbolState(name: topMarkerSymbol(for: metric), scale: base * configuration.topMarkerScale))
        case let .value(metric):
            // Geometry is decided by the configuration, not by data availability:
            // a temporarily missing value must keep the top gap (and thus the ring
            // shape) stable and show a placeholder instead of collapsing the gap.
            let sample = sample(for: metric, in: snapshot)
            let scale = topValueTextScale(for: sample.unit) * configuration.topMarkerScale
            if sample.availability == .measured, sample.isFresh(at: now),
               let value = sample.value, value.isFinite {
                return .text(IconTextState(text: formattedValue(value, unit: sample.unit),
                                           color: .primary, scale: scale))
            }
            return .text(IconTextState(text: "--", color: .primary, scale: scale))
        }
    }

    /// Simpler, higher-contrast glyphs for the tiny ring top marker. The list and
    /// card keep the richer `metric.systemImage`; at menu-bar size the detailed
    /// chip/memory outlines turn to mud, so the top gap uses filled variants.
    static func topMarkerSymbol(for metric: HardwareMonitorMetric) -> String {
        switch metric {
        case .cpuUsage: SymbolFallback.name("cpu.fill", "cpu")
        case .gpuUsage: "display"
        case .memoryUsage: SymbolFallback.name("memorychip.fill", "memorychip")
        case .cpuTemperature: "thermometer.medium"
        case .batteryTemperature: SymbolFallback.name("battery.100percent", "battery.100")
        case .fan: SymbolFallback.name("fanblades.fill", "fanblades")
        case .downloadSpeed: "arrow.down.circle.fill"
        case .uploadSpeed: "arrow.up.circle.fill"
        }
    }

    private static func symbolState(name: String, scale: Double) -> IconSymbolState {
        IconSymbolState(
            source: .symbol(name: name, variableValue: nil, fallback: Self.genericMonitorSymbol),
            color: .primary,
            scale: scale
        )
    }

    private static func singleGapStyle(for accessory: RingAccessoryState?) -> RingGapStyle {
        switch accessory {
        case .none: return .closed
        case .symbol: return .indicator
        case .text: return .value
        }
    }

    // MARK: - Helpers

    static func sample(for metric: HardwareMonitorMetric, in snapshot: HardwareMetricsSnapshot) -> HardwareMetricSample {
        switch metric {
        case .fan: return snapshot.fanSummarySample
        default: return snapshot[metric.metricID]
        }
    }

    /// Compact accessory text. Percentage values render as a plain number, like
    /// the battery percentage in the same gap; temperature shows °C; RPM uses a
    /// compact "1.2k".
    static func formattedValue(_ value: Double, unit: HardwareMetricUnit) -> String {
        switch unit {
        case .percent:
            return "\(Int(value.rounded()))"
        case .celsius:
            return "\(Int(value.rounded()))°"
        case .rpm:
            if value >= 1000 {
                return String(format: "%.1fk", value / 1000)
            }
            return "\(Int(value.rounded()))"
        case .bytesPerSecond:
            return NetworkSpeedFormatter.compact(bytesPerSecond: value)
        case .none:
            return "\(Int(value.rounded()))"
        }
    }
}
