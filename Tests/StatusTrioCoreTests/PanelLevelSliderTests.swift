import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class PanelLevelSliderTests: XCTestCase {
    private let controlWidth: CGFloat = 260
    private var inset: CGFloat { PanelLevelSliderMetrics.horizontalInset }

    // MARK: Geometry

    func testWithoutLabelTheThumbTravelsTheWholeCapsule() {
        let start = PanelLevelSliderMetrics.trackStartX(
            controlWidth: controlWidth,
            reservedLabelWidth: 0
        )
        XCTAssertEqual(start, inset, accuracy: 0.001)
        XCTAssertEqual(
            PanelLevelSliderMetrics.thumbCenterX(
                for: 0,
                width: controlWidth,
                trackStartX: start
            ),
            inset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PanelLevelSliderMetrics.thumbCenterX(
                for: 1,
                width: controlWidth,
                trackStartX: start
            ),
            controlWidth - inset,
            accuracy: 0.001
        )
    }

    func testLabelReservesAColumnAndPushesTheTrackStartRight() {
        let reserved = PanelLevelSliderMetrics.reservedLabelWidth(
            textWidth: 80,
            controlWidth: controlWidth,
            preferred: nil
        )
        XCTAssertEqual(reserved, 80, accuracy: 0.001)
        let start = PanelLevelSliderMetrics.trackStartX(
            controlWidth: controlWidth,
            reservedLabelWidth: reserved
        )
        XCTAssertEqual(
            start,
            PanelLevelSliderMetrics.labelLeadingInset + 80
                + PanelLevelSliderMetrics.labelGap
                + PanelLevelSliderMetrics.thumbRadius,
            accuracy: 0.001
        )
    }

    func testLabelColumnNeverExceedsHalfTheCapsule() {
        let reserved = PanelLevelSliderMetrics.reservedLabelWidth(
            textWidth: 400,
            controlWidth: controlWidth,
            preferred: nil
        )
        XCTAssertEqual(
            reserved,
            controlWidth * PanelLevelSliderMetrics.maximumLabelFraction,
            accuracy: 0.001
        )
    }

    func testSharedPreferredColumnKeepsRowsAligned() {
        let preferred: CGFloat = 72
        let short = PanelLevelSliderMetrics.reservedLabelWidth(
            textWidth: 40,
            controlWidth: controlWidth,
            preferred: preferred
        )
        let long = PanelLevelSliderMetrics.reservedLabelWidth(
            textWidth: 70,
            controlWidth: controlWidth,
            preferred: preferred
        )
        XCTAssertEqual(short, long, accuracy: 0.001)
        let startShort = PanelLevelSliderMetrics.trackStartX(
            controlWidth: controlWidth,
            reservedLabelWidth: short
        )
        let startLong = PanelLevelSliderMetrics.trackStartX(
            controlWidth: controlWidth,
            reservedLabelWidth: long
        )
        XCTAssertEqual(startShort, startLong, accuracy: 0.001)
    }

    func testThumbNeverEntersTheLabelColumnAcrossTheRange() {
        let reserved = PanelLevelSliderMetrics.reservedLabelWidth(
            textWidth: 90,
            controlWidth: controlWidth,
            preferred: nil
        )
        let start = PanelLevelSliderMetrics.trackStartX(
            controlWidth: controlWidth,
            reservedLabelWidth: reserved
        )
        for value in [0.0, 0.1, 0.5, 0.9, 1.0] {
            let center = PanelLevelSliderMetrics.thumbCenterX(
                for: value,
                width: controlWidth,
                trackStartX: start
            )
            let labelEnd = PanelLevelSliderMetrics.labelLeadingInset + reserved
            XCTAssertGreaterThanOrEqual(
                center - PanelLevelSliderMetrics.thumbRadius,
                labelEnd + PanelLevelSliderMetrics.labelGap - 0.001,
                "thumb must stay right of the label column at \(value)"
            )
        }
    }

    func testLabelColumnStaysInsideTheCapsule() {
        let reserved = PanelLevelSliderMetrics.reservedLabelWidth(
            textWidth: 70,
            controlWidth: controlWidth,
            preferred: nil
        )
        let trackStart = PanelLevelSliderMetrics.trackStartX(
            controlWidth: controlWidth,
            reservedLabelWidth: reserved
        )
        XCTAssertLessThanOrEqual(
            PanelLevelSliderMetrics.labelLeadingInset + reserved
                + PanelLevelSliderMetrics.labelGap
                + PanelLevelSliderMetrics.thumbRadius,
            trackStart + 0.001
        )
    }

    func testZeroWidthControlCollapsesSafely() {
        let start = PanelLevelSliderMetrics.trackStartX(
            controlWidth: 0,
            reservedLabelWidth: 40
        )
        XCTAssertEqual(start, inset, accuracy: 0.001)
        XCTAssertEqual(
            PanelLevelSliderMetrics.thumbCenterX(for: 0.5, width: 0, trackStartX: start),
            start,
            accuracy: 0.001
        )
    }

    func testLabelTextUsesTheSmallerPanelFont() {
        // 10pt medium for a 9-character name stays under the 50% column cap on a
        // typical brightness slider.
        let width = PanelLevelSliderLabelLayout.textWidth("XV272U")
        XCTAssertGreaterThan(width, 0)
        XCTAssertLessThan(width, 120)
    }

    // MARK: AppKit control

    func testControlUsesNativeLinearContinuousSliderConfiguration() {
        let slider = PanelLevelSliderView()
        XCTAssertEqual(slider.minValue, 0)
        XCTAssertEqual(slider.maxValue, 1)
        XCTAssertTrue(slider.isContinuous)
        XCTAssertFalse(slider.isVertical)
        XCTAssertEqual(slider.sliderType, .linear)
        XCTAssertTrue(slider.isEnabled)
    }

    func testControlReportsThePanelDesignHeight() {
        let slider = PanelLevelSliderView()
        XCTAssertEqual(
            slider.intrinsicContentSize.height,
            PanelLevelSliderMetrics.controlHeight
        )
    }

    func testKnobRectMatchesTheDrawnThumbGeometry() {
        let slider = PanelLevelSliderView()
        slider.frame = NSRect(x: 0, y: 0, width: controlWidth, height: 30)
        slider.doubleValue = 0.5
        let center = slider.knobCenter(in: slider.bounds)
        let cellRect = (slider.cell as? PanelLevelSliderCell)?.knobRect(flipped: true)
        XCTAssertNotNil(cellRect)
        XCTAssertEqual(cellRect?.midX ?? 0, center.x, accuracy: 0.001)
        XCTAssertEqual(cellRect?.midY ?? 0, center.y, accuracy: 0.001)
        XCTAssertEqual(
            cellRect?.width ?? 0,
            PanelLevelSliderMetrics.thumbDiameter,
            accuracy: 0.001
        )
    }

    func testValueChangeBridgeClampsAndEmits() {
        let slider = PanelLevelSliderView()
        slider.frame = NSRect(x: 0, y: 0, width: controlWidth, height: 30)
        var values: [Double] = []
        slider.onValueChanged = { values.append($0) }

        slider.doubleValue = 0.2
        slider.valueDidChange(nil)
        slider.doubleValue = 0.8
        slider.valueDidChange(nil)
        slider.doubleValue = 1.4
        slider.valueDidChange(nil)

        XCTAssertEqual(values, [0.2, 0.8, 1.0])
    }

    func testDisabledControlDoesNotAcceptUserInput() {
        let slider = PanelLevelSliderView()
        slider.isEnabled = false
        slider.frame = NSRect(x: 0, y: 0, width: controlWidth, height: 30)
        XCTAssertFalse(slider.isEnabled)
        XCTAssertFalse(slider.acceptsFirstResponder)
    }
}