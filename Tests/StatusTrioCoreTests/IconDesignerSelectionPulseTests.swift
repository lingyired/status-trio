import XCTest
@testable import StatusTrioCore

final class IconDesignerSelectionPulseTests: XCTestCase {
    func testSelectionPulseRunsTwiceWithTwoSecondPulseAndRepeatsEveryFourSeconds() {
        let timing = IconDesignerSelectionPulseTiming.self

        XCTAssertEqual(timing.period, 4, accuracy: 0.001)
        XCTAssertEqual(timing.fadeDuration, 0.3, accuracy: 0.001)
        XCTAssertEqual(timing.holdDuration, 0.2, accuracy: 0.001)
        XCTAssertEqual(timing.interPulseDelay, 0.2, accuracy: 0.001)
        XCTAssertEqual(timing.pulseStartOffsets, [0, 1.0])
        XCTAssertEqual(timing.fadeOutStartsAt, 0.5, accuracy: 0.001)
        XCTAssertEqual(timing.visibleDuration, 0.8, accuracy: 0.001)
        XCTAssertEqual(timing.secondFadeOutStartsAt, 1.5, accuracy: 0.001)
        XCTAssertEqual(timing.cycleVisibleDuration, 1.8, accuracy: 0.001)
        XCTAssertEqual(timing.remainingPeriod, 2.2, accuracy: 0.001)

        XCTAssertTrue(timing.isVisible(at: 0))
        XCTAssertTrue(timing.isVisible(at: 0.5))
        XCTAssertTrue(timing.isVisible(at: 0.799))
        XCTAssertFalse(timing.isVisible(at: 0.8))
        XCTAssertFalse(timing.isVisible(at: 0.999))
        XCTAssertTrue(timing.isVisible(at: 1.0))
        XCTAssertTrue(timing.isVisible(at: 1.5))
        XCTAssertTrue(timing.isVisible(at: 1.799))
        XCTAssertFalse(timing.isVisible(at: 1.8))
        XCTAssertFalse(timing.isVisible(at: timing.period - 0.001))
        XCTAssertTrue(timing.isVisible(at: timing.period))
        XCTAssertTrue(timing.isVisible(at: timing.period + 1.0))
        XCTAssertFalse(timing.isVisible(at: timing.period + 1.801))
    }

    func testSelectedSlotsMapToTheirOwnIconGeometry() {
        XCTAssertEqual(IconDesignerSelectionHighlight.part(for: .outerRing), .battery)
        XCTAssertEqual(IconDesignerSelectionHighlight.part(for: .center), .network)
        XCTAssertEqual(IconDesignerSelectionHighlight.part(for: .footer), .volume)
    }

    func testReducedMotionUsesStaticLowOpacityAndTaskIdentityRestartsForSlotChanges() {
        XCTAssertEqual(IconDesignerSelectionPulseTiming.reducedMotionOpacity, 0.12, accuracy: 0.001)
        XCTAssertNotEqual(
            IconDesignerSelectionPulseTaskKey(slot: .outerRing, reduceMotion: false),
            IconDesignerSelectionPulseTaskKey(slot: .center, reduceMotion: false)
        )
        XCTAssertNotEqual(
            IconDesignerSelectionPulseTaskKey(slot: .center, reduceMotion: false),
            IconDesignerSelectionPulseTaskKey(slot: .center, reduceMotion: true)
        )
    }

    func testOverlayOwnsCancelableTaskAndDoesNotRenderOrCacheRasterArtwork() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Sources/StatusTrioCore/UI/Settings/IconDesigner/IconDesignerSelectionPulseOverlay.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains(".task(id: taskKey)"))
        XCTAssertTrue(source.contains(".onDisappear"))
        XCTAssertTrue(source.contains("IconDesignerSelectionPulseTiming.pulseStartOffsets.enumerated()"))
        XCTAssertTrue(source.contains("let delayUntilPulse = pulseStart - previousPulseEnd"))
        XCTAssertTrue(source.contains("Task.sleep(for: .seconds(delayUntilPulse))"))
        XCTAssertTrue(source.contains("Task.sleep(for: .seconds(IconDesignerSelectionPulseTiming.fadeOutStartsAt))"))
        XCTAssertTrue(source.contains("Task.sleep(for: .seconds(IconDesignerSelectionPulseTiming.fadeDuration))"))
        XCTAssertTrue(source.contains("Task.sleep(for: .seconds(IconDesignerSelectionPulseTiming.remainingPeriod))"))
        XCTAssertFalse(source.contains("Task.sleep(for: .seconds(IconDesignerSelectionPulseTiming.visibleDuration))"))
        XCTAssertFalse(source.contains("repeatForever"))
        XCTAssertFalse(source.contains("StatusIconRenderer"))
        XCTAssertFalse(source.contains("DockIconRenderer"))
        XCTAssertFalse(source.contains("DockIconPreviewCache"))
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
