import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class TelemetryLocalWorkerSmokeTests: XCTestCase {
    func testOptInLocalWorkerConsentAndHeartbeatRoundTrip() async throws {
        guard ProcessInfo.processInfo.environment["STATUS_TRIO_TELEMETRY_LOCAL_SMOKE"] == "1" else {
            throw XCTSkip("Set STATUS_TRIO_TELEMETRY_LOCAL_SMOKE=1 to run against a local Worker.")
        }
        let endpointValue = try XCTUnwrap(
            ProcessInfo.processInfo.environment["STATUS_TRIO_TELEMETRY_LOCAL_ENDPOINT"]
        )
        let endpoint = try XCTUnwrap(URL(string: endpointValue))
        XCTAssertEqual(endpoint.scheme, "http", "The opt-in smoke test must use local HTTP.")
        XCTAssertTrue(
            ["localhost", "127.0.0.1", "::1"].contains(endpoint.host ?? ""),
            "The opt-in smoke test only permits loopback hosts."
        )

        let suiteName = "TelemetryLocalWorkerSmokeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        settings.appIconPlacement = .both
        settings.completeTelemetryConsent(sharesAnalytics: false)
        let configuration = TelemetryConfiguration(endpoint: endpoint, requestTimeout: 5)
        let client = TelemetryClient(
            transport: URLSessionTelemetryTransport(configuration: configuration),
            configuration: configuration,
            persistenceSuiteName: suiteName
        )
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let reporter = TelemetryReporter(
            settings: settings,
            localization: localization,
            client: client,
            eligibilityContext: TelemetryEligibilityContext(
                bundleIdentifier: TelemetryEligibility.productionBundleIdentifier,
                productionMarker: true,
                isDebugBuild: false
            ),
            configuration: configuration,
            wakeNotificationCenter: NotificationCenter(),
            snapshotContext: { language, placement in
                TelemetryContext(
                    appVersion: "2.0.0",
                    build: "18",
                    osName: "macOS",
                    osVersion: "15.0",
                    architecture: "arm64",
                    distribution: "github",
                    osLanguage: "en",
                    appLanguage: language.rawValue,
                    appIconPlacement: placement
                )
            }
        )
        defer { reporter.stop() }

        reporter.start()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(defaults.string(forKey: TelemetryClient.installationIDKey), "OFF must not create an ID.")
        XCTAssertNil(defaults.object(forKey: TelemetryClient.lastAttemptAtKey), "OFF must not send a request.")

        settings.setSharesAnonymousAnalytics(true)
        let deadline = ContinuousClock.now + .seconds(10)
        while defaults.object(forKey: TelemetryClient.lastSuccessfulAtKey) == nil,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        reporter.stop()

        XCTAssertNotNil(defaults.string(forKey: TelemetryClient.installationIDKey))
        XCTAssertNotNil(defaults.object(forKey: TelemetryClient.lastSuccessfulAtKey), "The local Worker must return 2xx.")
    }
}
