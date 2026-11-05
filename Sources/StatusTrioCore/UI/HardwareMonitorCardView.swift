import SwiftUI

/// A separately observed, fixed-size leaf: metric ticks never invalidate the
/// surrounding status panel or change its measured content height.
struct HardwareMonitorCardView: View {
    static let height: CGFloat = 84

    /// The card's own fill is an overlay on the panel material, not a separate
    /// surface. Reduce Transparency raises it so the card keeps a visible edge
    /// when the panel material becomes opaque.
    static func backgroundOpacity(reduceTransparency: Bool) -> Double {
        reduceTransparency ? 0.10 : 0.045
    }

    @ObservedObject var model: HardwareMonitorObservable
    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let tiles = HardwareMetricTilePresentation.tiles(snapshot: model.snapshot, localization: localization)
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                HardwareMonitorTileView(presentation: tiles[0])
                HardwareMonitorTileView(presentation: tiles[1])
            }
            HStack(spacing: 14) {
                HardwareMonitorTileView(presentation: tiles[2])
                HardwareMonitorTileView(presentation: tiles[3])
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(Self.backgroundOpacity(reduceTransparency: reduceTransparency)))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localization.string(.hardwareMonitorTitle))
    }
}

enum HardwareMonitorTile: CaseIterable, Equatable {
    case cpu, gpu, temperature, fan

    var labelKey: LocalizationKey {
        switch self {
        case .cpu: .hardwareMonitorCPU
        case .gpu: .hardwareMonitorGPU
        case .temperature: .hardwareMonitorTemperature
        case .fan: .hardwareMonitorFan
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "display"
        case .temperature: "thermometer.medium"
        case .fan: "fanblades"
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

    @MainActor
    static func tiles(snapshot: HardwareMetricsSnapshot, localization: Localization) -> [Self] {
        [
            make(metric: .cpu, sample: snapshot.cpuUsage, localization: localization),
            make(metric: .gpu, sample: snapshot.gpuUsage, localization: localization),
            make(metric: .temperature, sample: snapshot.cpuTemperature, localization: localization),
            make(metric: .fan, sample: snapshot.fanSummarySample, localization: localization)
        ]
    }

    @MainActor
    static func make(metric: HardwareMonitorTile, sample: HardwareMetricSample, localization: Localization) -> Self {
        let value = sample.availability == .measured ? sample.value.flatMap { $0.isFinite ? $0 : nil } : nil
        let availability: HardwareMetricAvailability = sample.availability == .measured && value == nil
            ? .temporarilyUnavailable : sample.availability
        let label = localization.string(metric.labelKey)
        let valueText: String
        let accessibilityValue: String
        let progress: Double?
        if let value {
            let locale = localization.resolvedLanguage.locale
            let number = value.formatted(.number.precision(.fractionLength(0)).locale(locale))
            switch metric {
            case .cpu, .gpu:
                valueText = (value / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
                accessibilityValue = valueText
                progress = MetricProgressMapper.percent(sample)
            case .temperature:
                valueText = "\(number)°C"
                accessibilityValue = valueText
                progress = MetricProgressMapper.temperature(sample)
            case .fan:
                valueText = number
                accessibilityValue = localization.format(.hardwareMonitorRPM, number)
                progress = MetricProgressMapper.rpm(sample)
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
        case .fan: explanation = localization.string(.hardwareMonitorFanHelp)
        case .cpu, .gpu: explanation = ""
        }
        let help = ["\(label): \(accessibilityValue)", explanation].filter { !$0.isEmpty }.joined(separator: "\n")
        return Self(metric: metric, label: label, valueText: valueText,
                    accessibilityValue: accessibilityValue, help: help, explanation: explanation, progress: progress,
                    availability: availability, sensorLabel: sample.sensorLabel)
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
                Image(systemName: presentation.metric.symbol)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Text(presentation.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Text(presentation.valueText)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 52, alignment: .trailing)
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
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * displayedProgress)
                    .opacity(presentation.progress == nil ? 0 : 1)
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
