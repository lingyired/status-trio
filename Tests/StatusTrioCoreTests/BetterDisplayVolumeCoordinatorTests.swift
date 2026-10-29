import CoreAudio
import XCTest
@testable import StatusTrioCore

@MainActor
final class BetterDisplayVolumeCoordinatorTests: XCTestCase {
    func testOutputChangeDuringFramebufferReadDiscardsTheOldAssociation() async {
        let client = RecordingBetterDisplayClient()
        client.responder = { _ in
            #"[{"UUID":"display-a","deviceType":"Display","registryLocation":"IOService:/a"},{"UUID":"display-b","deviceType":"Display","registryLocation":"IOService:/b"}]"#
        }
        let gate = AssociationFramebufferGate()
        let started = expectation(description: "framebuffer read starts")
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            readFramebuffers: {
                await gate.read(onFirstRead: { started.fulfill() })
            }
        ) { _ in }
        var updates: [BetterDisplayCatalogUpdate] = []
        let task = Task { @MainActor in
            for await update in coordinator.catalogUpdates { updates.append(update) }
        }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-a", displayUUID: nil)
        await fulfillment(of: [started], timeout: 1)
        coordinator.select(outputID: 94, uid: "audio-b", displayUUID: nil)
        await gate.release()
        await assertBetterDisplayCondition {
            updates.last?.automaticDisplayUUID == "display-b"
        }
        XCTAssertEqual(updates.last?.outputUID, "audio-b")
        XCTAssertFalse(updates.contains { $0.automaticDisplayUUID == "display-a" })
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertTrue(client.requests.allSatisfy { $0.has("identifiers") })
        coordinator.stop()
        task.cancel()
    }

    func testSavedAssociationStillDiscoversAllDisplaysForChangingTheBinding() async {
        let client = RecordingBetterDisplayClient()
        client.responder = { request in
            if request.has("identifiers") {
                return request.string("UUID") == nil
                    ? #"[{"UUID":"display-a","deviceType":"Display","name":"First"},{"UUID":"display-b","deviceType":"Display","name":"Second"}]"#
                    : #"[{"UUID":"display-a","deviceType":"Display","name":"First"}]"#
            }
            XCTAssertEqual(request.string("UUID"), "display-a")
            return request.has("mute") ? "off" : "5,0,10"
        }
        let clock = BetterDisplayTestClock()
        var catalog: [BetterDisplayCatalogUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client, sleep: { try await clock.sleep($0) }
        ) { _ in }
        let task = Task { @MainActor in
            for await update in coordinator.catalogUpdates { catalog.append(update) }
        }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-a", displayUUID: "display-a")
        await assertBetterDisplayCondition { catalog.last?.availability == .available }
        XCTAssertEqual(catalog.last?.devices.map(\.uuid), ["display-a", "display-b"])
        XCTAssertTrue(client.requests.allSatisfy { $0.commands == ["get"] })
        coordinator.stop()
        task.cancel()
        clock.cancelAll()
    }

    func testReenablingBackendAfterTimeoutMakesOneFreshAttempt() async {
        let client = RecordingBetterDisplayClient()
        var shouldFail = true
        client.responder = { request in
            if shouldFail { throw BetterDisplayIntegrationError.timedOut }
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk"}]"#
            }
            return request.has("mute") ? "off" : "5,0,10"
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayCatalogUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client, sleep: { try await clock.sleep($0) }
        ) { _ in }
        let task = Task { @MainActor in
            for await update in coordinator.catalogUpdates { updates.append(update) }
        }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-a", displayUUID: nil)
        await assertBetterDisplayCondition { updates.last?.availability == .unresponsive }
        shouldFail = false
        coordinator.clearSelection()
        coordinator.select(outputID: 93, uid: "audio-a", displayUUID: nil)
        await assertBetterDisplayCondition { updates.last?.availability == .deviceUnassociated }
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertTrue(client.requests.allSatisfy { $0.has("identifiers") })
        coordinator.stop()
        task.cancel()
        clock.cancelAll()
    }

    func testFirstUnassociatedSelectionDiscoversDisplaysWithoutManualRefresh() async {
        let client = RecordingBetterDisplayClient()
        client.responder = { request in
            XCTAssertEqual(request.commands, ["get"])
            XCTAssertTrue(request.has("identifiers"))
            XCTAssertNil(request.string("UUID"))
            return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
        }
        let clock = BetterDisplayTestClock()
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client, sleep: { try await clock.sleep($0) }
        ) { _ in }
        var catalog: [BetterDisplayCatalogUpdate] = []
        let task = Task { @MainActor in
            for await update in coordinator.catalogUpdates { catalog.append(update) }
        }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: nil)

        await assertBetterDisplayCondition {
            catalog.last?.devices == [BetterDisplayDevice(uuid: "display-a", name: "Desk Display")]
        }
        XCTAssertEqual(catalog.last?.availability, .deviceUnassociated)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.stopCount, 1)
        XCTAssertFalse(clock.pendingDurations.contains(.seconds(2)))
        XCTAssertFalse(clock.pendingDurations.contains(.seconds(10)))
        coordinator.stop()
        task.cancel()
        clock.cancelAll()
    }

    func testReselectingCachedDisplayPublishesConnectedStateWithoutManualRefresh() async {
        let client = RecordingBetterDisplayClient()
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
            }
            return request.has("mute") ? "off" : "5,0,10"
        }
        let clock = BetterDisplayTestClock()
        var values: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client, sleep: { try await clock.sleep($0) }
        ) { values.append($0) }
        var catalog: [BetterDisplayCatalogUpdate] = []
        let task = Task { @MainActor in
            for await update in coordinator.catalogUpdates { catalog.append(update) }
        }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
        await assertBetterDisplayCondition { values.last?.canSetVolume == true }

        coordinator.clearSelection()
        values.removeAll()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
        await assertBetterDisplayCondition { values.last?.canSetVolume == true }
        await assertBetterDisplayCondition { catalog.last?.availability == .available }
        XCTAssertEqual(catalog.last?.devices, [BetterDisplayDevice(uuid: "display-a", name: "Desk Display")])
        XCTAssertEqual(client.requests.filter { $0.has("identifiers") }.count, 1)
        XCTAssertTrue(client.requests.allSatisfy { $0.commands == ["get"] })
        coordinator.stop()
        task.cancel()
        clock.cancelAll()
    }

    func testDiscoveryDoesNotReportReadyBeforeTheVolumeReadCompletes() async {
        let client = RecordingBetterDisplayClient()
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
            }
            return request.has("mute") ? "off" : "5,0,10"
        }
        client.shouldWait = { $0.has("volume") }
        let clock = BetterDisplayTestClock()
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client, sleep: { try await clock.sleep($0) }
        ) { _ in }
        var catalog: [BetterDisplayCatalogUpdate] = []
        let task = Task { @MainActor in
            for await update in coordinator.catalogUpdates { catalog.append(update) }
        }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
        await assertBetterDisplayCondition { client.pendingContinuationCount == 1 }
        XCTAssertEqual(catalog.last?.availability, .discovering)

        client.completeNext(.success("5,0,10"))
        await assertBetterDisplayCondition { catalog.last?.availability == .available }
        coordinator.stop()
        task.cancel()
        clock.cancelAll()
    }

    func testCatalogParserAcceptsDocumentedArrayAndFiltersNonDisplays() throws {
        let payload = """
        [
          {"UUID":"display-a","deviceType":"Display","name":"Desk Display"},
          {"deviceType":"DisplayGroup","name":"Studio","tagID":"group-a"},
          {"UUID":"","deviceType":"Display","name":"Missing identity"}
        ]
        """

        let devices = try BetterDisplayVolumeParser.parseDevices(payload)

        XCTAssertEqual(
            devices,
            [BetterDisplayDevice(uuid: "display-a", name: "Desk Display")]
        )
    }

    func testCatalogParserAcceptsObservedCommaSeparatedObjectFramingWithoutSplittingNames() throws {
        let payload = """
        {"UUID":"display-a","deviceType":"Display","name":"Desk, Main"},
        {"deviceType":"DisplayGroup","name":"Studio","tagID":"group-a"}
        """

        let devices = try BetterDisplayVolumeParser.parseDevices(payload)

        XCTAssertEqual(
            devices,
            [BetterDisplayDevice(uuid: "display-a", name: "Desk, Main")]
        )
    }

    func testCatalogParserRejectsDuplicateDisplayIdentity() {
        let payload = """
        [
          {"UUID":"display-a","deviceType":"Display","name":"Desk"},
          {"UUID":"display-a","deviceType":"Display","name":"Duplicate"}
        ]
        """

        XCTAssertThrowsError(try BetterDisplayVolumeParser.parseDevices(payload))
    }

    func testRangeParserNormalizesNonHundredRangeAndRejectsInvalidValues() throws {
        let range = try BetterDisplayVolumeParser.parseVolumeRange("5.0,0.0,10.0")

        XCTAssertEqual(range.normalizedScalar, 0.5, accuracy: 0.0001)
        XCTAssertEqual(range.rawValue(for: 0.8), 8.0, accuracy: 0.0001)
        for payload in ["nan,0,1", "inf,0,1", "5,10,0", "11,0,10", "5,0", "5,0,10,11"] {
            XCTAssertThrowsError(
                try BetterDisplayVolumeParser.parseVolumeRange(payload),
                "Malformed range must be rejected: \(payload)"
            )
        }
    }

    func testMuteParserReturnsUnknownForMissingOrUnrecognizedPayload() {
        XCTAssertEqual(BetterDisplayVolumeParser.parseMuteState(nil), .unknown)
        XCTAssertEqual(BetterDisplayVolumeParser.parseMuteState(""), .unknown)
        XCTAssertEqual(BetterDisplayVolumeParser.parseMuteState("unknown"), .unknown)
        XCTAssertEqual(BetterDisplayVolumeParser.parseMuteState(" ON "), .muted)
        XCTAssertEqual(BetterDisplayVolumeParser.parseMuteState("off"), .unmuted)
    }

    func testSelectionDiscoversCatalogAndUsesExplicitTargetForRangeAndMuteReads() async {
        let client = RecordingBetterDisplayClient()
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
            }
            if request.has("mute") {
                XCTAssertEqual(request.commands, ["get"])
                XCTAssertEqual(request.string("UUID"), "display-a")
                return "off"
            }
            if request.has("volume") {
                XCTAssertEqual(request.commands, ["get"])
                XCTAssertEqual(request.string("UUID"), "display-a")
                XCTAssertTrue(request.has("value"))
                XCTAssertTrue(request.has("min"))
                XCTAssertTrue(request.has("max"))
                return "5,0,10"
            }
            return nil
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { update in
            updates.append(update)
        }
        coordinator.start()

        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")

        await assertBetterDisplayCondition {
            updates.last?.availability == .available && updates.last?.scalar != nil
        }
        let update = try? XCTUnwrap(updates.last)
        XCTAssertEqual(update?.scalar, 0.5)
        XCTAssertEqual(update?.muteState, .unmuted)
        XCTAssertEqual(update?.canSetVolume, true)
        XCTAssertEqual(update?.canMute, true)
        XCTAssertEqual(update?.displayUUID, "display-a")
        XCTAssertTrue(client.requests.allSatisfy {
            $0.has("identifiers")
                ? $0.commands == ["get"] && $0.string("UUID") == nil
                : $0.string("UUID") == "display-a"
        })
        coordinator.stop()
        clock.cancelAll()
    }

    func testTopologyChangeBeforeQueuedMutationRunsPreventsStaleWrites() async {
        for mutatesMute in [false, true] {
            let client = RecordingBetterDisplayClient()
            client.responder = { request in
                if request.has("identifiers") {
                    return #"[{"UUID":"display-a","deviceType":"Display"}]"#
                }
                if request.commands == ["set"] { return nil }
                return request.has("mute") ? "off" : "5,0,10"
            }
            let clock = BetterDisplayTestClock()
            var updates: [BetterDisplayVolumeUpdate] = []
            let coordinator = BetterDisplayVolumeCoordinator(
                client: client,
                sleep: { try await clock.sleep($0) }
            ) { updates.append($0) }
            coordinator.start()
            coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
            await assertBetterDisplayCondition {
                updates.last?.availability == .available
            }

            if mutatesMute {
                coordinator.toggleMute()
            } else {
                coordinator.setVolume(0.8)
                coordinator.flushPendingVolume()
            }
            // Invalidate the selection in the same actor turn, before the
            // mutation task gets an opportunity to send its request.
            coordinator.topologyChanged()

            await assertBetterDisplayCondition {
                updates.last?.availability == .available
            }
            XCTAssertFalse(
                client.requests.contains { $0.commands == ["set"] },
                "A queued \(mutatesMute ? "mute" : "volume") write outlived its target generation"
            )
            coordinator.stop()
            clock.cancelAll()
        }
    }

    func testSelectionChangeBeforeQueuedMutationRunsPreventsStaleWrites() async {
        for mutatesMute in [false, true] {
            let client = RecordingBetterDisplayClient()
            client.responder = { request in
                if request.has("identifiers") {
                    return """
                    [
                      {"UUID":"display-a","deviceType":"Display"},
                      {"UUID":"display-b","deviceType":"Display"}
                    ]
                    """
                }
                if request.commands == ["set"] { return nil }
                return request.has("mute") ? "off" : "5,0,10"
            }
            let clock = BetterDisplayTestClock()
            var updates: [BetterDisplayVolumeUpdate] = []
            let coordinator = BetterDisplayVolumeCoordinator(
                client: client,
                sleep: { try await clock.sleep($0) }
            ) { updates.append($0) }
            coordinator.start()
            coordinator.select(outputID: 93, uid: "audio-a", displayUUID: "display-a")
            await assertBetterDisplayCondition {
                updates.last?.availability == .available
            }

            if mutatesMute {
                coordinator.toggleMute()
            } else {
                coordinator.setVolume(0.8)
                coordinator.flushPendingVolume()
            }
            // Keep the client alive by moving directly to another BetterDisplay
            // target in the same actor turn.
            coordinator.select(outputID: 94, uid: "audio-b", displayUUID: "display-b")

            await assertBetterDisplayCondition {
                updates.last?.displayUUID == "display-b"
                    && updates.last?.availability == .available
            }
            XCTAssertFalse(
                client.requests.contains { $0.commands == ["set"] },
                "A queued \(mutatesMute ? "mute" : "volume") write outlived its selected display"
            )
            coordinator.stop()
            clock.cancelAll()
        }
    }

    func testMissingMuteKeepsVolumeAvailableButDisablesMute() async {
        let client = RecordingBetterDisplayClient()
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
            }
            if request.has("mute") { return nil }
            return "4,0,10"
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        coordinator.start()

        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")

        await assertBetterDisplayCondition {
            updates.last?.scalar == 0.4 && updates.last?.availability == .available
        }
        XCTAssertEqual(updates.last?.muteState, .unknown)
        XCTAssertFalse(updates.last?.canMute == true)
        coordinator.toggleMute()
        XCTAssertFalse(client.requests.contains {
            $0.commands == ["set"] && ($0.string("mute") == "on" || $0.string("mute") == "off")
        })
        coordinator.stop()
        clock.cancelAll()
    }

    func testKnownMuteWriteUsesExplicitTargetAndReadsBack() async {
        let client = RecordingBetterDisplayClient()
        var muted = false
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
            }
            if request.has("mute") {
                if request.commands == ["set"] {
                    XCTAssertEqual(request.string("UUID"), "display-a")
                    XCTAssertEqual(request.string("mute"), "on")
                    muted = true
                    return nil
                }
                return muted ? "on" : "off"
            }
            return "5,0,10"
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { update in
            updates.append(update)
        }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")

        await assertBetterDisplayCondition {
            updates.last?.muteState == .unmuted && updates.last?.canMute == true
        }

        coordinator.toggleMute()

        await assertBetterDisplayCondition {
            updates.last?.muteState == .muted && updates.last?.availability == .available
        }
        XCTAssertTrue(client.requests
            .filter { $0.commands == ["set"] }
            .allSatisfy {
                $0.string("UUID") == "display-a" && $0.string("mute") == "on"
            })
        coordinator.stop()
        clock.cancelAll()
    }

    func testDuplicateCatalogIdentityFailsBeforeAnyVolumeCommand() async {
        let client = RecordingBetterDisplayClient()
        client.responder = { request in
            if request.has("identifiers") {
                return """
                [
                  {"UUID":"display-a","deviceType":"Display","name":"Desk"},
                  {"UUID":"display-a","deviceType":"Display","name":"Duplicate"}
                ]
                """
            }
            return "5,0,10"
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        coordinator.start()

        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")

        await assertBetterDisplayCondition {
            updates.last?.availability == .invalidResponse
        }
        XCTAssertFalse(client.requests.contains { $0.has("volume") || $0.has("mute") })
        coordinator.stop()
        clock.cancelAll()
    }

    func testVolumeMutationUsesLatestValueAndReadbackConfirmsNonHundredRange() async {
        let client = RecordingBetterDisplayClient()
        var didWrite = false
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
            }
            if request.has("mute") { return "off" }
            if request.commands == ["set"] {
                didWrite = true
                XCTAssertEqual(request.string("UUID"), "display-a")
                XCTAssertEqual(Double(request.string("volume") ?? "") ?? -1, 8, accuracy: 0.0001)
                XCTAssertEqual(Double(request.string("min") ?? "") ?? -1, 0, accuracy: 0.0001)
                XCTAssertEqual(Double(request.string("max") ?? "") ?? -1, 10, accuracy: 0.0001)
                return nil
            }
            return didWrite ? "8,0,10" : "5,0,10"
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
        await assertBetterDisplayCondition { updates.last?.scalar == 0.5 }

        coordinator.setVolume(0.2)
        coordinator.setVolume(0.4)
        coordinator.setVolume(0.8)
        coordinator.flushPendingVolume()

        await assertBetterDisplayCondition {
            updates.last?.scalar == 0.8 && updates.last?.availability == .available
        }
        XCTAssertEqual(client.requests.filter { $0.commands == ["set"] }.count, 1)
        coordinator.stop()
        clock.cancelAll()
    }

    func testReadbackMismatchPublishesActualValueAndDisablesConfirmation() async {
        let client = RecordingBetterDisplayClient()
        var didWrite = false
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
            }
            if request.has("mute") { return "off" }
            if request.commands == ["set"] {
                didWrite = true
                return nil
            }
            return didWrite ? "5,0,10" : "5,0,10"
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
        await assertBetterDisplayCondition { updates.last?.scalar == 0.5 }

        coordinator.setVolume(0.8)
        coordinator.flushPendingVolume()

        await assertBetterDisplayCondition {
            updates.last?.availability == .writeNotConfirmed
        }
        XCTAssertEqual(updates.last?.scalar, 0.5)
        XCTAssertFalse(updates.last?.canSetVolume == true)
        XCTAssertFalse(updates.contains { $0.scalar == 0.8 && $0.availability == .available })
        coordinator.stop()
        clock.cancelAll()
    }

    func testOverlappingVolumeAndMuteWritesBothRemainConfirmedByTheFinalReadback() async {
        let client = RecordingBetterDisplayClient()
        var muted = false
        client.shouldWait = { request in
            guard request.commands == ["set"] else { return false }
            if request.has("mute") {
                muted = true
            }
            return true
        }
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
            }
            if request.has("mute") {
                return muted ? "on" : "off"
            }
            // The volume mutation was acknowledged but had no effect.
            return "5,0,10"
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
        await assertBetterDisplayCondition {
            updates.last?.scalar == 0.5
                && updates.last?.muteState == .unmuted
        }

        coordinator.setVolume(0.8)
        coordinator.flushPendingVolume()
        await assertBetterDisplayCondition {
            client.requests.filter { $0.commands == ["set"] }.count == 1
        }
        coordinator.toggleMute()

        client.completeNext(.success(nil))
        await assertBetterDisplayCondition {
            client.requests.filter { $0.commands == ["set"] }.count == 2
        }
        client.completeNext(.success(nil))

        await assertBetterDisplayCondition {
            updates.last?.availability == .writeNotConfirmed
        }
        XCTAssertEqual(updates.last?.scalar, 0.5)
        XCTAssertEqual(updates.last?.muteState, .muted)
        XCTAssertFalse(updates.last?.canSetVolume == true)
        XCTAssertTrue(updates.last?.canMute == true)
        coordinator.stop()
        clock.cancelAll()
    }

    func testTimedOutMutationIsNotRetriedAndStopsReconciliationPolling() async {
        let client = RecordingBetterDisplayClient()
        var setCount = 0
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
            }
            if request.has("mute") { return "off" }
            if request.commands == ["set"] {
                setCount += 1
                throw BetterDisplayIntegrationError.timedOut
            }
            return "5,0,10"
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
        await assertBetterDisplayCondition { updates.last?.scalar == 0.5 }

        coordinator.setVolume(0.8)
        coordinator.flushPendingVolume()

        await assertBetterDisplayCondition {
            updates.last?.availability == .unresponsive
        }
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(setCount, 1)
        XCTAssertFalse(clock.pendingDurations.contains { $0 == .seconds(2) || $0 == .seconds(10) })
        coordinator.stop()
        clock.cancelAll()
    }

    func testLaunchRecoversAfterTimeoutWithoutPollingWhileUnavailable() async {
        let client = RecordingBetterDisplayClient()
        var appReady = false
        client.responder = { request in
            if request.has("identifiers") {
                guard appReady else { throw BetterDisplayIntegrationError.timedOut }
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
            }
            if request.has("mute") { return "off" }
            return "5,0,10"
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")

        await assertBetterDisplayCondition {
            updates.last?.availability == .unresponsive
        }
        XCTAssertEqual(client.startCount, 1)
        XCTAssertEqual(client.stopCount, 0, "Selected unavailability must keep lifecycle observers")
        XCTAssertFalse(clock.pendingDurations.contains { $0 == .seconds(2) || $0 == .seconds(10) })

        appReady = true
        client.send(.launched)

        await assertBetterDisplayCondition {
            updates.last?.availability == .available && updates.last?.scalar == 0.5
        }
        coordinator.stop()
        XCTAssertEqual(client.stopCount, 1)
        clock.cancelAll()
    }

    func testManualRefreshRecoversAfterTimeoutWithoutLaunchEvent() async {
        let client = RecordingBetterDisplayClient()
        var appReady = false
        client.responder = { request in
            if request.has("identifiers") {
                guard appReady else { throw BetterDisplayIntegrationError.timedOut }
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
            }
            if request.has("mute") { return "off" }
            return "5,0,10"
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
        await assertBetterDisplayCondition {
            updates.last?.availability == .unresponsive
        }
        let discoveryCount = client.requests.filter { $0.has("identifiers") }.count

        appReady = true
        coordinator.refreshDevices()

        await assertBetterDisplayCondition {
            updates.last?.availability == .available && updates.last?.scalar == 0.5
        }
        XCTAssertEqual(
            client.requests.filter { $0.has("identifiers") }.count,
            discoveryCount + 1
        )
        XCTAssertEqual(client.startCount, 1)
        XCTAssertEqual(client.stopCount, 0)
        coordinator.stop()
        clock.cancelAll()
    }

    func testTerminationClearsStateAndBlocksWorkUntilLaunchRecovery() async {
        let client = RecordingBetterDisplayClient()
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
            }
            if request.has("mute") { return "off" }
            return "5,0,10"
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
        await assertBetterDisplayCondition {
            updates.last?.scalar == 0.5 && updates.last?.canSetVolume == true
        }

        client.send(.terminated)
        await assertBetterDisplayCondition {
            updates.last?.availability == .appAbsent
        }
        XCTAssertNil(updates.last?.scalar)
        XCTAssertEqual(updates.last?.muteState, .unknown)
        XCTAssertFalse(updates.last?.canSetVolume == true)
        XCTAssertFalse(updates.last?.canMute == true)
        let requestCountAtTermination = client.requests.count

        coordinator.setDetailsVisible(false)
        coordinator.setDetailsVisible(true)
        coordinator.setVolume(0.8)
        coordinator.flushPendingVolume()
        coordinator.toggleMute()
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(client.requests.count, requestCountAtTermination)
        XCTAssertFalse(clock.pendingDurations.contains(.milliseconds(150)))
        XCTAssertFalse(clock.pendingDurations.contains(.seconds(2)))
        XCTAssertFalse(clock.pendingDurations.contains(.seconds(10)))

        client.send(.launched)
        await assertBetterDisplayCondition {
            updates.last?.availability == .available && updates.last?.scalar == 0.5
        }
        coordinator.stop()
        clock.cancelAll()
    }

    func testHiddenDetailsKeepTenSecondPollingCadence() async {
        let client = RecordingBetterDisplayClient()
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
            }
            if request.has("mute") { return "off" }
            return "5,0,10"
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        coordinator.start()
        coordinator.setDetailsVisible(true)
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
        await assertBetterDisplayCondition {
            updates.last?.availability == .available
                && clock.pendingDurations.contains(.seconds(2))
        }

        coordinator.setDetailsVisible(false)
        await assertBetterDisplayCondition {
            clock.pendingDurations.contains(.seconds(10))
        }
        XCTAssertFalse(clock.pendingDurations.contains(.seconds(2)))
        let readsBeforeHiddenPoll = client.requests.filter { $0.has("volume") }.count
        clock.release(.seconds(10))
        await assertBetterDisplayCondition {
            client.requests.filter { $0.has("volume") }.count > readsBeforeHiddenPoll
                && clock.pendingDurations.contains(.seconds(10))
        }

        coordinator.setDisplayAsleep(true)
        XCTAssertFalse(clock.pendingDurations.contains(.seconds(2)))
        XCTAssertFalse(clock.pendingDurations.contains(.seconds(10)))
        coordinator.stop()
        clock.cancelAll()
    }

    func testSleepInvalidatesCatalogBeforeWakeRestoresSelectedDisplay() async {
        let client = RecordingBetterDisplayClient()
        var devices = #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
        client.responder = { request in
            if request.has("identifiers") {
                return devices
            }
            if request.has("mute") { return "off" }
            return "5,0,10"
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
        await assertBetterDisplayCondition {
            updates.last?.availability == .available && updates.last?.scalar == 0.5
        }

        coordinator.clearSelection()
        coordinator.setDisplayAsleep(true)
        devices = #"[{"UUID":"display-b","deviceType":"Display","name":"Other Display"}]"#
        coordinator.setDisplayAsleep(false)
        let volumeReadsBeforeReselect = client.requests.filter { $0.has("volume") }.count
        let discoveryCountBeforeReselect = client.requests.filter { $0.has("identifiers") }.count
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")

        await assertBetterDisplayCondition {
            updates.last?.availability == .deviceUnassociated
        }
        XCTAssertEqual(
            client.requests.filter { $0.has("identifiers") }.count,
            discoveryCountBeforeReselect + 1
        )
        XCTAssertEqual(
            client.requests.filter { $0.has("volume") }.count,
            volumeReadsBeforeReselect
        )
        XCTAssertFalse(client.requests.contains {
            $0.commands == ["set"] && $0.string("UUID") == "display-a"
        })
        coordinator.stop()
        clock.cancelAll()
    }

    func testTopologyInvalidatesCatalogBeforeNextSelection() async {
        let client = RecordingBetterDisplayClient()
        var devices = #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
        client.responder = { request in
            if request.has("identifiers") {
                return devices
            }
            if request.has("mute") { return "off" }
            return "5,0,10"
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
        await assertBetterDisplayCondition {
            updates.last?.availability == .available && updates.last?.scalar == 0.5
        }

        coordinator.clearSelection()
        coordinator.topologyChanged()
        devices = #"[{"UUID":"display-b","deviceType":"Display","name":"Other Display"}]"#
        let volumeReadsBeforeReselect = client.requests.filter { $0.has("volume") }.count
        let discoveryCountBeforeReselect = client.requests.filter { $0.has("identifiers") }.count
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")

        await assertBetterDisplayCondition {
            updates.last?.availability == .deviceUnassociated
        }
        XCTAssertEqual(
            client.requests.filter { $0.has("identifiers") }.count,
            discoveryCountBeforeReselect + 1
        )
        XCTAssertEqual(
            client.requests.filter { $0.has("volume") }.count,
            volumeReadsBeforeReselect
        )
        coordinator.stop()
        clock.cancelAll()
    }

    func testABARejectsResponseFromEarlierGeneration() async {
        let client = RecordingBetterDisplayClient()
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
            }
            return "5,0,10"
        }
        client.shouldWait = { request in
            request.has("volume") && request.commands == ["get"]
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        coordinator.start()
        coordinator.refreshDevices()
        await assertBetterDisplayCondition { client.requests.contains { $0.has("identifiers") } }

        coordinator.select(outputID: 93, uid: "audio-a", displayUUID: "display-a")
        await assertBetterDisplayCondition { client.pendingContinuationCount == 1 }
        coordinator.select(outputID: 94, uid: "audio-b", displayUUID: "display-a")
        coordinator.select(outputID: 93, uid: "audio-a", displayUUID: "display-a")

        client.completeNext(.success("1,0,10"))
        await assertBetterDisplayCondition { client.pendingContinuationCount == 1 }
        XCTAssertFalse(updates.contains { $0.scalar == 0.1 })
        client.completeNext(.success("9,0,10"))

        await assertBetterDisplayCondition {
            updates.last?.scalar == 0.9 && updates.last?.uid == "audio-a"
        }
        coordinator.stop()
        clock.cancelAll()
    }

    func testContinuousInputUsesInjectedMaximumSendRate() async {
        let client = RecordingBetterDisplayClient()
        var current = 2.0
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
            }
            if request.has("mute") {
                return "off"
            }
            if request.commands == ["set"] {
                current = Double(request.string("volume") ?? "") ?? current
                return nil
            }
            return "\(current),0,10"
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
        await assertBetterDisplayCondition {
            updates.last?.scalar == 0.2 && updates.last?.availability == .available
        }

        coordinator.setVolume(0.4)
        coordinator.setVolume(0.6)
        coordinator.setVolume(0.8)
        XCTAssertEqual(client.requests.filter { $0.commands == ["set"] }.count, 0)
        await assertBetterDisplayCondition {
            clock.pendingDurations.contains(.milliseconds(150))
        }
        XCTAssertEqual(
            clock.recordedDurations.filter { $0 == .milliseconds(150) }.count,
            1,
            "Continuous input must retain the open rate window instead of restarting it"
        )
        clock.release(.milliseconds(150))
        await assertBetterDisplayCondition {
            client.requests.filter { $0.commands == ["set"] }.count == 1
                && updates.last?.scalar == 0.8
        }

        coordinator.setVolume(0.7)
        coordinator.setVolume(0.9)
        await assertBetterDisplayCondition {
            clock.pendingDurations.contains(.milliseconds(150))
        }
        clock.release(.milliseconds(150))
        await assertBetterDisplayCondition {
            client.requests.filter { $0.commands == ["set"] }.count == 2
                && updates.last?.scalar == 0.9
                && updates.last?.availability == .available
        }
        let setValues = client.requests
            .filter { $0.commands == ["set"] }
            .compactMap { Double($0.string("volume") ?? "") }
        XCTAssertEqual(setValues, [8, 9])
        coordinator.stop()
        clock.cancelAll()
    }

    func testClearSelectionStopsLifecycleObserverAndScheduledWork() async {
        let client = RecordingBetterDisplayClient()
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
            }
            if request.has("mute") { return "off" }
            return "5,0,10"
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        var catalogUpdates: [BetterDisplayCatalogUpdate] = []
        let catalogTask = Task { @MainActor in
            for await update in coordinator.catalogUpdates {
                catalogUpdates.append(update)
            }
        }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
        await assertBetterDisplayCondition {
            updates.last?.availability == .available
        }
        XCTAssertEqual(client.startCount, 1)

        coordinator.clearSelection()

        await assertBetterDisplayCondition {
            catalogUpdates.last?.availability == .idle
        }
        XCTAssertEqual(catalogUpdates.last?.devices, [])
        XCTAssertEqual(client.stopCount, 1)
        XCTAssertFalse(clock.pendingDurations.contains(.milliseconds(150)))
        XCTAssertFalse(clock.pendingDurations.contains(.seconds(2)))
        XCTAssertFalse(clock.pendingDurations.contains(.seconds(10)))
        catalogTask.cancel()
        clock.cancelAll()
    }

    func testMuteWaitsForInFlightVolumeMutation() async {
        let client = RecordingBetterDisplayClient()
        var current = 5.0
        var muted = false
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
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
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
        await assertBetterDisplayCondition {
            updates.last?.scalar == 0.5 && updates.last?.canMute == true
        }

        coordinator.setVolume(0.8)
        coordinator.flushPendingVolume()
        await assertBetterDisplayCondition {
            client.pendingContinuationCount == 1
        }

        coordinator.toggleMute()

        XCTAssertEqual(client.requests.filter { $0.commands == ["set"] }.count, 1)
        XCTAssertEqual(client.pendingContinuationCount, 1)
        client.completeNext(.success(nil))

        await assertBetterDisplayCondition {
            client.requests.filter { $0.commands == ["set"] }.count == 2
                && client.pendingContinuationCount == 1
        }
        let setRequests = client.requests.filter { $0.commands == ["set"] }
        XCTAssertTrue(setRequests[0].has("volume"))
        XCTAssertTrue(setRequests[1].has("mute"))
        XCTAssertEqual(setRequests[1].string("mute"), "on")

        client.completeNext(.success(nil))
        await assertBetterDisplayCondition {
            updates.last?.scalar == 0.8
                && updates.last?.muteState == .muted
                && updates.last?.availability == .available
        } message: {
            "last=\(String(describing: updates.last)); requests=\(client.requests.map(\.parameters))"
        }
        coordinator.stop()
        clock.cancelAll()
    }

    func testRapidMuteTogglesUseLatestDesiredTarget() async {
        let client = RecordingBetterDisplayClient()
        var muted = false
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
            }
            if request.has("mute") {
                return muted ? "on" : "off"
            }
            return "5,0,10"
        }
        client.shouldWait = { request in
            guard request.commands == ["set"] else { return false }
            if request.has("mute") {
                muted = request.string("mute") == "on"
            }
            return true
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
        await assertBetterDisplayCondition {
            updates.last?.muteState == .unmuted && updates.last?.canMute == true
        }

        coordinator.toggleMute()
        await assertBetterDisplayCondition {
            client.pendingContinuationCount == 1
        }
        coordinator.toggleMute()
        XCTAssertEqual(client.requests.filter { $0.commands == ["set"] }.count, 1)
        client.completeNext(.success(nil))

        await assertBetterDisplayCondition {
            client.requests.filter { $0.commands == ["set"] }.count == 2
                && client.pendingContinuationCount == 1
        }
        let muteTargets = client.requests
            .filter { $0.commands == ["set"] && $0.has("mute") }
            .compactMap { $0.string("mute") }
        XCTAssertEqual(muteTargets, ["on", "off"])
        client.completeNext(.success(nil))

        await assertBetterDisplayCondition {
            updates.last?.muteState == .unmuted
                && updates.last?.availability == .available
        }
        coordinator.stop()
        clock.cancelAll()
    }

    func testReadStartedBeforeNewerInputCannotPublish() async {
        let client = RecordingBetterDisplayClient()
        var current = 5.0
        var volumeReadCount = 0
        client.responder = { request in
            if request.has("identifiers") {
                return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
            }
            if request.has("mute") {
                return "off"
            }
            if request.commands == ["set"] {
                current = Double(request.string("volume") ?? "") ?? current
                return nil
            }
            return "\(current),0,10"
        }
        client.shouldWait = { request in
            guard request.commands == ["get"], request.has("volume") else {
                return false
            }
            volumeReadCount += 1
            return volumeReadCount == 2
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
        await assertBetterDisplayCondition {
            updates.last?.scalar == 0.5
        }

        coordinator.refresh()
        await assertBetterDisplayCondition {
            client.pendingContinuationCount == 1
        }
        coordinator.setVolume(0.8)
        coordinator.flushPendingVolume()
        client.completeNext(.success("1,0,10"))
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertFalse(updates.contains {
            $0.scalar == 0.1 && $0.availability == .available
        })
        await assertBetterDisplayCondition {
            updates.last?.scalar == 0.8 && updates.last?.availability == .available
        }
        coordinator.stop()
        clock.cancelAll()
    }

    func testWakeCatalogRemovalRejectsQueuedReadAndDisablesWrites() async {
        let client = RecordingBetterDisplayClient()
        var devices = #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
        client.responder = { request in
            if request.has("identifiers") {
                return devices
            }
            if request.has("mute") { return "off" }
            if request.commands == ["set"] { return nil }
            return "5,0,10"
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        var catalogUpdates: [BetterDisplayCatalogUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        let catalogTask = Task { @MainActor in
            for await update in coordinator.catalogUpdates {
                catalogUpdates.append(update)
            }
        }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: "display-a")
        await assertBetterDisplayCondition {
            updates.last?.availability == .available && updates.last?.canSetVolume == true
        }

        client.shouldWait = { $0.has("identifiers") }
        coordinator.setDisplayAsleep(true)
        coordinator.setDisplayAsleep(false)
        await assertBetterDisplayCondition {
            client.pendingContinuationCount == 1
        }
        coordinator.refresh()

        let volumeReadsBeforeDiscovery = client.requests.filter { $0.has("volume") }.count
        devices = #"[{"UUID":"display-b","deviceType":"Display","name":"Other Display"}]"#
        client.completeNext(.success(devices))

        await assertBetterDisplayCondition {
            updates.last?.availability == .deviceUnassociated
                && catalogUpdates.last?.availability == .deviceUnassociated
        }
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(
            client.requests.filter { $0.has("volume") }.count,
            volumeReadsBeforeDiscovery,
            "A catalog-invalid target must not receive a queued volume read"
        )
        XCTAssertFalse(
            client.requests.contains {
                $0.string("UUID") == "display-a" && $0.commands == ["set"]
            }
        )
        XCTAssertEqual(updates.last?.canSetVolume, false)
        XCTAssertEqual(updates.last?.canMute, false)
        coordinator.setVolume(0.8)
        coordinator.flushPendingVolume()
        XCTAssertFalse(
            client.requests.contains {
                $0.string("UUID") == "display-a" && $0.commands == ["set"]
            }
        )
        coordinator.stop()
        catalogTask.cancel()
        clock.cancelAll()
    }

    func testUnboundBetterDisplayWakeCatalogDiscoverySettlesUnassociated() async {
        let client = RecordingBetterDisplayClient()
        client.responder = { request in
            XCTAssertTrue(request.has("identifiers"))
            XCTAssertNil(request.string("UUID"))
            return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        var catalogUpdates: [BetterDisplayCatalogUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        let catalogTask = Task { @MainActor in
            for await update in coordinator.catalogUpdates {
                catalogUpdates.append(update)
            }
        }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: nil)
        await assertBetterDisplayCondition {
            catalogUpdates.last?.availability == .deviceUnassociated
        }

        coordinator.setDisplayAsleep(true)
        coordinator.setDisplayAsleep(false)

        await assertBetterDisplayCondition {
            client.requests.filter { $0.has("identifiers") }.count == 2
                && catalogUpdates.last?.availability == .deviceUnassociated
                && updates.last?.availability == .deviceUnassociated
        }
        XCTAssertEqual(
            catalogUpdates.last?.devices,
            [BetterDisplayDevice(uuid: "display-a", name: "Desk Display")]
        )
        XCTAssertFalse(catalogUpdates.contains { $0.availability == .available })
        XCTAssertEqual(updates.last?.availability, .deviceUnassociated)
        XCTAssertEqual(updates.last?.canSetVolume, false)
        XCTAssertEqual(client.stopCount, 2)
        coordinator.stop()
        catalogTask.cancel()
        clock.cancelAll()
    }

    func testUnboundBetterDisplayTopologyCatalogDiscoverySettlesUnassociated() async {
        let client = RecordingBetterDisplayClient()
        client.responder = { request in
            XCTAssertTrue(request.has("identifiers"))
            XCTAssertNil(request.string("UUID"))
            return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        var catalogUpdates: [BetterDisplayCatalogUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        let catalogTask = Task { @MainActor in
            for await update in coordinator.catalogUpdates {
                catalogUpdates.append(update)
            }
        }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: nil)
        await assertBetterDisplayCondition {
            catalogUpdates.last?.availability == .deviceUnassociated
        }

        coordinator.topologyChanged()

        await assertBetterDisplayCondition {
            client.requests.filter { $0.has("identifiers") }.count == 2
                && catalogUpdates.last?.availability == .deviceUnassociated
                && updates.last?.availability == .deviceUnassociated
        }
        XCTAssertEqual(
            catalogUpdates.last?.devices,
            [BetterDisplayDevice(uuid: "display-a", name: "Desk Display")]
        )
        XCTAssertFalse(catalogUpdates.contains { $0.availability == .available })
        XCTAssertEqual(updates.last?.availability, .deviceUnassociated)
        XCTAssertEqual(client.stopCount, 2)
        coordinator.stop()
        catalogTask.cancel()
        clock.cancelAll()
    }

    func testUnboundBetterDisplayManualRefreshCatalogDiscoverySettlesUnassociated() async {
        let client = RecordingBetterDisplayClient()
        client.responder = { request in
            XCTAssertTrue(request.has("identifiers"))
            XCTAssertNil(request.string("UUID"))
            return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
        }
        let clock = BetterDisplayTestClock()
        var updates: [BetterDisplayVolumeUpdate] = []
        var catalogUpdates: [BetterDisplayCatalogUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { updates.append($0) }
        let catalogTask = Task { @MainActor in
            for await update in coordinator.catalogUpdates {
                catalogUpdates.append(update)
            }
        }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: nil)
        await assertBetterDisplayCondition {
            catalogUpdates.last?.availability == .deviceUnassociated
        }

        coordinator.refresh()

        await assertBetterDisplayCondition {
            client.requests.filter { $0.has("identifiers") }.count == 2
                && catalogUpdates.last?.availability == .deviceUnassociated
                && updates.last?.availability == .deviceUnassociated
        }
        XCTAssertEqual(
            catalogUpdates.last?.devices,
            [BetterDisplayDevice(uuid: "display-a", name: "Desk Display")]
        )
        XCTAssertFalse(catalogUpdates.contains { $0.availability == .available })
        XCTAssertEqual(updates.last?.availability, .deviceUnassociated)
        XCTAssertEqual(client.stopCount, 2)
        coordinator.stop()
        catalogTask.cancel()
        clock.cancelAll()
    }

    func testUnboundCatalogFailureStopsClientAndExplicitRefreshRestarts() async {
        let client = RecordingBetterDisplayClient()
        var failDiscovery = true
        client.responder = { request in
            XCTAssertTrue(request.has("identifiers"))
            XCTAssertNil(request.string("UUID"))
            if failDiscovery {
                throw BetterDisplayIntegrationError.requestFailed
            }
            return #"[{"UUID":"display-a","deviceType":"Display","name":"Desk Display"}]"#
        }
        let clock = BetterDisplayTestClock()
        var catalogUpdates: [BetterDisplayCatalogUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { _ in }
        let catalogTask = Task { @MainActor in
            for await update in coordinator.catalogUpdates {
                catalogUpdates.append(update)
            }
        }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: nil)

        coordinator.refresh()

        await assertBetterDisplayCondition {
            catalogUpdates.last?.availability == .requestFailed
        }
        XCTAssertEqual(
            client.requests.filter { $0.has("identifiers") }.count,
            1
        )
        XCTAssertEqual(client.stopCount, 1)

        failDiscovery = false
        coordinator.refresh()

        await assertBetterDisplayCondition {
            catalogUpdates.last?.devices == [
                BetterDisplayDevice(uuid: "display-a", name: "Desk Display")
            ] && catalogUpdates.last?.availability == .deviceUnassociated
        }
        XCTAssertEqual(
            client.requests.filter { $0.has("identifiers") }.count,
            2
        )
        XCTAssertEqual(client.startCount, 2)
        XCTAssertEqual(client.stopCount, 2)
        coordinator.stop()
        catalogTask.cancel()
        clock.cancelAll()
    }

    func testQueuedCatalogRequestSurvivesStopBoundaryUntilQueueDrains() async {
        let client = RecordingBetterDisplayClient()
        var catalogPayloads = [
            #"[{"UUID":"display-a","deviceType":"Display","name":"First"}]"#,
            #"[{"UUID":"display-b","deviceType":"Display","name":"Second"}]"#
        ]
        client.responder = { request in
            XCTAssertTrue(request.has("identifiers"))
            XCTAssertNil(request.string("UUID"))
            return catalogPayloads.removeFirst()
        }
        client.shouldWait = { request in
            request.has("identifiers") && request.commands == ["get"]
        }
        let clock = BetterDisplayTestClock()
        var catalogUpdates: [BetterDisplayCatalogUpdate] = []
        let coordinator = BetterDisplayVolumeCoordinator(
            client: client,
            sleep: { try await clock.sleep($0) }
        ) { _ in }
        let catalogTask = Task { @MainActor in
            for await update in coordinator.catalogUpdates {
                catalogUpdates.append(update)
            }
        }
        coordinator.start()
        coordinator.select(outputID: 93, uid: "audio-benq", displayUUID: nil)

        coordinator.refresh()
        await assertBetterDisplayCondition {
            client.pendingContinuationCount == 1
        }
        coordinator.topologyChanged()
        client.completeNext(.success(catalogPayloads[0]))

        await assertBetterDisplayCondition {
            client.requests.filter { $0.has("identifiers") }.count == 2
                && client.pendingContinuationCount == 1
        }
        XCTAssertEqual(client.stopCount, 0)
        XCTAssertFalse(catalogUpdates.contains { $0.availability == .unresponsive })

        client.completeNext(.success(catalogPayloads[1]))

        await assertBetterDisplayCondition {
            catalogUpdates.last?.devices == [
                BetterDisplayDevice(uuid: "display-b", name: "Second")
            ] && client.stopCount == 1
        }
        XCTAssertFalse(catalogUpdates.contains { $0.availability == .unresponsive })
        coordinator.stop()
        catalogTask.cancel()
        clock.cancelAll()
    }
}

private actor AssociationFramebufferGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var firstRead = true

    func read(onFirstRead: @Sendable () -> Void) async -> [BetterDisplayFramebufferIdentity] {
        if firstRead {
            firstRead = false
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                onFirstRead()
            }
        }
        return [
            .init(registryLocation: "IOService:/a", edidUUID: "audio-a"),
            .init(registryLocation: "IOService:/b", edidUUID: "audio-b")
        ]
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class BetterDisplayTestClock {
    private struct Entry {
        let id: UUID
        let duration: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var entries: [Entry] = []
    private var recorded: [Duration] = []
    private let cancellation = BetterDisplayCancellationBox()

    var pendingDurations: [Duration] {
        entries
            .filter { !cancellation.contains($0.id) }
            .map(\.duration)
    }
    var recordedDurations: [Duration] { recorded }

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                recorded.append(duration)
                entries.append(Entry(id: id, duration: duration, continuation: continuation))
            }
        } onCancel: {
            cancellation.mark(id)
        }
    }

    func release(_ duration: Duration) {
        guard let index = entries.firstIndex(where: {
            $0.duration == duration && !cancellation.consume($0.id)
        }) else {
            return
        }
        entries.remove(at: index).continuation.resume()
    }

    func cancelAll() {
        let pending = entries
        entries.removeAll()
        pending.forEach { $0.continuation.resume(throwing: CancellationError()) }
    }
}

private final class BetterDisplayCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = Set<UUID>()

    func mark(_ id: UUID) {
        lock.withLock { _ = cancelled.insert(id) }
    }

    func contains(_ id: UUID) -> Bool {
        lock.withLock { cancelled.contains(id) }
    }

    func consume(_ id: UUID) -> Bool {
        lock.withLock { cancelled.remove(id) != nil }
    }
}

@MainActor
final class RecordingBetterDisplayClient: BetterDisplayRequesting {
    struct Request {
        let commands: [String]
        let parameters: [String: String?]

        func has(_ key: String) -> Bool {
            parameters.keys.contains(key)
        }

        func string(_ key: String) -> String? {
            parameters[key] ?? nil
        }
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

    func request(
        commands: [String],
        parameters: [String: String?]
    ) async throws -> String? {
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

    func send(_ event: BetterDisplayEvent) {
        eventHandler?(event)
    }

    func completeNext(_ result: Result<String?, any Error>) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(with: result)
    }
}

@MainActor
private func assertBetterDisplayCondition(
    timeout: Duration = .seconds(2),
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @escaping @MainActor () -> Bool,
    message: @escaping @MainActor () -> String = { "" }
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
    XCTAssertTrue(condition(), message(), file: file, line: line)
}
