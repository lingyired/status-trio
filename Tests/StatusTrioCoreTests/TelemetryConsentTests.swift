import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class TelemetryConsentTests: XCTestCase {
    func testFreshInstallIsPendingAndDoesNotCreateInstallationID() {
        let suite = makeSuite()
        defer { clear(suite) }

        let settings = SettingsStore(defaults: suite.defaults)

        XCTAssertFalse(settings.canShareAnonymousAnalytics)
        XCTAssertFalse(settings.sharesAnonymousAnalytics)
        XCTAssertEqual(settings.telemetryConsentVersion, 0)
        XCTAssertNil(suite.defaults.string(forKey: "telemetry.installationId"))
    }

    func testEachLegacyInstallMarkerDefaultsConsentOffAndCompletesMigration() {
        for key in ["SUHasLaunchedBefore", SettingsStore.hasSeenIconGuideDefaultsKey,
                    SettingsStore.hasCompletedIconGuideOnboardingDefaultsKey] {
            let suite = makeSuite()
            suite.defaults.set(true, forKey: key)

            let settings = SettingsStore(defaults: suite.defaults)

            XCTAssertFalse(settings.canShareAnonymousAnalytics, "legacy marker: \(key)")
            XCTAssertFalse(settings.sharesAnonymousAnalytics, "legacy marker: \(key)")
            XCTAssertEqual(settings.telemetryConsentVersion, TelemetryConsent.currentVersion)
            clear(suite)
        }
    }

    func testPendingConsentSurvivesGuideAndSparkleFlagsChangingBeforeRelaunch() {
        let suite = makeSuite()
        defer { clear(suite) }
        let first = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(first.telemetryConsentVersion, 0)

        suite.defaults.set(true, forKey: "SUHasLaunchedBefore")
        suite.defaults.set(true, forKey: SettingsStore.hasCompletedIconGuideOnboardingDefaultsKey)
        let relaunched = SettingsStore(defaults: suite.defaults)

        XCTAssertEqual(relaunched.telemetryConsentVersion, 0)
        XCTAssertFalse(relaunched.canShareAnonymousAnalytics)
    }

    func testPersistedConsentAndFutureVersionFailClosed() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(true, forKey: SettingsStore.sharesAnonymousAnalyticsDefaultsKey)
        suite.defaults.set(TelemetryConsent.currentVersion, forKey: SettingsStore.telemetryConsentVersionDefaultsKey)
        XCTAssertTrue(SettingsStore(defaults: suite.defaults).canShareAnonymousAnalytics)

        suite.defaults.set(99, forKey: SettingsStore.telemetryConsentVersionDefaultsKey)
        let future = SettingsStore(defaults: suite.defaults)
        XCTAssertFalse(future.canShareAnonymousAnalytics)
        XCTAssertTrue(future.sharesAnonymousAnalytics)
    }

    func testCompletionPublishesCoherentConsentSnapshotAfterPersistence() {
        let suite = makeSuite()
        defer { clear(suite) }
        let settings = SettingsStore(defaults: suite.defaults)
        var received: [TelemetryConsent] = []
        let cancellable = settings.telemetryConsentUpdates.sink { received.append($0) }
        defer { cancellable.cancel() }

        settings.completeTelemetryConsent(sharesAnalytics: true)

        XCTAssertEqual(received.last, TelemetryConsent(version: 1, sharesAnonymousAnalytics: true))
        XCTAssertTrue(settings.canShareAnonymousAnalytics)
        XCTAssertEqual(suite.defaults.integer(forKey: SettingsStore.telemetryConsentVersionDefaultsKey), 1)
        XCTAssertTrue(suite.defaults.bool(forKey: SettingsStore.sharesAnonymousAnalyticsDefaultsKey))
    }

    func testSettingsToggleExplicitlyCompletesConsentAndPersistsBothChoices() {
        let suite = makeSuite()
        defer { clear(suite) }
        let settings = SettingsStore(defaults: suite.defaults)

        settings.setSharesAnonymousAnalytics(true)
        XCTAssertTrue(settings.canShareAnonymousAnalytics)
        XCTAssertTrue(suite.defaults.bool(forKey: SettingsStore.sharesAnonymousAnalyticsDefaultsKey))

        settings.setSharesAnonymousAnalytics(false)
        XCTAssertEqual(settings.telemetryConsentVersion, TelemetryConsent.currentVersion)
        XCTAssertFalse(settings.canShareAnonymousAnalytics)
        XCTAssertFalse(suite.defaults.bool(forKey: SettingsStore.sharesAnonymousAnalyticsDefaultsKey))
    }

    func testADowngradedBuildCanWithdrawConsentButCannotGrantItAgain() {
        let suite = makeSuite()
        defer { clear(suite) }
        let newerVersion = TelemetryConsent.currentVersion + 1
        suite.defaults.set(true, forKey: SettingsStore.sharesAnonymousAnalyticsDefaultsKey)
        suite.defaults.set(newerVersion, forKey: SettingsStore.telemetryConsentVersionDefaultsKey)
        let settings = SettingsStore(defaults: suite.defaults)
        XCTAssertTrue(settings.sharesAnonymousAnalytics)

        settings.setSharesAnonymousAnalytics(false)

        // Withdrawal is never version-gated, otherwise the analytics toggle
        // would silently refuse to move on a downgraded install.
        XCTAssertFalse(settings.sharesAnonymousAnalytics)
        XCTAssertFalse(settings.canShareAnonymousAnalytics)
        XCTAssertFalse(suite.defaults.bool(forKey: SettingsStore.sharesAnonymousAnalyticsDefaultsKey))
        // The newer build's answer is kept so it still sees what it recorded.
        XCTAssertEqual(
            suite.defaults.integer(forKey: SettingsStore.telemetryConsentVersionDefaultsKey),
            newerVersion
        )
        XCTAssertEqual(settings.telemetryConsentVersion, newerVersion)

        settings.setSharesAnonymousAnalytics(true)

        // Re-granting would accept a prompt this build never showed.
        XCTAssertFalse(settings.sharesAnonymousAnalytics)
        XCTAssertFalse(suite.defaults.bool(forKey: SettingsStore.sharesAnonymousAnalyticsDefaultsKey))
    }

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "TelemetryConsentTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func clear(_ suite: (defaults: UserDefaults, name: String)) {
        suite.defaults.removePersistentDomain(forName: suite.name)
    }
}
