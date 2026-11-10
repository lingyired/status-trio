import XCTest
@testable import StatusTrioCore

final class PopupVolumeScrollAdjustmentTests: XCTestCase {
    private let adjustment = PopupVolumeScrollAdjustment()

    func testNaturalScrollingRaisesVolumeForPhysicalScrollUpWithSystemNaturalScrolling() throws {
        // The system reports a negative value after natural-scrolling inversion.
        let delta = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: -4,
                isPrecise: true,
                isDirectionInverted: true,
                usesNaturalScrolling: true
            )
        )

        XCTAssertEqual(delta, 0.008, accuracy: 0.000_001)
    }

    func testNaturalScrollingRaisesVolumeForPhysicalScrollUpWithoutSystemNaturalScrolling() throws {
        let delta = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 4,
                isPrecise: true,
                isDirectionInverted: false,
                usesNaturalScrolling: true
            )
        )

        XCTAssertEqual(delta, 0.008, accuracy: 0.000_001)
    }

    func testNaturalScrollingOffUsesSystemReportedDirection() throws {
        let naturalSystem = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: -4,
                isPrecise: true,
                isDirectionInverted: true,
                usesNaturalScrolling: false
            )
        )
        XCTAssertEqual(naturalSystem, -0.008, accuracy: 0.000_001)

        let classicSystem = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 4,
                isPrecise: true,
                isDirectionInverted: false,
                usesNaturalScrolling: false
            )
        )
        XCTAssertEqual(classicSystem, 0.008, accuracy: 0.000_001)
    }

    func testNaturalScrollingOffMatchesTheOriginalRawDeltaMapping() throws {
        let negative = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: -2.5,
                isPrecise: true,
                isDirectionInverted: true,
                usesNaturalScrolling: false
            )
        )
        XCTAssertEqual(negative, -0.005, accuracy: 0.000_001)

        let positive = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 2.5,
                isPrecise: true,
                isDirectionInverted: false,
                usesNaturalScrolling: false
            )
        )
        XCTAssertEqual(positive, 0.005, accuracy: 0.000_001)
    }

    func testPreciseScrollKeepsFractionalVolumeWithoutStepping() throws {
        let first = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 1,
                isPrecise: true,
                isDirectionInverted: false,
                usesNaturalScrolling: false
            )
        )
        let second = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 9,
                isPrecise: true,
                isDirectionInverted: false,
                usesNaturalScrolling: false
            )
        )

        XCTAssertEqual(first + second, 0.02, accuracy: 0.000_001)
    }

    func testDiscreteWheelScrollUsesLineDeltaAsStepCount() throws {
        let increase = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 1,
                isPrecise: false,
                isDirectionInverted: false,
                usesNaturalScrolling: false
            )
        )
        XCTAssertEqual(increase, 0.02, accuracy: 0.000_001)

        let decrease = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: -2,
                isPrecise: false,
                isDirectionInverted: false,
                usesNaturalScrolling: false
            )
        )
        XCTAssertEqual(decrease, -0.04, accuracy: 0.000_001)
    }

    func testInvalidAndZeroDeltasAreIgnored() {
        XCTAssertNil(
            adjustment.volumeDelta(
                deltaY: .nan,
                isPrecise: true,
                isDirectionInverted: false,
                usesNaturalScrolling: true
            )
        )
        XCTAssertNil(
            adjustment.volumeDelta(
                deltaY: .infinity,
                isPrecise: true,
                isDirectionInverted: true,
                usesNaturalScrolling: false
            )
        )
        XCTAssertNil(
            adjustment.volumeDelta(
                deltaY: -.infinity,
                isPrecise: false,
                isDirectionInverted: false,
                usesNaturalScrolling: true
            )
        )
        XCTAssertNil(
            adjustment.volumeDelta(
                deltaY: 0,
                isPrecise: true,
                isDirectionInverted: false,
                usesNaturalScrolling: true
            )
        )
        XCTAssertNil(
            adjustment.volumeDelta(
                deltaY: 0,
                isPrecise: false,
                isDirectionInverted: true,
                usesNaturalScrolling: false
            )
        )
    }

    func testScrollSessionDropsItsDraftWhenTheOutputIdentityChanges() throws {
        let first = VolumeControlInteractionIdentity(
            output: PanelAudioDeviceID(id: 1, uid: "output-a"),
            configuration: .default,
            transitionGeneration: 4
        )
        let second = VolumeControlInteractionIdentity(
            output: PanelAudioDeviceID(id: 2, uid: "output-b"),
            configuration: ExternalVolumeConfiguration(
                backend: .betterDisplay,
                betterDisplayUUID: "display-b"
            ),
            transitionGeneration: 5
        )
        var session = PopupVolumeScrollSession()

        let initial = try XCTUnwrap(
            session.scalar(at: 10, identity: first, fallback: 0.2)
        )
        _ = session.applying(delta: 0.3, to: initial)
        let nextOutput = try XCTUnwrap(
            session.scalar(at: 10.1, identity: second, fallback: 0.7)
        )

        XCTAssertEqual(nextOutput, 0.7, accuracy: 0.000_001)
    }
}
