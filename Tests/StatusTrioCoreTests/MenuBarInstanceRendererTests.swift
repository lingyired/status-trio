import AppKit
import XCTest
@testable import StatusTrioCore

final class MenuBarInstanceRendererTests: XCTestCase {
    private let appearance = NSAppearance(named: .aqua)!

    private func input(
        top: MenuBarLine?,
        bottom: MenuBarLine? = nil,
        innerPadding: Double = 0,
        outerMargin: Double = 0,
        readings: [MenuBarMetricID: MenuBarMetricReading] = [:]
    ) -> MenuBarRenderInput {
        MenuBarRenderInput(
            instance: MenuBarInstance(top: top, bottom: bottom, innerPadding: innerPadding, outerMargin: outerMargin),
            readings: readings
        )
    }

    func testSharedWidthIsMaxPlusInnerPadding() {
        let top = MenuBarLine(segments: [.text("CPU")])
        let bottom = MenuBarLine(segments: [.text("CPU CPU CPU CPU")])
        let result = MenuBarInstanceRenderer.measure(
            input(top: top, bottom: bottom, innerPadding: 6, outerMargin: 4),
            appearance: appearance
        )
        let expected = max(result.lineWidths[0], result.lineWidths[1]) + 12
        XCTAssertEqual(result.totalWidth, expected, accuracy: 0.6)
    }

    func testOuterMarginDoesNotChangeMeasuredWidth() {
        let top = MenuBarLine(segments: [.text("CPU 45%")])
        let without = MenuBarInstanceRenderer.measure(
            input(top: top, innerPadding: 0, outerMargin: 0),
            appearance: appearance
        )
        let with = MenuBarInstanceRenderer.measure(
            input(top: top, innerPadding: 0, outerMargin: 24),
            appearance: appearance
        )
        XCTAssertEqual(with.totalWidth, without.totalWidth, accuracy: 0.1)
    }

    func testPerLineLeadingIconReservesOneSharedColumn() {
        let top = MenuBarLine(
            elements: [MenuBarElement(content: .text("13 KB/s"))],
            leadingIcon: MenuBarIconSpec(source: .sfSymbol("arrow.up"))
        )
        let bottom = MenuBarLine(
            elements: [MenuBarElement(content: .text("1.6 MB/s"))],
            leadingIcon: MenuBarIconSpec(source: .sfSymbol("arrow.down"))
        )
        let result = MenuBarInstanceRenderer.measure(
            input(top: top, bottom: bottom, innerPadding: 0),
            appearance: appearance
        )
        let expected = max(result.lineWidths[0], result.lineWidths[1]) + 16 + 3
        XCTAssertEqual(result.totalWidth, expected, accuracy: 0.6)
    }

    func testLongerTextWider() {
        let short = MenuBarInstanceRenderer.measure(input(top: MenuBarLine(segments: [.text("CPU")])), appearance: appearance)
        let long = MenuBarInstanceRenderer.measure(input(top: MenuBarLine(segments: [.text("CPU CPU CPU")])), appearance: appearance)
        XCTAssertGreaterThan(long.lineWidths[0], short.lineWidths[0])
    }

    func testSegmentConcatenation() {
        let segmented = MenuBarInstanceRenderer.measure(
            input(
                top: MenuBarLine(segments: [.text("CPU "), .metric(.cpuUsage)]),
                readings: [.cpuUsage: MenuBarMetricReading(text: "45%", value: 45, availability: .measured)]
            ),
            appearance: appearance
        )
        let combined = MenuBarInstanceRenderer.measure(
            input(top: MenuBarLine(segments: [.text("CPU 45%")])),
            appearance: appearance
        )
        XCTAssertEqual(segmented.lineWidths[0], combined.lineWidths[0], accuracy: 1.0)
    }

    func testMonospacedReducesJitter() {
        let nine = MenuBarInstanceRenderer.measure(input(top: MenuBarLine(segments: [.text("9%")])), appearance: appearance)
        let ten = MenuBarInstanceRenderer.measure(input(top: MenuBarLine(segments: [.text("10%")])), appearance: appearance)
        let digit = MenuBarInstanceRenderer.measure(input(top: MenuBarLine(segments: [.text("9")])), appearance: appearance)
        XCTAssertLessThanOrEqual(abs(ten.lineWidths[0] - nine.lineWidths[0]), digit.lineWidths[0] + 0.5)
    }

    func testSingleLineHeightCentered() {
        let result = MenuBarInstanceRenderer.measure(
            input(top: MenuBarLine(segments: [.text("CPU")])),
            appearance: appearance
        )
        XCTAssertEqual(result.lineHeights[1], 0)
        XCTAssertEqual(result.totalHeight, result.lineHeights[0], accuracy: 0.001)
    }

    func testMinimumWidthWidensMeasurement() {
        var instance = MenuBarInstance(top: MenuBarLine(segments: [.text("CPU")]))
        instance.minimumWidth = 220
        let measurement = MenuBarInstanceRenderer.measure(
            MenuBarRenderInput(instance: instance, readings: [:]),
            appearance: appearance
        )
        XCTAssertGreaterThanOrEqual(measurement.totalWidth, 220)
    }

    func testFixedWidthDoesNotGrowWithContent() {
        var instance = MenuBarInstance(
            top: MenuBarLine(segments: [.text("1234567890123456789012345678901234567890")])
        )
        instance.minimumWidth = 220
        let measurement = MenuBarInstanceRenderer.measure(
            MenuBarRenderInput(instance: instance, readings: [:]),
            appearance: appearance
        )
        XCTAssertEqual(measurement.totalWidth, 220, accuracy: 0.001)
    }

    func testLeadingIconSizeGrowsTheRow() {
        let line = MenuBarLine(
            elements: [MenuBarElement(content: .text("13 KB/s"))],
            leadingIcon: MenuBarIconSpec(source: .sfSymbol("arrow.up")),
            leadingIconSize: 16
        )
        let measurement = MenuBarInstanceRenderer.measure(
            input(top: line),
            appearance: appearance
        )
        XCTAssertEqual(measurement.lineHeights[0], 16, accuracy: 0.001)
        XCTAssertEqual(measurement.totalWidth, measurement.lineWidths[0] + 16 + 3, accuracy: 0.6)
    }

    func testLargeTopLayoutMakesTopRowTaller() {
        let instance = MenuBarInstance(
            layoutMode: .doubleLineLargeTop,
            top: MenuBarLine(segments: [.text("CPU")]),
            bottom: MenuBarLine(segments: [.metric(.cpuUsage)])
        )
        let result = MenuBarInstanceRenderer.measure(
            MenuBarRenderInput(instance: instance, readings: [.cpuUsage: MenuBarMetricReading(text: "45%", value: 45, availability: .measured)]),
            appearance: appearance
        )
        XCTAssertGreaterThan(result.lineHeights[0], result.lineHeights[1])
    }

    func testLargeBottomLayoutMakesBottomRowTaller() {
        let instance = MenuBarInstance(
            layoutMode: .doubleLineLargeBottom,
            top: MenuBarLine(segments: [.text("CPU")]),
            bottom: MenuBarLine(segments: [.metric(.cpuUsage)])
        )
        let result = MenuBarInstanceRenderer.measure(
            MenuBarRenderInput(instance: instance, readings: [.cpuUsage: MenuBarMetricReading(text: "45%", value: 45, availability: .measured)]),
            appearance: appearance
        )
        XCTAssertGreaterThan(result.lineHeights[1], result.lineHeights[0])
    }

    func testCharacterIconMeasures() {
        let line = MenuBarLine(
            elements: [MenuBarElement(content: .icon(MenuBarIconSpec(source: .character("A"))))]
        )
        let result = MenuBarInstanceRenderer.measure(
            input(top: line),
            appearance: appearance
        )
        XCTAssertGreaterThan(result.totalWidth, 0)
        XCTAssertGreaterThan(result.lineHeights[0], 0)
    }

    func testMetricShowsDashWhenMissing() {
        let result = MenuBarInstanceRenderer.measure(
            input(top: MenuBarLine(segments: [.metric(.gpuUsage)])),
            appearance: appearance
        )
        XCTAssertGreaterThan(result.lineWidths[0], 0)
    }

    func testRenderProducesImageAtMeasuredSize() {
        let renderInput = input(top: MenuBarLine(segments: [.text("CPU "), .metric(.cpuUsage)]),
                                readings: [.cpuUsage: MenuBarMetricReading(text: "45%", value: 45, availability: .measured)])
        let measurement = MenuBarInstanceRenderer.measure(renderInput, appearance: appearance)
        let image = MenuBarInstanceRenderer.render(renderInput, appearance: appearance, scale: 2)
        XCTAssertNotNil(image)
        XCTAssertEqual(Double(image?.size.width ?? 0), measurement.totalWidth, accuracy: 1.0)
        XCTAssertEqual(Double(image?.size.height ?? 0), measurement.totalHeight, accuracy: 1.0)
    }

    func testDarkAppearanceDoesNotCrash() {
        let dark = NSAppearance(named: .darkAqua)!
        let renderInput = input(top: MenuBarLine(segments: [.text("CPU")]), bottom: MenuBarLine(segments: [.metric(.cpuUsage)]))
        XCTAssertNotNil(MenuBarInstanceRenderer.render(renderInput, appearance: dark, scale: 2))
    }
}
