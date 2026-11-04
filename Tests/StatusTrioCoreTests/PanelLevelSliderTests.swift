import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class PanelLevelSliderTests: XCTestCase {
    private let controlWidth: CGFloat = 224

    // MARK: Geometry

    func testThumbTravelsAcrossTheWholeCapsule() {
        XCTAssertEqual(
            PanelLevelSliderMetrics.thumbCenterX(for: 0, width: controlWidth),
            PanelLevelSliderMetrics.horizontalInset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PanelLevelSliderMetrics.thumbCenterX(for: 1, width: controlWidth),
            controlWidth - PanelLevelSliderMetrics.horizontalInset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PanelLevelSliderMetrics.thumbCenterX(for: 0.5, width: controlWidth),
            controlWidth / 2,
            accuracy: 0.001
        )
    }

    func testThumbCenterIsStableForZeroWidth() {
        XCTAssertEqual(
            PanelLevelSliderMetrics.thumbCenterX(for: 0.5, width: 0),
            PanelLevelSliderMetrics.horizontalInset,
            accuracy: 0.001
        )
    }

    // MARK: Inline label avoidance at 0/10/50/90/100 %

    private func center(_ value: Double) -> CGFloat {
        PanelLevelSliderMetrics.thumbCenterX(for: value, width: controlWidth)
    }

    private func side(
        _ value: Double,
        text: String
    ) -> PanelLevelSliderLabelLayout.Side {
        PanelLevelSliderLabelLayout.side(
            thumbCenterX: center(value),
            controlWidth: controlWidth,
            textWidth: PanelLevelSliderLabelLayout.textWidth(text)
        )
    }

    func testShortNameStaysFullyVisibleOnTheThumbFreeSide() {
        let name = "XV272U"
        // Low values: thumb on the left, so the label parks on the right.
        XCTAssertEqual(side(0, text: name), .trailing)
        XCTAssertEqual(side(0.1, text: name), .trailing)
        // Mid/high values: thumb moved right, label returns to the left.
        XCTAssertEqual(side(0.5, text: name), .leading)
        XCTAssertEqual(side(0.9, text: name), .leading)
        XCTAssertEqual(side(1.0, text: name), .leading)

        for value in [0.0, 0.1, 0.5, 0.9, 1.0] {
            let frame = PanelLevelSliderLabelLayout.frame(
                side: side(value, text: name),
                thumbCenterX: center(value),
                controlWidth: controlWidth,
                textWidth: PanelLevelSliderLabelLayout.textWidth(name)
            )
            XCTAssertTrue(frame.isVisible)
            XCTAssertEqual(
                frame.width,
                PanelLevelSliderLabelLayout.textWidth(name),
                accuracy: 0.001,
                "short names must never be truncated at \(value)"
            )
        }
    }

    func testVeryShortNameIsNeverTruncated() {
        let name = "A"
        for value in [0.0, 0.1, 0.5, 0.9, 1.0] {
            let frame = PanelLevelSliderLabelLayout.frame(
                side: side(value, text: name),
                thumbCenterX: center(value),
                controlWidth: controlWidth,
                textWidth: PanelLevelSliderLabelLayout.textWidth(name)
            )
            XCTAssertTrue(frame.isVisible)
            XCTAssertEqual(
                frame.width,
                PanelLevelSliderLabelLayout.textWidth(name),
                accuracy: 0.001
            )
        }
    }

    func testLabelFrameNeverRunsUnderTheThumb() {
        for name in ["A", "XV272U", "Built-in Retina Display", "A Very Long Display Name Here"] {
            for value in [0.0, 0.1, 0.5, 0.9, 1.0] {
                let thumbCenter = center(value)
                let frame = PanelLevelSliderLabelLayout.frame(
                    side: side(value, text: name),
                    thumbCenterX: thumbCenter,
                    controlWidth: controlWidth,
                    textWidth: PanelLevelSliderLabelLayout.textWidth(name)
                )
                let thumbMinX = thumbCenter - PanelLevelSliderMetrics.thumbRadius
                let thumbMaxX = thumbCenter + PanelLevelSliderMetrics.thumbRadius
                switch frame.side {
                case .leading:
                    XCTAssertLessThanOrEqual(
                        frame.originX + frame.width,
                        thumbMinX - PanelLevelSliderMetrics.labelGap + 0.001,
                        "\(name) at \(value) must stay left of the thumb"
                    )
                case .trailing:
                    XCTAssertGreaterThanOrEqual(
                        frame.originX,
                        thumbMaxX + PanelLevelSliderMetrics.labelGap - 0.001,
                        "\(name) at \(value) must start right of the thumb"
                    )
                }
            }
        }
    }

    func testLongNameTruncatesOnlyWhenNeitherSideFits() {
        let name = "LG UltraFine 5K Display With A Very Long Name"
        let textWidth = PanelLevelSliderLabelLayout.textWidth(name)

        // Mid value: neither side holds the full name, so it truncates.
        let midFrame = PanelLevelSliderLabelLayout.frame(
            side: side(0.5, text: name),
            thumbCenterX: center(0.5),
            controlWidth: controlWidth,
            textWidth: textWidth
        )
        XCTAssertLessThan(midFrame.width, textWidth)
        XCTAssertTrue(midFrame.isVisible)

        // Value 0: the whole trailing side is free, so the label gets far more
        // room there even for an unusually long name.
        let zeroFrame = PanelLevelSliderLabelLayout.frame(
            side: side(0, text: name),
            thumbCenterX: center(0),
            controlWidth: controlWidth,
            textWidth: textWidth
        )
        XCTAssertGreaterThan(zeroFrame.width, midFrame.width)
        XCTAssertLessThanOrEqual(zeroFrame.width, textWidth)
    }

    func testLeadingSideWinsWheneverTheTextFitsThere() {
        let name = "Studio Display"
        let textWidth = PanelLevelSliderLabelLayout.textWidth(name)
        // Mid value: both sides fit, so the leading (blue) side wins.
        let mid = center(0.5)
        XCTAssertEqual(
            PanelLevelSliderLabelLayout.side(
                thumbCenterX: mid,
                controlWidth: controlWidth,
                textWidth: textWidth
            ),
            .leading
        )
        // Very low value: the leading side no longer fits, so it yields.
        let low = center(0.0)
        XCTAssertEqual(
            PanelLevelSliderLabelLayout.side(
                thumbCenterX: low,
                controlWidth: controlWidth,
                textWidth: textWidth
            ),
            .trailing
        )
    }

    func testLabelTextUsesTheSmallerPanelFont() {
        let width = PanelLevelSliderLabelLayout.textWidth("XV272U")
        XCTAssertGreaterThan(width, 0)
        XCTAssertLessThan(width, 60)
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
        let knobCenter = slider.knobCenter(in: slider.bounds)
        let cellRect = (slider.cell as? PanelLevelSliderCell)?.knobRect(flipped: true)
        XCTAssertNotNil(cellRect)
        XCTAssertEqual(cellRect?.midX ?? 0, knobCenter.x, accuracy: 0.001)
        XCTAssertEqual(cellRect?.midY ?? 0, knobCenter.y, accuracy: 0.001)
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