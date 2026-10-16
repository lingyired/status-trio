import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconGuideTests: XCTestCase {
    func testFirstOnboardingRequestPresentsOnlyOnce() {
        let name = "IconGuideTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removeTestSuite(named: name) }
        let settings = SettingsStore(defaults: defaults)
        settings.volumeDisplayStyle = .arc
        settings.showsBatteryPercentage = false

        XCTAssertFalse(settings.hasCompletedIconGuideOnboarding)
        XCTAssertTrue(IconGuideOnboardingPolicy.consumeIfNeeded(settings: settings))
        XCTAssertTrue(settings.hasCompletedIconGuideOnboarding)
        XCTAssertFalse(IconGuideOnboardingPolicy.consumeIfNeeded(settings: settings))

        let restored = SettingsStore(defaults: defaults)
        XCTAssertTrue(restored.hasCompletedIconGuideOnboarding)
        XCTAssertFalse(IconGuideOnboardingPolicy.consumeIfNeeded(settings: restored))
        XCTAssertEqual(restored.volumeDisplayStyle, .arc)
        XCTAssertFalse(restored.showsBatteryPercentage)
    }

    func testExistingInstallationSkipsAutomaticOnboarding() {
        let name = "IconGuideTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removeTestSuite(named: name) }
        defaults.set(true, forKey: "SUHasLaunchedBefore")

        let settings = SettingsStore(defaults: defaults)

        XCTAssertTrue(settings.hasCompletedIconGuideOnboarding)
        XCTAssertFalse(IconGuideOnboardingPolicy.consumeIfNeeded(settings: settings))
    }

    func testLegacySeenGuideSkipsAutomaticOnboarding() {
        let name = "IconGuideTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removeTestSuite(named: name) }
        defaults.set(true, forKey: SettingsStore.hasSeenIconGuideDefaultsKey)

        let settings = SettingsStore(defaults: defaults)

        XCTAssertTrue(settings.hasCompletedIconGuideOnboarding)
        XCTAssertFalse(IconGuideOnboardingPolicy.consumeIfNeeded(settings: settings))
    }

    func testPendingTelemetryConsentKeepsGuideEligibleAfterGuideDismissal() {
        let name = "IconGuideTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removeTestSuite(named: name) }
        let settings = SettingsStore(defaults: defaults)

        XCTAssertTrue(IconGuideOnboardingPolicy.shouldPresentGuide(settings: settings))
        XCTAssertTrue(settings.hasCompletedIconGuideOnboarding)
        XCTAssertEqual(settings.telemetryConsentVersion, 0)

        let relaunched = SettingsStore(defaults: defaults)
        XCTAssertTrue(IconGuideOnboardingPolicy.shouldPresentGuide(settings: relaunched))
        XCTAssertEqual(relaunched.telemetryConsentVersion, 0)

        relaunched.completeTelemetryConsent(sharesAnalytics: false)
        let completed = SettingsStore(defaults: defaults)
        XCTAssertFalse(IconGuideOnboardingPolicy.shouldPresentGuide(settings: completed))
    }

    func testTelemetryConsentDraftIsPersistedOnlyWhenAcknowledged() {
        let name = "IconGuideTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removeTestSuite(named: name) }
        let settings = SettingsStore(defaults: defaults)
        var draft = TelemetryConsentDraft()

        XCTAssertFalse(draft.sharesAnalytics)

        draft.sharesAnalytics = false
        XCTAssertEqual(settings.telemetryConsentVersion, 0)
        XCTAssertFalse(settings.sharesAnonymousAnalytics)

        draft.sharesAnalytics = true
        draft.acknowledge(settings: settings)
        XCTAssertEqual(settings.telemetryConsentVersion, TelemetryConsent.currentVersion)
        XCTAssertTrue(settings.sharesAnonymousAnalytics)

        let optOutName = "IconGuideTests.\(UUID().uuidString)"
        let optOutDefaults = UserDefaults(suiteName: optOutName)!
        defer { optOutDefaults.removeTestSuite(named: optOutName) }
        let optOutSettings = SettingsStore(defaults: optOutDefaults)
        var optOutDraft = TelemetryConsentDraft()
        optOutDraft.sharesAnalytics = false
        optOutDraft.acknowledge(settings: optOutSettings)
        XCTAssertEqual(optOutSettings.telemetryConsentVersion, TelemetryConsent.currentVersion)
        XCTAssertFalse(optOutSettings.sharesAnonymousAnalytics)
    }

    func testOnboardingViewRendersWithoutCrashing() {
        let name = "IconGuideTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removeTestSuite(named: name) }
        let settings = SettingsStore(defaults: defaults)
        let localization = Localization(
            defaults: defaults,
            preferredLanguages: ["en"]
        )
        let view = IconGuideOnboardingView(
            settings: settings,
            onCustomize: {},
            onDone: {}
        )
        .environmentObject(localization)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 360)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertNotNil(hostingView.subviews)
    }

    func testVolumeExplanationFollowsConfiguredStyle() {
        XCTAssertEqual(IconGuidePart.volume.explanationKey(volumeStyle: .dots), .guideVolumeDots)
        XCTAssertEqual(IconGuidePart.volume.explanationKey(volumeStyle: .arc), .guideVolumeArc)
    }
}
