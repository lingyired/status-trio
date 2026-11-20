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
/// metric's raw value. `batteryPercentage` shows the Mac battery's level
/// number in the gap, and `chargingIndicator` shows the battery's power-state
/// glyph (bolt while charging, plug when full or connected to power, level
/// number while on battery). `hidden` removes it. The top marker is part of
/// the hardware source, not a separate top-level slot.
enum HardwareRingTopContent: Codable, Equatable, Hashable, Sendable {
    case automatic
    case symbol(HardwareMonitorMetric)
    case value(HardwareMonitorMetric)
    /// The Mac battery's level percentage, drawn like the battery ring's own
    /// percentage marker.
    case batteryPercentage
    /// A battery power-state marker: bolt while charging, plug when charged or
    /// connected to power, and the level number while running on battery.
    case chargingIndicator
    case hidden

    /// The metric whose sample the top marker depends on, if any. `automatic`
    /// resolves against the active side metrics and adds no dependency of its
    /// own; the resolver combines it with the ring metrics.
    var referencedMetric: HardwareMonitorMetric? {
        switch self {
        case .automatic, .hidden, .batteryPercentage, .chargingIndicator: return nil
        case let .symbol(metric), let .value(metric): return metric
        }
    }

    /// Whether the top marker reads the Mac battery rather than a hardware
    /// metric. Battery content adds no hardware-metric sampling demand, but it
    /// does require the battery sample.
    var usesBatteryStatus: Bool {
        switch self {
        case .batteryPercentage, .chargingIndicator: return true
        case .automatic, .symbol, .value, .hidden: return false
        }
    }

    // MARK: - Lenient Codable

    private enum CodingKeys: String, CodingKey { case kind, metric }

    private enum Kind: String {
        case automatic, symbol, value, batteryPercentage, chargingIndicator, hidden
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .automatic:
            try container.encode(Kind.automatic.rawValue, forKey: .kind)
        case .batteryPercentage:
            try container.encode(Kind.batteryPercentage.rawValue, forKey: .kind)
        case .chargingIndicator:
            try container.encode(Kind.chargingIndicator.rawValue, forKey: .kind)
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
        case .batteryPercentage:
            self = .batteryPercentage
        case .chargingIndicator:
            self = .chargingIndicator
        case .hidden:
            self = .hidden
        case .symbol:
            self = metric.map { HardwareRingTopContent.symbol($0) } ?? .automatic
        case .value:
            self = metric.map { HardwareRingTopContent.value($0) } ?? .automatic
        }
    }
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
        case .cpuTemperature, .gpuTemperature:
            return .init(displayMinimum: 30, displayMaximum: 100, warningThreshold: 85, criticalThreshold: 95)
        case .batteryTemperature:
            return .init(displayMinimum: 20, displayMaximum: 60, warningThreshold: 45, criticalThreshold: 55)
        case .fan:
            // `displayMaximum == displayMinimum` means "use the sample's trusted
            // maximum RPM"; without one the arc stays an unfilled track.
            return .init(displayMinimum: 0, displayMaximum: 0, warningThreshold: 3000, criticalThreshold: 5000)
        case .downloadSpeed:
            return .init(displayMinimum: 0, displayMaximum: 1000, warningThreshold: 0, criticalThreshold: 0)
        case .uploadSpeed:
            return .init(displayMinimum: 0, displayMaximum: 100, warningThreshold: 0, criticalThreshold: 0)
        case .volume, .wifiSignal:
            // Top-marker-only readings are plain percentages; the thresholds are
            // unused because they never fill an arc.
            return .init(displayMinimum: 0, displayMaximum: 100, warningThreshold: 0, criticalThreshold: 0)
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
        } else if metric.isSpeedMetric {
            // Range is a broadband cap in Mbps; keep it ordered and sane.
            min = 0
            max = Swift.min(100000, Swift.max(1, max))
            if max <= min {
                min = fallback.displayMinimum
                max = fallback.displayMaximum
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

/// Colour strategy for the hardware ring, expressed as two independent choices
/// instead of a three-way mode:
/// - `monochrome`: draw the ring in the menu-bar foreground (template), ignoring
///   metric colours entirely.
/// - `thresholdColors`: when coloured, recolour the whole filled arc orange/red
///   at the warning/critical thresholds. Irrelevant while `monochrome` is on.
///
/// The per-metric base colour is *not* stored here: it is the shared
/// "monitor metric colour" owned by the settings store, so the status-panel bar
/// and the ring arc always agree and editing the colour in either place writes
/// the same field.
struct HardwareRingColorConfiguration: Codable, Equatable, Hashable, Sendable {
    var monochrome: Bool
    var thresholdColors: Bool

    init(monochrome: Bool = false, thresholdColors: Bool = false) {
        self.monochrome = monochrome
        self.thresholdColors = thresholdColors
    }

    func normalized() -> HardwareRingColorConfiguration { self }

    // MARK: - Lenient Codable (migrates the old three-way `mode`)

    private enum CodingKeys: String, CodingKey {
        case monochrome, thresholdColors, mode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let monochrome = try container.decodeIfPresent(Bool.self, forKey: .monochrome) {
            self.monochrome = monochrome
            self.thresholdColors = (try container.decodeIfPresent(Bool.self, forKey: .thresholdColors)) ?? true
            return
        }
        // Legacy payload: status / fixed / monochrome.
        let rawMode = (try container.decodeIfPresent(String.self, forKey: .mode)) ?? "status"
        switch rawMode {
        case "monochrome":
            self.monochrome = true
            self.thresholdColors = false
        case "fixed":
            self.monochrome = false
            self.thresholdColors = false
        default:
            self.monochrome = false
            self.thresholdColors = true
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(monochrome, forKey: .monochrome)
        try container.encode(thresholdColors, forKey: .thresholdColors)
    }

    // MARK: - Apple-Silicon cool-glass palette (default identity colours)

    static let cpuColor = IconRGBA(red: 0.262745, green: 0.788235, blue: 0.478431, alpha: 1)      // #43C97A
    static let gpuColor = IconRGBA(red: 0.290196, green: 0.564706, blue: 1.000000, alpha: 1)      // #4A90FF
    static let memoryColor = IconRGBA(red: 0.643137, green: 0.466667, blue: 0.960784, alpha: 1)   // #A477F5
    static let solidStateDriveColor = IconRGBA(red: 0.666667, green: 0.709804, blue: 0.784314, alpha: 1) // #AAB5C8
    static let cpuTemperatureColor = IconRGBA(red: 0.207843, green: 0.749020, blue: 0.811765, alpha: 1)  // #35BFCF
    static let batteryTemperatureColor = IconRGBA(red: 0.211765, green: 0.678431, blue: 0.643137, alpha: 1) // #36ADA4
    static let fanColor = IconRGBA(red: 0.545098, green: 0.643137, blue: 0.764706, alpha: 1)      // #8BA4C3
    static let downloadColor = IconRGBA(red: 0.192157, green: 0.725490, blue: 0.521569, alpha: 1) // #31B985
    static let uploadColor = IconRGBA(red: 0.949020, green: 0.639216, blue: 0.294118, alpha: 1)   // #F2A34B
    static let volumeColor = IconRGBA(red: 0.462745, green: 0.560784, blue: 1.000000, alpha: 1)    // #768FFF
    static let signalStrengthColor = IconRGBA(red: 0.203922, green: 0.780392, blue: 0.349020, alpha: 1) // #34C759

    /// The recommended base colour for a metric (the default of the shared
    /// per-metric colour; used until the user picks a custom one).
    static func recommendedBaseColor(for metric: HardwareMonitorMetric) -> IconRGBA {
        switch metric {
        case .cpuUsage: cpuColor
        case .gpuUsage: gpuColor
        case .memoryUsage: memoryColor
        case .cpuTemperature: cpuColor
        case .gpuTemperature: cpuTemperatureColor
        case .batteryTemperature: batteryTemperatureColor
        case .fan: fanColor
        case .downloadSpeed: downloadColor
        case .uploadSpeed: uploadColor
        case .volume: volumeColor
        case .wifiSignal: signalStrengthColor
        }
    }

    /// Fixed warning / critical tints shared by every metric (whole-arc recolor).
    static let warningColor = IconRGBA(red: 0.960784, green: 0.647059, blue: 0.141176, alpha: 1)  // #F5A524
    static let criticalColor = IconRGBA(red: 0.894118, green: 0.329412, blue: 0.329412, alpha: 1) // #E45454
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
    /// User scale multiplier for the top marker (symbol or value), 0.6...1.6.
    var topMarkerScale: Double
    var color: HardwareRingColorConfiguration
    /// Sparse overrides; a missing metric uses `HardwareMetricRingOptions.default`.
    var overrides: [HardwareMonitorMetric: HardwareMetricRingOptions]

    static let topMarkerScaleRange: ClosedRange<Double> = 0.6...1.6
    static let defaultTopMarkerScale: Double = 1.0

    static func normalizedTopMarkerScale(_ value: Double) -> Double {
        guard value.isFinite else { return defaultTopMarkerScale }
        return min(topMarkerScaleRange.upperBound, max(topMarkerScaleRange.lowerBound, value))
    }

    init(layout: HardwareRingLayout = .single,
         primaryMetric: HardwareMonitorMetric = .cpuUsage,
         secondaryMetric: HardwareMonitorMetric? = nil,
         topContent: HardwareRingTopContent = .automatic,
         topMarkerScale: Double = HardwareRingConfiguration.defaultTopMarkerScale,
         color: HardwareRingColorConfiguration = .init(),
         overrides: [HardwareMonitorMetric: HardwareMetricRingOptions] = [:]) {
        self.layout = layout
        self.primaryMetric = primaryMetric
        self.secondaryMetric = secondaryMetric
        self.topContent = topContent
        self.topMarkerScale = Self.normalizedTopMarkerScale(topMarkerScale)
        self.color = color
        self.overrides = overrides
    }

    static let `default` = HardwareRingConfiguration()

    /// The top marker now offers only value or hidden. Legacy saved symbol /
    /// automatic choices migrate to a numeric value for the same metric so an
    /// upgrade never keeps drawing the unreadable menu-bar glyph.
    func migratingLegacyTopIcon() -> HardwareRingConfiguration {
        var copy = self
        switch copy.topContent {
        case .automatic:
            copy.topContent = .value(copy.primaryMetric)
        case let .symbol(metric):
            copy.topContent = .value(metric)
        case .value, .hidden, .batteryPercentage, .chargingIndicator:
            break
        }
        return copy
    }

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
        copy.topMarkerScale = Self.normalizedTopMarkerScale(topMarkerScale)
        copy.overrides = overrides.mapValues { $0 } // placeholder-normalised below
        for (metric, options) in overrides {
            copy.overrides[metric] = options.normalized(for: metric)
        }
        return copy
    }

    // MARK: - Lenient Codable

    private enum CodingKeys: String, CodingKey {
        case layout, primaryMetric, secondaryMetric, topContent, topMarkerScale, color, overrides
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
        let topScale = (try? container.decodeIfPresent(Double.self, forKey: .topMarkerScale)).flatMap { $0 }
            ?? fallback.topMarkerScale
        let color = (try? container.decode(HardwareRingColorConfiguration.self, forKey: .color)) ?? fallback.color
        let overrides = (try? container.decode([HardwareMonitorMetric: HardwareMetricRingOptions].self, forKey: .overrides)) ?? [:]
        self.init(layout: layout, primaryMetric: primary, secondaryMetric: secondary,
                  topContent: top, topMarkerScale: topScale, color: color, overrides: overrides)
    }
}

extension HardwareMonitorMetric {
    /// CPU/GPU/memory are percentages and their ring range is fixed 0...100%.
    var isPercentageMetric: Bool {
        switch self {
        case .cpuUsage, .gpuUsage, .memoryUsage: return true
        case .cpuTemperature, .gpuTemperature, .batteryTemperature, .fan: return false
        case .downloadSpeed, .uploadSpeed: return false
        case .volume, .wifiSignal: return true
        }
    }
}
