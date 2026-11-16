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
        XCTAssertFalse(service.isRunning)

        // Back to summary resumes it.
        panel.showSummaryPage()
        XCTAssertEqual(service.demands[.panel], HardwareMetricsService.hardwareSummaryMetricIDs)
        XCTAssertTrue(service.isRunning)

        // Hiding the whole panel stops it too.
        fixture.store.setPopoverVisible(false)
        XCTAssertNil(service.demands[.panel])
        XCTAssertFalse(service.isRunning)

        // Reopening starts it again.
        fixture.store.setPopoverVisible(true)
        XCTAssertNotNil(service.demands[.panel])
    }


    func testBackgroundDemandFollowsSettingWhilePanelClosed() {
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
        XCTAssertNil(service.demands[.background])

        fixture.store.setPopoverVisible(false)
        XCTAssertNil(service.demands[.background], "off by default: no background reads when closed")

        fixture.settings.hardwareBackgroundRefreshSeconds = 30
        XCTAssertEqual(service.demands[.background], HardwareMetricsService.hardwareSummaryMetricIDs)
        XCTAssertNil(service.demands[.panel])
        XCTAssertEqual(service.backgroundIntervalSeconds, 30)

        fixture.store.setPopoverVisible(true)
        XCTAssertEqual(service.demands[.panel], HardwareMetricsService.hardwareSummaryMetricIDs)
        XCTAssertNil(service.demands[.background], "an open panel ends the background demand")

        fixture.settings.hardwareBackgroundRefreshSeconds = 0
        fixture.store.setPopoverVisible(false)
        XCTAssertNil(service.demands[.background])
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
}