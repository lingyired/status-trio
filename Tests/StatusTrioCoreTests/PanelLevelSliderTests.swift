import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class PanelLevelSliderTests: XCTestCase {
    private let controlWidth: CGFloat = 260

    // MARK: Geometry

    func testThumbTravelsBetweenCapsuleInsets() {
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

    func testCapsuleIsTallerThanThumbAndFullyRounded() {
        XCTAssertGreaterThan(PanelLevelSliderMetrics.controlHeight, PanelLevelSliderMetrics.barHeight)
        XCTAssertEqual(
            PanelLevelSliderMetrics.barCornerRadius,
            PanelLevelSliderMetrics.barHeight / 2,
            accuracy: 0.001
        )
    }

    // MARK: Inline label avoidance at 0/10/50/90/100 %

    private func labelSide(
        at value: Double,
        text: String,
        currentlyTrailing: Bool = false
    ) -> PanelLevelSliderLabelLayout.Side {
        PanelLevelSliderLabelLayout.side(
            thumbCenterX: PanelLevelSliderMetrics.thumbCenterX(
                for: value,
                width: controlWidth
            ),
            controlWidth: controlWidth,
            textWidth: PanelLevelSliderLabelLayout.textWidth(text),
            currentlyTrailing: currentlyTrailing
        )
    }

    func testLabelAvoidsTheThumbAcrossTheWholeRange() {
        let name = "Built-in Display"
        // Low values: the thumb sits over the leading slot, so the label moves
        // to the thumb's trailing side.
        XCTAssertEqual(labelSide(at: 0, text: name), .trailing)
        XCTAssertEqual(labelSide(at: 0.1, text: name), .trailing)
        // Mid/high values: enough leading room for the full name.
        for value in [0.5, 0.9, 1.0] {
            XCTAssertEqual(labelSide(at: value, text: name), .leading)
        }
    }

    func testEveryRenderedLabelFrameStaysClearOfTheThumb() {
        for name in ["A", "Built-in Display", "LG UltraFine 5K Display With A Very Long Name"] {
            let textWidth = PanelLevelSliderLabelLayout.textWidth(name)
            for value in [0.0, 0.1, 0.5, 0.9, 1.0] {
                let centerX = PanelLevelSliderMetrics.thumbCenterX(
                    for: value,
                    width: controlWidth
                )
                let side = PanelLevelSliderLabelLayout.side(
                    thumbCenterX: centerX,
                    controlWidth: controlWidth,
                    textWidth: textWidth,
                    currentlyTrailing: false
                )
                let frame = PanelLevelSliderLabelLayout.frame(
                    side: side,
                    thumbCenterX: centerX,
                    controlWidth: controlWidth,
                    textWidth: textWidth
                )
                let thumbMinX = centerX - PanelLevelSliderMetrics.thumbRadius
                let thumbMaxX = centerX + PanelLevelSliderMetrics.thumbRadius
                switch side {
                case .leading:
                    XCTAssertLessThanOrEqual(
                        frame.originX + frame.width,
                        thumbMinX - PanelLevelSliderMetrics.labelGap + 0.001,
                        "\(name) at \(value) must not run under the thumb"
                    )
                case .trailing:
                    XCTAssertGreaterThanOrEqual(
                        frame.originX,
                        thumbMaxX + PanelLevelSliderMetrics.labelGap - 0.001,
                        "\(name) at \(value) must start after the thumb"
                    )
                }
            }
        }
    }

    func testHysteresisKeepsTheCurrentSideWhenBothFit() {
        let textWidth = PanelLevelSliderLabelLayout.textWidth("Studio Display")
        // 50%: both sides hold the full name, so the parked side wins.
        let centerX = PanelLevelSliderMetrics.thumbCenterX(for: 0.5, width: controlWidth)
        XCTAssertEqual(
            PanelLevelSliderLabelLayout.side(
                thumbCenterX: centerX,
                controlWidth: controlWidth,
                textWidth: textWidth,
                currentlyTrailing: true
            ),
            .trailing
        )
        XCTAssertEqual(
            PanelLevelSliderLabelLayout.side(
                thumbCenterX: centerX,
                controlWidth: controlWidth,
                textWidth: textWidth,
                currentlyTrailing: false
            ),
            .leading
        )
    }

    func testSideMovesWhenTheCurrentSideNoLongerFits() {
        let textWidth = PanelLevelSliderLabelLayout.textWidth("Studio Display")
        // Near the leading edge only the trailing side fits.
        let low = PanelLevelSliderMetrics.thumbCenterX(for: 0.0, width: controlWidth)
        XCTAssertEqual(
            PanelLevelSliderLabelLayout.side(
                thumbCenterX: low,
                controlWidth: controlWidth,
                textWidth: textWidth,
                currentlyTrailing: false
            ),
            .trailing
        )
        // Near the trailing edge only the leading side fits.
        let high = PanelLevelSliderMetrics.thumbCenterX(for: 1.0, width: controlWidth)
        XCTAssertEqual(
            PanelLevelSliderLabelLayout.side(
                thumbCenterX: high,
                controlWidth: controlWidth,
                textWidth: textWidth,
                currentlyTrailing: true
            ),
            .leading
        )
    }

    func testLongNameIsTruncatedToTheAvailableWidth() {
        let longName = "Extremely Long External Display Name That Does Not Fit"
        let textWidth = PanelLevelSliderLabelLayout.textWidth(longName)
        let frame = PanelLevelSliderLabelLayout.frame(
            side: .trailing,
            thumbCenterX: PanelLevelSliderMetrics.horizontalInset,
            controlWidth: 160,
            textWidth: textWidth
        )
        XCTAssertLessThan(frame.width, textWidth)
        XCTAssertTrue(frame.isVisible)
    }

    func testLeadingLabelNeverRunsUnderTheFill() {
        // High value: the thumb is near the trailing edge, so a leading label
        // must stop before the thumb/fill boundary.
        let name = "Studio Display"
        let textWidth = PanelLevelSliderLabelLayout.textWidth(name)
        let thumbCenterX = PanelLevelSliderMetrics.thumbCenterX(
            for: 0.9,
            width: controlWidth
        )
        let frame = PanelLevelSliderLabelLayout.frame(
            side: .leading,
            thumbCenterX: thumbCenterX,
            controlWidth: controlWidth,
            textWidth: textWidth
        )
        XCTAssertEqual(frame.side, .leading)
        XCTAssertTrue(PanelLevelSliderLabelLayout.usesLightText(side: frame.side))
        XCTAssertLessThanOrEqual(
            frame.originX + frame.width,
            thumbCenterX - PanelLevelSliderMetrics.thumbRadius
                - PanelLevelSliderMetrics.labelGap + 0.001
        )
    }

    func testTrailingFrameStaysInsideTheCapsule() {
        let name = "Display"
        let textWidth = PanelLevelSliderLabelLayout.textWidth(name)
        let frame = PanelLevelSliderLabelLayout.frame(
            side: .trailing,
            thumbCenterX: PanelLevelSliderMetrics.horizontalInset,
            controlWidth: controlWidth,
            textWidth: textWidth
        )
        XCTAssertGreaterThanOrEqual(frame.originX, 0)
        XCTAssertLessThanOrEqual(
            frame.originX + frame.width,
            controlWidth - PanelLevelSliderMetrics.labelLeadingInset + 0.001
        )
    }

    func testUnavailableSpaceHidesTheLabelInsteadOfDrawingASliver() {
        // Thumb parked at the very start leaves no trailing room.
        let frame = PanelLevelSliderLabelLayout.frame(
            side: .trailing,
            thumbCenterX: 0,
            controlWidth: 20,
            textWidth: 80
        )
        XCTAssertFalse(frame.isVisible)
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
        let cellRect = (slider.cell as? PanelLevelSliderCell)?
            .knobRect(flipped: true)
        XCTAssertNotNil(cellRect)
        XCTAssertEqual(
            cellRect?.midX ?? 0,
            center.x,
            accuracy: 0.001,
            "hit/drag geometry must match the drawn thumb"
        )
        XCTAssertEqual(
            cellRect?.midY ?? 0,
            center.y,
            accuracy: 0.001
        )
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
        // Out-of-range native values (system echoes) clamp to 0...1.
        slider.doubleValue = 1.4
        slider.valueDidChange(nil)

        XCTAssertEqual(values, [0.2, 0.8, 1.0])
    }

    func testDisabledControlDoesNotReportUserChanges() {
        let slider = PanelLevelSliderView()
        slider.isEnabled = false
        slider.frame = NSRect(x: 0, y: 0, width: controlWidth, height: 30)
        // A disabled NSSlider ignores interaction; its value can still be
        // mirrored programmatically but must not emit through the action.
        slider.doubleValue = 0.4
        XCTAssertFalse(slider.isEnabled)
        XCTAssertFalse(slider.acceptsFirstResponder)
    }
}