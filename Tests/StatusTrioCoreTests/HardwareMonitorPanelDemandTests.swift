import XCTest
@testable import StatusTrioCore

/// Proves the panel wires the hardware card's sampling lifecycle: it samples
/// only while the card is actually visible, and every way of leaving the card
/// ends the demand synchronously (so no hardware timer keeps running).
@MainActor
final class HardwareMonitorPanelDemandTests: XCTestCase {
    private func makeFixture() -> PanelStoreFixture {
        PanelStoreFixture(hardwareMetrics: HardwareMetricsService(automaticScheduling: false,
                                                                reader: { _, _ in .empty }))
    }

    private func startVisible(_ fixture: PanelStoreFixture) -> StatusPanelViewModel {
        fixture.settings.setPopupSection(.hardwareMonitor, enabled: true)
        let panel = fixture.makePanel()
        panel.start()
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        return panel
    }

    func testDemandFollowsCardVisibility() {
        let fixture = makeFixture()
        let panel = startVisible(fixture)
        defer {
            panel.showSummaryPage()
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }

        let service = fixture.store.hardwareMetrics
        XCTAssertEqual(service.demands[.panel], HardwareMetricsService.hardwareSummaryMetricIDs)
        XCTAssertTrue(service.isRunning)
        XCTAssertEqual(panel.hardwareMonitor.snapshot, .empty)

        // Leaving the summary route (to a detail page) stops sampling.
        panel.showBatteryPage()
        XCTAssertEqual(panel.route, .battery)
        XCTAssertNil(service.demands[.panel])
        XCTAssertFalse(service.isRunning, "no consumer should sample while another page is shown")

        // Back to summary resumes it.
        panel.showSummaryPage()
        XCTAssertEqual(service.demands[.panel], HardwareMetricsService.hardwareSummaryMetricIDs)
        XCTAssertTrue(service.isRunning)

        // Hiding the whole panel stops it too.
        fixture.store.setPopoverVisible(false)
        XCTAssertNil(service.demands[.panel])
        XCTAssertFalse(service.isRunning, "background history defaults off, so a closed panel stops sampling")

        // Reopening starts it again.
        fixture.store.setPopoverVisible(true)
        XCTAssertNotNil(service.demands[.panel])
    }


    func testBackgroundHistoryFollowsSettingWhilePanelClosed() {
        let fixture = makeFixture()
        fixture.settings.hardwareBackgroundHistoryEnabled = true
        let panel = startVisible(fixture)
        let controller = HardwareBackgroundDemandController(store: fixture.store, settings: fixture.settings)
        controller.start()
        defer {
            controller.stop()
            panel.showSummaryPage()
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }
        let service = fixture.store.hardwareMetrics
        XCTAssertEqual(service.demands[.panel], HardwareMetricsService.hardwareSummaryMetricIDs)
        XCTAssertNil(service.demands[.background], "an open panel yields the background demand")

        // Opt-in: closing the panel keeps recording only the primary metrics the
        // enabled summary blocks would record (no temperature/fan).
        let expectedBackground = HardwareMetricDemandResolver.backgroundHistoryMetrics(
            summary: HardwareMetricDemandResolver.PanelSummaryInputs(
                showsHardwareRings: fixture.settings.showsHardwareRings,
                enabledRingSlots: fixture.settings.enabledHardwareRingSlots,
                showsHardwareSummaryRow: fixture.settings.showsHardwareSummaryRow,
                enabledSummaryMetrics: fixture.settings.enabledHardwareSummaryMetrics))
        fixture.store.setPopoverVisible(false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(service.demands[.background], expectedBackground)
        XCTAssertEqual(service.backgroundCadenceProvider(.cpuUsage),
                       TimeInterval(fixture.settings.hardwareRefreshSeconds(for: .cpuUsage)))

        fixture.settings.hardwareMemoryRefreshSeconds = 5
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(service.backgroundCadenceProvider(.memory), 5,
                       "background history follows the per-group cadence")

        fixture.store.setPopoverVisible(true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(service.demands[.panel], HardwareMetricsService.hardwareSummaryMetricIDs)
        XCTAssertNil(service.demands[.background], "an open panel ends the background demand")

        fixture.settings.hardwareBackgroundHistoryEnabled = false
        fixture.store.setPopoverVisible(false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertNil(service.demands[.background], "turning the toggle off stops background history")
    }

    func testBackgroundHistoryDefaultsOffWhilePanelClosed() {
        let fixture = makeFixture()
        let panel = startVisible(fixture)
        let controller = HardwareBackgroundDemandController(store: fixture.store, settings: fixture.settings)
        controller.start()
        defer {
            controller.stop()
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }
        let service = fixture.store.hardwareMetrics
        fixture.store.setPopoverVisible(false)
        XCTAssertNil(service.demands[.background], "a fresh install must not sample in the background")
        XCTAssertFalse(service.isRunning)
    }

    func testDisablingTheSectionStopsSampling() {
        let fixture = makeFixture()
        let panel = startVisible(fixture)
        defer {
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }
        let service = fixture.store.hardwareMetrics
        XCTAssertTrue(service.isRunning)

        fixture.settings.setPopupSection(.hardwareMonitor, enabled: false)
        XCTAssertNil(service.demands[.panel])
        XCTAssertFalse(service.isRunning)
    }

    func testExplicitHiddenHardwareDetailStillDemandsPanelSampling() {
        let fixture = makeFixture()
        let panel = startVisible(fixture)
        defer {
            panel.showSummaryPage()
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }
        let service = fixture.store.hardwareMetrics
        fixture.settings.setPopupSection(.hardwareMonitor, enabled: false)
        XCTAssertNil(service.demands[.panel])

        panel.showHardwareDetail(.cpu, forcing: true)
        XCTAssertNotNil(service.demands[.panel])
        panel.showSummaryPage()
        XCTAssertNil(service.demands[.panel])
    }

    func testPanelStopEndsDemand() {
        let fixture = makeFixture()
        let panel = startVisible(fixture)
        defer {
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }
        let service = fixture.store.hardwareMetrics
        XCTAssertTrue(service.isRunning)

        panel.stop()
        XCTAssertNil(service.demands[.panel])
        XCTAssertFalse(service.isRunning)
    }

    func testCardMetricsFollowSettingsOrderAndEnabledSet() {
        let fixture = makeFixture()
        fixture.settings.setPopupSection(.hardwareMonitor, enabled: true)
        let batteryIndex = fixture.settings.hardwareMonitorMetricOrder.firstIndex(of: .batteryTemperature)!
        fixture.settings.moveHardwareMonitorMetrics(fromOffsets: IndexSet(integer: batteryIndex), toOffset: 0)
        fixture.settings.setHardwareMonitorMetric(.cpuUsage, enabled: false)
        let panel = fixture.makePanel()
        panel.start()
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        defer {
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }

        let expected = fixture.settings.visibleHardwareMetrics
        XCTAssertEqual(panel.hardwareMonitorMetrics, expected)
        XCTAssertEqual(expected.first, .batteryTemperature,
                       "reordering is reflected in the panel")
        XCTAssertEqual(fixture.store.hardwareMetrics.demands[.panel],
                       HardwareMetricsService.hardwareSummaryMetricIDs,
                       "the compact summary samples a fixed set regardless of card metrics")
    }

    func testEachDetailRouteRequestsOnlyItsMetricsAndPayload() {
        let fixture = makeFixture()
        let panel = startVisible(fixture)
        defer {
            panel.showSummaryPage()
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }
        let service = fixture.store.hardwareMetrics
        XCTAssertEqual(service.demands[.panel], HardwareMetricsService.hardwareSummaryMetricIDs)
        XCTAssertNil(service.detailKind)

        for kind in HardwareDetailKind.allCases {
            panel.showHardwareDetail(kind)
            XCTAssertEqual(panel.route, .hardwareDetail(kind))
            XCTAssertEqual(service.demands[.panel], HardwareMetricsService.detailMetricIDs(for: kind))
            XCTAssertEqual(service.detailKind, kind)
        }

        panel.showSummaryPage()
        XCTAssertEqual(panel.route, .summary)
        XCTAssertEqual(service.demands[.panel], HardwareMetricsService.hardwareSummaryMetricIDs)
        XCTAssertNil(service.detailKind)
    }

    func testClosingPanelOnDetailEndsDemandAndDetailPayload() {
        let fixture = makeFixture()
        let panel = startVisible(fixture)
        defer {
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }
        let service = fixture.store.hardwareMetrics
        panel.showHardwareDetail(.network)
        XCTAssertEqual(service.demands[.panel], HardwareMetricsService.detailMetricIDs(for: .network))
        XCTAssertEqual(service.detailKind, .network)

        fixture.store.setPopoverVisible(false)
        XCTAssertNil(service.demands[.panel])
        XCTAssertNil(service.detailKind)
        XCTAssertNil(service.demands[.background], "background history is off by default")
        XCTAssertFalse(service.isRunning)
    }

    func testAlongsideHardwareDemandUnionsMetricsAndDropsDetailOnlyWork() {
        let fixture = makeFixture()
        let panel = startVisible(fixture)
        defer {
            panel.showSummaryPage()
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }
        let service = fixture.store.hardwareMetrics

        panel.setDetailPresentation(.alongside)
        panel.showHardwareDetail(.cpu)
        XCTAssertEqual(
            service.demands[.panel],
            HardwareMetricsService.hardwareSummaryMetricIDs
                .union(HardwareMetricsService.detailMetricIDs(for: .cpu))
        )
        XCTAssertEqual(service.detailKind, .cpu)

        panel.showHardwareDetail(.network)
        XCTAssertEqual(
            service.demands[.panel],
            HardwareMetricsService.hardwareSummaryMetricIDs
                .union(HardwareMetricsService.detailMetricIDs(for: .network))
        )
        XCTAssertEqual(service.detailKind, .network)
        XCTAssertNil(service.observable.snapshot.cpuDetail)

        panel.showSummaryPage()
        XCTAssertEqual(service.demands[.panel], HardwareMetricsService.hardwareSummaryMetricIDs)
        XCTAssertNil(service.detailKind)
    }

    func testDefaultSettingsKeepCardOffAndSampleNothing() {
        let fixture = makeFixture()
        // No explicit enable: a fresh install must not sample hardware at all.
        XCTAssertFalse(fixture.settings.enabledPopupSections.contains(.hardwareMonitor))
        XCTAssertFalse(fixture.settings.visiblePopupSections.contains(.hardwareMonitor))

        let panel = fixture.makePanel()
        panel.start()
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        defer {
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }
        let service = fixture.store.hardwareMetrics
        XCTAssertTrue(service.demands.isEmpty)
        XCTAssertFalse(service.isRunning)
    }

    func testBackgroundDemandRecomputesWhenSettingsChangeWhilePanelClosed() {
        let fixture = makeFixture()
        fixture.settings.setPopupSection(.hardwareMonitor, enabled: true)
        fixture.settings.hardwareBackgroundHistoryEnabled = true
        fixture.store.start()
        let controller = HardwareBackgroundDemandController(store: fixture.store, settings: fixture.settings)
        controller.start()
        defer { controller.stop(); fixture.store.stop() }
        let service = fixture.store.hardwareMetrics

        XCTAssertEqual(service.demands[.background], Set(HardwareMonitorObservable.historyMetricIDs))

        // Hiding the rings while the panel stays closed must drop CPU/GPU/RAM
        // from the background set, leaving only the data row's history metrics.
        fixture.settings.showsHardwareRings = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(service.demands[.background], Set([.networkDownload, .networkUpload, .diskRead, .diskWrite]))

        // Hiding the row too leaves no history consumer at all.
        fixture.settings.showsHardwareSummaryRow = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertNil(service.demands[.background])
        XCTAssertFalse(service.isRunning)
    }
}