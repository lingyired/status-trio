import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconGuideTests: XCTestCase {
    func testFirstOnboardingRequestPresentsOnlyOnce() {
        let name = "IconGuideTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
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
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "SUHasLaunchedBefore")

        let settings = SettingsStore(defaults: defaults)

        XCTAssertTrue(settings.hasCompletedIconGuideOnboarding)
        XCTAssertFalse(IconGuideOnboardingPolicy.consumeIfNeeded(settings: settings))
    }

    func testLegacySeenGuideSkipsAutomaticOnboarding() {
        let name = "IconGuideTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: SettingsStore.hasSeenIconGuideDefaultsKey)

        let settings = SettingsStore(defaults: defaults)

        XCTAssertTrue(settings.hasCompletedIconGuideOnboarding)
        XCTAssertFalse(IconGuideOnboardingPolicy.consumeIfNeeded(settings: settings))
    }

    func testOnboardingViewRendersWithoutCrashing() {
        let name = "IconGuideTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
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
