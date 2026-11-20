import Foundation

/// Pure translation of UI consumers into the hardware metrics they need.
///
/// No sampling, no state, no clocks: callers decide which consumers are
/// currently visible and this resolver answers the exact set that should stay
/// demanded. Keeping it pure makes every mapping table unit-testable and stops
/// the old "request the whole summary set" shortcut from creeping back in.
enum HardwareMetricDemandResolver {
    /// Which parts of the compact status-panel hardware summary can be seen.
    struct PanelSummaryInputs: Equatable, Sendable {
        var showsHardwareRings: Bool
        var enabledRingSlots: Set<HardwareRingSlot>
        var showsHardwareSummaryRow: Bool
        var enabledSummaryMetrics: Set<HardwareSummaryMetric>

        init(showsHardwareRings: Bool,
             enabledRingSlots: Set<HardwareRingSlot>,
             showsHardwareSummaryRow: Bool,
             enabledSummaryMetrics: Set<HardwareSummaryMetric>) {
            self.showsHardwareRings = showsHardwareRings
            self.enabledRingSlots = enabledRingSlots
            self.showsHardwareSummaryRow = showsHardwareSummaryRow
            self.enabledSummaryMetrics = enabledSummaryMetrics
        }
    }

    /// Metrics the visible summary blocks need. The SSD ring shows a one-shot
    /// capacity read, never a periodic metric, so it contributes nothing here.
    static func summaryMetrics(for inputs: PanelSummaryInputs) -> Set<HardwareMetricID> {
        var metrics: Set<HardwareMetricID> = []
        if inputs.showsHardwareRings {
            for slot in inputs.enabledRingSlots {
                switch slot {
                case .cpu:
                    metrics.insert(.cpuUsage)
                    metrics.insert(.cpuTemperature)
                case .gpu:
                    metrics.insert(.gpuUsage)
                    metrics.insert(.gpuTemperature)
                case .ram:
                    metrics.insert(.memoryUsage)
                case .ssd:
                    break
                }
            }
        }
        if inputs.showsHardwareSummaryRow {
            for item in inputs.enabledSummaryMetrics {
                switch item {
                case .download:
                    metrics.insert(.networkDownload)
                case .upload:
                    metrics.insert(.networkUpload)
                case .fan:
                    metrics.insert(.fanRPM(index: 0))
                case .disk:
                    metrics.insert(.diskRead)
                    metrics.insert(.diskWrite)
                }
            }
        }
        return metrics
    }

    /// Metrics each detail page needs. Kept here as the single canonical table;
    /// `HardwareMetricsService.detailMetricIDs(for:)` delegates to it.
    static func detailMetrics(for kind: HardwareDetailKind) -> Set<HardwareMetricID> {
        switch kind {
        case .cpu:
            return [.cpuUsage, .cpuTemperature]
        case .gpu:
            return [.gpuUsage, .gpuTemperature]
        case .memory:
            return [.memoryUsage]
        case .network:
            return [.networkDownload, .networkUpload]
        case .disk:
            return [.diskRead, .diskWrite]
        case .fan:
            return [.fanRPM(index: 0), .cpuTemperature, .gpuTemperature, .batteryTemperature]
        }
    }

    /// Union of the visible summary blocks and the open detail page. Returns an
    /// empty set when neither consumer is visible, so callers can end the
    /// `.panel` demand instead of sampling on behalf of a hidden card.
    static func panelMetrics(summary: PanelSummaryInputs?,
                             detailKind: HardwareDetailKind?) -> Set<HardwareMetricID> {
        var metrics: Set<HardwareMetricID> = []
        if let summary {
            metrics.formUnion(summaryMetrics(for: summary))
        }
        if let detailKind {
            metrics.formUnion(detailMetrics(for: detailKind))
        }
        return metrics
    }

    /// Which metrics a menu-bar/Dock hardware ring needs. Volume and Wi-Fi
    /// signal ride the general status snapshot, so they never start the
    /// hardware sampler; selecting only those yields an empty set.
    static func iconRingMetrics(configuration: HardwareRingConfiguration) -> Set<HardwareMetricID> {
        Set(configuration.normalized().referencedMetrics
            .filter { !$0.usesStatusSnapshot }
            .map { $0.metricID })
    }

    /// Background history only ever records the primary sample metrics. Union
    /// the enabled summary blocks and intersect with the history metric list so
    /// a background consumer never samples a temperature or fan it will not
    /// record.
    static func backgroundHistoryMetrics(summary: PanelSummaryInputs) -> Set<HardwareMetricID> {
        summaryMetrics(for: summary)
            .intersection(HardwareMonitorObservable.historyMetricIDs)
    }
}
