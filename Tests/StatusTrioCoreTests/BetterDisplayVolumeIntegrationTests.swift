import CoreAudio
import XCTest
@testable import StatusTrioCore

private actor IntegrationFramebufferReadCounter {
    private(set) var count = 0
    func read() -> [BetterDisplayFramebufferIdentity] {
        count += 1
        return []
    }
}

@MainActor
private final class AutomaticSetupBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class AutomaticSetupWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
final class BetterDisplayVolumeIntegrationTests: XCTestCase {
    func testCurrentAudioOutputAutomaticallyAssociatesAndConnectsWithoutSettingsViewOrWrites() async throws {
        let suite = "BetterDisplayAutoSetup.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.setExternalVolumeConfiguration(
            .init(backend: .betterDisplay, betterDisplayUUID: nil), for: "audio-desk"
        )
        let device = AudioOutputDevice(id: 93, name: "Desk", uid: "audio-desk", isCurrent: true)
        let reader = CoreAudioStatusReader { _ in
            AudioStatusReading(
                volume: .init(
                    scalar: nil, isMuted: false, deviceName: device.name,
                    currentDevice: device, canSetVolume: false, canMute: false
                ),
                outputDevices: [device]
            )
        }
        let client = IntegrationBetterDisplayClient()
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk","registryLocation":"IOService:/a"}]"#
            }
            XCTAssertEqual(request.string("UUID"), "display-a")
            return request.has("mute") ? "off" : "5,0,10"
        }
        let clock = BetterDisplayTestClock()
        let ddc = RecordingIntegrationDDCTransport()
        let monitor = VolumeMonitor(
            statusReader: reader, eventMonitor: IntegrationVolumeEventMonitor(),
            outputController: RecordingExternalAudioOutputController(),
            ddcTransport: ddc, betterDisplayClient: client,
            betterDisplaySleep: { try await clock.sleep($0) },
            betterDisplayReadFramebuffers: {
                [.init(registryLocation: "IOService:/a", edidUUID: "audio-desk")]
            },
            refreshDebounceSleep: { _ in }
        )
        let store = SystemStatusStore(
            batteryMonitor: AutomaticSetupBatteryMonitor(),
            wifiMonitor: AutomaticSetupWiFiMonitor(), volumeMonitor: monitor,
            wakeNotificationCenter: NotificationCenter()
        )
        store.bindExternalVolumeSettings(settings)
        store.start()
        defer {
            store.stop()
            clock.cancelAll()
        }
        await assertIntegrationCondition {
            store.betterDisplayState.availability == .available
                && store.liveVolume.canSetVolume
        }
        XCTAssertEqual(settings.externalVolumeConfiguration(for: "audio-desk").betterDisplayUUID, "display-a")
        XCTAssertEqual(store.betterDisplayState.automaticDisplayUUID, "display-a")
        XCTAssertEqual(store.liveVolume.controlSource, .betterDisplay)
        XCTAssertEqual(store.liveVolume.scalar, 0.5)
        XCTAssertEqual(client.requests.filter { $0.has("identifiers") }.count, 1)
        XCTAssertTrue(client.requests.allSatisfy { $0.commands == ["get"] })
        XCTAssertEqual(ddc.readCount, 0)
        XCTAssertEqual(ddc.writeValues, [])
    }

    func testChoosingBackendThenDisplayConnectsAutomaticallyWithoutVolumeWrites() async {
        let device = AudioOutputDevice(id: 93, name: "Desk", uid: "audio-desk", isCurrent: true)
        let reader = CoreAudioStatusReader { _ in
            AudioStatusReading(
                volume: VolumeReading(
                    scalar: nil, isMuted: false, deviceName: device.name,
                    currentDevice: device, canSetVolume: false, canMute: false
                ),
                outputDevices: [device]
            )
        }
        let client = IntegrationBetterDisplayClient()
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk"}]"#
            }
            XCTAssertEqual(request.string("UUID"), "display-a")
            return request.has("mute") ? "off" : "5,0,10"
        }
        let ddc = RecordingIntegrationDDCTransport()
        let clock = BetterDisplayTestClock()
        let monitor = VolumeMonitor(
            statusReader: reader, eventMonitor: IntegrationVolumeEventMonitor(),
            outputController: RecordingExternalAudioOutputController(),
            ddcTransport: ddc, betterDisplayClient: client,
            betterDisplaySleep: { try await clock.sleep($0) }
        )
        var catalog: [BetterDisplayCatalogUpdate] = []
        let task = Task { @MainActor in
            for await update in monitor.betterDisplayCatalogUpdates { catalog.append(update) }
        }
        monitor.setExternalVolumeConfigurations([
            "audio-desk": ExternalVolumeConfiguration(backend: .betterDisplay, betterDisplayUUID: nil)
        ])
        monitor.start()
        await assertIntegrationCondition { catalog.last?.availability == .deviceUnassociated }
        XCTAssertEqual(catalog.last?.devices.map(\.uuid), ["display-a"])
        XCTAssertEqual(catalog.last?.canSetVolume, false)

        monitor.setExternalVolumeConfigurations([
            "audio-desk": ExternalVolumeConfiguration(backend: .betterDisplay, betterDisplayUUID: "display-a")
        ])
        await assertIntegrationCondition {
            catalog.last?.availability == .available && catalog.last?.canSetVolume == true
        }
        XCTAssertEqual(catalog.last?.outputUID, "audio-desk")
        XCTAssertEqual(catalog.last?.displayUUID, "display-a")
        let status = await nextVolumeStatus(from: monitor.updates) { $0.canSetVolume }
        XCTAssertEqual(status?.controlSource, .betterDisplay)
        XCTAssertEqual(status?.scalar, 0.5)
        XCTAssertTrue(client.requests.allSatisfy { $0.commands == ["get"] })
        XCTAssertEqual(client.requests.filter { $0.has("identifiers") }.count, 1)
        XCTAssertEqual(ddc.readCount, 0)
        XCTAssertEqual(ddc.writeValues, [])
        monitor.stop()
        task.cancel()
        clock.cancelAll()
    }

    func testDefaultDirectDDCNeverStartsBetterDisplayIntegration() async {
        let framebufferReads = IntegrationFramebufferReadCounter()
        let device = AudioOutputDevice(
            id: 93,
            name: "BenQ",
            uid: "audio-benq",
            isCurrent: true
        )
        let reader = CoreAudioStatusReader { _ in
            AudioStatusReading(
                volume: VolumeReading(
                    scalar: nil,
                    isMuted: false,
                    deviceName: device.name,
                    currentDevice: device,
                    canSetVolume: false,
                    canMute: false
                ),
                outputDevices: [device]
            )
        }
        let client = IntegrationBetterDisplayClient()
        let ddc = RecordingIntegrationDDCTransport()
        let monitor = VolumeMonitor(
            statusReader: reader,
            eventMonitor: IntegrationVolumeEventMonitor(),
            outputController: RecordingExternalAudioOutputController(),
            ddcTransport: ddc,
            betterDisplayClient: client,
            betterDisplayReadFramebuffers: { await framebufferReads.read() }
        )
        monitor.setDetailsVisible(true)
        monitor.start()

        let status = await nextVolumeStatus(from: monitor.updates) {
            $0.scalar == 0.5
        }

        XCTAssertNotNil(status)
        XCTAssertEqual(status?.controlSource, .directDDC)
        XCTAssertGreaterThan(ddc.readCount, 0)
        XCTAssertEqual(client.startCount, 0)
        XCTAssertTrue(client.requests.isEmpty)
        let framebufferReadCount = await framebufferReads.count
        XCTAssertEqual(framebufferReadCount, 0)
        monitor.stop()
    }

    func testNativeWritableVolumeWinsWithoutBetterDisplayOrDDCOperations() async {
        let framebufferReads = IntegrationFramebufferReadCounter()
        let device = AudioOutputDevice(
            id: 93,
            name: "BenQ",
            uid: "audio-benq",
            isCurrent: true
        )
        let reader = CoreAudioStatusReader { _ in
            AudioStatusReading(
                volume: VolumeReading(
                    scalar: 0.4,
                    isMuted: false,
                    deviceName: device.name,
                    currentDevice: device,
                    canSetVolume: true,
                    canMute: true
                ),
                outputDevices: [device]
            )
        }
        let output = RecordingExternalAudioOutputController()
        let client = IntegrationBetterDisplayClient()
        let ddc = RecordingIntegrationDDCTransport()
        let monitor = VolumeMonitor(
            statusReader: reader,
            eventMonitor: IntegrationVolumeEventMonitor(),
            outputController: output,
            ddcTransport: ddc,
            betterDisplayClient: client,
            betterDisplaySleep: { _ in },
            betterDisplayReadFramebuffers: { await framebufferReads.read() }
        )
        monitor.setExternalVolumeConfigurations([
            "audio-benq": ExternalVolumeConfiguration(
                backend: .betterDisplay,
                betterDisplayUUID: "display-a"
            )
        ])
        monitor.setDetailsVisible(true)
        monitor.start()
        let initial = await nextVolumeStatus(from: monitor.updates) { $0.scalar == 0.4 }
        XCTAssertEqual(initial?.canSetVolume, true)
        XCTAssertEqual(initial?.controlSource, .native)

        monitor.setVolume(0.7)

        XCTAssertEqual(output.volumeValues, [0.7])
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertEqual(ddc.resolveCount, 0)
        XCTAssertEqual(ddc.writeValues, [])
        let framebufferReadCount = await framebufferReads.count
        XCTAssertEqual(framebufferReadCount, 0)
        monitor.stop()
    }

    func testBetterDisplaySelectionNeverFallsBackToDDCDuringRequestFailure() async {
        let device = AudioOutputDevice(
            id: 93,
            name: "BenQ",
            uid: "audio-benq",
            isCurrent: true
        )
        let reader = CoreAudioStatusReader { _ in
            AudioStatusReading(
                volume: VolumeReading(
                    scalar: nil,
                    isMuted: false,
                    deviceName: device.name,
                    currentDevice: device,
                    canSetVolume: false,
                    canMute: false
                ),
                outputDevices: [device]
            )
        }
        let output = RecordingExternalAudioOutputController()
        let client = IntegrationBetterDisplayClient()
        var initialRead = true
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"BenQ"}]"#
            }
            if request.has("mute") { return "off" }
            if request.commands == ["set"] {
                initialRead = false
                throw BetterDisplayIntegrationError.requestFailed
            }
            return initialRead ? "5,0,10" : "5,0,10"
        }
        let ddc = RecordingIntegrationDDCTransport()
        let monitor = VolumeMonitor(
            statusReader: reader,
            eventMonitor: IntegrationVolumeEventMonitor(),
            outputController: output,
            ddcTransport: ddc,
            betterDisplayClient: client,
            betterDisplaySleep: { _ in }
        )
        monitor.setExternalVolumeConfigurations([
            "audio-benq": ExternalVolumeConfiguration(
                backend: .betterDisplay,
                betterDisplayUUID: "display-a"
            )
        ])
        monitor.setDetailsVisible(true)
        monitor.start()
        let readable = await nextVolumeStatus(from: monitor.updates) { $0.scalar == 0.5 }
        XCTAssertEqual(readable?.canSetVolume, true)

        monitor.setVolume(0.8)
        monitor.flushPendingVolume()

        await assertIntegrationCondition {
            client.requests.contains { $0.commands == ["set"] }
        }
        XCTAssertEqual(client.requests.filter { $0.commands == ["set"] }.count, 1)
        XCTAssertTrue(output.volumeValues.isEmpty)
        XCTAssertEqual(ddc.resolveCount, 0)
        XCTAssertEqual(ddc.readCount, 0)
        XCTAssertEqual(ddc.writeValues, [])
        monitor.stop()
    }

    func testBackendChangeImmediatelyStopsBetterDisplayRoutingAndObserver() async {
        let device = AudioOutputDevice(
            id: 93,
            name: "BenQ",
            uid: "audio-benq",
            isCurrent: true
        )
        let reader = CoreAudioStatusReader { _ in
            AudioStatusReading(
                volume: VolumeReading(
                    scalar: nil,
                    isMuted: false,
                    deviceName: device.name,
                    currentDevice: device,
                    canSetVolume: false,
                    canMute: false
                ),
                outputDevices: [device]
            )
        }
        let output = RecordingExternalAudioOutputController()
        let client = IntegrationBetterDisplayClient()
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"BenQ"}]"#
            }
            if request.has("mute") { return "off" }
            if request.commands == ["set"] { return nil }
            return "5,0,10"
        }
        let ddc = RecordingIntegrationDDCTransport()
        let monitor = VolumeMonitor(
            statusReader: reader,
            eventMonitor: IntegrationVolumeEventMonitor(),
            outputController: output,
            ddcTransport: ddc,
            betterDisplayClient: client,
            betterDisplaySleep: { _ in }
        )
        monitor.setExternalVolumeConfigurations([
            "audio-benq": ExternalVolumeConfiguration(
                backend: .betterDisplay,
                betterDisplayUUID: "display-a"
            )
        ])
        monitor.setDetailsVisible(true)
        monitor.start()
        let readable = await nextVolumeStatus(from: monitor.updates) { $0.scalar == 0.5 }
        XCTAssertEqual(readable?.canSetVolume, true)

        monitor.setExternalVolumeConfigurations([:])
        monitor.setVolume(0.8)
        monitor.flushPendingVolume()

        XCTAssertEqual(client.stopCount, 1)
        XCTAssertFalse(client.requests.contains { $0.commands == ["set"] })
        XCTAssertTrue(output.volumeValues.isEmpty)
        XCTAssertEqual(ddc.writeValues, [])
        monitor.stop()
    }

    func testUnknownMutePublishesExplicitUnknownAndBlocksMuteWrites() async {
        let device = AudioOutputDevice(
            id: 93,
            name: "BenQ",
            uid: "audio-benq",
            isCurrent: true
        )
        let reader = CoreAudioStatusReader { _ in
            AudioStatusReading(
                volume: VolumeReading(
                    scalar: nil,
                    isMuted: false,
                    deviceName: device.name,
                    currentDevice: device,
                    canSetVolume: false,
                    canMute: false
                ),
                outputDevices: [device]
            )
        }
        let output = RecordingExternalAudioOutputController()
        let client = IntegrationBetterDisplayClient()
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"BenQ"}]"#
            }
            if request.has("mute") { return nil }
            return "5,0,10"
        }
        let monitor = VolumeMonitor(
            statusReader: reader,
            eventMonitor: IntegrationVolumeEventMonitor(),
            outputController: output,
            ddcTransport: RecordingIntegrationDDCTransport(),
            betterDisplayClient: client,
            betterDisplaySleep: { _ in }
        )
        monitor.setExternalVolumeConfigurations([
            "audio-benq": ExternalVolumeConfiguration(
                backend: .betterDisplay,
                betterDisplayUUID: "display-a"
            )
        ])
        monitor.setDetailsVisible(true)
        monitor.start()
        let status = await nextVolumeStatus(from: monitor.updates) {
            $0.scalar == 0.5 && $0.muteState == .unknown
        }
        XCTAssertEqual(status?.muteState, .unknown)
        XCTAssertFalse(status?.canMute == true)

        monitor.toggleMute()

        XCTAssertFalse(client.requests.contains {
            $0.commands == ["set"] && ($0.string("mute") == "on" || $0.string("mute") == "off")
        })
        XCTAssertTrue(output.muteValues.isEmpty)
        monitor.stop()
    }

    func testUnboundBetterDisplayStaysBetterDisplayAndReportsUnassociatedWithoutDDC() async {
        let device = AudioOutputDevice(
            id: 93,
            name: "BenQ",
            uid: "audio-benq",
            isCurrent: true
        )
        let reader = CoreAudioStatusReader { _ in
            AudioStatusReading(
                volume: VolumeReading(
                    scalar: nil,
                    isMuted: false,
                    deviceName: device.name,
                    currentDevice: device,
                    canSetVolume: false,
                    canMute: false
                ),
                outputDevices: [device]
            )
        }
        let client = IntegrationBetterDisplayClient()
        client.responder = { request in
            XCTAssertEqual(request.commands, ["get"])
            XCTAssertTrue(request.has("identifiers"))
            return "[]"
        }
        let ddc = RecordingIntegrationDDCTransport()
        let clock = BetterDisplayTestClock()
        let monitor = VolumeMonitor(
            statusReader: reader,
            eventMonitor: IntegrationVolumeEventMonitor(),
            outputController: RecordingExternalAudioOutputController(),
            ddcTransport: ddc,
            betterDisplayClient: client,
            betterDisplaySleep: { try await clock.sleep($0) }
        )
        monitor.setExternalVolumeConfigurations([
            "audio-benq": ExternalVolumeConfiguration(
                backend: .betterDisplay,
                betterDisplayUUID: nil
            )
        ])
        var catalogUpdates: [BetterDisplayCatalogUpdate] = []
        let catalogTask = Task { @MainActor in
            for await update in monitor.betterDisplayCatalogUpdates {
                catalogUpdates.append(update)
            }
        }
        monitor.setDetailsVisible(true)
        monitor.start()

        await assertIntegrationCondition {
            catalogUpdates.last?.availability == .deviceUnassociated
        }
        XCTAssertEqual(catalogUpdates.last?.devices, [])
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertTrue(client.requests.allSatisfy { $0.has("identifiers") })
        XCTAssertEqual(ddc.resolveCount, 0)
        XCTAssertEqual(ddc.readCount, 0)
        XCTAssertEqual(ddc.writeValues, [])
        monitor.stop()
        catalogTask.cancel()
        clock.cancelAll()
    }

    func testMuteDuringPendingVolumeDoesNotPublishConfirmedScalarRollback() async {
        let device = AudioOutputDevice(
            id: 93,
            name: "BenQ",
            uid: "audio-benq",
            isCurrent: true
        )
        let reader = CoreAudioStatusReader { _ in
            AudioStatusReading(
                volume: VolumeReading(
                    scalar: nil,
                    isMuted: false,
                    deviceName: device.name,
                    currentDevice: device,
                    canSetVolume: false,
                    canMute: false
                ),
                outputDevices: [device]
            )
        }
        let client = IntegrationBetterDisplayClient()
        var current = 5.0
        var muted = false
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"BenQ"}]"#
            }
            if request.commands == ["set"] {
                if request.has("volume") {
                    current = Double(request.string("volume") ?? "") ?? current
                }
                if request.has("mute") {
                    muted = request.string("mute") == "on"
                }
                return nil
            }
            if request.has("mute") {
                return muted ? "on" : "off"
            }
            return "\(current),0,10"
        }
        client.shouldWait = { request in
            guard request.commands == ["set"] else { return false }
            if request.has("volume") {
                current = Double(request.string("volume") ?? "") ?? current
            }
            if request.has("mute") {
                muted = request.string("mute") == "on"
            }
            return true
        }
        let clock = BetterDisplayTestClock()
        let monitor = VolumeMonitor(
            statusReader: reader,
            eventMonitor: IntegrationVolumeEventMonitor(),
            outputController: RecordingExternalAudioOutputController(),
            ddcTransport: RecordingIntegrationDDCTransport(),
            betterDisplayClient: client,
            betterDisplaySleep: { try await clock.sleep($0) }
        )
        monitor.setExternalVolumeConfigurations([
            "audio-benq": ExternalVolumeConfiguration(
                backend: .betterDisplay,
                betterDisplayUUID: "display-a"
            )
        ])
        var statuses: [VolumeStatus] = []
        let statusTask = Task { @MainActor in
            for await status in monitor.updates {
                statuses.append(status)
            }
        }
        monitor.setDetailsVisible(true)
        monitor.start()
        await assertIntegrationCondition {
            statuses.last?.scalar == 0.5 && statuses.last?.canMute == true
        }

        monitor.setVolume(0.8)
        monitor.flushPendingVolume()
        await assertIntegrationCondition { client.pendingContinuationCount == 1 }
        monitor.toggleMute()
        XCTAssertEqual(client.requests.filter { $0.commands == ["set"] }.count, 1)

        client.completeNext(.success(nil))
        await assertIntegrationCondition {
            client.requests.filter { $0.commands == ["set"] }.count == 2
                && client.pendingContinuationCount == 1
        }
        client.completeNext(.success(nil))
        await assertIntegrationCondition {
            statuses.last?.scalar == 0.8
                && statuses.last?.muteState == .muted
        }

        let firstDraft = try? XCTUnwrap(statuses.firstIndex { $0.scalar == 0.8 })
        if let firstDraft {
            XCTAssertFalse(
                statuses[firstDraft...].contains { $0.scalar == 0.5 },
                "A mute update must not republish the older confirmed scalar."
            )
        }
        monitor.stop()
        statusTask.cancel()
        clock.cancelAll()
    }

    func testVolumeDuringPendingMuteDoesNotPublishConfirmedUnmutedRollback() async {
        let device = AudioOutputDevice(
            id: 93,
            name: "BenQ",
            uid: "audio-benq",
            isCurrent: true
        )
        let reader = CoreAudioStatusReader { _ in
            AudioStatusReading(
                volume: VolumeReading(
                    scalar: nil,
                    isMuted: false,
                    deviceName: device.name,
                    currentDevice: device,
                    canSetVolume: false,
                    canMute: false
                ),
                outputDevices: [device]
            )
        }
        let client = IntegrationBetterDisplayClient()
        var current = 5.0
        var muted = false
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"BenQ"}]"#
            }
            if request.commands == ["set"] {
                if request.has("volume") {
                    current = Double(request.string("volume") ?? "") ?? current
                }
                if request.has("mute") {
                    muted = request.string("mute") == "on"
                }
                return nil
            }
            if request.has("mute") {
                return muted ? "on" : "off"
            }
            return "\(current),0,10"
        }
        client.shouldWait = { request in
            guard request.commands == ["set"] else { return false }
            if request.has("volume") {
                current = Double(request.string("volume") ?? "") ?? current
            }
            if request.has("mute") {
                muted = request.string("mute") == "on"
            }
            return true
        }
        let clock = BetterDisplayTestClock()
        let monitor = VolumeMonitor(
            statusReader: reader,
            eventMonitor: IntegrationVolumeEventMonitor(),
            outputController: RecordingExternalAudioOutputController(),
            ddcTransport: RecordingIntegrationDDCTransport(),
            betterDisplayClient: client,
            betterDisplaySleep: { try await clock.sleep($0) }
        )
        monitor.setExternalVolumeConfigurations([
            "audio-benq": ExternalVolumeConfiguration(
                backend: .betterDisplay,
                betterDisplayUUID: "display-a"
            )
        ])
        var statuses: [VolumeStatus] = []
        let statusTask = Task { @MainActor in
            for await status in monitor.updates {
                statuses.append(status)
            }
        }
        monitor.setDetailsVisible(true)
        monitor.start()
        await assertIntegrationCondition {
            statuses.last?.scalar == 0.5
                && statuses.last?.muteState == .unmuted
                && statuses.last?.canMute == true
        }

        monitor.toggleMute()
        await assertIntegrationCondition {
            statuses.contains { $0.muteState == .muted }
                && client.pendingContinuationCount == 1
        }
        let firstMuteDraft = try? XCTUnwrap(
            statuses.firstIndex { $0.muteState == .muted }
        )

        monitor.setVolume(0.8)
        monitor.flushPendingVolume()
        await assertIntegrationCondition {
            statuses.contains { $0.scalar == 0.8 }
        }
        if let firstMuteDraft {
            XCTAssertFalse(
                statuses[firstMuteDraft...].contains { $0.muteState == .unmuted },
                "A volume update must not republish the older confirmed mute state."
            )
        }

        client.completeNext(.success(nil))
        await assertIntegrationCondition {
            client.requests.filter { $0.commands == ["set"] }.count == 2
                && client.pendingContinuationCount == 1
        }
        let setRequests = client.requests.filter { $0.commands == ["set"] }
        XCTAssertTrue(setRequests[0].has("mute"))
        XCTAssertTrue(setRequests[1].has("volume"))

        client.completeNext(.success(nil))
        await assertIntegrationCondition {
            statuses.last?.scalar == 0.8
                && statuses.last?.muteState == .muted
        }
        monitor.stop()
        statusTask.cancel()
        clock.cancelAll()
    }

    func testStoreBindsPerOutputConfigurationAndPublishesCatalogAPI() async {
        let suiteName = "BetterDisplayVolumeIntegrationTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        settings.setExternalVolumeConfiguration(
            ExternalVolumeConfiguration(
                backend: .betterDisplay,
                betterDisplayUUID: "display-a"
            ),
            for: "audio-benq"
        )
        let volume = ExternalVolumeStoreMonitor()
        let store = SystemStatusStore(
            batteryMonitor: ExternalVolumeBatteryMonitor(),
            wifiMonitor: ExternalVolumeWiFiMonitor(),
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            wakeNotificationCenter: NotificationCenter()
        )
        defer { store.stop() }

        store.bindExternalVolumeSettings(settings)
        XCTAssertEqual(
            volume.configurations["audio-benq"],
            ExternalVolumeConfiguration(backend: .betterDisplay, betterDisplayUUID: "display-a")
        )
        store.start()
        store.refreshBetterDisplayDevices()

        XCTAssertEqual(volume.refreshDevicesCount, 1)
        XCTAssertEqual(store.betterDisplayAvailability, .discovering)
        volume.sendCatalog(
            BetterDisplayCatalogUpdate(
                devices: [BetterDisplayDevice(uuid: "display-a", name: "BenQ")],
                availability: .available
            )
        )
        await assertIntegrationCondition {
            store.betterDisplayDevices == [
                BetterDisplayDevice(uuid: "display-a", name: "BenQ")
            ] && store.betterDisplayAvailability == .available
        }
    }

    func testDirectDDCOptimisticVolumePublishesUnknownMute() async {
        let device = AudioOutputDevice(
            id: 93,
            name: "BenQ",
            uid: "audio-benq",
            isCurrent: true
        )
        let reader = CoreAudioStatusReader { _ in
            AudioStatusReading(
                volume: VolumeReading(
                    scalar: nil,
                    isMuted: false,
                    deviceName: device.name,
                    currentDevice: device,
                    canSetVolume: false,
                    canMute: false
                ),
                outputDevices: [device]
            )
        }
        let ddc = RecordingIntegrationDDCTransport()
        let monitor = VolumeMonitor(
            statusReader: reader,
            eventMonitor: IntegrationVolumeEventMonitor(),
            ddcTransport: ddc,
            betterDisplayClient: IntegrationBetterDisplayClient()
        )
        monitor.setExternalVolumeConfigurations([
            "audio-benq": ExternalVolumeConfiguration(
                backend: .directDDC,
                betterDisplayUUID: nil
            )
        ])
        var statuses: [VolumeStatus] = []
        let statusTask = Task { @MainActor in
            for await status in monitor.updates {
                statuses.append(status)
            }
        }
        monitor.setDetailsVisible(true)
        monitor.start()
        await assertIntegrationCondition {
            statuses.contains { $0.scalar == 0.5 }
        }

        monitor.setVolume(0.8)
        await assertIntegrationCondition {
            statuses.contains { $0.scalar == 0.8 && $0.canSetVolume }
        }

        let optimistic = statuses.first { $0.scalar == 0.8 && $0.canSetVolume }
        XCTAssertEqual(optimistic?.muteState, .unknown)
        monitor.stop()
        statusTask.cancel()
    }

    func testDirectDDCClearPublishesUnknownMute() async {
        let device = AudioOutputDevice(
            id: 93,
            name: "BenQ",
            uid: "audio-benq",
            isCurrent: true
        )
        let reader = CoreAudioStatusReader { _ in
            AudioStatusReading(
                volume: VolumeReading(
                    scalar: nil,
                    isMuted: false,
                    deviceName: device.name,
                    currentDevice: device,
                    canSetVolume: false,
                    canMute: false
                ),
                outputDevices: [device]
            )
        }
        let ddc = RecordingIntegrationDDCTransport()
        let monitor = VolumeMonitor(
            statusReader: reader,
            eventMonitor: IntegrationVolumeEventMonitor(),
            ddcTransport: ddc,
            betterDisplayClient: IntegrationBetterDisplayClient()
        )
        monitor.setExternalVolumeConfigurations([
            "audio-benq": ExternalVolumeConfiguration(
                backend: .directDDC,
                betterDisplayUUID: nil
            )
        ])
        var statuses: [VolumeStatus] = []
        let statusTask = Task { @MainActor in
            for await status in monitor.updates {
                statuses.append(status)
            }
        }
        monitor.setDetailsVisible(true)
        monitor.start()
        await assertIntegrationCondition {
            statuses.contains { $0.scalar == 0.5 }
        }

        monitor.setDisplayAsleep(true)
        await assertIntegrationCondition {
            statuses.last?.scalar == nil && statuses.last?.canSetVolume == false
        }

        XCTAssertEqual(statuses.last?.muteState, .unknown)
        monitor.stop()
        statusTask.cancel()
    }
}

@MainActor
private final class IntegrationBetterDisplayClient: BetterDisplayRequesting {
    struct Request {
        let commands: [String]
        let parameters: [String: String?]

        func has(_ key: String) -> Bool { parameters.keys.contains(key) }
        func string(_ key: String) -> String? { parameters[key] ?? nil }
    }

    var responder: (@MainActor (Request) async throws -> String?)?
    var shouldWait: (@MainActor (Request) -> Bool)?
    private(set) var requests: [Request] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var eventHandler: (@MainActor (BetterDisplayEvent) -> Void)?
    private var continuations: [CheckedContinuation<String?, any Error>] = []

    var pendingContinuationCount: Int { continuations.count }

    func start(onEvent: @escaping @MainActor (BetterDisplayEvent) -> Void) {
        startCount += 1
        eventHandler = onEvent
    }

    func request(commands: [String], parameters: [String: String?]) async throws -> String? {
        let request = Request(commands: commands, parameters: parameters)
        requests.append(request)
        if shouldWait?(request) == true {
            return try await withCheckedThrowingContinuation { continuation in
                continuations.append(continuation)
            }
        }
        return try await responder?(request)
    }

    func stop() {
        stopCount += 1
        eventHandler = nil
    }

    func completeNext(_ result: Result<String?, any Error>) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(with: result)
    }
}

@MainActor
private final class RecordingExternalAudioOutputController: AudioOutputControlling {
    private(set) var volumeValues: [Double] = []
    private(set) var muteValues: [Void] = []

    func outputDevices() -> [AudioOutputDevice] { [] }
    func setVolume(_ scalar: Double) -> Bool {
        volumeValues.append(scalar)
        return true
    }
    func toggleMute() -> Bool {
        muteValues.append(())
        return true
    }
    func selectOutputDevice(_ deviceID: AudioDeviceID) -> Bool { true }
}

@MainActor
private final class IntegrationVolumeEventMonitor: VolumeEventMonitoring {
    func start(
        onDefaultDeviceChange: @escaping @MainActor () -> Void,
        onVolumeChange: @escaping @MainActor () -> Void
    ) {}
    func reconcile() {}
    func recover() {}
    func stop() {}
}

private final class RecordingIntegrationDDCTransport: DDCVolumeTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var storedResolveCount = 0
    private var storedReadCount = 0
    private var storedWriteValues: [UInt16] = []

    var resolveCount: Int { lock.withLock { storedResolveCount } }
    var readCount: Int { lock.withLock { storedReadCount } }
    var writeValues: [UInt16] { lock.withLock { storedWriteValues } }

    func resolve(uid: String) -> DDCDisplayTarget? {
        lock.withLock {
            storedResolveCount += 1
            return DDCDisplayTarget(uid: uid, service: nil)
        }
    }

    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult {
        lock.withLock {
            storedReadCount += 1
            return .reply(DDCVolumeReply(current: 50, maximum: 100))
        }
    }

    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool {
        lock.withLock {
            storedWriteValues.append(value)
            return true
        }
    }
}

@MainActor
private final class ExternalVolumeStoreMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { $0.finish() }
    let betterDisplayCatalogUpdates: AsyncStream<BetterDisplayCatalogUpdate>
    private let catalogContinuation: AsyncStream<BetterDisplayCatalogUpdate>.Continuation
    private(set) var configurations: [String: ExternalVolumeConfiguration] = [:]
    private(set) var refreshDevicesCount = 0

    init() {
        (betterDisplayCatalogUpdates, catalogContinuation) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() { catalogContinuation.finish() }
    func refresh() {}
    func recover() {}
    func setExternalVolumeConfigurations(_ configurations: [String: ExternalVolumeConfiguration]) {
        self.configurations = configurations
    }
    func refreshBetterDisplayDevices() {
        refreshDevicesCount += 1
    }
    func sendCatalog(_ update: BetterDisplayCatalogUpdate) {
        catalogContinuation.yield(update)
    }
}

@MainActor
private final class ExternalVolumeBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class ExternalVolumeWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

private func nextVolumeStatus(
    from stream: AsyncStream<VolumeStatus>,
    matching predicate: @escaping @Sendable (VolumeStatus) -> Bool
) async -> VolumeStatus? {
    var iterator = stream.makeAsyncIterator()
    for _ in 0..<12 {
        guard let status = await iterator.next() else { return nil }
        if predicate(status) { return status }
    }
    return nil
}

@MainActor
private func assertIntegrationCondition(
    timeout: Duration = .seconds(2),
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @escaping @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() {
            XCTAssertTrue(true)
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(condition(), file: file, line: line)
}
