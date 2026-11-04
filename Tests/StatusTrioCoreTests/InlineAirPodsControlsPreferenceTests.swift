import Foundation
import XCTest
@testable import StatusTrioCore

/// The AirPods inline-control preference is a persisted SettingsStore toggle,
/// defaulting to on so the private-API helper-backed controls ship by default.
@MainActor
final class InlineAirPodsControlsPreferenceTests: XCTestCase {
    private func makeDefaults() throws -> (String, UserDefaults) {
        let suite = "InlineAirPodsControlsPreferenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        return (suite, defaults)
    }

    func testDefaultsToOnWhenNeverSet() throws {
        let (_, defaults) = try makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        XCTAssertTrue(settings.showsInlineAirPodsControls)
    }

    func testReadsPersistedOffValue() throws {
        let (_, defaults) = try makeDefaults()
        defaults.set(false, forKey: SettingsStore.showsInlineAirPodsControlsDefaultsKey)
        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.showsInlineAirPodsControls)
    }

    func testWriteRoundTripsThroughUserDefaults() throws {
        let (suite, defaults) = try makeDefaults()
        var settings = SettingsStore(defaults: defaults)
        settings.showsInlineAirPodsControls = false
        XCTAssertFalse(defaults.bool(forKey: SettingsStore.showsInlineAirPodsControlsDefaultsKey))
        // A fresh store sharing the same suite sees the persisted value.
        let reloaded = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertFalse(reloaded.showsInlineAirPodsControls)

        settings.showsInlineAirPodsControls = true
        let reloadedOn = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertTrue(reloadedOn.showsInlineAirPodsControls)
    }
}