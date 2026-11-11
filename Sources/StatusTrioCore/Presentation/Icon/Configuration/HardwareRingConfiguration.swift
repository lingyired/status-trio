import Foundation

/// How the hardware-monitor outer ring is laid out.
///
/// This is an *internal* setting of the `hardwareMonitor` ring source; it is not
/// a top-level ring layout option. `single` draws one arc for `primaryMetric`,
/// `dual` draws a left/right pair for `primaryMetric` / `secondaryMetric`.
enum HardwareRingLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case single
    case dual

    var id: Self { self }
}

/// What sits in the top gap of the hardware-monitor ring.
///
/// `automatic` follows the selected metric (single: that metric's glyph; dual:
/// a generic monitor glyph). `symbol` pins a metric glyph, `value` shows the
/// metric's raw value, `hidden` removes it. The top marker is part of the
/// hardware source, not a separate top-level slot.
enum HardwareRingTopContent: Codable, Equatable, Hashable, Sendable {
    case automatic
    case symbol(HardwareMonitorMetric)
    case value(HardwareMonitorMetric)
    case hidden

    /// The metric whose sample the top marker depends on, if any. `automatic`
    /// resolves against the active side metrics and adds no dependency of its
    /// own; the resolver combines it with the ring metrics.
    var referencedMetric: HardwareMonitorMetric? {
        switch self {
        case .automatic, .hidden: return nil
        case let .symbol(metric), let .value(metric): return metric
        }
    }

    // MARK: - Lenient Codable

    private enum CodingKeys: String, CodingKey { case kind, metric }

    private enum Kind: String {
        case automatic, symbol, value, hidden
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .automatic:
            try container.encode(Kind.automatic.rawValue, forKey: .kind)
        case .hidden:
            try container.encode(Kind.hidden.rawValue, forKey: .kind)
        case let .symbol(metric):
            try container.encode(Kind.symbol.rawValue, forKey: .kind)
            try container.encode(metric, forKey: .metric)
        case let .value(metric):
            try container.encode(Kind.value.rawValue, forKey: .kind)
            try container.encode(metric, forKey: .metric)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = (try? container.decode(String.self, forKey: .kind)) ?? Kind.automatic.rawValue
        let kind = Kind(rawValue: rawKind) ?? .automatic
        let metric = try? container.decode(HardwareMonitorMetric.self, forKey: .metric)
        switch kind {
        case .automatic:
            self = .automatic
        case .hidden:
            self = .hidden
        case .symbol:
            self = metric.map { HardwareRingTopContent.symbol($0) } ?? .automatic
        case .value:
            self = metric.map { HardwareRingTopContent.value($0) } ?? .automatic
        }
    }
}

/// Colour strategy for the hardware-monitor ring. Mirrors the requested
/// three-way choice; the left/right base colours are only used by `status` and
/// `fixed` (monochrome draws through the template foreground).
enum HardwareRingColorMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Metric base colour normally; whole filled arc turns orange at the warning
    /// threshold and red at the critical threshold.
    case status
    /// Metric base colour, unaffected by load.
    case fixed
    /// Template foreground, no warning colour (matches the menu-bar tint).
    case monochrome

    var id: Self { self }
}

/// Per-metric display range and warning/critical thresholds. Thresholds compare
/// the *raw* sampled value (not a fraction of the display range).
struct HardwareMetricRingOptions: Codable, Equatable, Hashable, Sendable {
    var displayMinimum: Double
    var displayMaximum: Double
    var warningThreshold: Double
    var criticalThreshold: Double

    init(displayMinimum: Double, displayMaximum: Double,
         warningThreshold: Double, criticalThreshold: Double) {
        self.displayMinimum = displayMinimum
        self.displayMaximum = displayMaximum
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
    }

    // MARK: - Defaults

    static func `default`(for metric: HardwareMonitorMetric) -> HardwareMetricRingOptions {
        switch metric {
        case .cpuUsage:
            return .init(displayMinimum: 0, displayMaximum: 100, warningThreshold: 75, criticalThreshold: 90)
        case .gpuUsage, .memoryUsage:
            return .init(displayMinimum: 0, displayMaximum: 100, warningThreshold: 80, criticalThreshold: 95)
        case .cpuTemperature:
            return .init(displayMinimum: 30, displayMaximum: 100, warningThreshold: 85, criticalThreshold: 95)
        case .batteryTemperature:
            return .init(displayMinimum: 20, displayMaximum: 60, warningThreshold: 45, criticalThreshold: 55)
        case .fan:
            // `displayMaximum == displayMinimum` means "use the sample's trusted
            // maximum RPM"; without one the arc stays an unfilled track.
            return .init(displayMinimum: 0, displayMaximum: 0, warningThreshold: 3000, criticalThreshold: 5000)
        }
    }

    /// Normalise this option set for `metric`, enforcing the plan's invariants:
    /// percentage metrics are pinned to 0...100, finite values, `max > min`,
    /// and `warning < critical`.
    func normalized(for metric: HardwareMonitorMetric) -> HardwareMetricRingOptions {
        let fallback = Self.default(for: metric)
        func finite(_ value: Double, _ fallback: Double) -> Double {
            value.isFinite ? value : fallback
        }
        var min = finite(displayMinimum, fallback.displayMinimum)
        var max = finite(displayMaximum, fallback.displayMaximum)

        if metric.isPercentageMetric {
            min = 0
            max = 100
        } else if metric == .fan {
            if max <= min {
                // Keep the dynamic-limit sentinel (0...0) or repair a bogus range.
                min = 0
                max = 0
            }
        } else {
            // Temperature: keep range sane and ordered.
            min = Swift.min(150, Swift.max(-50, min))
            max = Swift.min(150, Swift.max(-50, max))
            if max <= min {
                min = fallback.displayMinimum
                max = fallback.displayMaximum
            }
        }

        var warning = finite(warningThreshold, fallback.warningThreshold)
        var critical = finite(criticalThreshold, fallback.criticalThreshold)
        if !(warning < critical) {
            warning = fallback.warningThreshold
            critical = fallback.criticalThreshold
        }
        return .init(displayMinimum: min, displayMaximum: max,
                     warningThreshold: warning, criticalThreshold: critical)
    }
}

/// Colour strategy for the hardware ring. The per-metric base colour is *not*
/// stored here: it is the shared "monitor metric colour" owned by the settings
/// store, so the status-panel bar and the ring arc always agree and editing the
/// colour in either place writes the same field.
struct HardwareRingColorConfiguration: Codable, Equatable, Hashable, Sendable {
    var mode: HardwareRingColorMode

    init(mode: HardwareRingColorMode = .status) {
        self.mode = mode
    }

    func normalized() -> HardwareRingColorConfiguration { self }

    /// The recommended base colour for a metric (the default of the shared
    /// per-metric colour; used until the user picks a custom one).
    static func recommendedBaseColor(for metric: HardwareMonitorMetric) -> IconRGBA {
        switch metric {
        case .cpuUsage:
            return IconRGBA(red: 0.20, green: 0.72, blue: 0.36, alpha: 1)
        case .gpuUsage:
            return IconRGBA(red: 0.20, green: 0.51, blue: 0.95, alpha: 1)
        case .memoryUsage:
            return IconRGBA(red: 0.60, green: 0.36, blue: 0.85, alpha: 1)
        case .cpuTemperature:
            return IconRGBA(red: 0.13, green: 0.69, blue: 0.75, alpha: 1)
        case .batteryTemperature:
            return IconRGBA(red: 0.16, green: 0.66, blue: 0.62, alpha: 1)
        case .fan:
            return IconRGBA(red: 0.45, green: 0.55, blue: 0.68, alpha: 1)
        }
    }

    /// Fixed warning / critical tints shared by every metric (whole-arc recolor).
    static let warningColor = IconRGBA(red: 0.98, green: 0.60, blue: 0.10, alpha: 1)
    static let criticalColor = IconRGBA(red: 0.88, green: 0.21, blue: 0.21, alpha: 1)
}

/// The complete internal configuration of the `hardwareMonitor` outer-ring
/// source. Stored as a compatible extension of the V1 behaviours payload; every
/// field decodes leniently so an older or partially-unknown payload keeps the
/// classic behaviour instead of failing the whole icon configuration.
struct HardwareRingConfiguration: Codable, Equatable, Hashable, Sendable {
    var layout: HardwareRingLayout
    var primaryMetric: HardwareMonitorMetric
    /// Left/right split for `dual`; ignored (and normalised to nil) for `single`.
    var secondaryMetric: HardwareMonitorMetric?
    var topContent: HardwareRingTopContent
    var color: HardwareRingColorConfiguration
    /// Sparse overrides; a missing metric uses `HardwareMetricRingOptions.default`.
    var overrides: [HardwareMonitorMetric: HardwareMetricRingOptions]

    init(layout: HardwareRingLayout = .single,
         primaryMetric: HardwareMonitorMetric = .cpuUsage,
         secondaryMetric: HardwareMonitorMetric? = nil,
         topContent: HardwareRingTopContent = .automatic,
         color: HardwareRingColorConfiguration = .init(),
         overrides: [HardwareMonitorMetric: HardwareMetricRingOptions] = [:]) {
        self.layout = layout
        self.primaryMetric = primaryMetric
        self.secondaryMetric = secondaryMetric
        self.topContent = topContent
        self.color = color
        self.overrides = overrides
    }

    static let `default` = HardwareRingConfiguration()

    /// The effective options for `metric` (override if present, else default).
    func options(for metric: HardwareMonitorMetric) -> HardwareMetricRingOptions {
        (overrides[metric] ?? .default(for: metric)).normalized(for: metric)
    }

    /// Metrics this configuration actually reads. The top marker's own metric is
    /// added by the caller from `topContent`; this covers the arc sides.
    var arcMetrics: [HardwareMonitorMetric] {
        switch layout {
        case .single:
            return [primaryMetric]
        case .dual:
            let right = normalizedSecondaryMetric ?? Self.fallbackSecondary(to: primaryMetric)
            return [primaryMetric, right]
        }
    }

    /// Every metric the source depends on, including an explicitly pinned top
    /// marker metric. Kept ordered and de-duplicated.
    var referencedMetrics: [HardwareMonitorMetric] {
        var result = arcMetrics
        if let topMetric = topContent.referencedMetric, !result.contains(topMetric) {
            result.append(topMetric)
        }
        return result
    }

    /// The right metric for `dual`, guaranteed distinct from `primaryMetric`.
    var normalizedSecondaryMetric: HardwareMonitorMetric? {
        guard layout == .dual else { return nil }
        guard let secondary = secondaryMetric, secondary != primaryMetric else {
            return Self.fallbackSecondary(to: primaryMetric)
        }
        return secondary
    }

    private static func fallbackSecondary(to primary: HardwareMonitorMetric) -> HardwareMonitorMetric {
        HardwareMonitorMetric.allCases.first { $0 != primary } ?? .gpuUsage
    }

    func normalized() -> HardwareRingConfiguration {
        var copy = self
        if copy.layout == .single {
            copy.secondaryMetric = nil
        } else {
            copy.secondaryMetric = copy.normalizedSecondaryMetric
        }
        copy.color = color.normalized()
        copy.overrides = overrides.mapValues { $0 } // placeholder-normalised below
        for (metric, options) in overrides {
            copy.overrides[metric] = options.normalized(for: metric)
        }
        return copy
    }

    // MARK: - Lenient Codable

    private enum CodingKeys: String, CodingKey {
        case layout, primaryMetric, secondaryMetric, topContent, color, overrides
    }

    init(from decoder: Decoder) throws {
        let fallback = HardwareRingConfiguration.default
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = fallback
            return
        }
        let layout = (try? container.decode(HardwareRingLayout.self, forKey: .layout)) ?? fallback.layout
        let primary = (try? container.decode(HardwareMonitorMetric.self, forKey: .primaryMetric)) ?? fallback.primaryMetric
        let secondary = try? container.decodeIfPresent(HardwareMonitorMetric.self, forKey: .secondaryMetric)
        let top = (try? container.decode(HardwareRingTopContent.self, forKey: .topContent)) ?? fallback.topContent
        let color = (try? container.decode(HardwareRingColorConfiguration.self, forKey: .color)) ?? fallback.color
        let overrides = (try? container.decode([HardwareMonitorMetric: HardwareMetricRingOptions].self, forKey: .overrides)) ?? [:]
        self.init(layout: layout, primaryMetric: primary, secondaryMetric: secondary,
                  topContent: top, color: color, overrides: overrides)
    }
}

extension HardwareMonitorMetric {
    /// CPU/GPU/memory are percentages and their ring range is fixed 0...100%.
    var isPercentageMetric: Bool {
        switch self {
        case .cpuUsage, .gpuUsage, .memoryUsage: return true
        case .cpuTemperature, .batteryTemperature, .fan: return false
        }
    }
}
