import XCTest
@testable import StatusTrioCore

final class MihomoTunnelTests: XCTestCase {
    func testParserOnlyReportsAnEnabledTunWithADevice() {
        XCTAssertEqual(
            MihomoConfigParser.tunnel(
                fromJSON: ["tun": ["enable": true, "device": "utun4"]],
                provider: "Clash Verge"
            ),
            MihomoTunnelInfo(provider: "Clash Verge", device: "utun4", isEnabled: true)
        )
        XCTAssertNil(MihomoConfigParser.tunnel(
            fromJSON: ["tun": ["enable": false, "device": "utun4"]],
            provider: "Clash Verge"
        ))
        XCTAssertNil(MihomoConfigParser.tunnel(
            fromJSON: ["tun": ["enable": true, "device": ""]],
            provider: "Clash Verge"
        ))
        XCTAssertNil(MihomoConfigParser.tunnel(fromJSON: [:], provider: "Clash Verge"))
    }

    @MainActor
    func testControllerDeduplicatesAndClearsAttributionOnDeactivate() async {
        let client = FakeMihomoReader(info: MihomoTunnelInfo(
            provider: "Clash Verge", device: "utun4", isEnabled: true
        ))
        let controller = MihomoTunnelController(client: client, observer: FakeMihomoObserver())
        controller.activate()
        let loaded = await waitUntil { controller.info != nil }
        XCTAssertTrue(loaded)
        controller.activate()
        await Task.yield()
        XCTAssertEqual(client.calls, 1)
        controller.deactivate()
        XCTAssertNil(controller.info)
    }

    func testLocalClashVergeSocketWhenPresent() async throws {
        let socket = "/var/run/clash-verge-service/users/\(getuid())/verge-mihomo.sock"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: socket),
                          "No local Clash Verge service socket")
        let info = await SystemMihomoTunnelClient().read()
        // The parser intentionally returns nil when TUN is disabled; if it is
        // enabled, the attribution must name the client and device.
        if let info {
            XCTAssertEqual(info.provider, "Clash Verge")
            XCTAssertFalse(info.device.isEmpty)
            XCTAssertTrue(info.isEnabled)
        }
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return condition()
    }
}

private final class FakeMihomoReader: MihomoTunnelReading, @unchecked Sendable {
    let info: MihomoTunnelInfo?
    private(set) var calls = 0
    init(info: MihomoTunnelInfo?) { self.info = info }
    func read() async -> MihomoTunnelInfo? {
        calls += 1
        return info
    }
}

private final class FakeMihomoObserver: NetworkChangeObserving {
    func start(queue: DispatchQueue, handler: @escaping @Sendable () -> Void) {}
    func cancel() {}
}
