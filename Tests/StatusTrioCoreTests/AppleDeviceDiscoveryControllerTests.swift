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
