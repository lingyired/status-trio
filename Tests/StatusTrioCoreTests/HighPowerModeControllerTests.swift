import XCTest
@testable import StatusTrioCore

@MainActor
final class HighPowerModeControllerTests: XCTestCase {
    func testOutdatedDaemonSurfacesANeedsUpdateNotice() async {
        // Protocol version 1 is the Low Power Mode-only daemon: it answers the
        // version handshake but cannot serve the High Power Mode methods.
        let client = FakeHighPowerClient(version: .success(1))
        let controller = HighPowerModeController(client: client, platformSupported: true)
        controller.setEnabled(true)
        await waitUntil { controller.hasProbed }

        XCTAssertTrue(controller.needsHelperUpdate)
        XCTAssertFalse(controller.isSupported)
        XCTAssertEqual(client.supportCallCount, 0)
    }

    func testLegacyDaemonWithoutTheVersionSelectorNeedsAnUpdate() async {
        // A daemon built before the handshake invalidates the version request.
        // It still answers the original Low Power Mode read, which is what
        // separates "outdated" from "not there".
        let client = FakeHighPowerClient(
            version: .failure(FakeError.missingSelector),
            legacyAnswers: true
        )
        let controller = HighPowerModeController(client: client, platformSupported: true)
        controller.setEnabled(true)
        await waitUntil { controller.hasProbed }

        XCTAssertTrue(controller.needsHelperUpdate)
        XCTAssertFalse(controller.isSupported)
    }

    func testUnreachableHelperHidesTheControlWithoutANeedsUpdateNotice() async {
        // Nothing answers at all: there is no update to ask for, so the control
        // simply stays hidden.
        let client = FakeHighPowerClient(
            version: .failure(FakeError.missingSelector),
            legacyAnswers: false
        )
        let controller = HighPowerModeController(client: client, platformSupported: true)
        controller.setEnabled(true)
        await waitUntil { controller.hasProbed }

        XCTAssertFalse(controller.needsHelperUpdate)
        XCTAssertFalse(controller.isSupported)
    }

    func testUnsupportedMachineHidesTheControl() async {
        let client = FakeHighPowerClient(version: .success(2), supported: false)
        let controller = HighPowerModeController(client: client, platformSupported: true)
        controller.setEnabled(true)
        await waitUntil { controller.hasProbed }

        XCTAssertFalse(controller.isSupported)
        XCTAssertFalse(controller.needsHelperUpdate)
        XCTAssertEqual(client.readCallCount, 0)
    }

    func testSupportedMachineReadsTheCurrentState() async {
        let client = FakeHighPowerClient(version: .success(2), supported: true, reads: true)
        let controller = HighPowerModeController(client: client, platformSupported: true)
        controller.setEnabled(true)
        await waitUntil { controller.hasProbed && client.readCallCount == 1 }

        XCTAssertTrue(controller.isSupported)
        XCTAssertTrue(controller.isHighPowerMode)
        XCTAssertFalse(controller.needsHelperUpdate)
    }

    func testWriteForwardsAndAdoptsTheObservedValue() async {
        let client = FakeHighPowerClient(version: .success(2), supported: true, reads: false)
        // The daemon observes the switch still off after the write.
        client.setResult = false
        let controller = HighPowerModeController(client: client, platformSupported: true)
        controller.setEnabled(true)
        await waitUntil { controller.hasProbed }

        controller.setHighPowerMode(true)
        await waitUntil { !controller.isApplying }

        XCTAssertEqual(client.setCallCount, 1)
        XCTAssertEqual(client.lastSetValue, true)
        XCTAssertFalse(controller.isHighPowerMode, "the reply is authoritative, not the request")
    }

    func testWriteIsIgnoredWhenTheMachineIsUnsupported() async {
        let client = FakeHighPowerClient(version: .success(2), supported: false)
        let controller = HighPowerModeController(client: client, platformSupported: true)
        controller.setEnabled(true)
        await waitUntil { controller.hasProbed }

        controller.setHighPowerMode(true)
        await settle()
        XCTAssertEqual(client.setCallCount, 0)
    }

    func testOptOutBeforeAQueuedProbePreventsHelperContact() async {
        let client = FakeHighPowerClient(version: .success(2))
        let controller = HighPowerModeController(client: client, platformSupported: true)
        controller.setEnabled(true)
        controller.setEnabled(false)
        await settle()

        XCTAssertEqual(client.versionCallCount, 0)
        XCTAssertNil(controller.lastError)
    }

    func testOldPlatformNeverContactsHelperEvenWhenCapabilityWouldBeSupported() async {
        let client = FakeHighPowerClient()
        let controller = HighPowerModeController(client: client, platformSupported: false)
        controller.setEnabled(true)
        controller.setHighPowerMode(true)
        await settle()
        XCTAssertEqual(client.versionCallCount, 0)
        XCTAssertEqual(client.setCallCount, 0)
        XCTAssertFalse(controller.isSupported)
    }

    func testCurrentDaemonProbeErrorIsNotReportedAsOutdated() async {
        let client = FakeHighPowerClient(legacyAnswers: true)
        client.supportError = FakeError.missingSelector
        let controller = HighPowerModeController(client: client, platformSupported: true)
        controller.setEnabled(true)
        await waitUntil { controller.hasProbed }
        XCTAssertFalse(controller.needsHelperUpdate)
        XCTAssertNotNil(controller.lastError)
    }

    // MARK: - Helpers

    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() {
            if ContinuousClock.now >= deadline {
                XCTFail("Timed out waiting for the high power mode controller to settle.")
                return
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    private func settle() async {
        for _ in 0..<25 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    private enum FakeError: Error {
        case missingSelector
    }
}

private final class FakeHighPowerClient: HighPowerModeClienting, @unchecked Sendable {
    var version: Result<Int, any Error>
    var supported: Bool
    var reads: Bool
    var setResult: Bool?
    var setError: Error?
    var supportError: Error?
    var legacyAnswers: Bool
    private(set) var versionCallCount = 0
    private(set) var supportCallCount = 0
    private(set) var readCallCount = 0
    private(set) var setCallCount = 0
    private(set) var lastSetValue: Bool?

    init(
        version: Result<Int, any Error> = .success(2),
        supported: Bool = true,
        reads: Bool = false,
        legacyAnswers: Bool = false
    ) {
        self.version = version
        self.supported = supported
        self.reads = reads
        self.legacyAnswers = legacyAnswers
    }

    func protocolVersion() async throws -> Int {
        versionCallCount += 1
        return try version.get()
    }

    func highPowerModeSupported() async throws -> Bool {
        supportCallCount += 1
        if let supportError { throw supportError }
        return supported
    }

    func readHighPowerMode() async throws -> Bool {
        readCallCount += 1
        return reads
    }

    func setHighPowerMode(_ enabled: Bool) async throws -> Bool {
        setCallCount += 1
        lastSetValue = enabled
        if let setError { throw setError }
        return setResult ?? enabled
    }

    func canReadLowPowerMode() async -> Bool {
        legacyAnswers
    }
}
