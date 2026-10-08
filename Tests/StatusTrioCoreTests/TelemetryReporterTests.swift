import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class TelemetryReporterTests: XCTestCase {
    func testAcceptedEligibleStartupSendsImmediately() async throws {
        let fixture = makeFixture(accepted: true)
        defer { fixture.stopAndClear() }
        fixture.reporter.start()
        await fixture.sender.waitForSendCount(1)
        await assertSendCount(1, from: fixture.sender)
    }

    func testPendingDisabledAndDevelopmentInstallNeverSend() async throws {
        let pending = makeFixture(accepted: false)
        defer { pending.stopAndClear() }
        pending.reporter.start()
        await Task.yield()
        await assertSendCount(0, from: pending.sender)

        let disabled = makeFixture(accepted: false, legacyInstall: true)
        defer { disabled.stopAndClear() }
        disabled.settings.setSharesAnonymousAnalytics(false)
        disabled.reporter.start()
        await assertSendCount(0, from: disabled.sender)

        let development = makeFixture(accepted: true, productionMarker: false)
        defer { development.stopAndClear() }
        development.reporter.start()
        await assertSendCount(0, from: development.sender)
    }

    func testTurningConsentOnSendsOnceAndRepeatedOnDoesNotDuplicate() async throws {
        let fixture = makeFixture(accepted: false)
        defer { fixture.stopAndClear() }
        fixture.reporter.start()
        fixture.settings.completeTelemetryConsent(sharesAnalytics: true)
        await fixture.sender.waitForSendCount(1)
        fixture.settings.completeTelemetryConsent(sharesAnalytics: true)
        await Task.yield()
        await assertSendCount(1, from: fixture.sender)
    }

    func testTurningConsentOffCancelsInFlightAttemptAndPeriodicSleep() async throws {
        let fixture = makeFixture(accepted: true, suspendSender: true)
        defer { fixture.stopAndClear() }
        fixture.reporter.start()
        await fixture.sender.waitForSendCount(1)
        await fixture.sleeper.waitForSleepCount(1)

        fixture.settings.setSharesAnonymousAnalytics(false)
        await fixture.sender.resume()
        await fixture.sender.waitForCancellationObservation()
        let cancelled = await fixture.sender.lastSendWasCancelled()
        XCTAssertTrue(cancelled)
        fixture.wakeCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await assertSendCount(1, from: fixture.sender)
    }

    func testWakeSendsFreshLanguageAndPlacementSnapshot() async throws {
        let fixture = makeFixture(accepted: true)
        defer { fixture.stopAndClear() }
        fixture.reporter.start()
        await fixture.sender.waitForSendCount(1)
        fixture.localization.setPreference(.language(.french))
        fixture.settings.appIconPlacement = .dock
        await assertSendCount(1, from: fixture.sender)

        fixture.wakeCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await fixture.sender.waitForSendCount(2)
        let contexts = await fixture.sender.contexts()
        XCTAssertEqual(contexts.last?.appLanguage, "fr")
        XCTAssertEqual(contexts.last?.appIconPlacement, .dock)
    }

    func testStartIsIdempotentStopCancelsScheduleAndRestartStartsOneSchedule() async throws {
        let fixture = makeFixture(accepted: true)
        fixture.reporter.start()
        fixture.reporter.start()
        await fixture.sender.waitForSendCount(1)
        await fixture.sleeper.waitForSleepCount(1)
        fixture.reporter.stop()
        await fixture.sleeper.waitForCancellationCount(1)
        fixture.wakeCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        fixture.reporter.start()
        await fixture.sender.waitForSendCount(2)
        await fixture.sleeper.waitForSleepCount(2)
        fixture.reporter.start()
        await Task.yield()
        await assertSendCount(2, from: fixture.sender)
        let sleepCount = await fixture.sleeper.sleepCount()
        XCTAssertEqual(sleepCount, 2)
        fixture.reporter.stop()
        fixture.clear()
    }

    func testSimultaneousWakeStartAndConsentProducesOneRealClientRequest() async throws {
        let suiteName = "TelemetryReporterClientTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = SettingsStore(defaults: defaults)
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let wakeCenter = NotificationCenter()
        let configuration = TelemetryConfiguration(endpoint: URL(string: "https://example.invalid/ping")!)
        let transport = StubTelemetryTransport(statusCode: 204)
        let client = TelemetryClient(
            transport: transport,
            configuration: configuration,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            persistenceSuiteName: suiteName
        )
        let reporter = TelemetryReporter(
            settings: settings,
            localization: localization,
            client: client,
            eligibilityContext: .init(bundleIdentifier: "com.lingsmbp.StatusTrio", productionMarker: true, isDebugBuild: false),
            configuration: configuration,
            wakeNotificationCenter: wakeCenter,
            sleep: { _ in try await Task.sleep(for: .seconds(600)) },
            snapshotContext: { language, placement in
                TelemetryContext(appVersion: "2.0.0", build: "103", osName: "macOS", osVersion: "15.4",
                                 architecture: "arm64", distribution: "direct", osLanguage: "en",
                                 appLanguage: language.rawValue, appIconPlacement: placement)
            }
        )
        defer {
            reporter.stop()
            defaults.removePersistentDomain(forName: suiteName)
        }

        reporter.start()
        wakeCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        settings.completeTelemetryConsent(sharesAnalytics: true)
        wakeCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        reporter.start()
        await transport.waitForRequestCount(1)
        await Task.yield()

        let count = await transport.requestCount()
        XCTAssertEqual(count, 1)
    }

    func testPeriodicTickTriggersAnotherAttempt() async throws {
        let fixture = makeFixture(accepted: true)
        defer { fixture.stopAndClear() }
        fixture.reporter.start()
        await fixture.sender.waitForSendCount(1)
        await fixture.sleeper.waitForSleepCount(1)
        await fixture.sleeper.resumeNext()
        await fixture.sender.waitForSendCount(2)
        await assertSendCount(2, from: fixture.sender)
    }

    private func assertSendCount(
        _ expected: Int,
        from sender: RecordingTelemetrySender,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let actual = await sender.sendCount()
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    private func makeFixture(
        accepted: Bool,
        productionMarker: Bool = true,
        legacyInstall: Bool = false,
        suspendSender: Bool = false
    ) -> Fixture {
        let suiteName = "TelemetryReporterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        if legacyInstall { defaults.set(true, forKey: "SUHasLaunchedBefore") }
        let settings = SettingsStore(defaults: defaults)
        if accepted { settings.completeTelemetryConsent(sharesAnalytics: true) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let sender = RecordingTelemetrySender(suspend: suspendSender)
        let sleeper = ManualTelemetrySleeper()
        let wakeCenter = NotificationCenter()
        let reporter = TelemetryReporter(
            settings: settings,
            localization: localization,
            client: sender,
            eligibilityContext: .init(
                bundleIdentifier: "com.lingsmbp.StatusTrio",
                productionMarker: productionMarker,
                isDebugBuild: false
            ),
            configuration: TelemetryConfiguration(
                endpoint: URL(string: "https://example.invalid/ping")!,
                reporterCheckInterval: 21_600
            ),
            wakeNotificationCenter: wakeCenter,
            sleep: { duration in try await sleeper.sleep(for: duration) },
            snapshotContext: { language, placement in
                TelemetryContext(
                    appVersion: "2.0.0", build: "103", osName: "macOS", osVersion: "15.4.2",
                    architecture: "arm64", distribution: "direct", osLanguage: "en-GB",
                    appLanguage: language.rawValue, appIconPlacement: placement
                )
            }
        )
        return Fixture(reporter: reporter, settings: settings, localization: localization,
                       sender: sender, sleeper: sleeper, wakeCenter: wakeCenter,
                       defaults: defaults, suiteName: suiteName)
    }
}

@MainActor
private struct Fixture {
    let reporter: TelemetryReporter
    let settings: SettingsStore
    let localization: Localization
    let sender: RecordingTelemetrySender
    let sleeper: ManualTelemetrySleeper
    let wakeCenter: NotificationCenter
    let defaults: UserDefaults
    let suiteName: String
    func clear() { defaults.removePersistentDomain(forName: suiteName) }
    func stopAndClear() { reporter.stop(); clear() }
}

private actor RecordingTelemetrySender: TelemetrySending {
    private var recordedContexts: [TelemetryContext] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private var cancelled = false
    private let suspend: Bool

    init(suspend: Bool) { self.suspend = suspend }

    func sendIfNeeded(context: TelemetryContext) async {
        recordedContexts.append(context)
        resumeWaiters()
        guard suspend else { return }
        await withCheckedContinuation { continuation = $0 }
        cancelled = Task.isCancelled
        for waiter in cancellationWaiters { waiter.resume() }
        cancellationWaiters.removeAll()
    }

    func sendCount() -> Int { recordedContexts.count }
    func contexts() -> [TelemetryContext] { recordedContexts }
    func lastSendWasCancelled() -> Bool { cancelled }

    func waitForSendCount(_ count: Int) async {
        if recordedContexts.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }

    func waitForCancellationObservation() async {
        if cancelled { return }
        await withCheckedContinuation { cancellationWaiters.append($0) }
    }

    private func resumeWaiters() {
        let ready = waiters.filter { recordedContexts.count >= $0.0 }
        waiters.removeAll { recordedContexts.count >= $0.0 }
        for (_, waiter) in ready { waiter.resume() }
    }
}

private actor ManualTelemetrySleeper {
    private var continuation: CheckedContinuation<Void, Error>?
    private var sleepCountValue = 0
    private var sleepWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var cancellationCountValue = 0
    private var cancellationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func sleep(for _: Duration) async throws {
        sleepCountValue += 1
        resumeWaiters()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation = $0 }
        } onCancel: {
            Task { await self.cancelCurrentSleep() }
        }
    }

    func sleepCount() -> Int { sleepCountValue }
    func waitForSleepCount(_ value: Int) async {
        if sleepCountValue >= value { return }
        await withCheckedContinuation { sleepWaiters.append((value, $0)) }
    }

    func resumeNext() {
        continuation?.resume()
        continuation = nil
    }

    func waitForCancellationCount(_ value: Int) async {
        if cancellationCountValue >= value { return }
        await withCheckedContinuation { cancellationWaiters.append((value, $0)) }
    }

    private func cancelCurrentSleep() {
        cancellationCountValue += 1
        continuation?.resume(throwing: CancellationError())
        continuation = nil
        let ready = cancellationWaiters.filter { cancellationCountValue >= $0.0 }
        cancellationWaiters.removeAll { cancellationCountValue >= $0.0 }
        for (_, waiter) in ready { waiter.resume() }
    }

    private func resumeWaiters() {
        let ready = sleepWaiters.filter { sleepCountValue >= $0.0 }
        sleepWaiters.removeAll { sleepCountValue >= $0.0 }
        for (_, waiter) in ready { waiter.resume() }
    }
}
