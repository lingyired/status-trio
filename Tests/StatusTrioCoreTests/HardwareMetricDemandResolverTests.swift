import XCTest
@testable import StatusTrioCore

final class HardwareMetricDemandResolverTests: XCTestCase {
    private func summary(rings: Bool = true,
                         slots: Set<HardwareRingSlot> = Set(HardwareRingSlot.allCases),
                         row: Bool = true,
                         metrics: Set<HardwareSummaryMetric> = Set(HardwareSummaryMetric.allCases))
        -> HardwareMetricDemandResolver.PanelSummaryInputs {
        .init(showsHardwareRings: rings, enabledRingSlots: slots,
              showsHardwareSummaryRow: row, enabledSummaryMetrics: metrics)
    }

    func testOnlyCPURingNeedsUsageAndTemperature() {
        XCTAssertEqual(HardwareMetricDemandResolver.summaryMetrics(
            for: summary(slots: [.cpu], row: false)), Set([.cpuUsage, .cpuTemperature]))
    }

    func testOnlyGPURingNeedsUsageAndTemperature() {
        XCTAssertEqual(HardwareMetricDemandResolver.summaryMetrics(
            for: summary(slots: [.gpu], row: false)), Set([.gpuUsage, .gpuTemperature]))
    }

    func testOnlyRAMRingNeedsMemoryUsage() {
        XCTAssertEqual(HardwareMetricDemandResolver.summaryMetrics(
            for: summary(slots: [.ram], row: false)), Set([.memoryUsage]))
    }

    func testOnlySSDRingNeedsNoPeriodicMetric() {
        XCTAssertEqual(HardwareMetricDemandResolver.summaryMetrics(
            for: summary(slots: [.ssd], row: false)), Set<HardwareMetricID>())
    }

    func testOnlyDownloadNeedsOneNetworkMetric() {
        XCTAssertEqual(HardwareMetricDemandResolver.summaryMetrics(
            for: summary(rings: false, metrics: [.download])), Set([.networkDownload]))
    }

    func testOnlyUploadNeedsOneNetworkMetric() {
        XCTAssertEqual(HardwareMetricDemandResolver.summaryMetrics(
            for: summary(rings: false, metrics: [.upload])), Set([.networkUpload]))
    }

    func testOnlyFanNeedsAverageFan() {
        XCTAssertEqual(HardwareMetricDemandResolver.summaryMetrics(
            for: summary(rings: false, metrics: [.fan])), Set([.fanRPM(index: 0)]))
    }

    func testOnlyDiskIONeedsReadAndWrite() {
        XCTAssertEqual(HardwareMetricDemandResolver.summaryMetrics(
            for: summary(rings: false, metrics: [.disk])), Set([.diskRead, .diskWrite]))
    }

    func testAllMonitorsOffNeedsNothing() {
        XCTAssertEqual(HardwareMetricDemandResolver.summaryMetrics(
            for: summary(rings: false, row: false)), Set<HardwareMetricID>())
        XCTAssertTrue(HardwareMetricDemandResolver.panelMetrics(summary: nil, detailKind: nil).isEmpty)
    }

    func testHiddenRingRemovedEvenWhenOtherConsumersExist() {
        let on = HardwareMetricDemandResolver.summaryMetrics(
            for: summary(slots: [.cpu, .gpu], row: false))
        XCTAssertTrue(on.contains(.cpuUsage))
        let off = HardwareMetricDemandResolver.summaryMetrics(
            for: summary(slots: [.gpu], row: false))
        XCTAssertFalse(off.contains(.cpuUsage), "a hidden CPU ring must drop its metrics")
        XCTAssertFalse(off.contains(.cpuTemperature))
    }

    func testSummaryAndDetailUseUnion() {
        let metrics = HardwareMetricDemandResolver.panelMetrics(
            summary: summary(slots: [.cpu], row: false), detailKind: .gpu)
        XCTAssertEqual(metrics, Set([.cpuUsage, .cpuTemperature, .gpuUsage, .gpuTemperature]))
    }

    func testDetailAloneKeepsOnlyDetailMetrics() {
        XCTAssertEqual(HardwareMetricDemandResolver.panelMetrics(summary: nil, detailKind: .network),
                       Set([.networkDownload, .networkUpload]))
        XCTAssertEqual(HardwareMetricDemandResolver.panelMetrics(summary: nil, detailKind: .fan),
                       Set([.fanRPM(index: 0), .cpuTemperature, .gpuTemperature, .batteryTemperature]))
    }

    func testBackgroundHistoryOnlyRecordsPrimaryMetrics() {
        let all = HardwareMetricDemandResolver.backgroundHistoryMetrics(summary: summary())
        XCTAssertEqual(all, Set(HardwareMonitorObservable.historyMetricIDs))
        XCTAssertFalse(all.contains(.cpuTemperature), "temperatures are not history rows")
        XCTAssertFalse(all.contains(.fanRPM(index: 0)))

        let cpuOnly = HardwareMetricDemandResolver.backgroundHistoryMetrics(
            summary: summary(slots: [.cpu], row: false))
        XCTAssertEqual(cpuOnly, Set([.cpuUsage]))
    }

    func testIconRingFiltersStatusSnapshotMetrics() {
        let volumeOnly = HardwareRingConfiguration(
            layout: .single, primaryMetric: .volume, secondaryMetric: nil)
        XCTAssertTrue(HardwareMetricDemandResolver.iconRingMetrics(configuration: volumeOnly).isEmpty)

        let wifiOnly = HardwareRingConfiguration(
            layout: .single, primaryMetric: .wifiSignal, secondaryMetric: nil)
        XCTAssertTrue(HardwareMetricDemandResolver.iconRingMetrics(configuration: wifiOnly).isEmpty)

        let mixed = HardwareRingConfiguration(
            layout: .dual, primaryMetric: .cpuUsage, secondaryMetric: .volume)
        XCTAssertEqual(HardwareMetricDemandResolver.iconRingMetrics(configuration: mixed), Set([.cpuUsage]))
    }
}
