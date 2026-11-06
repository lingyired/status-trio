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
        XCTAssertEqual(
            MihomoConfigParser.tunnel(
                fromJSON: ["tun": ["enable": false, "device": "utun4"]],
                provider: "Clash Verge"
            )?.isEnabled,
            false
        )
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

    @MainActor
    func testControllerPublishesAReadbackAfterToggle() async {
        let client = FakeMihomoReader(info: MihomoTunnelInfo(
            provider: "Clash Verge", device: "utun4", isEnabled: true
        ))
        let controller = MihomoTunnelController(client: client, observer: FakeMihomoObserver())
        controller.activate()
        _ = await waitUntil { controller.info != nil }
        await controller.setEnabled(false)
        XCTAssertEqual(controller.info?.isEnabled, false)
        XCTAssertFalse(controller.info?.isChanging ?? true)
        XCTAssertNil(controller.info?.failure)
        controller.deactivate()
    }

    func testSettingsStoreOnlyTouchesTunFlagsAndPreservesEverythingElse() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClashVergeSettingsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let verge = directory.appendingPathComponent("verge.yaml")
        let generated = directory.appendingPathComponent("clash-verge.yaml")
        try """
        language: zh
        enable_tun_mode: true
        enable_system_proxy: true
        secret: keep-me
        """.write(to: verge, atomically: true, encoding: .utf8)
        try """
        mode: rule
        tun:
          enable: true
          stack: gvisor
        secret: keep-me
        """.write(to: generated, atomically: true, encoding: .utf8)

        XCTAssertTrue(ClashVergeSettingsStore(directory: directory).setTunMode(false))

        let vergeText = try String(contentsOf: verge, encoding: .utf8)
        let generatedText = try String(contentsOf: generated, encoding: .utf8)
        XCTAssertTrue(vergeText.contains("enable_tun_mode: false"))
        XCTAssertTrue(vergeText.contains("enable_system_proxy: true"))
        XCTAssertTrue(vergeText.contains("secret: keep-me"))
        XCTAssertTrue(generatedText.contains("tun:\n  enable: false\n  stack: gvisor"))
        XCTAssertTrue(generatedText.contains("secret: keep-me"))
    }

    func testLocalClashVergeSocketWhenPresent() async throws {
        let socket = "/var/run/clash-verge-service/users/\(getuid())/verge-mihomo.sock"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: socket),
                          "No local Clash Verge service socket")
        let info = await SystemMihomoTunnelClient().read()
        XCTAssertEqual(info?.provider, "Clash Verge")
        XCTAssertNotNil(info?.device)
        XCTAssertNotNil(info?.isEnabled)
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

private final class FakeMihomoReader: MihomoTunnelControlling, @unchecked Sendable {
    let info: MihomoTunnelInfo?
    private(set) var calls = 0
    init(info: MihomoTunnelInfo?) { self.info = info }
    func read() async -> MihomoTunnelInfo? {
        calls += 1
        return info
    }
    func setEnabled(_ enabled: Bool, expectedDevice: String) async -> MihomoTunnelWriteResult {
        guard let info, info.device == expectedDevice else { return .rejected }
        return .updated(MihomoTunnelInfo(
            provider: info.provider, device: info.device, isEnabled: enabled
        ))
    }
}

private final class FakeMihomoObserver: NetworkChangeObserving {
    func start(queue: DispatchQueue, handler: @escaping @Sendable () -> Void) {}
    func cancel() {}
}
