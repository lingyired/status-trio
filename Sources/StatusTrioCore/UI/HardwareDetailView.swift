import SwiftUI

/// One unified system-monitor detail page for CPU / GPU / memory / network / disk.
/// All five share the header, card, trend chart and history buffer; only the
/// per-kind bodies differ.
struct HardwareDetailView: View {
    let kind: HardwareDetailKind
    @ObservedObject var hardware: HardwareMonitorObservable
    let onBack: () -> Void
    /// Static history for an offscreen render; nil in the live app.
    var previewHistory: [HardwareDetailHistoryPoint]? = nil

    @EnvironmentObject private var localization: Localization
    @StateObject private var history: HardwareDetailHistoryStore

    init(kind: HardwareDetailKind, hardware: HardwareMonitorObservable,
         onBack: @escaping () -> Void,
         previewHistory: [HardwareDetailHistoryPoint]? = nil) {
        self.kind = kind
        _hardware = ObservedObject(wrappedValue: hardware)
        self.onBack = onBack
        self.previewHistory = previewHistory
        _history = StateObject(wrappedValue: HardwareDetailHistoryStore(seriesCount: kind.historySeriesCount,
                                                                        seeded: previewHistory))
    }

    private var snapshot: HardwareMetricsSnapshot { hardware.snapshot }
    private var now: Date { Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationBackRow(accessibilityLabel: localization.string(.hardwareDetailBack),
                              title: localization.string(kind.titleKey),
                              action: onBack)
            content
        }
        .onAppear {
            guard previewHistory == nil else { return }
            history.start(observable: hardware,
                          timestamp: kind.sampleDate,
                          values: kind.sampleValues,
                          seedRows: hardware.historyRowsForDetail,
                          seedMetricIDs: kind.historyMetricIDs)
        }
        .onDisappear { history.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .cpu: cpuContent
        case .gpu: gpuContent
        case .memory: memoryContent
        case .network: networkContent
        case .disk: diskContent
        }
    }

    // MARK: - CPU

    private var cpuContent: some View {
        let detail = snapshot.cpuDetail
        let usage = detail?.usage ?? snapshot[.cpuUsage].value
        let temperature = snapshot[.cpuTemperature].value
        return VStack(alignment: .leading, spacing: 12) {
            HardwareDetailCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(localization.string(.hardwareDetailTotalUsage))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(HardwareDetailFormat.percent(usage))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    HardwareDetailProgressBar(fraction: (usage ?? 0) / 100)
                    HStack(spacing: 0) {
                        topMetric(localization.string(.hardwareDetailTemperature),
                                  HardwareDetailFormat.temperature(temperature))
                        verticalDivider
                        topMetric(localization.string(.hardwareDetailLogicalCores),
                                  HardwareDetailFormat.integer(detail?.coreCount))
                    }
                }
            }
            HStack(alignment: .top, spacing: 8) {
                coreCard(title: localization.string(.hardwareDetailEfficiencyCores),
                         average: detail?.groupUsage?.efficiencyAverage,
                         count: detail?.topology?.efficiencyCoreCount,
                         frequency: detail?.frequency?.efficiencyGHz)
                coreCard(title: localization.string(.hardwareDetailPerformanceCores),
                         average: detail?.groupUsage?.performanceAverage,
                         count: detail?.topology?.performanceCoreCount,
                         frequency: detail?.frequency?.performanceGHz)
            }
            trendCard(title: localization.string(.hardwareDetailUsageTrend),
                      colors: [Color.accentColor], scale: .percent)
            HardwareDetailCard {
                VStack(alignment: .leading, spacing: 6) {
                    HardwareDetailRow(label: localization.string(.hardwareDetailUser),
                                      value: HardwareDetailFormat.percent(detail?.breakdown.user))
                    HardwareDetailRow(label: localization.string(.hardwareDetailSystem),
                                      value: HardwareDetailFormat.percent(detail?.breakdown.system))
                    HardwareDetailRow(label: localization.string(.hardwareDetailIdle),
                                      value: HardwareDetailFormat.percent(detail?.breakdown.idle))
                    HardwareDetailRow(label: localization.string(.hardwareDetailNice),
                                      value: HardwareDetailFormat.percent(detail?.breakdown.nice))
                    divider
                    HardwareDetailRow(label: localization.string(.hardwareDetailComposition),
                                      value: coreComposition(detail?.topology))
                }
            }
        }
    }

    private func coreCard(title: String, average: Double?, count: Int?, frequency: Double?) -> some View {
        HardwareDetailCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Text("\(localization.string(.hardwareDetailCores)) \(HardwareDetailFormat.integer(count))")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(HardwareDetailFormat.percent(average))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                HStack(spacing: 3) {
                    Text(localization.string(.hardwareDetailEstimatedFrequency))
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(HardwareDetailFormat.frequency(frequency))
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                HardwareDetailProgressBar(fraction: (average ?? 0) / 100)
            }
        }
    }

    private func coreComposition(_ topology: CPUCoreTopology?) -> String {
        guard let topology, topology.isRecognized else { return HardwareDetailFormat.dash }
        var parts: [String] = []
        if topology.performanceCoreCount > 0 { parts.append("\(topology.performanceCoreCount)P") }
        if topology.efficiencyCoreCount > 0 { parts.append("\(topology.efficiencyCoreCount)E") }
        if topology.superCoreCount > 0 { parts.append("\(topology.superCoreCount)S") }
        return parts.isEmpty ? HardwareDetailFormat.dash : parts.joined(separator: " + ")
    }

    // MARK: - GPU

    private var gpuContent: some View {
        let detail = snapshot.gpuDetail
        let usage = detail?.usage ?? snapshot[.gpuUsage].value
        let temperature = snapshot[.gpuTemperature].value
        return VStack(alignment: .leading, spacing: 12) {
            HardwareDetailCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(localization.string(.hardwareDetailUsage))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(HardwareDetailFormat.percent(usage))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    HardwareDetailProgressBar(fraction: (usage ?? 0) / 100)
                    HStack(spacing: 0) {
                        topMetric(localization.string(.hardwareDetailTemperature),
                                  HardwareDetailFormat.temperature(temperature))
                        verticalDivider
                        topMetric(localization.string(.hardwareDetailDevice),
                                  detail?.deviceName ?? snapshot[.gpuUsage].sensorLabel ?? HardwareDetailFormat.dash)
                    }
                }
            }
            trendCard(title: localization.string(.hardwareDetailUsageTrend),
                      colors: [Color.accentColor], scale: .percent)
            HardwareDetailCard {
                VStack(alignment: .leading, spacing: 6) {
                    HardwareDetailRow(label: localization.string(.hardwareDetailRenderer),
                                      value: HardwareDetailFormat.percent(detail?.rendererUtilization))
                    HardwareDetailRow(label: localization.string(.hardwareDetailTiler),
                                      value: HardwareDetailFormat.percent(detail?.tilerUtilization))
                    HardwareDetailRow(label: localization.string(.hardwareDetailGPUMemory),
                                      value: HardwareDetailFormat.bytes(detail?.inUseSystemMemoryBytes))
                    divider
                    HardwareDetailRow(label: localization.string(.hardwareDetailDevice),
                                      value: detail?.deviceName ?? HardwareDetailFormat.dash)
                }
            }
        }
    }

    // MARK: - Memory

    private var memoryContent: some View {
        let detail = snapshot.memoryDetail
        let percent = detail?.percent ?? snapshot[.memoryUsage].value
        return VStack(alignment: .leading, spacing: 12) {
            HardwareDetailCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(localization.string(.hardwareDetailUsage))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(HardwareDetailFormat.percent(percent))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    HardwareDetailProgressBar(fraction: (percent ?? 0) / 100)
                    HStack(spacing: 0) {
                        topMetric(localization.string(.hardwareDetailUsed),
                                  HardwareDetailFormat.bytes(detail?.usedBytes))
                        verticalDivider
                        topMetric(localization.string(.hardwareDetailTotal),
                                  HardwareDetailFormat.bytes(detail?.totalBytes))
                    }
                }
            }
            trendCard(title: localization.string(.hardwareDetailUsageTrend),
                      colors: [Color.accentColor], scale: .percent)
            HardwareDetailCard {
                VStack(alignment: .leading, spacing: 6) {
                    HardwareDetailRow(label: localization.string(.hardwareDetailAppMemory),
                                      value: HardwareDetailFormat.bytes(detail?.appBytes))
                    HardwareDetailRow(label: localization.string(.hardwareDetailWired),
                                      value: HardwareDetailFormat.bytes(detail?.wiredBytes))
                    HardwareDetailRow(label: localization.string(.hardwareDetailCompressed),
                                      value: HardwareDetailFormat.bytes(detail?.compressedBytes))
                    HardwareDetailRow(label: localization.string(.hardwareDetailCached),
                                      value: HardwareDetailFormat.bytes(detail?.cachedBytes))
                    HardwareDetailRow(label: localization.string(.hardwareDetailSwapUsed),
                                      value: HardwareDetailFormat.bytes(detail?.swapUsedBytes))
                    divider
                    HardwareDetailRow(label: localization.string(.hardwareDetailPressure),
                                      value: pressureText(detail?.pressure))
                }
            }
        }
    }

    private func pressureText(_ pressure: MemoryPressureLevel?) -> String {
        switch pressure {
        case .normal: return localization.string(.hardwareDetailPressureNormal)
        case .warning: return localization.string(.hardwareDetailPressureWarning)
        case .critical: return localization.string(.hardwareDetailPressureCritical)
        case .unknown, .none: return HardwareDetailFormat.dash
        }
    }

    // MARK: - Network

    private var networkContent: some View {
        let detail = snapshot.networkDetail
        let download = detail?.downloadBytesPerSecond ?? snapshot[.networkDownload].value
        let upload = detail?.uploadBytesPerSecond ?? snapshot[.networkUpload].value
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                coloredMetricCard(title: localization.string(.hardwareDetailDownload),
                                  value: HardwareDetailFormat.rate(download), color: .blue)
                coloredMetricCard(title: localization.string(.hardwareDetailUpload),
                                  value: HardwareDetailFormat.rate(upload), color: .green)
            }
            trendCard(title: localization.string(.hardwareDetailSpeedTrend),
                      colors: [.blue, .green], scale: .auto)
            HardwareDetailCard {
                VStack(alignment: .leading, spacing: 6) {
                    HardwareDetailRow(label: localization.string(.hardwareDetailInterfaces),
                                      value: interfaceText(detail?.interfaces))
                    divider
                    HardwareDetailRow(label: localization.string(.hardwareDetailDownload),
                                      value: HardwareDetailFormat.rate(download))
                    HardwareDetailRow(label: localization.string(.hardwareDetailUpload),
                                      value: HardwareDetailFormat.rate(upload))
                    divider
                    HardwareDetailRow(label: localization.string(.hardwareDetailSessionDownload),
                                      value: HardwareDetailFormat.bytes(detail?.sessionReceivedBytes))
                    HardwareDetailRow(label: localization.string(.hardwareDetailSessionUpload),
                                      value: HardwareDetailFormat.bytes(detail?.sessionSentBytes))
                }
            }
        }
    }

    private func interfaceText(_ interfaces: [String]?) -> String {
        guard let interfaces, !interfaces.isEmpty else { return HardwareDetailFormat.dash }
        return interfaces.joined(separator: ", ")
    }

    // MARK: - Disk

    private var diskContent: some View {
        let detail = snapshot.diskDetail
        let capacity = detail?.capacity
        return VStack(alignment: .leading, spacing: 12) {
            HardwareDetailCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(localization.string(.hardwareDetailFreeSpace))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(HardwareDetailFormat.bytes(capacity?.freeBytes))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    HardwareDetailProgressBar(fraction: capacity?.usedFraction ?? 0)
                    HStack(spacing: 0) {
                        topMetric(localization.string(.hardwareDetailTotal),
                                  HardwareDetailFormat.bytes(capacity?.totalBytes))
                        verticalDivider
                        topMetric(localization.string(.hardwareDetailUsage),
                                  HardwareDetailFormat.fractionPercent(capacity?.usedFraction))
                    }
                }
            }
            trendCard(title: localization.string(.hardwareDetailSpeedTrend),
                      colors: [.orange, .purple], scale: .auto)
            HardwareDetailCard {
                VStack(alignment: .leading, spacing: 6) {
                    HardwareDetailRow(label: localization.string(.hardwareDetailUsedSpace),
                                      value: HardwareDetailFormat.bytes(capacity?.usedBytes))
                    HardwareDetailRow(label: localization.string(.hardwareDetailFreeSpace),
                                      value: HardwareDetailFormat.bytes(capacity?.freeBytes))
                    HardwareDetailRow(label: localization.string(.hardwareDetailTotalSpace),
                                      value: HardwareDetailFormat.bytes(capacity?.totalBytes))
                    HardwareDetailRow(label: localization.string(.hardwareDetailFileSystem),
                                      value: capacity?.fileSystem ?? HardwareDetailFormat.dash)
                    divider
                    HardwareDetailRow(label: localization.string(.hardwareDetailReadSpeed),
                                      value: HardwareDetailFormat.rate(detail?.readBytesPerSecond))
                    HardwareDetailRow(label: localization.string(.hardwareDetailWriteSpeed),
                                      value: HardwareDetailFormat.rate(detail?.writeBytesPerSecond))
                }
            }
        }
    }

    // MARK: - Shared pieces

    private func topMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 2)
    }

    private func coloredMetricCard(title: String, value: String, color: Color) -> some View {
        HardwareDetailCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.vertical, 1)
    }

    private var verticalDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1, height: 26)
    }

    private func trendCard(title: String, colors: [Color], scale: HardwareDetailChartScale) -> some View {
        HardwareDetailCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                HardwareDetailHistoryChart(points: history.points, colors: colors, scale: scale, now: now)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

extension HardwareDetailKind {
    var titleKey: LocalizationKey {
        switch self {
        case .cpu: return .hardwareDetailTitleCPU
        case .gpu: return .hardwareDetailTitleGPU
        case .memory: return .hardwareDetailTitleMemory
        case .network: return .hardwareDetailTitleNetwork
        case .disk: return .hardwareDetailTitleDisk
        }
    }

    var historySeriesCount: Int {
        switch self {
        case .network, .disk: return 2
        case .cpu, .gpu, .memory: return 1
        }
    }

    /// Primary metrics the summary already samples, used to prefill the chart.
    var historyMetricIDs: [HardwareMetricID] {
        switch self {
        case .cpu: return [.cpuUsage]
        case .gpu: return [.gpuUsage]
        case .memory: return [.memoryUsage]
        case .network: return [.networkDownload, .networkUpload]
        case .disk: return [.diskRead, .diskWrite]
        }
    }

    func sampleDate(_ snapshot: HardwareMetricsSnapshot) -> Date? {
        switch self {
        case .cpu:
            return snapshot.cpuDetail?.sampledAt ?? snapshot[.cpuUsage].sampledAt
        case .gpu:
            return snapshot.gpuDetail?.sampledAt ?? snapshot[.gpuUsage].sampledAt
        case .memory:
            return snapshot.memoryDetail?.sampledAt ?? snapshot[.memoryUsage].sampledAt
        case .network:
            return snapshot.networkDetail?.sampledAt ?? snapshot[.networkDownload].sampledAt
        case .disk:
            return snapshot.diskDetail?.sampledAt ?? snapshot[.diskRead].sampledAt
        }
    }

    func sampleValues(_ snapshot: HardwareMetricsSnapshot) -> [Double?] {
        switch self {
        case .cpu:
            return [snapshot.cpuDetail?.usage ?? snapshot[.cpuUsage].value]
        case .gpu:
            return [snapshot.gpuDetail?.usage ?? snapshot[.gpuUsage].value]
        case .memory:
            return [snapshot.memoryDetail?.percent ?? snapshot[.memoryUsage].value]
        case .network:
            return [snapshot.networkDetail?.downloadBytesPerSecond ?? snapshot[.networkDownload].value,
                    snapshot.networkDetail?.uploadBytesPerSecond ?? snapshot[.networkUpload].value]
        case .disk:
            return [snapshot.diskDetail?.readBytesPerSecond ?? snapshot[.diskRead].value,
                    snapshot.diskDetail?.writeBytesPerSecond ?? snapshot[.diskWrite].value]
        }
    }
}