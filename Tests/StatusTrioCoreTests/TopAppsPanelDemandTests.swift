import XCTest
@testable import StatusTrioCore

private actor NeverReadTopAppsSampler: TopAppsSampling {
    func read(_ metric: TopAppMetric, applications: [ProcessApplication]) async -> TopAppsReadResult {
        .measured([])
    }

    func reset() async {}
}

@MainActor
final class TopAppsPanelDemandTests: XCTestCase {
    private func makeFixture() -> (PanelStoreFixture, TopAppsService) {
        let service = TopAppsService(sampler: NeverReadTopAppsSampler(),
                                     applications: { [] },
                                     automaticScheduling: false)
        let fixture = PanelStoreFixture(
            hardwareMetrics: HardwareMetricsService(automaticScheduling: false, reader: { _, _ in .empty }),
            topApps: service
        )
        return (fixture, service)
    }

    private func startVisible(_ fixture: PanelStoreFixture) -> StatusPanelViewModel {
        fixture.settings.setPopupSection(.hardwareMonitor, enabled: true)
        let panel = fixture.makePanel()
        panel.start()
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        return panel
    }

    func testAlongsideDetailKeepsTopAppsDemandUntilTheDetailCloses() {
        let (fixture, service) = makeFixture()
        let panel = startVisible(fixture)
        defer {
            panel.showSummaryPage()
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }

        panel.setDetailPresentation(.alongside)
        panel.showHardwareDetail(.cpu)
        XCTAssertEqual(service.demand, .cpu)

        panel.showHardwareDetail(.network)
        XCTAssertEqual(service.demand, .network)

        panel.showSummaryPage()
        XCTAssertNil(service.demand)
    }

    func testOnlyVisibleHardwareDetailDemandsTopApps() {
        let (fixture, service) = makeFixture()
        let panel = startVisible(fixture)
        defer {
            panel.showSummaryPage()
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }

        XCTAssertNil(service.demand)

        panel.showHardwareDetail(.cpu)
        XCTAssertEqual(service.demand, .cpu)
        XCTAssertEqual(service.observable.state, .collecting(.cpu))

        panel.showHardwareDetail(.gpu)
        XCTAssertEqual(service.demand, .gpu)
        panel.showHardwareDetail(.memory)
        XCTAssertEqual(service.demand, .memory)
        panel.showHardwareDetail(.network)
        XCTAssertEqual(service.demand, .network)

        panel.showHardwareDetail(.disk)
        XCTAssertNil(service.demand)
        XCTAssertEqual(service.observable.state, .idle)

        panel.showHardwareDetail(.cpu)
        XCTAssertEqual(service.demand, .cpu)
        panel.showSummaryPage()
        XCTAssertNil(service.demand)
    }

    func testHidingHardwareModuleAndClosingPanelEndDemand() {
        let (fixture, service) = makeFixture()
        let panel = startVisible(fixture)
        defer {
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }

        panel.showHardwareDetail(.memory)
        XCTAssertEqual(service.demand, .memory)

        fixture.settings.setPopupSection(.hardwareMonitor, enabled: false)
        XCTAssertNil(service.demand)

        fixture.settings.setPopupSection(.hardwareMonitor, enabled: true)
        panel.showHardwareDetail(.memory)
        XCTAssertEqual(service.demand, .memory)

        fixture.store.setPopoverVisible(false)
        XCTAssertNil(service.demand)
    }

    func testTopAppsToggleStopsTheRankedListDemand() {
        let (fixture, service) = makeFixture()
        let panel = startVisible(fixture)
        defer {
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }

        panel.showHardwareDetail(.cpu)
        XCTAssertEqual(service.demand, .cpu)

        fixture.settings.showsHardwareTopApps = false
        XCTAssertNil(service.demand, "turning the list off releases its sampling")

        fixture.settings.showsHardwareTopApps = true
        XCTAssertEqual(service.demand, .cpu)
    }

    func testBackgroundHardwareRefreshDoesNotEnableTopApps() {
        let (fixture, service) = makeFixture()
        let panel = startVisible(fixture)
        defer {
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }

        fixture.settings.hardwareBackgroundHistoryEnabled = true
        XCTAssertNil(service.demand)

        panel.showHardwareDetail(.network)
        XCTAssertEqual(service.demand, .network)
        fixture.settings.hardwareBackgroundHistoryEnabled = false
        XCTAssertEqual(service.demand, .network)
    }

    func testStoreSleepWakeAndStopReachService() async throws {
        let (fixture, service) = makeFixture()
        let panel = startVisible(fixture)
        panel.showHardwareDetail(.cpu)
        XCTAssertEqual(service.demand, .cpu)

        fixture.wakeCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        for _ in 0..<100 {
            if service.isAsleep { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(service.isAsleep)

        fixture.wakeCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        for _ in 0..<100 {
            if !service.isAsleep { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(service.isAsleep)
        XCTAssertEqual(service.demand, .cpu)

        fixture.store.stop()
        XCTAssertTrue(service.isStopped)
        XCTAssertNil(service.demand)
    }

    func testHardwareRefreshIntervalBoundsTheTopAppsList() {
        let (fixture, service) = makeFixture()
        let panel = startVisible(fixture)
        defer {
            panel.showSummaryPage()
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }

        fixture.settings.hardwarePanelRefreshSeconds = 8
        panel.showHardwareDetail(.cpu)
        XCTAssertEqual(service.demand, .cpu)
        XCTAssertEqual(service.minimumIntervalSeconds, 8)

        // Changing the setting while the page is open updates the bound too, so
        // the list slows or speeds up with the panel instead of staying fixed.
        fixture.settings.hardwarePanelRefreshSeconds = 3
        XCTAssertEqual(service.minimumIntervalSeconds, 3)
    }
}
