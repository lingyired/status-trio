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
    /// The memory-pressure dot is a compact status marker, not a full-size top
    /// glyph: at the usual top-symbol scale it overflows the ring gap and clips
    /// against the menu-bar edge, so it uses its own smaller base (#398).
    static let memoryPressureDotScale: Double = 0.5
    /// The dual (left/right) ring sizes its top marker through the battery
    /// indicator's text scale, which is much smaller per unit; this base keeps
    /// the pressure dot visually matched to the single-ring dot.
    static let memoryPressureDualDotScale: Double = 1.0
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
        auxiliarySamples: [HardwareMonitorMetric: HardwareMetricSample] = [:],
        battery: BatteryStatus = .placeholder,
        batteryOptions: BatteryIconOptions = .standard,
        batteryArcColor: IconColorRole = .primary,
        now: Date = .now
    ) -> OuterRingState {
        let configuration = rawConfiguration.normalized()
        let accessory = topAccessory(configuration: configuration, snapshot: snapshot,
                                     metricColors: metricColors,
                                     auxiliarySamples: auxiliarySamples,
                                     battery: battery, batteryOptions: batteryOptions,
                                     now: now)

        switch configuration.layout {
        case .single:
            let metric = configuration.primaryMetric
            let segment = segment(metric: metric, position: nil, snapshot: snapshot,
                                  configuration: configuration, levels: levels,
                                  metricColors: metricColors, speedCapsMbps: speedCapsMbps,
                                  auxiliarySamples: auxiliarySamples, batteryArcColor: batteryArcColor,
                                  now: now)
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
                                      metricColors: metricColors, speedCapsMbps: speedCapsMbps,
                                      auxiliarySamples: auxiliarySamples, batteryArcColor: batteryArcColor,
                                      now: now)
            let rightSegment = segment(metric: right, position: .right, snapshot: snapshot,
                                       configuration: configuration, levels: levels,
                                       metricColors: metricColors, speedCapsMbps: speedCapsMbps,
                                       auxiliarySamples: auxiliarySamples, batteryArcColor: batteryArcColor,
                                       now: now)
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
        auxiliarySamples: [HardwareMonitorMetric: HardwareMetricSample],
        batteryArcColor: IconColorRole,
        now: Date
    ) -> RingSegmentState {
        // Memory pressure is a status, not a percentage sample: map the level to
        // a fixed arc fraction and use the shared pressure colours (#398).
        if metric == .memoryPressure {
            let level = snapshot.memoryPressure.flatMap { $0.isFresh(at: now) ? $0.level : nil } ?? .unknown
            let progress: Double
            let color: IconColorRole
            switch level {
            case .normal:
                progress = 0.5
                color = .custom(configuration.color.memoryPressureNormalColor)
            case .warning:
                progress = 0.75
                color = .custom(configuration.color.memoryPressureWarningColor)
            case .critical:
                progress = 1.0
                color = .custom(configuration.color.memoryPressureCriticalColor)
            case .unknown:
                return RingSegmentState(progress: 0, color: .inactive, position: position)
            }
            return RingSegmentState(
                progress: progress,
                color: configuration.color.monochrome ? .primary : color,
                position: position
            )
        }
        let options = configuration.options(for: metric)
        let sample = sample(for: metric, in: snapshot, auxiliary: auxiliarySamples)
        let capMbps = speedCapsMbps[metric]
        guard let progress = progress(metric: metric, sample: sample, options: options, capMbps: capMbps, now: now) else {
            return RingSegmentState(progress: 0, color: .inactive, position: position)
        }
        // The battery arc mirrors the system-battery ring: it follows the battery
        // status colour (critical / low power / charging) instead of a per-metric
        // colour, so a low battery still turns red. Its colour is not user-editable
        // here; the battery colour settings live on the system-battery ring.
        if metric == .batteryLevel {
            return RingSegmentState(
                progress: progress,
                color: configuration.color.monochrome ? .primary : batteryArcColor,
                position: position
            )
        }
        // Status-snapshot readings (volume, Wi-Fi signal) have no warning/critical
        // meaning, so they keep their base colour instead of threshold colours.
        let level: HardwareLoadLevel = metric.usesStatusSnapshot
            ? .normal
            : (levels[metric] ?? HardwareRingThresholdEngine.immediateLevel(value: sample.value ?? 0, options: options))
        let baseColor = metricColors[metric]
            ?? HardwareRingColorConfiguration.recommendedBaseColor(for: metric)
        let color = segmentColor(level: level,
                                 monochrome: configuration.color.monochrome,
                                 thresholdColors: configuration.color.thresholdColors,
                                 baseColor: baseColor)
        return RingSegmentState(progress: progress, color: color, position: position)
    }

    /// The same metric reading the hardware ring would draw, rendered as the
    /// footer's four-dot / arc bar. Reuses the ring's progress and colour rules
    /// so the bottom indicator never disagrees with the ring about a metric.
    /// Returns `nil` when the sample is stale/unavailable, matching the ring's
    /// "do not invent a live reading" rule.
    static func footerState(
        metric selection: BottomIndicatorMetric,
        snapshot: HardwareMetricsSnapshot,
        configuration: HardwareRingConfiguration,
        levels: [HardwareMonitorMetric: HardwareLoadLevel],
        metricColors: [HardwareMonitorMetric: IconRGBA],
        speedCapsMbps: [HardwareMonitorMetric: Double],
        now: Date,
        style: VolumeDisplayStyle,
        strokeScale: Double
    ) -> FooterState? {
        guard let metric = selection.hardwareMetric else {
            return MemoryPressureFooterMapper.state(reading: snapshot.memoryPressure, now: now,
                                                    style: style, strokeScale: strokeScale,
                                                    colors: configuration.color)
        }
        let options = configuration.options(for: metric)
        let sample = sample(for: metric, in: snapshot, auxiliary: [:])
        let capMbps = speedCapsMbps[metric]
        guard let progress = progress(metric: metric, sample: sample, options: options,
                                      capMbps: capMbps, now: now) else {
            return nil
        }
        if metric == .batteryLevel {
            return footerBar(progress: progress, color: .primary, style: style, strokeScale: strokeScale)
        }
        let level: HardwareLoadLevel = metric.usesStatusSnapshot
            ? .normal
            : (levels[metric] ?? HardwareRingThresholdEngine.immediateLevel(value: sample.value ?? 0, options: options))
        let baseColor = metricColors[metric]
            ?? HardwareRingColorConfiguration.recommendedBaseColor(for: metric)
        let color = segmentColor(level: level,
                                 monochrome: configuration.color.monochrome,
                                 thresholdColors: configuration.color.thresholdColors,
                                 baseColor: baseColor)
        return footerBar(progress: progress, color: color, style: style, strokeScale: strokeScale)
    }

    private static func footerBar(progress: Double, color: IconColorRole,
                               style: VolumeDisplayStyle, strokeScale: Double) -> FooterState {
        switch style {
        case .dots:
            return .dots(DotsState(
                count: 4,
                activeCount: StatusMappings.volumeSteps(scalar: progress, isMuted: false) ?? 0,
                color: color,
                strokeScale: strokeScale))
        case .arc:
            return .arc(ArcState(progress: progress, color: color, strokeScale: strokeScale))
        }
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
        metricColors: [HardwareMonitorMetric: IconRGBA],
        auxiliarySamples: [HardwareMonitorMetric: HardwareMetricSample],
        battery: BatteryStatus,
        batteryOptions: BatteryIconOptions,
        now: Date
    ) -> RingAccessoryState? {
        switch configuration.topContent {
        case .hidden:
            return nil
        case .automatic:
            if configuration.layout == .single, configuration.primaryMetric == .memoryPressure {
                return memoryPressureAccessory(configuration: configuration, snapshot: snapshot, now: now)
            }
            switch configuration.layout {
            case .single:
                return .symbol(symbolState(name: topMarkerSymbol(for: configuration.primaryMetric),
                                           scale: Self.singleTopSymbolScale * configuration.topMarkerScale))
            case .dual:
                return .symbol(symbolState(name: Self.genericMonitorSymbol,
                                           scale: Self.topSymbolScale * configuration.topMarkerScale))
            }
        case let .symbol(metric):
            if metric == .memoryPressure {
                return memoryPressureAccessory(configuration: configuration, snapshot: snapshot, now: now)
            }
            let base = configuration.layout == .single ? Self.singleTopSymbolScale : Self.topSymbolScale
            return .symbol(symbolState(name: topMarkerSymbol(for: metric),
                                       color: topMarkerColor(for: metric, configuration: configuration,
                                                             metricColors: metricColors),
                                       scale: base * configuration.topMarkerScale))
        case let .value(metric):
            if metric == .memoryPressure {
                return memoryPressureAccessory(configuration: configuration, snapshot: snapshot, now: now)
            }
            // Geometry is decided by the configuration, not by data availability:
            // a temporarily missing value must keep the top gap (and thus the ring
            // shape) stable and show a placeholder instead of collapsing the gap.
            let sample = sample(for: metric, in: snapshot, auxiliary: auxiliarySamples)
            let scale = topValueTextScale(for: sample.unit) * configuration.topMarkerScale
            let color = topMarkerColor(for: metric, configuration: configuration,
                                       metricColors: metricColors)
            if sample.availability == .measured, sample.isFresh(at: now),
               let value = sample.value, value.isFinite {
                return .text(IconTextState(text: formattedValue(value, unit: sample.unit),
                                           color: color, scale: scale))
            }
            return .text(IconTextState(text: "--", color: color, scale: scale))
        case .batteryPercentage:
            // Always the level number, even while charging or on power, mirroring
            // the battery ring's own percentage marker.
            guard battery.isPresent else { return nil }
            let percentScale = topValueTextScale(for: .percent) * configuration.topMarkerScale
            return .text(IconTextState(text: "\(battery.percentage)", color: .primary, scale: percentScale))
        case .chargingIndicator:
            return batteryChargingAccessory(
                battery: battery,
                configuration: configuration,
                batteryOptions: batteryOptions
            )
        case .memoryPressure:
            return memoryPressureAccessory(configuration: configuration,
                                           snapshot: snapshot,
                                           now: now)
        }
    }

    /// Builds the auto-switching marker used by the custom ring's
    /// `chargingIndicator` top content (#361).
    ///
    /// It reuses the battery ring's own per-state marker choice
    /// (`BatteryIconOptions` → `BatteryGapContent`), so the custom ring shows the
    /// same bolt / plug / percentage / nothing the user configured on the battery
    /// page instead of a hard-coded bolt-and-plug pair. A `.hidden` choice
    /// returns `nil`, which closes the top gap rather than drawing an empty slot.
    private static func batteryChargingAccessory(
        battery: BatteryStatus,
        configuration: HardwareRingConfiguration,
        batteryOptions: BatteryIconOptions
    ) -> RingAccessoryState? {
        let scale = topValueTextScale(for: .percent) * configuration.topMarkerScale
        return StatusMappings.batteryGapContent(battery, options: batteryOptions)
            .ringAccessory(battery: battery, scale: scale)
    }

    /// Colour of the top marker reading. Top-marker-only metrics (volume, Wi-Fi
    /// signal) honour their shared per-metric colour so the two new readings can
    /// be tinted; every other metric keeps the menu bar's own foreground colour.
    private static func topMarkerColor(
        for metric: HardwareMonitorMetric,
        configuration: HardwareRingConfiguration,
        metricColors: [HardwareMonitorMetric: IconRGBA]
    ) -> IconColorRole {
        guard metric.usesStatusSnapshot, !configuration.color.monochrome else { return .primary }
        let base = metricColors[metric]
            ?? HardwareRingColorConfiguration.recommendedBaseColor(for: metric)
        return .custom(base)
    }

    /// Memory pressure is a status, not a number (#398). The top gap therefore
    /// shows a level-coloured dot instead of text: it keeps the ring's gap
    /// geometry stable, works in every language, and stays legible at menu-bar
    /// size. `unknown`/stale uses an inactive dash so the slot never collapses.
    private static func memoryPressureAccessory(
        configuration: HardwareRingConfiguration,
        snapshot: HardwareMetricsSnapshot,
        now: Date
    ) -> RingAccessoryState {
        let level = snapshot.memoryPressure.flatMap { $0.isFresh(at: now) ? $0.level : nil } ?? .unknown
        let base = configuration.layout == .single
            ? Self.memoryPressureDotScale : Self.memoryPressureDualDotScale
        let scale = base * configuration.topMarkerScale
        let color: IconColorRole
        switch level {
        case .normal:
            color = topPressureColor(configuration.color.memoryPressureNormalColor,
                                     configuration: configuration)
        case .warning:
            color = topPressureColor(configuration.color.memoryPressureWarningColor,
                                     configuration: configuration)
        case .critical:
            color = topPressureColor(configuration.color.memoryPressureCriticalColor,
                                     configuration: configuration)
        case .unknown:
            return .symbol(symbolState(name: "minus", color: .inactive, scale: scale))
        }
        return .symbol(symbolState(
            name: SymbolFallback.name("circle.fill", "circle"),
            color: color,
            scale: scale))
    }

    private static func topPressureColor(
        _ rgba: IconRGBA,
        configuration: HardwareRingConfiguration
    ) -> IconColorRole {
        configuration.color.monochrome ? .primary : .custom(rgba)
    }

    /// Simpler, higher-contrast glyphs for the tiny ring top marker. The list and
    /// card keep the richer `metric.systemImage`; at menu-bar size the detailed
    /// chip/memory outlines turn to mud, so the top gap uses filled variants.
    static func topMarkerSymbol(for metric: HardwareMonitorMetric) -> String {
        switch metric {
        case .cpuUsage: SymbolFallback.name("cpu.fill", "cpu")
        case .gpuUsage: "display"
        case .memoryUsage: SymbolFallback.name("memorychip.fill", "memorychip")
        case .memoryPressure: SymbolFallback.name("circle.fill", "circle")
        case .cpuTemperature: "thermometer.medium"
        case .gpuTemperature: "thermometer.medium"
        case .batteryTemperature: SymbolFallback.name("battery.100percent", "battery.100")
        case .fan: SymbolFallback.name("fanblades.fill", "fanblades")
        case .downloadSpeed: "arrow.down.circle.fill"
        case .uploadSpeed: "arrow.up.circle.fill"
        case .volume: SymbolFallback.name("speaker.wave.2.fill", "speaker.wave.2")
        case .wifiSignal: "wifi"
        case .batteryLevel: SymbolFallback.name("battery.100percent", "battery.100")
        }
    }

    private static func symbolState(name: String, color: IconColorRole = .primary,
                                    scale: Double) -> IconSymbolState {
        IconSymbolState(
            source: .symbol(name: name, variableValue: nil, fallback: Self.genericMonitorSymbol),
            color: color,
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

    static func sample(for metric: HardwareMonitorMetric, in snapshot: HardwareMetricsSnapshot,
                       auxiliary: [HardwareMonitorMetric: HardwareMetricSample] = [:]) -> HardwareMetricSample {
        if let extra = auxiliary[metric] { return extra }
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
