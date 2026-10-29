import XCTest
@testable import StatusTrioCore

@MainActor
final class PopupVolumeScrollSessionTests: XCTestCase {
    private let identity = VolumeControlInteractionIdentity(
        output: PanelAudioDeviceID(id: 1, uid: "output-a"),
        configuration: .default
    )

    func testSessionStartsFromFallbackAndContinuesFromLocalTarget() throws {
        var session = PopupVolumeScrollSession()

        let initial = try XCTUnwrap(
            session.scalar(at: 1, identity: identity, fallback: 0.4)
        )
        XCTAssertEqual(initial, 0.4, accuracy: 0.000_001)

        let increased = session.applying(delta: 0.2, to: initial)
        XCTAssertEqual(increased, 0.6, accuracy: 0.000_001)

        let continued = try XCTUnwrap(
            session.scalar(at: 1.5, identity: identity, fallback: 0.1)
        )
        XCTAssertEqual(continued, 0.6, accuracy: 0.000_001)
    }

    func testSessionResetsToFallbackAfterInactivity() throws {
        var session = PopupVolumeScrollSession()
        let initial = try XCTUnwrap(
            session.scalar(at: 1, identity: identity, fallback: 0.4)
        )
        _ = session.applying(delta: 0.2, to: initial)

        let refreshed = try XCTUnwrap(
            session.scalar(
                at: 1 + PopupVolumeScrollSession.timeout + 0.001,
                identity: identity,
                fallback: 0.8
            )
        )
        XCTAssertEqual(refreshed, 0.8, accuracy: 0.000_001)
    }

    func testSessionClampsAdjustmentsToValidVolumeRange() throws {
        var session = PopupVolumeScrollSession()
        let initial = try XCTUnwrap(
            session.scalar(at: 1, identity: identity, fallback: 0.99)
        )
        XCTAssertEqual(session.applying(delta: 0.5, to: initial), 1)

        session.reset()
        let lowered = try XCTUnwrap(
            session.scalar(at: 2, identity: identity, fallback: 0.01)
        )
        XCTAssertEqual(session.applying(delta: -0.5, to: lowered), 0)
    }

    func testSessionRequestsUnmuteOnlyOnceForIncrease() {
        var session = PopupVolumeScrollSession()
        let muted = makeVolumeState(isMuted: true, canMute: true)
        _ = session.scalar(at: 1, identity: identity, fallback: 0.5)

        XCTAssertTrue(
            session.shouldUnmute(in: muted, isIncreasing: true)
        )
        XCTAssertFalse(
            session.shouldUnmute(in: muted, isIncreasing: true)
        )
        XCTAssertFalse(
            session.shouldUnmute(
                in: makeVolumeState(isMuted: false, canMute: true),
                isIncreasing: true
            )
        )
        XCTAssertFalse(
            session.shouldUnmute(in: muted, isIncreasing: false)
        )
        XCTAssertFalse(
            session.shouldUnmute(
                in: makeVolumeState(isMuted: true, canMute: false),
                isIncreasing: true
            )
        )
    }

    func testResetAllowsUnmuteRequestInNextSession() {
        var session = PopupVolumeScrollSession()
        let muted = makeVolumeState(isMuted: true, canMute: true)
        _ = session.scalar(at: 1, identity: identity, fallback: 0.5)
        XCTAssertTrue(
            session.shouldUnmute(in: muted, isIncreasing: true)
        )

        session.reset()
        _ = session.scalar(at: 2, identity: identity, fallback: 0.5)

        XCTAssertTrue(
            session.shouldUnmute(in: muted, isIncreasing: true)
        )
    }

    func testScrollSessionUsesTheCurrentOutputMuteStateAfterTransition() {
        var session = PopupVolumeScrollSession()
        let mutedFirst = makeVolumeState(isMuted: true, canMute: true)
        _ = session.scalar(at: 1, identity: identity, fallback: 0.2)
        XCTAssertTrue(
            session.shouldUnmute(in: mutedFirst, isIncreasing: true)
        )

        let secondIdentity = VolumeControlInteractionIdentity(
            output: PanelAudioDeviceID(id: 2, uid: "output-b"),
            configuration: .default,
            transitionGeneration: 1
        )
        let unmutedSecond = makeVolumeState(
            identity: secondIdentity,
            isMuted: false,
            canMute: true
        )
        _ = session.scalar(at: 1.1, identity: secondIdentity, fallback: 0.7)

        XCTAssertFalse(
            session.shouldUnmute(in: unmutedSecond, isIncreasing: true)
        )
    }

    private func makeVolumeState(
        identity: VolumeControlInteractionIdentity? = nil,
        isMuted: Bool,
        canMute: Bool
    ) -> VolumePanelState {
        let identity = identity ?? self.identity
        let output = AudioOutputDevice(
            id: identity.output?.id ?? 0,
            name: "Test output",
            uid: identity.output?.uid,
            isCurrent: true
        )
        let suiteName = "PopupVolumeScrollSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            TestUserDefaults.removeSuite(named: suiteName)
        }
        return AudioPanelMapper.volume(
            VolumeStatus(
                scalar: 0.5,
                isMuted: isMuted,
                deviceName: output.name,
                currentDevice: output,
                outputDevices: [output],
                canSetVolume: true,
                canMute: canMute,
                muteState: isMuted ? .muted : .unmuted,
                externalVolumeTransitionGeneration: identity.transitionGeneration
            ),
            controllerAvailable: true,
            externalVolumeConfiguration: identity.configuration,
            localization: Localization(
                defaults: defaults,
                preferredLanguages: ["en"]
            )
        )
    }
}
