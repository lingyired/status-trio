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
    /// Ring/card colours from settings; the chart uses the matching metric colour.
    var metricColors: [HardwareMonitorMetric: IconRGBA] = [:]
    /// The visible page's ranked list; nil keeps offscreen previews static.
    var topApps: TopAppsObservable? = nil

    @EnvironmentObject private var localization: Localization
    @StateObject private var history: HardwareDetailHistoryStore

    init(kind: HardwareDetailKind, hardware: HardwareMonitorObservable,
         onBack: @escaping () -> Void,
         metricColors: [HardwareMonitorMetric: IconRGBA] = [:],
         topApps: TopAppsObservable? = nil,
         previewHistory: [HardwareDetailHistoryPoint]? = nil) {
        self.kind = kind
        _hardware = ObservedObject(wrappedValue: hardware)
        self.onBack = onBack
        self.metricColors = metricColors
        self.topApps = topApps
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
            if let topApps, let metric = kind.topAppMetric {
                TopAppsListView(metric: metric, observable: topApps)
            }
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
                    HardwareDetailProgressBar(fraction: (usage ?? 0) / 100, tint: accentColor)
                    HStack(spacing: 0) {
                        topMetric(localization.string(.hardwareDetailTemperature),
                                  HardwareDetailFormat.temperature(temperature))
                        verticalDivider
                        topMetric(localization.string(.hardwareDetailLogicalCores),
                                  HardwareDetailFormat.integer(detail?.coreCount))
                    }
                }
            }
            HardwareCPUCoreGroupRow(groups: coreGroups(detail),
                                    coresLabel: localization.string(.hardwareDetailCores),
                                    frequencyLabel: localization.string(.hardwareDetailEstimatedFrequency))
            #if DEBUG
            if showsCoreLayoutSamples { coreLayoutSamples }
            #endif
            trendCard(title: localization.string(.hardwareDetailUsageTrend),
                      scale: .percent)
            HardwareDetailCard {
                VStack(alignment: .leading, spacing: 6) {
                    HardwareDetailRow(label: localization.string(.hardwareDetailUser),
                                      value: HardwareDetailFormat.percent(detail?.breakdown.user))
                    HardwareDetailRow(label: localization.string(.hardwareDetailSystem),
                                      value: HardwareDetailFormat.percent(detail?.breakdown.system))
                    HardwareDetailRow(label: localization.string(.hardwareDetailIdle),
                                      value: HardwareDetailFormat.percent(detail?.breakdown.idle))
                    divider
                    HardwareDetailRow(label: localization.string(.hardwareDetailComposition),
                                      value: coreComposition(detail?.topology))
                }
            }
        }
    }

    /// One group per core class the topology actually reports. A machine with
    /// only efficiency cores shows one card, M1–M4 show two, and a topology
    /// with super cores shows three.
    private func coreGroups(_ detail: CPUDetailReading?) -> [HardwareCPUCoreGroup] {
        guard let topology = detail?.topology, topology.isRecognized else { return [] }
        var groups: [HardwareCPUCoreGroup] = []
        if topology.superCoreCount > 0 {
            groups.append(HardwareCPUCoreGroup(
                id: "super",
                title: localization.string(.hardwareDetailSuperCores),
                average: detail?.groupUsage?.superAverage,
                count: topology.superCoreCount,
                frequency: nil,
                tint: .pink))
        }
        if topology.performanceCoreCount > 0 {
            groups.append(HardwareCPUCoreGroup(
                id: "performance",
                title: localization.string(.hardwareDetailPerformanceCores),
                average: detail?.groupUsage?.performanceAverage,
                count: topology.performanceCoreCount,
                frequency: detail?.frequency?.performanceGHz,
                tint: .orange))
        }
        if topology.efficiencyCoreCount > 0 {
            groups.append(HardwareCPUCoreGroup(
                id: "efficiency",
                title: localization.string(.hardwareDetailEfficiencyCores),
                average: detail?.groupUsage?.efficiencyAverage,
                count: topology.efficiencyCoreCount,
                frequency: detail?.frequency?.efficiencyGHz,
                tint: .teal))
        }
        return groups
    }

    #if DEBUG
    private var showsCoreLayoutSamples: Bool {
        ProcessInfo.processInfo.arguments.contains("--test-show-cpu-core-layouts")
    }

    /// Debug-only layout preview: renders the one/two/three-group rows at once
    /// so their widths can be compared in the real panel.
    private var coreLayoutSamples: some View {
        let cores = localization.string(.hardwareDetailCores)
        let frequency = localization.string(.hardwareDetailEstimatedFrequency)
        func group(_ id: String, _ title: String, _ average: Double?, _ count: Int?,
                   _ ghz: Double?, _ tint: Color) -> HardwareCPUCoreGroup {
            HardwareCPUCoreGroup(id: id, title: title, average: average, count: count,
                                 frequency: ghz, tint: tint)
        }
        let efficiency = localization.string(.hardwareDetailEfficiencyCores)
        let performance = localization.string(.hardwareDetailPerformanceCores)
        let superCore = localization.string(.hardwareDetailSuperCores)
        return VStack(alignment: .leading, spacing: 10) {
            Text("1").font(.caption).foregroundStyle(.secondary)
            HardwareCPUCoreGroupRow(
                groups: [group("e", efficiency, 42, 4, 1.79, .teal)],
                coresLabel: cores, frequencyLabel: frequency)
            Text("2").font(.caption).foregroundStyle(.secondary)
            HardwareCPUCoreGroupRow(
                groups: [group("p", performance, 24, 12, 4.01, .orange),
                         group("e", efficiency, 42, 4, 1.79, .teal)],
                coresLabel: cores, frequencyLabel: frequency)
            Text("3").font(.caption).foregroundStyle(.secondary)
            HardwareCPUCoreGroupRow(
                groups: [group("s", superCore, 65, 4, nil, .pink),
                         group("p", performance, 24, 12, 4.01, .orange),
                         group("e", efficiency, 42, 4, 1.79, .teal)],
                coresLabel: cores, frequencyLabel: frequency)
        }
    }
    #endif

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
                    HardwareDetailProgressBar(fraction: (usage ?? 0) / 100, tint: accentColor)
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
                      scale: .percent)
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
                    HardwareDetailProgressBar(fraction: (percent ?? 0) / 100, tint: accentColor)
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
                      scale: .percent)
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
                      scale: .auto)
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
                    HardwareDetailProgressBar(fraction: capacity?.usedFraction ?? 0, tint: accentColor)
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
                      scale: .auto)
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

    /// Colour(s) for the trend chart, taken from the user's hardware-metric
    /// colours so the CPU page uses the CPU colour (green by default).
    private var trendColors: [Color] {
        switch kind {
        case .cpu: return [metricColor(.cpuUsage)]
        case .gpu: return [metricColor(.gpuUsage)]
        case .memory: return [metricColor(.memoryUsage)]
        case .network: return [metricColor(.downloadSpeed), metricColor(.uploadSpeed)]
        case .disk: return [.orange, .purple]
        }
    }

    /// Page accent taken from the same hardware-metric colour as the trend.
    private var accentColor: Color { trendColors.first ?? .accentColor }

    private func metricColor(_ metric: HardwareMonitorMetric) -> Color {
        let rgba = metricColors[metric] ?? HardwareRingColorConfiguration.recommendedBaseColor(for: metric)
        return IconAppearanceColorConversion.color(from: rgba)
    }

    /// The trend card removes the inner content padding so the chart runs to the
    /// card edges; the title keeps its own inset and the fill is clipped to the
    /// rounded card shape.
    private func trendCard(title: String, scale: HardwareDetailChartScale) -> some View {
        // The chart fills the whole card and the title floats over it, so a
        // 100% sample reaches the card's top edge instead of stopping under a
        // separate title row.
        ZStack(alignment: .topLeading) {
            HardwareDetailHistoryChart(points: history.points, colors: trendColors, scale: scale, now: now)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 78, alignment: .topLeading)
        .panelCardSurface(.silver(.connected), tint: .clear, cornerRadius: 13)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
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