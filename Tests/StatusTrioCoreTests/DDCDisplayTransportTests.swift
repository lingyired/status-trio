import XCTest
@testable import StatusTrioCore

final class DDCDisplayTransportTests: XCTestCase {
    func testBranchTokenComesFromTheNumberedDispextPrefix() {
        XCTAssertEqual(DDCDisplayTransport.branchToken(fromIONameMatched: "dispext0,t603x"), "dispext0")
        XCTAssertEqual(DDCDisplayTransport.branchToken(fromIONameMatched: "dispext12,t603x"), "dispext12")
        XCTAssertEqual(DDCDisplayTransport.branchToken(fromIONameMatched: "dispext3"), "dispext3")
        XCTAssertNil(DDCDisplayTransport.branchToken(fromIONameMatched: "disp0,t603x"))
        XCTAssertNil(DDCDisplayTransport.branchToken(fromIONameMatched: "dispext,t603x"))
        XCTAssertNil(DDCDisplayTransport.branchToken(fromIONameMatched: "dispextX,t603x"))
        XCTAssertNil(DDCDisplayTransport.branchToken(fromIONameMatched: nil))
    }

    func testServiceBranchTokenComesFromTheDcpavServiceEpicAncestor() {
        // Real macOS 27 sample: the external proxy sits under
        // `dispext0:dcpav-service-epic:0` inside the `dcpext0` branch.
        let realSample = [
            "dispext0:dcpav-service-epic:0",
            "AFKEPInterfaceServiceKextV2",
            "AFKDCPEXT0Endpoint9",
            "DCPEXT0Endpoint9",
            "RTBuddy(DCPEXT0)",
            "AppleH15IO"
        ]
        XCTAssertEqual(DDCDisplayTransport.branchToken(fromServiceAncestorNames: realSample), "dispext0")

        let secondBranch = ["dispext2:dcpav-service-epic:0", "RTBuddy(DCPEXT2)", "AppleH15IO"]
        XCTAssertEqual(DDCDisplayTransport.branchToken(fromServiceAncestorNames: secondBranch), "dispext2")

        // A controller endpoint is not the DDC service endpoint.
        XCTAssertNil(DDCDisplayTransport.branchToken(fromServiceAncestorNames: ["dispext0:dcpav-controller-epic:0"]))
        // The internal display's audio service must never yield an external token.
        XCTAssertNil(DDCDisplayTransport.branchToken(fromServiceAncestorNames: ["disp0:dcpav-service-epic:0"]))
        XCTAssertNil(DDCDisplayTransport.branchToken(fromServiceAncestorNames: ["AFKDCPEXT0Endpoint9", "AppleH15IO"]))
        XCTAssertNil(DDCDisplayTransport.branchToken(fromServiceAncestorNames: []))
    }

    func testResolvedTargetOpensOnlyTheMatchedService() {
        var opened: [Int] = []
        let resolution = DDCTargetResolver.resolve(
            outputUID: "XV272U-UUID",
            framebuffers: [DDCFramebufferSnapshot(entryID: 1, branchName: "dispext0", edidUUID: "XV272U-UUID")],
            services: [DDCServiceSnapshot(entryID: 20, branchName: "dispext0", location: "External")]
        )
        let result = DDCTargetResolver.openResolvedTarget(
            resolution,
            services: [(entryID: 20, handle: "service-20")]
        ) { handle in
            opened.append(20)
            return handle
        }

        XCTAssertEqual(result?.serviceEntryID, 20)
        XCTAssertEqual(result?.opened, "service-20")
        XCTAssertEqual(opened, [20])
    }

    func testNoServiceIsOpenedWhenTheTopologyIsAmbiguous() {
        var openAttempts = 0
        let open: (Int) -> Int? = { _ in openAttempts += 1; return 0 }
        let ambiguous = DDCTargetResolver.resolve(
            outputUID: "XV272U-UUID",
            framebuffers: [
                DDCFramebufferSnapshot(entryID: 1, branchName: "dispext0", edidUUID: "XV272U-UUID"),
                DDCFramebufferSnapshot(entryID: 2, branchName: "dispext1", edidUUID: "XV272U-UUID")
            ],
            services: [
                DDCServiceSnapshot(entryID: 20, branchName: "dispext0", location: "External"),
                DDCServiceSnapshot(entryID: 21, branchName: "dispext1", location: "External")
            ]
        )
        XCTAssertNil(DDCTargetResolver.openResolvedTarget(
            ambiguous,
            services: [(entryID: 20, handle: 20), (entryID: 21, handle: 21)],
            open: open
        ))

        let unavailable = DDCTargetResolver.resolve(
            outputUID: "OTHER",
            framebuffers: [DDCFramebufferSnapshot(entryID: 1, branchName: "dispext0", edidUUID: "XV272U-UUID")],
            services: [DDCServiceSnapshot(entryID: 20, branchName: "dispext0", location: "External")]
        )
        XCTAssertNil(DDCTargetResolver.openResolvedTarget(
            unavailable,
            services: [(entryID: 20, handle: 20)],
            open: open
        ))

        let failedOpen = DDCTargetResolver.resolve(
            outputUID: "XV272U-UUID",
            framebuffers: [DDCFramebufferSnapshot(entryID: 1, branchName: "dispext0", edidUUID: "XV272U-UUID")],
            services: [DDCServiceSnapshot(entryID: 20, branchName: "dispext0", location: "External")]
        )
        XCTAssertNil(DDCTargetResolver.openResolvedTarget(
            failedOpen,
            services: [(entryID: 20, handle: 20)],
            open: { (_: Int) -> Int? in nil }
        ))

        XCTAssertEqual(openAttempts, 0)
    }

    func testOnlyConnectedExternalFramebufferEntriesAreRelevant() {
        XCTAssertTrue(DDCDisplayTransport.isConnectedExternalFramebuffer(
            ioNameMatched: "dispext0,t603x",
            displayWidth: 2560,
            displayHeight: 1440
        ))
        XCTAssertFalse(DDCDisplayTransport.isConnectedExternalFramebuffer(
            ioNameMatched: "dispext1,t603x",
            displayWidth: nil,
            displayHeight: nil
        ))
        XCTAssertFalse(DDCDisplayTransport.isConnectedExternalFramebuffer(
            ioNameMatched: "disp0,t603x",
            displayWidth: 3456,
            displayHeight: 2234
        ))
        XCTAssertFalse(DDCDisplayTransport.isConnectedExternalFramebuffer(
            ioNameMatched: "dispext2,t603x",
            displayWidth: 0,
            displayHeight: 1440
        ))
    }

    func testInvalidReplyIsRejectedByDecoder() {
        let transport = InvalidReplyTransport()
        XCTAssertEqual(
            transport.read(DDCDisplayTarget(uid: "display", service: nil)),
            .failure(.replyReadFailed)
        )
    }

    func testReadOutcomeSeparatesFailureStagesFromAValidatedReply() {
        let reply = DDCVolumeReply(current: 40, maximum: 100)
        XCTAssertEqual(DDCVolumeReadResult.reply(reply).replyValue, reply)
        XCTAssertNil(DDCVolumeReadResult.reply(reply).failureReason)

        for failure in [
            DDCReadFailure.serviceUnavailable,
            .requestWriteFailed,
            .replyReadFailed,
            .replyRejected(.badChecksum),
            .vcpRejected,
            .timeout
        ] {
            let result = DDCVolumeReadResult.failure(failure)
            XCTAssertEqual(result.failureReason, failure)
            XCTAssertNil(result.replyValue, "\(failure.diagnosticName) must not publish a value")
        }
    }

    func testFailureDiagnosticsNameTheStageAndStayIdentifierFree() {
        let names = [
            DDCReadFailure.serviceUnavailable,
            .requestWriteFailed,
            .replyReadFailed,
            .replyRejected(.badChecksum),
            .vcpRejected,
            .timeout
        ].map(\.diagnosticName)

        XCTAssertEqual(Set(names).count, names.count, "Every failure stage needs its own label")
        XCTAssertEqual(DDCReadFailure.serviceUnavailable.diagnosticName, "serviceUnavailable")
        XCTAssertEqual(DDCReadFailure.replyRejected(.badChecksum).diagnosticName, "replyRejected(badChecksum)")
        XCTAssertEqual(DDCReadFailure.vcpRejected.diagnosticName, "vcpRejected")
        XCTAssertEqual(DDCReadFailure.serviceUnavailable.diagnosticStage, "resolve")
        XCTAssertEqual(DDCReadFailure.requestWriteFailed.diagnosticStage, "requestWrite")
        XCTAssertEqual(DDCReadFailure.replyReadFailed.diagnosticStage, "replyRead")
        XCTAssertEqual(DDCReadFailure.replyRejected(.zeros).diagnosticStage, "validate")
        XCTAssertEqual(DDCReadFailure.vcpRejected.diagnosticStage, "validate")
    }

    // MARK: - Get VCP request bytes (issue #115 Task A)

    func testStandardGetVCPRequestFoldsInTheDataAddress() {
        XCTAssertEqual(
            DDCPacket.getVCPRequest(checksumMode: .standard),
            [0x82, 0x01, 0x62, 0xDE]
        )
    }

    func testLegacyGetVCPRequestMatchesThePreviouslyShippedBytes() {
        XCTAssertEqual(
            DDCPacket.getVCPRequest(checksumMode: .legacy),
            [0x82, 0x01, 0x62, 0x8F]
        )
    }

    func testGetVCPRequestChecksumTracksTheVCPCode() {
        XCTAssertEqual(
            DDCPacket.getVCPRequest(vcp: 0x10, checksumMode: .standard),
            [0x82, 0x01, 0x10, 0xAC]
        )
        XCTAssertEqual(
            DDCPacket.getVCPRequest(vcp: 0x10, checksumMode: .legacy),
            [0x82, 0x01, 0x10, 0xFD]
        )
    }

    func testSetVCPRequestBytesForZeroFiftyAndFullVolume() {
        XCTAssertEqual(DDCPacket.setVCPRequest(value: 0), [0x84, 0x03, 0x62, 0x00, 0x00, 0xDA])
        XCTAssertEqual(DDCPacket.setVCPRequest(value: 50), [0x84, 0x03, 0x62, 0x00, 0x32, 0xE8])
        XCTAssertEqual(DDCPacket.setVCPRequest(value: 100), [0x84, 0x03, 0x62, 0x00, 0x64, 0xBE])
    }

    func testEveryGeneratedPacketCarriesAVerifiableXorChecksum() {
        let requests = [
            (DDCPacket.getVCPRequest(checksumMode: .standard), true),
            (DDCPacket.getVCPRequest(checksumMode: .legacy), false),
            (DDCPacket.setVCPRequest(value: 0), true),
            (DDCPacket.setVCPRequest(value: 100), true)
        ]
        for (packet, includesDataAddress) in requests {
            XCTAssertEqual(packet.count >= 4, true, "Packet must carry a header, opcode and checksum")
            XCTAssertEqual(
                packet.last,
                DDCPacket.checksum(Array(packet.dropLast()), includeDataAddress: includesDataAddress),
                "Checksum must be the XOR of the seed and every preceding byte"
            )
        }
    }

    func testWritePacketIsUnchangedByTheReadProfileWork() {
        // The Set VCP format was verified on hardware; only Get VCP gained a
        // second checksum candidate.
        XCTAssertEqual(DDCPacket.setVCPRequest(value: 95), [0x84, 0x03, 0x62, 0x00, 0x5F, 0x85])
    }

    func testFreshServiceStartsWithNoProvenProfileAndProbesImmediately() {
        // The profile cache lives on the target, so a re-resolved service
        // (output switch, topology change, wake) always starts unproven.
        let target = DDCDisplayTarget(uid: "display", service: nil)

        XCTAssertNil(target.readProfile)
        XCTAssertTrue(DDCReadProfilePolicy.shouldRunProbe(
            cachedProfile: target.readProfile,
            readsSinceLastProbe: target.readsSinceLastProbe
        ))
    }
}

private final class InvalidReplyTransport: DDCVolumeTransport {
    func resolve(uid: String) -> DDCDisplayTarget? { DDCDisplayTarget(uid: uid, service: nil) }
    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult {
        guard let reply = DDCVolumeReply.decode([0x62]) else { return .failure(.replyReadFailed) }
        return .reply(reply)
    }
    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool { false }
}
