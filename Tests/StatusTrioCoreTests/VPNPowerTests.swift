import XCTest
@testable import StatusTrioCore

@MainActor
final class VPNPowerTests: XCTestCase {
    private let office = VPNServiceReading(
        serviceID: "service.office", name: "Office", state: .disconnected, isEnabled: true
    )
    private let home = VPNServiceReading(
        serviceID: "service.home", name: "Home", state: .connected, isEnabled: true
    )

    func testResolverKeepsServiceIdentityInSystemOrderAndReportsActiveName() {
        let status = VPNStatusResolver.resolve(
            VPNProbeReading(services: [office, home])
        )
        XCTAssertEqual(status.services.map(\.serviceID), ["service.office", "service.home"])
        XCTAssertEqual(status.serviceName, "Home")
        XCTAssertEqual(status.services.first?.name, "Office")
    }

    func testDisconnectedServicesStillOfferPowerControl() {
        let status = VPNStatusResolver.resolve(VPNProbeReading(services: [office]))
        XCTAssertTrue(status.showsPowerControl)
        XCTAssertEqual(status.powerControlIsOn, false)
    }

    func testProxyOnlyAndTunnelOnlyHaveNoPowerControl() {
        let proxy = VPNStatusResolver.resolve(
            VPNProbeReading(proxy: VPNProxyStatus(kind: .http, host: "127.0.0.1", port: 10808))
        )
        let tunnel = VPNStatusResolver.resolve(VPNProbeReading(tunnelInterfaces: ["utun4"]))
        XCTAssertFalse(proxy.showsPowerControl)
        XCTAssertFalse(tunnel.showsPowerControl)
    }

    func testStartsFirstConfiguredServiceWhenDisconnected() async {
        let backend = FakeVPNConnectionBackend(result: .confirmed)
        let controller = VPNPowerController(backend: backend, refresh: {})
        let status = VPNStatusResolver.resolve(VPNProbeReading(services: [office, home]))

        await controller.setPower(false, status: status)

        XCTAssertEqual(backend.calls, [.init(connected: false, serviceID: "service.home")])
        XCTAssertFalse(controller.state.isChanging)
        XCTAssertNil(controller.state.failure)
    }

    func testStartsFirstServiceWhenEverythingIsDisconnected() async {
        let backend = FakeVPNConnectionBackend(result: .confirmed)
        let controller = VPNPowerController(backend: backend, refresh: {})
        let status = VPNStatusResolver.resolve(VPNProbeReading(services: [office]))

        await controller.setPower(true, status: status)

        XCTAssertEqual(backend.calls, [.init(connected: true, serviceID: "service.office")])
    }

    func testConnectingServiceWinsOverFirstDisconnectedService() async {
        let backend = FakeVPNConnectionBackend(result: .confirmed)
        let controller = VPNPowerController(backend: backend, refresh: {})
        let status = VPNStatusResolver.resolve(VPNProbeReading(services: [office, home]))

        await controller.setPower(false, status: status)

        XCTAssertEqual(backend.calls.first?.serviceID, "service.home")
    }

    func testNoServicesAndProxyOnlyDoNothing() async {
        let backend = FakeVPNConnectionBackend(result: .confirmed)
        let controller = VPNPowerController(backend: backend, refresh: {})
        let proxy = VPNStatusResolver.resolve(VPNProbeReading(proxy: .init(kind: .http, host: "h", port: 1)))

        await controller.setPower(true, status: .placeholder)
        await controller.setPower(true, status: proxy)

        XCTAssertTrue(backend.calls.isEmpty)
    }

    func testDuplicateTapIsIgnoredAndFailureIsExposed() async {
        let backend = FakeVPNConnectionBackend(result: .rejected, delay: .milliseconds(40))
        let controller = VPNPowerController(backend: backend, refresh: {})
        let status = VPNStatusResolver.resolve(VPNProbeReading(services: [office]))
        let first = Task { await controller.setPower(true, status: status) }
        try? await Task.sleep(for: .milliseconds(10))
        await controller.setPower(true, status: status)
        await first.value

        XCTAssertEqual(backend.calls.count, 1)
        XCTAssertEqual(controller.state.failure, .requestRejected)
        XCTAssertFalse(controller.state.isChanging)
    }

    func testSuccessRefreshesStatusAndClearsFailure() async {
        let backend = FakeVPNConnectionBackend(result: .confirmed)
        var refreshes = 0
        let controller = VPNPowerController(backend: backend, refresh: { refreshes += 1 })
        let status = VPNStatusResolver.resolve(VPNProbeReading(services: [office]))
        await controller.setPower(true, status: status)
        XCTAssertEqual(refreshes, 1)
    }
}

private struct VPNCall: Equatable {
    let connected: Bool
    let serviceID: String
}

private final class FakeVPNConnectionBackend: VPNConnectionControlling, @unchecked Sendable {
    let result: VPNConnectionResult
    let delay: Duration
    private(set) var calls: [VPNCall] = []

    init(result: VPNConnectionResult, delay: Duration = .zero) {
        self.result = result
        self.delay = delay
    }

    func setConnected(_ connected: Bool, serviceID: String) async -> VPNConnectionResult {
        calls.append(VPNCall(connected: connected, serviceID: serviceID))
        if delay > .zero { try? await Task.sleep(for: delay) }
        return result
    }
}
