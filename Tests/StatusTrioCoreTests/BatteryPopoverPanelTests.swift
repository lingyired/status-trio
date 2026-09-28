import SwiftUI
import XCTest
@testable import StatusTrioCore

/// The battery page is a popover panel, so it has to satisfy the same
/// contracts as the Wi-Fi and Bluetooth panels.
@MainActor
final class BatteryPopoverPanelTests: XCTestCase {
    private func battery(isPresent: Bool, percentage: Int? = 80) -> BatteryStatus {
        BatteryStatus(rawPercentage: percentage, isPresent: isPresent, isCharging: false,
                      isLowPowerMode: false, isConnectedToPower: false)
    }

    private func summary(
        _ battery: BatteryStatus,
        actionLabel: String? = nil
    ) -> BatteryStatusView {
        BatteryStatusView(
            battery: battery,
            actionLabel: actionLabel,
            onOpenBatteryDetails: {},
            onOpenBatterySettings: {}
        )
    }

    /// A Mac without a battery has nothing to show, so the row stays inert —
    /// the same shape as an unavailable Bluetooth radio.
    func testBatterySummaryOnlyOffersDetailsWhenTheBatteryIsPresent() {
        XCTAssertTrue(summary(battery(isPresent: true)).showsDetailAffordance)
        XCTAssertFalse(summary(battery(isPresent: false, percentage: nil)).showsDetailAffordance)
    }

    func testSummaryAndDetailsUseTheSameLocalizedActionLabel() throws {
        let name = "StatusTrioCoreTests.BatteryActionPopover.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removeTestSuite(named: name) }

        for language in [AppLanguage.english, .simplifiedChinese] {
            let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
            localization.setPreference(.language(language))
            let label = BatteryActionPresentation.openLabel(
                for: .knownApp(.alDente),
                localization: localization
            )
            let summaryView = summary(battery(isPresent: true), actionLabel: label)
            let detailsView = BatteryDetailsView(
                controller: BatteryDetailsController { _, _ in BatteryDetails() },
                battery: battery(isPresent: true),
                actionLabel: label,
                onBack: {},
                onOpenBatterySettings: {}
            )

            XCTAssertEqual(summaryView.settingsActionLabel, label)
            XCTAssertEqual(detailsView.settingsActionLabel, label)
            XCTAssertEqual(label, language == .english ? "Open AlDente" : "打开AlDente")
        }
    }

    /// `StatusBarController.popoverDidClose` discards the retained popover
    /// content only while a detail panel is open, so an open battery page has
    /// to be reported like the other panels — otherwise the next open would
    /// land straight back on the battery page.
    func testOpenBatteryPageCountsAsActivePopoverDetails() {
        let details = BatteryDetailsController { _, _ in BatteryDetails(cycleCount: 43) }
        let store = makeStore(batteryDetails: details)
        XCTAssertFalse(store.hasOpenPopoverPanel)

        details.activate(state: BatteryPowerState(.placeholder))
        XCTAssertTrue(store.hasOpenPopoverPanel)

        store.closeBatteryDetails()
        XCTAssertFalse(store.hasOpenPopoverPanel)
        XCTAssertFalse(details.isActive)
        store.stop()
    }

    /// `StatusBarController.popoverDidClose` samples this before closing the
    /// popover, because the battery page stops its collector on disappear while
    /// the popover is already closing. A sample taken after that would retain
    /// the built content, and the next open would land on the battery page.
    func testOpenPanelIsReportedUntilThePageActuallyDisappears() {
        let details = BatteryDetailsController { _, _ in BatteryDetails(cycleCount: 43) }
        let store = makeStore(batteryDetails: details)

        details.activate(state: BatteryPowerState(.placeholder))
        XCTAssertTrue(store.hasOpenPopoverPanel)

        // The popover is already closing by the time the page disappears.
        details.deactivate()
        XCTAssertFalse(store.hasOpenPopoverPanel)
        store.stop()
    }

    /// Leaving the page through the back row and closing the popover itself
    /// both have to stop the on-demand collector.
    func testClosingPopoverDetailsStopsBatteryCollection() {
        let details = BatteryDetailsController { _, _ in BatteryDetails(cycleCount: 43) }
        let store = makeStore(batteryDetails: details)
        details.activate(state: BatteryPowerState(.placeholder))

        store.closePopoverDetails()

        XCTAssertFalse(details.isActive)
        XCTAssertNil(details.details)
        XCTAssertFalse(store.hasOpenPopoverPanel)
        store.stop()
    }

    private func makeStore(batteryDetails: BatteryDetailsController) -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: StubBatteryMonitor(),
            wifiMonitor: StubWiFiMonitor(),
            volumeMonitor: StubVolumeMonitor(),
            batteryDetails: batteryDetails
        )
    }
}

// The fakes in SystemStatusStoreTests are file-private, so this suite keeps its
// own minimal stubs; these tests never start the store.
@MainActor
private final class StubBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus> = AsyncStream { _ in }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class StubWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus> = AsyncStream { _ in }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class StubVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus> = AsyncStream { _ in }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
