import XCTest
@testable import StatusTrioCore

@MainActor
final class StatusPanelRouteTests: XCTestCase {
    func testOpeningAndLeavingDetailPagesUpdatesRouteAndLifecycleActions() {
        let fixture = PanelStoreFixture()
        var batteryActivations = 0
        var batteryCloses = 0
        var wifiActivations = 0
        var wifiCloses = 0
        var wiredOpens = 0
        var wiredCloses = 0
        let actions = StatusPanelActions(
            batteryStatus: { fixture.store.popupSnapshot.battery },
            activateBatteryDetails: { _ in batteryActivations += 1 },
            closeBatteryDetails: { batteryCloses += 1 },
            wifiNameAccess: { .authorized },
            activateWiFiDetails: { _ in wifiActivations += 1 },
            closeWiFiDetails: { wifiCloses += 1 },
            openWiredDetails: { wiredOpens += 1 },
            closeWiredDetails: { wiredCloses += 1 }
        )
        let panel = fixture.makePanel(actions: actions)
        panel.start()
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        defer {
            panel.showSummaryPage()
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }

        panel.showBatteryPage()
        XCTAssertEqual(panel.route, .battery)
        XCTAssertEqual(batteryActivations, 1)

        panel.showSummaryPage()
        XCTAssertEqual(panel.route, .summary)
        XCTAssertEqual(batteryCloses, 1)

        panel.showWiFiPage(showsDetailsInitially: true)
        XCTAssertEqual(panel.route, .wifi)
        XCTAssertEqual(wifiActivations, 1)
        XCTAssertEqual(
            panel.wifiDisclosure,
            WiFiPanelDisclosureState(showsDetails: true, showsMore: false)
        )

        panel.setWiFiShowsDetails(false)
        panel.setWiFiShowsMore(true)
        XCTAssertEqual(
            panel.wifiDisclosure,
            WiFiPanelDisclosureState(showsDetails: false, showsMore: true)
        )

        panel.showSummaryPage()
        XCTAssertEqual(wifiCloses, 1)

        panel.showWiredPage()
        XCTAssertEqual(panel.route, .ethernet)
        XCTAssertEqual(wiredOpens, 1)

        panel.showSummaryPage()
        XCTAssertEqual(wiredCloses, 1)
    }

    func testBatteryRouteSurvivesReleasedContentWithoutKeepingCollectionActive() {
        let fixture = PanelStoreFixture()
        let actions = StatusPanelActions(store: fixture.store, settings: fixture.settings)
        let panel = fixture.makePanel(actions: actions)
        panel.start()
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        defer {
            panel.showSummaryPage()
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }

        panel.showBatteryPage()
        XCTAssertEqual(panel.route, .battery)
        XCTAssertTrue(fixture.store.batteryDetails.isActive)

        panel.stop()
        fixture.store.setPopoverVisible(false)
        fixture.store.closePopoverDetails()
        panel.releaseInactivePresentationState()

        XCTAssertEqual(panel.route, .battery)
        XCTAssertFalse(fixture.store.batteryDetails.isActive)

        fixture.store.setPopoverVisible(true)
        panel.start()
        panel.prepareForPresentation()

        XCTAssertEqual(panel.route, .battery)
        XCTAssertTrue(fixture.store.batteryDetails.isActive)
    }

    func testWiFiDisclosureStateSurvivesReleaseAndReopensTheWiFiPage() {
        let fixture = PanelStoreFixture()
        let actions = StatusPanelActions(store: fixture.store, settings: fixture.settings)
        let panel = fixture.makePanel(actions: actions)
        panel.start()
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        defer {
            panel.showSummaryPage()
            panel.stop()
            fixture.store.setPopoverVisible(false)
            fixture.store.stop()
        }

        panel.showWiFiPage(showsDetailsInitially: false)
        panel.setWiFiShowsDetails(true)
        panel.setWiFiShowsMore(true)

        panel.stop()
        fixture.store.setPopoverVisible(false)
        fixture.store.closePopoverDetails()
        panel.releaseInactivePresentationState()

        XCTAssertEqual(panel.route, .wifi)
        XCTAssertEqual(
            panel.wifiDisclosure,
            WiFiPanelDisclosureState(showsDetails: true, showsMore: true)
        )
        XCTAssertFalse(fixture.store.wifiNetworks.isActive)

        fixture.store.setPopoverVisible(true)
        panel.start()
        panel.prepareForPresentation()

        XCTAssertEqual(panel.route, .wifi)
        XCTAssertEqual(
            panel.wifiDisclosure,
            WiFiPanelDisclosureState(showsDetails: true, showsMore: true)
        )
        XCTAssertTrue(fixture.store.wifiNetworks.isActive)
    }

    func testPrepareFallsBackToSummaryWhenTheRouteSectionIsHidden() {
        let fixture = PanelStoreFixture()
        let actions = StatusPanelActions(store: fixture.store, settings: fixture.settings)
        let panel = fixture.makePanel(actions: actions)
        panel.start()
        fixture.store.start()
        fixture.store.setPopoverVisible(true)

        panel.showBatteryPage()
        panel.stop()
        fixture.store.setPopoverVisible(false)
        fixture.store.closePopoverDetails()
        panel.releaseInactivePresentationState()

        fixture.settings.setPopupSection(.battery, enabled: false)
        fixture.store.setPopoverVisible(true)
        panel.start()
        panel.prepareForPresentation()

        XCTAssertEqual(panel.route, .summary)
        XCTAssertFalse(fixture.store.batteryDetails.isActive)

        panel.stop()
        fixture.store.setPopoverVisible(false)
        fixture.store.stop()
    }
}
