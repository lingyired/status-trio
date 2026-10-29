import Combine
import XCTest
@testable import StatusTrioCore

final class BetterDisplayAutomaticAssociationTests: XCTestCase {
    func testParserPreservesTrimmedRegistryLocation() throws {
        let devices = try BetterDisplayVolumeParser.parseDevices(
            #"[{"UUID":"display-a","deviceType":"Display","name":"Desk","registryLocation":"  IOService:/external/a  "}]"#
        )
        XCTAssertEqual(devices.first?.registryLocation, "IOService:/external/a")
    }

    func testExactAudioIdentityAndRegistryPathResolveDisplayUUID() {
        XCTAssertEqual(
            BetterDisplayAudioDisplayMatcher.match(
                outputUID: "audio-a",
                framebuffers: [.init(registryLocation: "IOService:/a", edidUUID: "audio-a")],
                devices: [.init(uuid: "display-a", name: "Desk", registryLocation: "IOService:/a")]
            ),
            "display-a"
        )
    }

    func testMissingOrAmbiguousIdentityNeverGuessesFromNameOrPosition() {
        let framebuffer = BetterDisplayFramebufferIdentity(
            registryLocation: "IOService:/a", edidUUID: "audio-a"
        )
        let device = BetterDisplayDevice(
            uuid: "display-a", name: "Desk", registryLocation: "IOService:/a"
        )
        let cases: [([BetterDisplayFramebufferIdentity], [BetterDisplayDevice])] = [
            ([], [device]),
            ([framebuffer, framebuffer], [device]),
            ([framebuffer], [device, .init(uuid: "display-b", name: "Desk", registryLocation: "IOService:/a")]),
            ([.init(registryLocation: "IOService:/a", edidUUID: nil)], [device]),
            ([.init(registryLocation: "", edidUUID: "audio-a")], [device]),
            ([framebuffer], [.init(uuid: "audio-a", name: "Desk")]),
            ([framebuffer], [.init(uuid: "display-a", name: "Desk", registryLocation: "IOService:/b")])
        ]
        for (framebuffers, devices) in cases {
            XCTAssertNil(BetterDisplayAudioDisplayMatcher.match(
                outputUID: "audio-a", framebuffers: framebuffers, devices: devices
            ))
        }
    }
}

@MainActor
final class BetterDisplayAutomaticAssociationStoreTests: XCTestCase {
    func testExactMatchPersistsOnceWithoutSettingsView() async throws {
        try await checkAssociation(savedUUID: nil, expectedUUID: "display-a")
    }

    func testExplicitSavedDisplayIsNeverOverwritten() async throws {
        try await checkAssociation(savedUUID: "manual-display", expectedUUID: "manual-display")
    }

    func testOtherOutputCatalogCannotBindCurrentOutput() async throws {
        try await checkAssociation(savedUUID: nil, catalogOutput: "audio-other", expectedUUID: nil)
    }

    func testStandardAndNativeOutputsDoNotSaveAnAssociation() async throws {
        try await checkAssociation(savedUUID: nil, backend: .directDDC, expectedUUID: nil)
        try await checkAssociation(savedUUID: nil, native: true, expectedUUID: nil)
    }

    private func checkAssociation(
        savedUUID: String?,
        catalogOutput: String = "audio-a",
        backend: ExternalVolumeBackend = .betterDisplay,
        native: Bool = false,
        expectedUUID: String?
    ) async throws {
        let suite = "BetterDisplayAutomaticAssociation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.setExternalVolumeConfiguration(
            .init(backend: backend, betterDisplayUUID: savedUUID), for: "audio-a"
        )
        let output = AudioOutputDevice(id: 93, name: "Desk", uid: "audio-a", isCurrent: true)
        let monitor = AssociationVolumeMonitor()
        let store = SystemStatusStore(
            batteryMonitor: AssociationBatteryMonitor(),
            wifiMonitor: AssociationWiFiMonitor(),
            volumeMonitor: monitor,
            wakeNotificationCenter: NotificationCenter(),
            initialSnapshot: .init(
                battery: .placeholder, wifi: .placeholder,
                volume: .init(
                    scalar: nil, isMuted: false, deviceName: output.name,
                    currentDevice: output, outputDevices: [output],
                    controlSource: native ? .native : .unavailable
                )
            )
        )
        store.bindExternalVolumeSettings(settings)
        store.start()
        defer { store.stop() }
        var writes = 0
        let observation = settings.$externalVolumeConfigurations.dropFirst().sink { _ in writes += 1 }
        defer { observation.cancel() }
        for phase in [BetterDisplayAvailability.deviceUnassociated, .discovering] {
            let update = BetterDisplayCatalogUpdate(
                devices: [.init(uuid: "display-a", name: "Desk")],
                availability: phase, isCatalogLoaded: true,
                outputUID: catalogOutput, automaticDisplayUUID: "display-a"
            )
            let received = expectation(description: "catalog applied")
            let token = store.$betterDisplayState.sink {
                if $0 == update { received.fulfill() }
            }
            monitor.send(update)
            await fulfillment(of: [received], timeout: 1)
            token.cancel()
            XCTAssertEqual(settings.externalVolumeConfiguration(for: "audio-a").betterDisplayUUID, expectedUUID)
        }
        XCTAssertEqual(writes, expectedUUID == "display-a" ? 1 : 0)
    }
}

@MainActor
private final class AssociationVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { $0.finish() }
    let betterDisplayCatalogUpdates: AsyncStream<BetterDisplayCatalogUpdate>
    private let continuation: AsyncStream<BetterDisplayCatalogUpdate>.Continuation
    init() {
        (betterDisplayCatalogUpdates, continuation) = AsyncStream.makeStream()
    }
    func send(_ value: BetterDisplayCatalogUpdate) { continuation.yield(value) }
    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
}

@MainActor
private final class AssociationBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class AssociationWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}
