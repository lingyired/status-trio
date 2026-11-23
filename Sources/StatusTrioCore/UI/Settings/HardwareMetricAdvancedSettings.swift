import SwiftUI

/// Per-metric advanced settings (warning/critical thresholds, display range and
/// speed cap) shared by the icon ring, the bottom indicator and System
/// Monitoring. Every edit writes the shared `HardwareRingConfiguration`, so a
/// change applies to all surfaces at once.
struct HardwareMetricAdvancedRow: View {
    @ObservedObject var store: SettingsStore
    let metric: HardwareMonitorMetric
    @EnvironmentObject private var localization: Localization

    @ViewBuilder
    var body: some View {
        if metric.isSpeedMetric {
            SettingsRow(
                title: label,
                subtitle: localization.string(.hardwareMonitorSpeedCapDescription),
                leading: { SettingsIcon(symbol: metric.systemImage, tint: .orange) },
                trailing: { HardwareCapField(value: speedCapBinding, range: SettingsStore.hardwareSpeedCapRange) }
            )
        } else {
            let thresholdsEnabled = !store.hardwareRingConfiguration.color.monochrome
                && store.hardwareRingConfiguration.color.thresholdColors
            SettingsRow(
                title: label,
                subtitle: rangeSubtitle,
                leading: { SettingsIcon(symbol: metric.systemImage, tint: .orange) },
                trailing: {
                    VStack(alignment: .trailing, spacing: 6) {
                        stepper(localization.string(.settingsHardwareRingWarning),
                                binding(\.warningThreshold), range: stepperRange,
                                step: metric == .fan ? 100 : 1)
                            .disabled(!thresholdsEnabled)
                        stepper(localization.string(.settingsHardwareRingCritical),
                                binding(\.criticalThreshold), range: stepperRange,
                                step: metric == .fan ? 100 : 1)
                            .disabled(!thresholdsEnabled)
                        if !metric.isPercentageMetric && metric != .fan {
                            stepper("\(localization.string(.settingsHardwareRingRange)) ↓",
                                    binding(\.displayMinimum), range: -50...150, step: 1)
                            stepper("\(localization.string(.settingsHardwareRingRange)) ↑",
                                    binding(\.displayMaximum), range: -50...150, step: 1)
                        }
                    }
                }
            )
        }
    }

    private var label: String { localization.string(metric.titleKey) }

    private var stepperRange: ClosedRange<Double> {
        switch metric {
        case .cpuUsage, .gpuUsage, .memoryUsage: return 0...100
        case .cpuTemperature, .gpuTemperature: return 30...120
        case .batteryTemperature: return 20...80
        case .fan: return 0...10_000
        case .downloadSpeed, .uploadSpeed: return SettingsStore.hardwareSpeedCapRange
        case .volume, .wifiSignal, .batteryLevel: return 0...100
        }
    }

    private var rangeSubtitle: String? {
        guard !metric.isPercentageMetric, !metric.isSpeedMetric, metric != .fan else { return nil }
        let options = store.hardwareRingConfiguration.options(for: metric)
        return "\(localization.string(.settingsHardwareRingRange)): \(Int(options.displayMinimum))–\(Int(options.displayMaximum))°C"
    }

    private func binding(
        _ keyPath: WritableKeyPath<HardwareMetricRingOptions, Double>
    ) -> Binding<Double> {
        Binding(
            get: { store.hardwareRingConfiguration.options(for: metric)[keyPath: keyPath] },
            set: { newValue in
                var configuration = store.hardwareRingConfiguration
                var options = configuration.options(for: metric)
                options[keyPath: keyPath] = newValue
                configuration.overrides[metric] = options.normalized(for: metric)
                store.hardwareRingConfiguration = configuration
            }
        )
    }

    private var speedCapBinding: Binding<Double> {
        metric == .downloadSpeed
            ? Binding(get: { store.hardwareDownloadCapMbps },
                      set: { store.hardwareDownloadCapMbps = $0.rounded() })
            : Binding(get: { store.hardwareUploadCapMbps },
                      set: { store.hardwareUploadCapMbps = $0.rounded() })
    }

    private func stepper(
        _ label: String,
        _ value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Stepper(value: value, in: range, step: step) {
                Text("\(Int(value.wrappedValue.rounded()))")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 44, alignment: .trailing)
            }
            .controlSize(.small)
        }
    }
}

/// A group of advanced metric settings with an optional "reset all" action.
struct HardwareMetricAdvancedGroup: View {
    @ObservedObject var store: SettingsStore
    let metrics: [HardwareMonitorMetric]
    var title: LocalizationKey = .settingsHardwareRingGroupAdvanced
    var showsReset: Bool = true
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsGroup(localization.string(title)) {
            ForEach(Array(metrics.enumerated()), id: \.element) { index, metric in
                if index > 0 { SettingsDivider() }
                HardwareMetricAdvancedRow(store: store, metric: metric)
            }
            if showsReset {
                SettingsDivider()
                SettingsRow(
                    title: localization.string(.settingsHardwareRingReset),
                    subtitle: nil,
                    leading: { SettingsIcon(symbol: "arrow.counterclockwise", tint: .gray) },
                    trailing: {
                        Button(localization.string(.settingsHardwareRingReset)) { reset() }
                            .controlSize(.small)
                    }
                )
            }
        }
    }

    private func reset() {
        var configuration = store.hardwareRingConfiguration
        for metric in metrics { configuration.overrides[metric] = nil }
        store.hardwareRingConfiguration = configuration
    }
}
