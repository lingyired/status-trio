import Foundation
import XCTest
@testable import StatusTrioCore

final class TelemetryClientTests: XCTestCase {
    func testFirstAttemptCreatesAndPersistsStableIDBeforeTransportEvenOnFailure() async throws {
        let fixture = makeFixture(statusCode: 500)
        defer { fixture.clear() }

        await fixture.client.sendIfNeeded(context: context())

        let id = try XCTUnwrap(fixture.defaults.string(forKey: "telemetry.installationId"))
        XCTAssertEqual(id.count, 36)
        XCTAssertNotNil(fixture.defaults.object(forKey: "telemetry.lastAttemptAt"))
        XCTAssertNil(fixture.defaults.object(forKey: "telemetry.lastSuccessfulAt"))
        let requests = await fixture.transport.recordedRequests()
        let body = try XCTUnwrap(requests.first?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["install_id"] as? String, id)
    }

    func testRetryAfterFailureReusesInstallIDAndRespectsSixHourBoundary() async throws {
        let fixture = makeFixture(statusCode: 503)
        defer { fixture.clear() }
        await fixture.client.sendIfNeeded(context: context())
        let originalID = fixture.defaults.string(forKey: "telemetry.installationId")

        fixture.clock.advance(by: 6 * 60 * 60 - 1)
        await fixture.client.sendIfNeeded(context: context())
        var requestCount = await fixture.transport.requestCount()
        XCTAssertEqual(requestCount, 1)

        fixture.clock.advance(by: 1)
        await fixture.client.sendIfNeeded(context: context())
        requestCount = await fixture.transport.requestCount()
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(fixture.defaults.string(forKey: "telemetry.installationId"), originalID)
    }

    func testEveryTwoHundredResponseIsSuccessAndTwentyHourBoundaryAllowsNextSend() async throws {
        for statusCode in [200, 299] {
            let fixture = makeFixture(statusCode: statusCode)
            defer { fixture.clear() }
            await fixture.client.sendIfNeeded(context: context())
            XCTAssertNotNil(fixture.defaults.object(forKey: "telemetry.lastSuccessfulAt"))
            fixture.clock.advance(by: 20 * 60 * 60 - 1)
            await fixture.client.sendIfNeeded(context: context())
            var requestCount = await fixture.transport.requestCount()
            XCTAssertEqual(requestCount, 1)
            fixture.clock.advance(by: 1)
            await fixture.client.sendIfNeeded(context: context())
            requestCount = await fixture.transport.requestCount()
            XCTAssertEqual(requestCount, 2)
        }
    }

    func testNonSuccessStatusesAndTransportErrorsNeverRecordSuccess() async throws {
        for statusCode in [400, 404, 429, 500] {
            let fixture = makeFixture(statusCode: statusCode)
            await fixture.client.sendIfNeeded(context: context())
            XCTAssertNil(fixture.defaults.object(forKey: "telemetry.lastSuccessfulAt"))
            fixture.clear()
        }
        let failed = makeFixture(shouldThrow: true)
        await failed.client.sendIfNeeded(context: context())
        XCTAssertNil(failed.defaults.object(forKey: "telemetry.lastSuccessfulAt"))
        failed.clear()
    }

    func testFutureStoredTimestampsConservativelySkipAfterClockRollback() async throws {
        let fixture = makeFixture(statusCode: 204)
        defer { fixture.clear() }
        fixture.defaults.set(fixture.clock.now.addingTimeInterval(1), forKey: "telemetry.lastAttemptAt")

        await fixture.client.sendIfNeeded(context: context())

        let requestCount = await fixture.transport.requestCount()
        XCTAssertEqual(requestCount, 0)
        XCTAssertNil(fixture.defaults.string(forKey: "telemetry.installationId"))
    }

    @MainActor
    func testCancelledQueuedAttemptDoesNotCreateIDOrSend() async throws {
        let fixture = makeFixture(statusCode: 204)
        defer { fixture.clear() }
        let client = fixture.client
        let telemetryContext = context()
        let task = Task { @MainActor in
            await client.sendIfNeeded(context: telemetryContext)
        }
        task.cancel()
        await task.value

        let requestCount = await fixture.transport.requestCount()
        XCTAssertEqual(requestCount, 0)
        XCTAssertNil(fixture.defaults.string(forKey: "telemetry.installationId"))
        XCTAssertNil(fixture.defaults.object(forKey: "telemetry.lastAttemptAt"))
    }

    func testCancelledInFlightResponseDoesNotRecordSuccess() async throws {
        let suite = uniqueSuite()
        let transport = GatedTelemetryTransport()
        let client = TelemetryClient(
            transport: transport,
            configuration: TelemetryConfiguration(endpoint: URL(string: "https://example.invalid/ping")!),
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            persistenceSuiteName: suite.name
        )
        defer { suite.defaults.removePersistentDomain(forName: suite.name) }
        let telemetryContext = context()
        let task = Task { await client.sendIfNeeded(context: telemetryContext) }
        await transport.waitUntilEntered()

        task.cancel()
        await transport.resume()
        await task.value

        XCTAssertNil(suite.defaults.object(forKey: TelemetryClient.lastSuccessfulAtKey))
    }

    func testOverlappingAttemptsSerializeToOneRequest() async throws {
        let suite = uniqueSuite()
        let transport = GatedTelemetryTransport()
        let client = TelemetryClient(
            transport: transport,
            configuration: TelemetryConfiguration(endpoint: URL(string: "https://example.invalid/ping")!),
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            persistenceSuiteName: suite.name
        )
        defer { suite.defaults.removePersistentDomain(forName: suite.name) }

        let telemetryContext = context()
        let first = Task { await client.sendIfNeeded(context: telemetryContext) }
        await transport.waitUntilEntered()
        XCTAssertNotNil(suite.defaults.string(forKey: TelemetryClient.installationIDKey))
        XCTAssertNotNil(suite.defaults.object(forKey: TelemetryClient.lastAttemptAtKey))
        await client.sendIfNeeded(context: context())
        let requestCount = await transport.requestCount()
        XCTAssertEqual(requestCount, 1)
        await transport.resume()
        await first.value
    }

    private func context() -> TelemetryContext {
        TelemetryContext(appVersion: "2.0.0", build: "103", osName: "macOS", osVersion: "15.4.2",
                         architecture: "arm64", distribution: "direct", osLanguage: "en", appLanguage: "en",
                         appIconPlacement: .menuBar)
    }

    private func makeFixture(statusCode: Int = 204, shouldThrow: Bool = false) -> Fixture {
        let suite = uniqueSuite()
        let clock = ControlledTelemetryClock(Date(timeIntervalSince1970: 1_800_000_000))
        let transport = StubTelemetryTransport(statusCode: statusCode, shouldThrow: shouldThrow)
        let client = TelemetryClient(
            transport: transport,
            configuration: TelemetryConfiguration(endpoint: URL(string: "https://example.invalid/ping")!),
            now: { clock.now },
            persistenceSuiteName: suite.name
        )
        return Fixture(client: client, transport: transport, clock: clock, defaults: suite.defaults, suiteName: suite.name)
    }

    private func uniqueSuite() -> (defaults: UserDefaults, name: String) {
        let name = "TelemetryClientTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }
}

private struct Fixture {
    let client: TelemetryClient
    let transport: StubTelemetryTransport
    let clock: ControlledTelemetryClock
    let defaults: UserDefaults
    let suiteName: String
    func clear() { defaults.removePersistentDomain(forName: suiteName) }
}

private final class ControlledTelemetryClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(by interval: TimeInterval) { lock.lock(); value.addTimeInterval(interval); lock.unlock() }
}

private actor GatedTelemetryTransport: TelemetryTransport {
    private var count = 0
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var responseWaiter: CheckedContinuation<HTTPURLResponse, Never>?
    private var entered = false

    func send(request: URLRequest) async throws -> HTTPURLResponse {
        count += 1
        entered = true
        requestWaiter?.resume()
        requestWaiter = nil
        return await withCheckedContinuation { responseWaiter = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func requestCount() -> Int { count }

    func resume() {
        let response = HTTPURLResponse(url: URL(string: "https://example.invalid/ping")!, statusCode: 204, httpVersion: nil, headerFields: nil)!
        responseWaiter?.resume(returning: response)
        responseWaiter = nil
    }
}
