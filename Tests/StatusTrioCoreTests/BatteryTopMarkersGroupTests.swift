import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// #362: the top-marker rows are a shared view rendered by both the App Icon
/// page (embedded in the ring-content card) and the Battery page (its own
/// card). This is a layout smoke test: both wrapper modes and both battery
/// states must produce a laid-out view, and the three-row battery form must be
/// taller than the single decorative row.
@MainActor
final class BatteryTopMarkersGroupTests: XCTestCase {
    private func makeLocalization() -> Localization {
        let suite = "BatteryTopMarkersGroupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        return Localization(defaults: defaults, preferredLanguages: ["en"])
    }

    private func height(
        store: SettingsStore,
        localization: Localization,
        hasBattery: Bool,
        embedsInGroup: Bool
    ) -> CGFloat {
        let view = BatteryTopMarkersGroup(
            store: store,
            hasBattery: hasBattery,
            embedsInGroup: embedsInGroup
        )
        .environmentObject(localization)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 800)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    func testSharedViewRendersEmbeddedAndAsOwnCard() {
        let suite = "BatteryTopMarkersGroupTests.store.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        let store = SettingsStore(defaults: defaults)
        let localization = makeLocalization()

        let embedded = height(store: store, localization: localization,
                              hasBattery: true, embedsInGroup: false)
        let card = height(store: store, localization: localization,
                          hasBattery: true, embedsInGroup: true)
        XCTAssertGreaterThan(embedded, 0)
        XCTAssertGreaterThan(card, 0)

        let noBattery = height(store: store, localization: localization,
                               hasBattery: false, embedsInGroup: false)
        XCTAssertGreaterThan(noBattery, 0)
        XCTAssertGreaterThan(embedded, noBattery,
                              "the three-row battery form must be taller than the single decorative row")
    }
}
