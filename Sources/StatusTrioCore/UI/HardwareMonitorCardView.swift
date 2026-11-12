import SwiftUI

/// A separately observed, fixed-size leaf: metric ticks never invalidate the
/// surrounding status panel or change its measured content height.
struct HardwareMonitorCardView: View {
    /// Card height for `count` visible tiles: two per row, fixed 24pt rows.
    static func height(for count: Int) -> CGFloat {
        let rows = max(1, (count + 1) / 2)
        return CGFloat(rows * 24 + (rows - 1) * 12 + 24)
    }

    /// The card's own fill is an overlay on the panel material, not a separate
    /// surface. Reduce Transparency raises it so the card keeps a visible edge
    /// when the panel material becomes opaque.
    static func backgroundOpacity(reduceTransparency: Bool) -> Double {
        reduceTransparency ? 0.10 : 0.045
    }

    @ObservedObject var model: HardwareMonitorObservable
    /// Visible tiles in the user's order; driven by Settings → 监控.
    let metrics: [HardwareMonitorMetric]
    /// Shared per-metric colours (same field as the hardware ring arc).
    var metricColors: [HardwareMonitorMetric: IconRGBA] = [:]
    /// Broadband caps (Mbps) for the network-speed tiles.
    var speedCapsMbps: [HardwareMonitorMetric: Double] = [:]
    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let tiles = HardwareMetricTilePresentation.tiles(metrics: metrics, snapshot: model.snapshot,
                                                          localization: localization, colors: metricColors,
                                                          speedCapsMbps: speedCapsMbps)
        VStack(spacing: 12) {
            ForEach(Array(stride(from: 0, to: max(tiles.count, 1), by: 2)), id: \.self) { index in
                HStack(spacing: 14) {
                    if index < tiles.count {
                        HardwareMonitorTileView(presentation: tiles[index])
                    }
                    if index + 1 < tiles.count {
                        HardwareMonitorTileView(presentation: tiles[index + 1])
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height(for: metrics.count))
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(Self.backgroundOpacity(reduceTransparency: reduceTransparency)))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localization.string(.hardwareMonitorTitle))
    }
}

enum HardwareMonitorTile: CaseIterable, Equatable {
    case cpu, gpu, memory, temperature, batteryTemperature, fan, download, upload

    var labelKey: LocalizationKey {
        switch self {
        case .cpu: .hardwareMonitorCPU
        case .gpu: .hardwareMonitorGPU
        case .memory: .hardwareMonitorMemory
        case .temperature: .hardwareMonitorTemperature
        case .batteryTemperature: .hardwareMonitorBattery
        case .fan: .hardwareMonitorFan
        case .download: .hardwareMonitorDownload
        case .upload: .hardwareMonitorUpload
        }
    }

    var isSpeed: Bool { self == .download || self == .upload }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "display"
        case .memory: "memorychip"
        case .temperature: "thermometer.medium"
        case .batteryTemperature: SymbolFallback.name("battery.100percent", "battery.100")
        case .fan: "fanblades"
        case .download: "arrow.down"
        case .upload: "arrow.up"
        }
    }
}

/// Keeps formatting, unavailable-state semantics, and animation policy testable
/// without presenting a native window.
struct HardwareMetricTilePresentation: Equatable {
    let metric: HardwareMonitorTile
    let label: String
    let valueText: String
    let accessibilityValue: String
    let help: String
    let explanation: String
    let progress: Double?
    let availability: HardwareMetricAvailability
    let sensorLabel: String?
    /// True when showing a cached last reading (rendered dimmed + marked expired).
    let isStale: Bool
    /// Shared per-metric colour (same field as the hardware ring arc).
    let tint: IconRGBA

    @MainActor
    static func tiles(snapshot: HardwareMetricsSnapshot, localization: Localization) -> [Self] {
        tiles(metrics: HardwareMonitorMetric.defaultCardMetrics, snapshot: snapshot, localization: localization)
    }

    @MainActor
    static func tiles(metrics: [HardwareMonitorMetric], snapshot: HardwareMetricsSnapshot,
                      localization: Localization,
                      colors: [HardwareMonitorMetric: IconRGBA] = [:],
                      speedCapsMbps: [HardwareMonitorMetric: Double] = [:]) -> [Self] {
        metrics.map { metric in
            let tint = colors[metric] ?? HardwareRingColorConfiguration.recommendedBaseColor(for: metric)
            switch metric {
            case .cpuUsage:
                return make(metric: .cpu, sample: snapshot.cpuUsage, localization: localization, tint: tint)
            case .gpuUsage:
                return make(metric: .gpu, sample: snapshot.gpuUsage, localization: localization, tint: tint)
            case .memoryUsage:
                return make(metric: .memory, sample: snapshot.memoryUsage, localization: localization, tint: tint)
            case .cpuTemperature:
                return make(metric: .temperature, sample: snapshot.cpuTemperature, localization: localization, tint: tint)
            case .batteryTemperature:
                return make(metric: .batteryTemperature, sample: snapshot.batteryTemperature,
                            localization: localization, tint: tint)
            case .fan:
                return make(metric: .fan, sample: snapshot.fanSummarySample, localization: localization, tint: tint)
            case .downloadSpeed:
                return make(metric: .download, sample: snapshot.networkDownload, localization: localization,
                            tint: tint, capMbps: speedCapsMbps[.downloadSpeed])
            case .uploadSpeed:
                return make(metric: .upload, sample: snapshot.networkUpload, localization: localization,
                            tint: tint, capMbps: speedCapsMbps[.uploadSpeed])
            }
        }
    }

    @MainActor
    static func make(metric: HardwareMonitorTile, sample: HardwareMetricSample, localization: Localization,
                     tint: IconRGBA = .white, capMbps: Double? = nil) -> Self {
        let isStale = sample.availability == .stale
        // A stale sample keeps its last value as a cached reading: show it dimmed
        // rather than flashing "—" until the next fresh sample arrives.
        let eligible = sample.availability == .measured || isStale
        let value = eligible ? sample.value.flatMap { $0.isFinite ? $0 : nil } : nil
        let availability: HardwareMetricAvailability = sample.availability == .measured && value == nil
            ? .temporarilyUnavailable : sample.availability
        let label = localization.string(metric.labelKey)
        let valueText: String
        var accessibilityValue: String
        let progress: Double?
        if let value {
            let locale = localization.resolvedLanguage.locale
            let number = value.formatted(.number.precision(.fractionLength(0)).locale(locale))
            switch metric {
            case .cpu, .gpu, .memory:
                valueText = (value / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
                accessibilityValue = valueText
                progress = MetricProgressMapper.percent(sample)
            case .temperature:
                valueText = "\(number)°C"
                accessibilityValue = valueText
                progress = MetricProgressMapper.temperature(sample)
            case .batteryTemperature:
                valueText = "\(number)°C"
                accessibilityValue = valueText
                // Battery runs near ambient: use a lower visual scale than CPU.
                progress = MetricProgressMapper.temperature(sample, range: 20...60)
            case .fan:
                valueText = number
                accessibilityValue = localization.format(.hardwareMonitorRPM, number)
                progress = MetricProgressMapper.rpm(sample)
            case .download, .upload:
                valueText = NetworkSpeedFormatter.displayWithBits(bytesPerSecond: value)
                accessibilityValue = valueText
                progress = MetricProgressMapper.speed(sample, capMbps: capMbps ?? 0)
            }
            if isStale {
                accessibilityValue += ", " + localization.string(.hardwareMonitorStale)
            }
        } else {
            valueText = "—"
            let statusKey: LocalizationKey
            if metric == .fan && sample.metadata.isFanless {
                statusKey = .hardwareMonitorFanless
            } else {
                switch availability {
                case .collecting: statusKey = .hardwareMonitorCollecting
                case .unsupported: statusKey = .hardwareMonitorUnsupported
                case .temporarilyUnavailable, .measured: statusKey = .hardwareMonitorUnavailable
                case .stale: statusKey = .hardwareMonitorStale
                }
            }
            accessibilityValue = localization.string(statusKey)
            progress = nil
        }
        let explanation: String
        switch metric {
        case .temperature: explanation = localization.string(.hardwareMonitorTemperatureHelp)
        case .batteryTemperature: explanation = localization.string(.hardwareMonitorBatteryTemperatureHelp)
        case .fan: explanation = localization.string(.hardwareMonitorFanHelp)
        case .cpu, .gpu, .memory: explanation = ""
        case .download, .upload: explanation = ""
        }
        let help = ["\(label): \(accessibilityValue)", explanation].filter { !$0.isEmpty }.joined(separator: "\n")
        return Self(metric: metric, label: label, valueText: valueText,
                    accessibilityValue: accessibilityValue, help: help, explanation: explanation, progress: progress,
                    availability: availability, sensorLabel: sample.sensorLabel, isStale: isStale, tint: tint)
    }

    static func shouldAnimateProgress(from previous: Self?, to current: Self, reduceMotion: Bool) -> Bool {
        guard !reduceMotion, let previous,
              previous.metric == current.metric,
              previous.availability == .measured, current.availability == .measured,
              previous.sensorLabel == current.sensorLabel,
              previous.progress != nil, current.progress != nil else { return false }
        return previous.progress != current.progress
    }
}

private struct HardwareMonitorTileView: View {
    let presentation: HardwareMetricTilePresentation

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                HardwareMetricSymbolView(symbol: presentation.metric.symbol, box: 14, glyph: 11)
                Text(presentation.label)
                    .font(.system(size: presentation.metric.isSpeed ? 10 : 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text(presentation.valueText)
                    .font(.system(size: presentation.metric.isSpeed ? 10 : 11, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(presentation.metric.isSpeed ? 0.5 : 0.8)
                    .frame(width: presentation.metric.isSpeed ? 118 : 52, alignment: .trailing)
                    .opacity(presentation.isStale ? 0.6 : 1)
            }
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            HardwareMonitorProgressTrack(presentation: presentation)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .help(presentation.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.label)
        .accessibilityValue(presentation.accessibilityValue)
        .accessibilityHint(presentation.explanation)
    }
}

private struct HardwareMonitorProgressTrack: View {
    let presentation: HardwareMetricTilePresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedProgress: Double
    @State private var previous: HardwareMetricTilePresentation?

    init(presentation: HardwareMetricTilePresentation) {
        self.presentation = presentation
        _displayedProgress = State(initialValue: presentation.progress ?? 0)
        _previous = State(initialValue: nil)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(IconAppearanceColorConversion.color(from: presentation.tint))
                    .frame(width: geometry.size.width * displayedProgress)
                    .opacity(presentation.progress == nil ? 0 : (presentation.isStale ? 0.45 : 1))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
        .onAppear { updateProgress(presentation, animated: false) }
        .onDisappear { previous = nil }
        // The single-argument overload keeps the macOS 13 deployment contract.
        // Use the value the modifier hands us: inside `updateProgress`, `self`
        // can still be the pre-change view, which made the bar stay grey until
        // the next sensor tick after reopening the panel.
        .onChange(of: presentation) { current in
            updateProgress(current, animated: HardwareMetricTilePresentation.shouldAnimateProgress(
                from: previous, to: current, reduceMotion: reduceMotion
            ))
        }
    }

    private func updateProgress(_ current: HardwareMetricTilePresentation, animated: Bool) {
        var transaction = Transaction(animation: animated ? .linear(duration: 0.2) : nil)
        transaction.disablesAnimations = !animated
        withTransaction(transaction) {
            displayedProgress = current.progress ?? 0
        }
        previous = current
    }
}
