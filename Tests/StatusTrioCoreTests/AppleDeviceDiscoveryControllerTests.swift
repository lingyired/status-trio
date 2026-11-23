import XCTest
@testable import StatusTrioCore

@MainActor
final class AppleDeviceDiscoveryControllerTests: XCTestCase {
    func testMasterSwitchAloneDoesNotDiscoverWithoutForegroundClaim() async {
        let reader = ControlledMobileBatteryReader()
        let controller = AppleDeviceDiscoveryController(reader: reader)
        controller.setEnabled(true)
        await settle()

        let discoveries = await reader.discoveryCount
        XCTAssertEqual(discoveries, 0)
        XCTAssertTrue(controller.candidates.isEmpty)
        XCTAssertFalse(controller.isDiscovering)
        let reads = await reader.readCount
        XCTAssertEqual(reads, 0)
        controller.stop()
    }

    func testMasterOffStopsDiscoveryAndRemovesCandidates() async {
        let reader = ControlledMobileBatteryReader()
        let controller = AppleDeviceDiscoveryController(reader: reader)
        controller.request("foreground-summary")
        controller.setEnabled(true)
        await waitUntil { await reader.discoveryCount == 1 }
        await reader.completeDiscovery(0, with: [candidate(id: "phone-1", model: "iPhone18,1")])
        await waitUntil { controller.candidates.count == 1 }

        controller.setEnabled(false)

        XCTAssertTrue(controller.candidates.isEmpty)
        XCTAssertFalse(controller.isDiscovering)
        controller.stop()
        await reader.finishAll()
    }

    func testForegroundClaimRequiresEnabledMasterAndNeverReadsBattery() async {
        let reader = ControlledMobileBatteryReader()
        let controller = AppleDeviceDiscoveryController(reader: reader)
        controller.request("foreground-summary")
        await settle()
        let countBeforeEnable = await reader.discoveryCount
        XCTAssertEqual(countBeforeEnable, 0)

        controller.setEnabled(true)
        await settle()
        let discoveryCount = await reader.discoveryCount
        let readCount = await reader.readCount
        XCTAssertEqual(discoveryCount, 1)
        XCTAssertEqual(readCount, 0)
        await reader.completeDiscovery(0, with: [candidate(id: "phone-1", model: "iPhone18,1")])
        await waitUntil { controller.candidates.count == 1 && !controller.isDiscovering }

        controller.release("foreground-summary")
        let readsAfterRelease = await reader.readCount
        XCTAssertEqual(readsAfterRelease, 0)
        controller.stop()
    }

    func testMasterOffRejectsLateDiscoveryResult() async {
        let reader = ControlledMobileBatteryReader()
        let controller = AppleDeviceDiscoveryController(reader: reader)
        controller.request("foreground-summary")
        controller.setEnabled(true)
        await waitUntil { await reader.discoveryCount == 1 }
        controller.setEnabled(false)
        await reader.completeDiscovery(0, with: [candidate(id: "phone-1", model: "iPhone18,1")])
        await settle()
        XCTAssertTrue(controller.candidates.isEmpty)
        XCTAssertFalse(controller.isDiscovering)
        XCTAssertNil(controller.discoveryDiagnostics)
        controller.stop()
        await reader.finishAll()
    }

    func testReleasedSurfaceRejectsLateDiscoveryDiagnostics() async {
        let reader = ControlledMobileBatteryReader()
        let controller = AppleDeviceDiscoveryController(reader: reader)
        controller.request("surface")
        controller.setEnabled(true)
        await waitUntil { await reader.discoveryCount == 1 }
        controller.release("surface")
        await reader.completeDiscovery(0, with: [candidate(id: "late", model: "iPhone18,1")])
        await settle()
        XCTAssertNil(controller.discoveryDiagnostics)
        XCTAssertTrue(controller.candidates.isEmpty)
        controller.stop()
        await reader.finishAll()
    }

    func testRefreshStartsANewReadAuthorityGeneration() async {
        let reader = ControlledMobileBatteryReader()
        let controller = AppleDeviceDiscoveryController(reader: reader)
        controller.request("foreground-summary")
        controller.setEnabled(true)
        await waitUntil { await reader.discoveryCount == 1 }
        await reader.completeDiscovery(0, with: [candidate(id: "phone-1", model: "iPhone18,1")])
        await waitUntil { controller.candidates.count == 1 && !controller.isDiscovering }
        let firstGeneration = controller.discoveryGeneration

        controller.refresh()

        XCTAssertGreaterThan(controller.discoveryGeneration, firstGeneration)
        XCTAssertTrue(controller.candidates.isEmpty)
        controller.setEnabled(false)
        controller.stop()
        await reader.finishAll()
    }

    func testDiscoveryDiagnosticsCountWatchesAndRejectedRoutes() async {
        let reader = ControlledMobileBatteryReader()
        let controller = AppleDeviceDiscoveryController(reader: reader)
        controller.request("foreground-summary")
        controller.setEnabled(true)
        await waitUntil { await reader.discoveryCount == 1 }
        await reader.completeDiscovery(0, with: [
            candidate(id: "phone-1", model: "iPhone18,1"),
            AppleDeviceCandidate(
                id: .trustedWatch(parentID: "phone-1", id: "watch-1"),
                name: "Watch", model: "Watch7,4",
                transports: [.usb], trustRequired: false, evidence: .verifiedAppleModel
            ),
            AppleDeviceCandidate(
                id: .trustedDevice("untrusted"), name: "Phone", model: "iPhone18,1",
                transports: [.usb], trustRequired: true, evidence: .verifiedAppleModel
            ),
        ])
        await waitUntil { controller.candidates.count == 3 && !controller.isDiscovering }

        let diagnostics = controller.discoveryDiagnostics
        XCTAssertEqual(diagnostics?.candidateCount, 3)
        XCTAssertEqual(diagnostics?.watchCandidateCount, 1)
        XCTAssertEqual(diagnostics?.verifiedCandidateCount, 2)
        XCTAssertEqual(diagnostics?.rejectedWatchCount, 0)
        XCTAssertEqual(diagnostics?.rejectedOtherCount, 1)
        XCTAssertNil(diagnostics?.failureCategory)

        controller.setEnabled(false)
        XCTAssertNil(controller.discoveryDiagnostics)
        controller.stop()
        await reader.finishAll()
    }

    func testActualReaderDistinguishesEmptyFailedAndPartialDiscovery() async {
        // All scenarios exercise the real Reader through the Controller.
        for scenario in DiscoveryRouteScenario.allCases {
            let controller = AppleDeviceDiscoveryController(
                reader: MobileBatteryHelperReader(executor: DiscoveryRouteExecutor(scenario: scenario))
            )
            controller.request("integration")
            controller.setEnabled(true)
            await waitUntil { !controller.isDiscovering }
            let diagnostics = controller.discoveryDiagnostics
            let routes = diagnostics?.routeDiagnostics
            XCTAssertNotNil(routes, "\(scenario)")
            XCTAssertEqual(routes?.attemptedRouteCount, scenario.attempted, "\(scenario)")
            XCTAssertEqual(routes?.failedRouteCount, scenario.failed, "\(scenario)")
            XCTAssertEqual(controller.candidates.count, scenario.candidateCount, "\(scenario)")
            if let category = scenario.category {
                XCTAssertTrue(routes?.failureCategories.contains(category) == true, "\(scenario)")
                XCTAssertNotNil(diagnostics?.failureCategory, "\(scenario) must not log failure=none")
            } else {
                XCTAssertNil(diagnostics?.failureCategory)
            }
            controller.stop()
        }
    }

    func testSuccessfulDiscoveryPublishesIDsButFailureLeavesThemUnknown() async {
        let success = AppleDeviceDiscoveryController(
            reader: MobileBatteryHelperReader(executor: DiscoveryRouteExecutor(scenario: .empty)))
        success.request("integration")
        success.setEnabled(true)
        await waitUntil { !success.isDiscovering }
        XCTAssertEqual(success.lastSuccessfulCandidateIDs, [])
        success.stop()

        let failure = AppleDeviceDiscoveryController(
            reader: MobileBatteryHelperReader(executor: DiscoveryRouteExecutor(scenario: .badJSON)))
        failure.request("integration")
        failure.setEnabled(true)
        await waitUntil { !failure.isDiscovering }
        XCTAssertNil(failure.lastSuccessfulCandidateIDs)
        failure.stop()
    }

    private func candidate(id: String, model: String) -> AppleDeviceCandidate {
        AppleDeviceCandidate(
            id: .trustedDevice(id), name: "Device", model: model,
            transports: [.usb], trustRequired: false, evidence: .verifiedAppleModel
        )
    }

    private func settle() async { for _ in 0..<8 { await Task.yield() } }

    private func waitUntil(_ condition: @escaping () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()), ContinuousClock.now < deadline { await Task.yield() }
        let satisfied = await condition()
        XCTAssertTrue(satisfied)
    }
}

private enum DiscoveryRouteScenario: CaseIterable, Sendable {
    case empty, timedOut, badJSON, partial, fallback, nativeFailure, unknownFailure

    var attempted: Int { self == .empty ? 0 : 2 }
    var failed: Int {
        switch self {
        case .empty: 0
        case .partial, .fallback: 1
        default: 2
        }
    }
    var candidateCount: Int {
        switch self {
        case .partial: 1
        case .fallback: 2
        default: 0
        }
    }
    var category: MobileBatteryDiscoveryFailureCategory? {
        switch self {
        case .empty: nil
        case .timedOut, .partial, .fallback: .helperTimeout
        case .badJSON: .invalidEnvelope
        case .nativeFailure: .sessionUnavailable
        case .unknownFailure: .other
        }
    }
}

private struct DiscoveryRouteExecutor: MobileBatteryHelperExecuting {
    let scenario: DiscoveryRouteScenario

    func run(arguments: [String], timeout: Duration) async throws -> Data {
        if arguments == ["--list"] {
            if scenario == .empty {
                return Data(#"{"schemaVersion":1,"phones":[]}"#.utf8)
            }
            if scenario == .partial {
                return Data(#"{"schemaVersion":1,"phones":[{"id":"p","transport":"usb"},{"id":"q","transport":"usb"}]}"#.utf8)
            }
            return Data(#"{"schemaVersion":1,"phones":[{"id":"p","transport":"usb","availableTransports":["usb","network"]}]}"#.utf8)
        }
        switch scenario {
        case .badJSON: return Data("invalid JSON".utf8)
        case .nativeFailure:
            return Data(#"{"schemaVersion":1,"candidates":[],"failures":[{"error":"session-unavailable"},{"error":"session-unavailable"}]}"#.utf8)
        case .unknownFailure:
            return Data(#"{"schemaVersion":1,"candidates":[],"failures":[{"error":"untrusted-external-text"}]}"#.utf8)
        case .partial where arguments[1] == "p":
            return Data(#"{"schemaVersion":1,"candidates":[{"id":"p","model":"iPhone18,1","transport":"usb","trustRequired":false}],"failures":[]}"#.utf8)
        case .fallback where arguments.last == "network":
            return Data(#"{"schemaVersion":1,"candidates":[{"id":"p","model":"iPhone18,1","transport":"network","trustRequired":false},{"id":"w","parentID":"p","transport":"network","trustRequired":false}],"failures":[]}"#.utf8)
        default: throw MobileBatteryHelperError.timedOut
        }
    }
}
