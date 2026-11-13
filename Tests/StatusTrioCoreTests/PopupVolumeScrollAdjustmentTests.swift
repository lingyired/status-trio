import XCTest
@testable import StatusTrioCore

final class PopupVolumeScrollAdjustmentTests: XCTestCase {
    private var adjustment = PopupVolumeScrollAdjustment()

    func testWheelNotchHasSameStepForOneAndThreeReportedLines() throws {
        for lines in [1.0, 3.0, -1.0, -3.0] {
            let delta = try XCTUnwrap(adjustment.volumeDelta(
                deltaY: lines, isPrecise: false, isDirectionInverted: false,
                usesNaturalScrolling: false, wheelStep: 0.05
            ))
            XCTAssertEqual(delta, lines > 0 ? 0.05 : -0.05, accuracy: 0.000_001)
        }
    }

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

    func testDefaultWheelStepIsTenPercent() throws {
        let delta = try XCTUnwrap(adjustment.volumeDelta(
            deltaY: 3, isPrecise: false, isDirectionInverted: false, usesNaturalScrolling: false
        ))
        XCTAssertEqual(delta, 0.10, accuracy: 0.000_001)
    }

    func testPreciseScrollIgnoresConfiguredWheelStep() throws {
        let delta = try XCTUnwrap(adjustment.volumeDelta(
            deltaY: 4, isPrecise: true, isDirectionInverted: false,
            usesNaturalScrolling: false, wheelStep: 0.2
        ))
        XCTAssertEqual(delta, 0.008, accuracy: 0.000_001)
    }

    func testFractionalWheelPacketsAccumulateAndReverseWithoutOldRemainder() throws {
        XCTAssertNil(wheel(0.25))
        XCTAssertNil(wheel(0.25))
        XCTAssertNil(wheel(0.25))
        XCTAssertEqual(try XCTUnwrap(wheel(0.25)), 0.05, accuracy: 0.000_001)
        XCTAssertNil(wheel(0.5))
        XCTAssertNil(wheel(-0.5))
        XCTAssertEqual(try XCTUnwrap(wheel(-0.5)), -0.05, accuracy: 0.000_001)
    }

    func testFractionalRemainderResetsAcrossTargetsTimeoutAndPreciseScroll() throws {
        XCTAssertNil(wheel(0.5, context: "volume"))
        XCTAssertNil(wheel(0.5, context: "audioInput"))
        XCTAssertNil(wheel(0.5, context: "brightness.1"))
        XCTAssertNil(wheel(0.5, timestamp: 1, context: "brightness.1"))
        _ = adjustment.volumeDelta(deltaY: 1, isPrecise: true,
            isDirectionInverted: false, usesNaturalScrolling: false)
        XCTAssertNil(wheel(0.5, timestamp: 1, context: "brightness.1"))
        XCTAssertEqual(try XCTUnwrap(wheel(0.5, timestamp: 1, context: "brightness.1")), 0.05, accuracy: 0.000_001)
    }

    func testNaturalWheelDirectionAndNewStepDiscardOldFraction() throws {
        XCTAssertNil(wheel(0.5))
        XCTAssertNil(wheel(0.5, step: 0.025))
        XCTAssertEqual(try XCTUnwrap(wheel(0.5, step: 0.025)), 0.025, accuracy: 0.000_001)
        let delta = try XCTUnwrap(adjustment.volumeDelta(deltaY: -3, isPrecise: false,
            isDirectionInverted: true, usesNaturalScrolling: true, wheelStep: 0.1))
        XCTAssertEqual(delta, 0.1, accuracy: 0.000_001)
    }

    private func wheel(_ lines: Double, timestamp: TimeInterval = 0,
                       context: String = "volume", step: Double = 0.05) -> Double? {
        adjustment.volumeDelta(deltaY: lines, isPrecise: false,
            isDirectionInverted: false, usesNaturalScrolling: false,
            wheelStep: step, timestamp: timestamp, context: context)
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
    func testPanelScrollFallbackAllowsSummaryWhenEnabled() {
        XCTAssertTrue(
            PanelScrollVolumeFallback.allows(
                panelScrollEnabled: true,
                route: .summary,
                isVolumeControlAvailable: true,
                canAdjustVolume: true
            )
        )
    }

    func testPanelScrollFallbackRejectsDetailRoutes() {
        let detailRoutes: [StatusPanelRoute] = [.battery, .wifi, .ethernet, .inputSource]
        for route in detailRoutes {
            XCTAssertFalse(
                PanelScrollVolumeFallback.allows(
                    panelScrollEnabled: true,
                    route: route,
                    isVolumeControlAvailable: true,
                    canAdjustVolume: true
                ),
                "scrolling a \(route) detail page must not change output volume"
            )
        }
    }

    func testPanelScrollFallbackRejectsWhenDisabledOrUnavailable() {
        XCTAssertFalse(
            PanelScrollVolumeFallback.allows(
                panelScrollEnabled: false,
                route: .summary,
                isVolumeControlAvailable: true,
                canAdjustVolume: true
            )
        )
        XCTAssertFalse(
            PanelScrollVolumeFallback.allows(
                panelScrollEnabled: true,
                route: .summary,
                isVolumeControlAvailable: false,
                canAdjustVolume: true
            )
        )
        XCTAssertFalse(
            PanelScrollVolumeFallback.allows(
                panelScrollEnabled: true,
                route: .summary,
                isVolumeControlAvailable: true,
                canAdjustVolume: false
            )
        )
    }

}
