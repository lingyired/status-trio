import XCTest
@testable import StatusTrioCore

/// Pure matching rules for Issue #115. These tests never touch IOKit or I2C:
/// they pin the identity chain `Core Audio UID -> framebuffer -> DCP branch ->
/// service` so multi-display setups can be supported without guessing.
final class DDCTargetResolverTests: XCTestCase {
    private let displayA = "XV272U-UUID-A"
    private let displayB = "XV272U-UUID-B"

    private func framebuffer(_ entryID: UInt64, branch: String, edid: String?) -> DDCFramebufferSnapshot {
        DDCFramebufferSnapshot(entryID: entryID, branchName: branch, edidUUID: edid)
    }

    private func service(_ entryID: UInt64, branch: String?, location: String? = "External") -> DDCServiceSnapshot {
        DDCServiceSnapshot(entryID: entryID, branchName: branch, location: location)
    }

    // MARK: - The original single-display behavior must not regress

    func testSingleDisplayWithUniqueServiceAndMatchingUIDResolves() {
        let resolution = DDCTargetResolver.resolve(
            outputUID: displayA,
            framebuffers: [framebuffer(1, branch: "dispext0", edid: displayA)],
            services: [service(20, branch: "dispext0")]
        )

        XCTAssertEqual(resolution, .matched(framebufferEntryID: 1, serviceEntryID: 20))
    }

    // MARK: - Two displays, resolved by identity rather than enumeration order

    func testDisplayAIsSelectedWhenAIsTheCurrentOutput() {
        let resolution = DDCTargetResolver.resolve(
            outputUID: displayA,
            framebuffers: [
                framebuffer(1, branch: "dispext0", edid: displayA),
                framebuffer(2, branch: "dispext1", edid: displayB)
            ],
            services: [
                service(20, branch: "dispext0"),
                service(21, branch: "dispext1")
            ]
        )

        XCTAssertEqual(resolution, .matched(framebufferEntryID: 1, serviceEntryID: 20))
    }

    func testDisplayBIsSelectedWhenBIsTheCurrentOutput() {
        let resolution = DDCTargetResolver.resolve(
            outputUID: displayB,
            framebuffers: [
                framebuffer(1, branch: "dispext0", edid: displayA),
                framebuffer(2, branch: "dispext1", edid: displayB)
            ],
            services: [
                service(20, branch: "dispext0"),
                service(21, branch: "dispext1")
            ]
        )

        XCTAssertEqual(resolution, .matched(framebufferEntryID: 2, serviceEntryID: 21))
    }

    func testEnumerationOrderDoesNotChangeTheResult() {
        let forward = DDCTargetResolver.resolve(
            outputUID: displayB,
            framebuffers: [
                framebuffer(1, branch: "dispext0", edid: displayA),
                framebuffer(2, branch: "dispext1", edid: displayB)
            ],
            services: [
                service(20, branch: "dispext0"),
                service(21, branch: "dispext1")
            ]
        )
        let reversed = DDCTargetResolver.resolve(
            outputUID: displayB,
            framebuffers: [
                framebuffer(2, branch: "dispext1", edid: displayB),
                framebuffer(1, branch: "dispext0", edid: displayA)
            ],
            services: [
                service(21, branch: "dispext1"),
                service(20, branch: "dispext0")
            ]
        )

        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(reversed, .matched(framebufferEntryID: 2, serviceEntryID: 21))
    }

    // MARK: - Fail closed when identity cannot be proven

    func testMultipleDisplaysWithoutBranchEvidenceAreUnavailable() {
        // Both services exist but neither branch token matches, so there is no
        // provable framebuffer -> service link. This is the exact case where
        // picking the first entry would risk writing to the wrong monitor.
        let resolution = DDCTargetResolver.resolve(
            outputUID: displayA,
            framebuffers: [framebuffer(1, branch: "dispext0", edid: displayA)],
            services: [
                service(20, branch: "dcpext0"),
                service(21, branch: "dcpext1")
            ]
        )

        XCTAssertEqual(resolution, .unavailable(.noAssociatedService))
    }

    func testTwoFramebuffersWithTheSameEDIDAreAmbiguous() {
        let resolution = DDCTargetResolver.resolve(
            outputUID: displayA,
            framebuffers: [
                framebuffer(1, branch: "dispext0", edid: displayA),
                framebuffer(2, branch: "dispext1", edid: displayA)
            ],
            services: [
                service(20, branch: "dispext0"),
                service(21, branch: "dispext1")
            ]
        )

        XCTAssertEqual(resolution, .unavailable(.ambiguousFramebuffer))
    }

    func testTwoServicesOnTheSameBranchAreAmbiguous() {
        let resolution = DDCTargetResolver.resolve(
            outputUID: displayA,
            framebuffers: [framebuffer(1, branch: "dispext0", edid: displayA)],
            services: [
                service(20, branch: "dispext0"),
                service(21, branch: "dispext0")
            ]
        )

        XCTAssertEqual(resolution, .unavailable(.ambiguousService))
    }

    func testSameModelSameEDIDWithoutIndependentPortEvidenceIsUnavailable() {
        // Two identical panels report the same EDID UUID. The EDID bytes alone
        // cannot select one, and each branch only carries its own service, so
        // the framebuffer step is already ambiguous.
        let resolution = DDCTargetResolver.resolve(
            outputUID: displayA,
            framebuffers: [
                framebuffer(1, branch: "dispext0", edid: displayA),
                framebuffer(2, branch: "dispext2", edid: displayA)
            ],
            services: [
                service(20, branch: "dispext0"),
                service(22, branch: "dispext2")
            ]
        )

        XCTAssertEqual(resolution, .unavailable(.ambiguousFramebuffer))
    }

    func testDisconnectedSiblingDisplayIsIgnored() {
        // dispext1 is powered but nothing is plugged in: no EDID UUID.
        let resolution = DDCTargetResolver.resolve(
            outputUID: displayA,
            framebuffers: [
                framebuffer(1, branch: "dispext0", edid: displayA),
                framebuffer(2, branch: "dispext1", edid: nil)
            ],
            services: [
                service(20, branch: "dispext0"),
                service(21, branch: "dispext1")
            ]
        )

        XCTAssertEqual(resolution, .matched(framebufferEntryID: 1, serviceEntryID: 20))
    }

    func testDisconnectedTargetFramebufferHasNoMatch() {
        // The display carrying the current output UID is unplugged, so its
        // framebuffer no longer reports an EDID UUID.
        let resolution = DDCTargetResolver.resolve(
            outputUID: displayA,
            framebuffers: [framebuffer(1, branch: "dispext0", edid: nil)],
            services: [service(20, branch: "dispext0")]
        )

        XCTAssertEqual(resolution, .unavailable(.noMatchingFramebuffer))
    }

    func testOfflineServiceProducesNoAssociatedService() {
        let resolution = DDCTargetResolver.resolve(
            outputUID: displayA,
            framebuffers: [framebuffer(1, branch: "dispext0", edid: displayA)],
            services: []
        )

        XCTAssertEqual(resolution, .unavailable(.noAssociatedService))
    }

    func testEmptyUIDIsRejectedBeforeMatching() {
        let resolution = DDCTargetResolver.resolve(
            outputUID: "",
            framebuffers: [framebuffer(1, branch: "dispext0", edid: displayA)],
            services: [service(20, branch: "dispext0")]
        )

        XCTAssertEqual(resolution, .unavailable(.missingAudioUID))
    }

    func testNilUIDIsRejectedBeforeMatching() {
        let resolution = DDCTargetResolver.resolve(
            outputUID: nil,
            framebuffers: [framebuffer(1, branch: "dispext0", edid: displayA)],
            services: [service(20, branch: "dispext0")]
        )

        XCTAssertEqual(resolution, .unavailable(.missingAudioUID))
    }

    func testUnknownUIDFindsNoMatchingFramebuffer() {
        let resolution = DDCTargetResolver.resolve(
            outputUID: "Bluetooth-Headphones",
            framebuffers: [framebuffer(1, branch: "dispext0", edid: displayA)],
            services: [service(20, branch: "dispext0")]
        )

        XCTAssertEqual(resolution, .unavailable(.noMatchingFramebuffer))
    }

    func testInternalFramebufferEDIDNeverMatches() {
        // The built-in panel is not an admissible DDC target even when the
        // current output UID happens to equal its framebuffer EDID.
        let resolution = DDCTargetResolver.resolve(
            outputUID: "BuiltInSpeakerDevice",
            framebuffers: [framebuffer(1, branch: "disp0", edid: "BuiltInSpeakerDevice")],
            services: [service(20, branch: "dispext0")]
        )

        XCTAssertEqual(resolution, .unavailable(.noMatchingFramebuffer),
                       "The internal disp0 branch must never become a DDC target")
    }

    func testNonExternalServicesAreExcludedFromMatching() {
        let resolution = DDCTargetResolver.resolve(
            outputUID: displayA,
            framebuffers: [framebuffer(1, branch: "dispext0", edid: displayA)],
            services: [
                service(20, branch: "dispext0", location: "Internal"),
                service(21, branch: "dispext0")
            ]
        )

        XCTAssertEqual(resolution, .matched(framebufferEntryID: 1, serviceEntryID: 21))
    }

    // MARK: - Legacy fallback for firmware without branch tokens

    func testLegacySingleDisplayWithoutAnyBranchTokenStillResolves() {
        // Older firmware may not register the `dispextN:dcpav-service-epic:*`
        // token. The strictly unambiguous one-display/one-service topology
        // keeps working exactly as it did before Issue #115.
        let resolution = DDCTargetResolver.resolve(
            outputUID: displayA,
            framebuffers: [framebuffer(1, branch: "dispext0", edid: displayA)],
            services: [service(20, branch: nil)]
        )

        XCTAssertEqual(resolution, .matched(framebufferEntryID: 1, serviceEntryID: 20))
    }

    func testLegacyFallbackRefusesMoreThanOneService() {
        let resolution = DDCTargetResolver.resolve(
            outputUID: displayA,
            framebuffers: [framebuffer(1, branch: "dispext0", edid: displayA)],
            services: [
                service(20, branch: nil),
                service(21, branch: nil)
            ]
        )

        XCTAssertEqual(resolution, .unavailable(.noAssociatedService))
    }

    func testLegacyFallbackRefusesMoreThanOneFramebuffer() {
        let resolution = DDCTargetResolver.resolve(
            outputUID: displayA,
            framebuffers: [
                framebuffer(1, branch: "dispext0", edid: displayA),
                framebuffer(2, branch: "dispext1", edid: displayB)
            ],
            services: [service(20, branch: nil)]
        )

        XCTAssertEqual(resolution, .unavailable(.noAssociatedService))
    }

    func testContradictoryBranchTokensAreNotFallenBackTo() {
        // Concrete tokens that disagree are real evidence against a match, so
        // the legacy single-display fallback must not override them.
        let resolution = DDCTargetResolver.resolve(
            outputUID: displayA,
            framebuffers: [framebuffer(1, branch: "dispext1", edid: displayA)],
            services: [service(20, branch: "dispext0")]
        )

        XCTAssertEqual(resolution, .unavailable(.noAssociatedService))
    }
}
