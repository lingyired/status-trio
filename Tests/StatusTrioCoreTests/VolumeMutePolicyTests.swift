import XCTest
@testable import StatusTrioCore

final class VolumeMutePolicyTests: XCTestCase {
    private let speaker = "BUILT-IN-SPEAKER"
    private let headphones = "3.5MM-HEADPHONES"

    func testDrivingToZeroMutesUnmutedDeviceAndClaimsOwnership() {
        var policy = VolumeMutePolicy()

        let write = policy.muteActionAfterWritingVolume(
            target: 0,
            deviceUID: speaker,
            currentlyMuted: false,
            canMute: true
        )

        XCTAssertEqual(write, true)
        XCTAssertTrue(policy.ownsAutoMute(deviceUID: speaker))
    }

    func testTinyNonZeroNeverMutes() {
        var policy = VolumeMutePolicy()

        let write = policy.muteActionAfterWritingVolume(
            target: 0.003,
            deviceUID: speaker,
            currentlyMuted: false,
            canMute: true
        )

        XCTAssertNil(write)
        XCTAssertFalse(policy.ownsAutoMute(deviceUID: speaker))
    }

    func testZeroOnAlreadyMutedDeviceDoesNotClaimManualMute() {
        var policy = VolumeMutePolicy()

        let write = policy.muteActionAfterWritingVolume(
            target: 0,
            deviceUID: speaker,
            currentlyMuted: true,
            canMute: true
        )

        XCTAssertNil(write)
        XCTAssertFalse(policy.ownsAutoMute(deviceUID: speaker))
    }

    func testRaisingVolumeFromAutoMuteUnmutesAndReleasesOwnership() {
        var policy = VolumeMutePolicy()
        _ = policy.muteActionAfterWritingVolume(
            target: 0, deviceUID: speaker, currentlyMuted: false, canMute: true
        )
        XCTAssertTrue(policy.ownsAutoMute(deviceUID: speaker))

        let write = policy.muteActionAfterWritingVolume(
            target: 0.2, deviceUID: speaker, currentlyMuted: true, canMute: true
        )

        XCTAssertEqual(write, false)
        XCTAssertFalse(policy.ownsAutoMute(deviceUID: speaker))
    }

    func testRaisingVolumeWhenAutoMuteAlreadyClearedExternallyReleasesOwnershipOnly() {
        var policy = VolumeMutePolicy()
        _ = policy.muteActionAfterWritingVolume(
            target: 0, deviceUID: speaker, currentlyMuted: false, canMute: true
        )

        let write = policy.muteActionAfterWritingVolume(
            target: 0.4, deviceUID: speaker, currentlyMuted: false, canMute: true
        )

        XCTAssertNil(write)
        XCTAssertFalse(policy.ownsAutoMute(deviceUID: speaker))
    }

    func testRaisingVolumeWithManualMuteLeavesMuteUntouched() {
        var policy = VolumeMutePolicy()

        let write = policy.muteActionAfterWritingVolume(
            target: 0.7, deviceUID: speaker, currentlyMuted: true, canMute: true
        )

        XCTAssertNil(write)
        XCTAssertFalse(policy.ownsAutoMute(deviceUID: speaker))
    }

    func testZeroWhileAlreadyOwnedKeepsOwnershipWithoutExtraWrite() {
        var policy = VolumeMutePolicy()
        _ = policy.muteActionAfterWritingVolume(
            target: 0, deviceUID: speaker, currentlyMuted: false, canMute: true
        )

        let write = policy.muteActionAfterWritingVolume(
            target: 0, deviceUID: speaker, currentlyMuted: true, canMute: true
        )

        XCTAssertNil(write)
        XCTAssertTrue(policy.ownsAutoMute(deviceUID: speaker))
    }

    func testDeviceChangeClearsOwnershipBeforeDecision() {
        var policy = VolumeMutePolicy()
        _ = policy.muteActionAfterWritingVolume(
            target: 0, deviceUID: speaker, currentlyMuted: false, canMute: true
        )

        let write = policy.muteActionAfterWritingVolume(
            target: 0.25, deviceUID: headphones, currentlyMuted: true, canMute: true
        )

        XCTAssertNil(write)
        XCTAssertFalse(policy.ownsAutoMute(deviceUID: headphones))
        XCTAssertFalse(policy.ownsAutoMute(deviceUID: speaker))
    }

    func testZeroWithoutMuteCapabilityDoesNotClaimOwnership() {
        var policy = VolumeMutePolicy()

        let write = policy.muteActionAfterWritingVolume(
            target: 0, deviceUID: speaker, currentlyMuted: false, canMute: false
        )

        XCTAssertNil(write)
        XCTAssertFalse(policy.ownsAutoMute(deviceUID: speaker))
    }

    func testInvalidateClearsOwnership() {
        var policy = VolumeMutePolicy()
        _ = policy.muteActionAfterWritingVolume(
            target: 0, deviceUID: speaker, currentlyMuted: false, canMute: true
        )

        policy.invalidate()

        XCTAssertFalse(policy.ownsAutoMute(deviceUID: speaker))
    }

    func testRaisingVolumeOnAnotherDeviceDoesNotUnmute() {
        var policy = VolumeMutePolicy()
        _ = policy.muteActionAfterWritingVolume(
            target: 0, deviceUID: speaker, currentlyMuted: false, canMute: true
        )

        let write = policy.muteActionAfterWritingVolume(
            target: 0.5, deviceUID: headphones, currentlyMuted: true, canMute: true
        )

        XCTAssertNil(write)
    }

    func testZeroReadBackRejectsPartiallyWrittenChannels() {
        XCTAssertTrue(ZeroVolumeVerification.allZero([0, 0, 0]))
        XCTAssertTrue(ZeroVolumeVerification.allZero([0, nil, 0]))
        XCTAssertFalse(ZeroVolumeVerification.allZero([0, 0.4, nil]))
        XCTAssertFalse(ZeroVolumeVerification.allZero([nil, 0.01]))
    }
}
