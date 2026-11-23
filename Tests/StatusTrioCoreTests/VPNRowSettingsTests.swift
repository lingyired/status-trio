import XCTest
@testable import StatusTrioCore

/// The VPN row's settings surface: it is off by default (opt-in), a stored
/// selection is honoured exactly as saved, and switching it on or off sticks
/// across relaunches.
@MainActor
final class VPNRowSettingsTests: XCTestCase {
    func testVPNIsNotInTheDefaultSelection() {
        XCTAssertFalse(SettingsStore.defaultEnabledPopupSections.contains(.vpn))
    }

    func testAFreshInstallHidesTheVPNRow() {
        let suite = makeSuite()
        defer { clear(suite) }

        let store = SettingsStore(defaults: suite.defaults)

        XCTAssertFalse(store.enabledPopupSections.contains(.vpn))
        XCTAssertFalse(store.visiblePopupSections.contains(.vpn))
        // The row still exists in the order; it is just switched off.
        XCTAssertTrue(store.popupSectionOrder.contains(.vpn))
    }

    func testEnablingTheRowSurvivesARelaunch() {
        let suite = makeSuite()
        defer { clear(suite) }

        let store = SettingsStore(defaults: suite.defaults)
        store.setPopupSection(.vpn, enabled: true)

        let reopened = SettingsStore(defaults: suite.defaults)
        XCTAssertTrue(reopened.enabledPopupSections.contains(.vpn))
        XCTAssertTrue(reopened.visiblePopupSections.contains(.vpn))
    }

    func testTurningTheRowOffSurvivesARelaunch() {
        let suite = makeSuite()
        defer { clear(suite) }

        let store = SettingsStore(defaults: suite.defaults)
        store.setPopupSection(.vpn, enabled: false)
        XCTAssertFalse(store.enabledPopupSections.contains(.vpn))

        let reopened = SettingsStore(defaults: suite.defaults)
        XCTAssertFalse(reopened.enabledPopupSections.contains(.vpn))
        XCTAssertFalse(reopened.visiblePopupSections.contains(.vpn))
    }

    /// A stored selection is the user's own choice, so the opt-in VPN row is
    /// never added to it automatically.
    func testAStoredSelectionIsHonouredWithoutAddingTheVPNRow() {
        let suite = makeSuite()
        defer { clear(suite) }

        suite.defaults.set(
            [PopupSection.battery.rawValue, PopupSection.volume.rawValue],
            forKey: SettingsStore.enabledPopupSectionsDefaultsKey
        )

        let store = SettingsStore(defaults: suite.defaults)
        XCTAssertFalse(store.enabledPopupSections.contains(.vpn))
        XCTAssertTrue(store.enabledPopupSections.contains(.battery))
        XCTAssertTrue(store.enabledPopupSections.contains(.volume))
    }

    func testSanitizerKeepsAStoredSelectionWithoutTheRow() {
        let stored = [PopupSection.battery.rawValue, PopupSection.volume.rawValue]

        XCTAssertEqual(
            SettingsStore.sanitizedEnabledPopupSections(stored),
            Set([.battery, .volume])
        )
    }

    func testSanitizerFallsBackToTheDefaultsWithoutAStoredList() {
        XCTAssertEqual(
            SettingsStore.sanitizedEnabledPopupSections(nil),
            SettingsStore.defaultEnabledPopupSections
        )
    }

    /// The order sanitizer appends a section it has never seen, so the row also
    /// reaches a user whose stored order predates it.
    func testStoredOrderPicksUpTheRow() {
        let order = SettingsStore.sanitizedPopupSectionOrder(
            [PopupSection.volume.rawValue, PopupSection.battery.rawValue]
        )

        XCTAssertEqual(order.first, .volume)
        XCTAssertTrue(order.contains(.vpn))
        XCTAssertEqual(order.count, PopupSection.allCases.count)
    }

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.VPNRowSettings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("could not create isolated user defaults suite")
        }
        defaults.removeTestSuite(named: name)
        addTeardownBlock { TestUserDefaults.removeSuite(named: name) }
        return (defaults, name)
    }

    private func clear(_ suite: (defaults: UserDefaults, name: String)) {
        suite.defaults.removeTestSuite(named: suite.name)
    }
}
