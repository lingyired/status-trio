import XCTest
@testable import StatusTrioCore

final class IconDesignerLifecycleTests: XCTestCase {
    func testPreviewClockStopsWhenDesignerLeavesVisibility() {
        var preview = IconDesignerPreviewState()
        preview.start(at: Date(timeIntervalSince1970: 100))
        XCTAssertTrue(preview.playback.isPlaying)

        preview.setVisible(false)

        XCTAssertFalse(preview.playback.isPlaying)
    }

    func testPreviewClockStopsWhenReduceMotionIsEnabled() {
        var preview = IconDesignerPreviewState()
        preview.start(at: Date(timeIntervalSince1970: 100))

        preview.setReduceMotion(true)

        XCTAssertFalse(preview.playback.isPlaying)
    }

    func testPreviewCannotStartWhileHiddenOrWithReduceMotion() {
        var preview = IconDesignerPreviewState()
        preview.setVisible(false)
        preview.start(at: Date(timeIntervalSince1970: 100))
        XCTAssertFalse(preview.playback.isPlaying)

        preview.setVisible(true)
        preview.setReduceMotion(true)
        preview.start(at: Date(timeIntervalSince1970: 101))
        XCTAssertFalse(preview.playback.isPlaying)
    }

    func testSwitchingAwayFromChargingPreviewStopsItsClock() {
        var preview = IconDesignerPreviewState()
        preview.setScenario(.batteryCharging)
        preview.start(at: Date(timeIntervalSince1970: 100))
        XCTAssertTrue(preview.playback.isPlaying)

        preview.setScenario(.networkHealthy)

        XCTAssertFalse(preview.playback.isPlaying)
        preview.start(at: Date(timeIntervalSince1970: 101))
        XCTAssertFalse(preview.playback.isPlaying)
    }

    func testAirPodsPreviewScenariosAreExposedAfterPhaseFive() {
        XCTAssertEqual(IconDesignerPreviewState.availableScenarios, IconPreviewScenario.allCases)
        XCTAssertTrue(IconDesignerPreviewState.availableScenarios.contains(.airPodsConnected))
        XCTAssertTrue(IconDesignerPreviewState.availableScenarios.contains(.airPodsDisconnected))
    }
}
