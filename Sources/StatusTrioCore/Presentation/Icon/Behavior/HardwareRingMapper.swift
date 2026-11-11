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
    /// Vertical scale of the top value text. Kept modest so "45%" fits the gap.
    static let topValueTextScale: Double = 1.0
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
        now: Date = .now
    ) -> OuterRingState {
        let configuration = rawConfiguration.normalized()
        let accessory = topAccessory(configuration: configuration, snapshot: snapshot, now: now)

        switch configuration.layout {
        case .single:
            let metric = configuration.primaryMetric
            let segment = segment(metric: metric, position: nil, snapshot: snapshot,
                                  configuration: configuration, levels: levels,
                                  metricColors: metricColors, now: now)
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
                                      metricColors: metricColors, now: now)
            let rightSegment = segment(metric: right, position: .right, snapshot: snapshot,
                                       configuration: configuration, levels: levels,
                                       metricColors: metricColors, now: now)
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
        now: Date
    ) -> RingSegmentState {
        let options = configuration.options(for: metric)
        let sample = sample(for: metric, in: snapshot)
        guard let progress = progress(metric: metric, sample: sample, options: options, now: now) else {
            return RingSegmentState(progress: 0, color: .inactive, position: position)
        }
        let level = levels[metric] ?? HardwareRingThresholdEngine.immediateLevel(value: sample.value ?? 0, options: options)
        let baseColor = metricColors[metric]
            ?? HardwareRingColorConfiguration.recommendedBaseColor(for: metric)
        let color = segmentColor(level: level, mode: configuration.color.mode, baseColor: baseColor)
        return RingSegmentState(progress: progress, color: color, position: position)
    }

    private static func segmentColor(
        level: HardwareLoadLevel,
        mode: HardwareRingColorMode,
        baseColor: IconRGBA
    ) -> IconColorRole {
        switch mode {
        case .monochrome:
            return .primary
        case .fixed:
            return .custom(baseColor)
        case .status:
            switch level {
            case .critical:
                return .custom(HardwareRingColorConfiguration.criticalColor)
            case .warning:
                return .custom(HardwareRingColorConfiguration.warningColor)
            case .normal:
                return .custom(baseColor)
            }
        }
    }

    // MARK: - Progress

    static func progress(
        metric: HardwareMonitorMetric,
        sample: HardwareMetricSample,
        options: HardwareMetricRingOptions,
        now: Date
    ) -> Double? {
        guard sample.availability == .measured, sample.isFresh(at: now) else { return nil }
        guard let value = sample.value, value.isFinite else { return nil }

        if metric.isPercentageMetric {
            return clamp(value / 100.0)
        }
        if metric == .fan {
            let upper = options.displayMaximum > options.displayMinimum
                ? options.displayMaximum
                : (sample.metadata.maximum ?? 0)
            let lower = options.displayMinimum
            guard upper > lower, upper > 0 else { return nil }
            return clamp((value - lower) / (upper - lower))
        }
        // Temperature: honour the configured display range.
        let span = options.displayMaximum - options.displayMinimum
        guard span > 0 else { return nil }
        return clamp((value - options.displayMinimum) / span)
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
                return .symbol(symbolState(name: configuration.primaryMetric.systemImage,
                                           scale: Self.singleTopSymbolScale))
            case .dual:
                return .symbol(symbolState(name: Self.genericMonitorSymbol, scale: Self.topSymbolScale))
            }
        case let .symbol(metric):
            let scale = configuration.layout == .single ? Self.singleTopSymbolScale : Self.topSymbolScale
            return .symbol(symbolState(name: metric.systemImage, scale: scale))
        case let .value(metric):
            let sample = sample(for: metric, in: snapshot)
            guard sample.availability == .measured, sample.isFresh(at: now),
                  let value = sample.value, value.isFinite else { return nil }
            let text = formattedValue(value, unit: sample.unit)
            return .text(IconTextState(text: text, color: .primary, scale: topValueTextScale))
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

    /// Compact accessory text: "45%", "62°", "1.2k RPM".
    static func formattedValue(_ value: Double, unit: HardwareMetricUnit) -> String {
        switch unit {
        case .percent:
            return "\(Int(value.rounded()))%"
        case .celsius:
            return "\(Int(value.rounded()))°"
        case .rpm:
            if value >= 1000 {
                return String(format: "%.1fk", value / 1000)
            }
            return "\(Int(value.rounded()))"
        case .none:
            return "\(Int(value.rounded()))"
        }
    }
}
