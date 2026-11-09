import Foundation
import XCTest
@testable import StatusTrioCore

/// The AirPods inline-control preferences are persisted SettingsStore toggles,
/// defaulting to on so the private-API helper-backed controls ship by default.
/// Spatial Audio and Conversation Awareness are now separate switches.
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
        XCTAssertTrue(settings.showsSpatialAudioControls)
        XCTAssertTrue(settings.showsConversationAwarenessControls)
    }

    func testMigratesLegacySingleSwitchToBothWhenUnset() throws {
        let (_, defaults) = try makeDefaults()
        defaults.set(false, forKey: SettingsStore.showsInlineAirPodsControlsDefaultsKey)
        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.showsSpatialAudioControls)
        XCTAssertFalse(settings.showsConversationAwarenessControls)
    }

    func testEachSwitchPersistsIndependently() throws {
        let (suite, defaults) = try makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.showsSpatialAudioControls = false
        XCTAssertFalse(defaults.bool(forKey: SettingsStore.showsSpatialAudioControlsDefaultsKey))
        XCTAssertTrue(settings.showsConversationAwarenessControls)

        settings.showsConversationAwarenessControls = false
        let reloaded = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertFalse(reloaded.showsSpatialAudioControls)
        XCTAssertFalse(reloaded.showsConversationAwarenessControls)

        reloaded.showsSpatialAudioControls = true
        let reloadedOn = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertTrue(reloadedOn.showsSpatialAudioControls)
        XCTAssertFalse(reloadedOn.showsConversationAwarenessControls)
    }
}
