import AppKit
import XCTest
@testable import StatusTrioCore

final class MenuBarAttributedTitleRendererTests: XCTestCase {
    private let appearance = NSAppearance(named: .aqua)!

    private func input(_ instance: MenuBarInstance, readings: [MenuBarMetricID: MenuBarMetricReading] = [:]) -> MenuBarRenderInput {
        MenuBarRenderInput(instance: instance, readings: readings)
    }

    func testTwoLineProducesTwoParagraphs() {
        let instance = MenuBarInstance(
            layoutMode: .doubleLine,
            top: MenuBarLine(elements: [MenuBarElement(content: .metric(.cpuUsage))]),
            bottom: MenuBarLine(elements: [MenuBarElement(content: .metric(.cpuTemperature))])
        )
        let content = MenuBarAttributedTitleRenderer.render(input(instance, readings: [
            .cpuUsage: MenuBarMetricReading(text: "45%", value: 45, availability: .measured),
            .cpuTemperature: MenuBarMetricReading(text: "62°", value: 62, availability: .measured),
        ]), appearance: appearance)
        XCTAssertNotNil(content)
        let string = content!.attributedTitle.string
        XCTAssertTrue(string.contains("\n"))
        XCTAssertEqual(string, "45%\n62°")
        XCTAssertGreaterThan(content!.measuredWidth, 0)
        XCTAssertGreaterThan(content!.measuredHeight, 0)
    }

    func testMetricCarriesInheritedColor() {
        let instance = MenuBarInstance(top: MenuBarLine(elements: [MenuBarElement(content: .metric(.cpuUsage))]))
        let content = MenuBarAttributedTitleRenderer.render(input(instance, readings: [
            .cpuUsage: MenuBarMetricReading(text: "12%", value: 12, availability: .measured),
        ]), appearance: appearance)!
        let color = content.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let expected = MenuBarMetricColorResolver.sourceColor(for: .cpuUsage, overrides: [:], batteryLevel: nil)!
        let rgb = color!.usingColorSpace(.sRGB)!
        XCTAssertEqual(Double(rgb.redComponent), expected.red, accuracy: 0.02)
        XCTAssertEqual(Double(rgb.greenComponent), expected.green, accuracy: 0.02)
    }

    func testFixedTextColor() {
        let line = MenuBarLine(elements: [MenuBarElement(content: .text("CPU"))], color: .fixed(ColorValue(red: 1, green: 0, blue: 0)))
        let instance = MenuBarInstance(top: line)
        let content = MenuBarAttributedTitleRenderer.render(input(instance), appearance: appearance)!
        let color = content.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(Double(color!.usingColorSpace(.sRGB)!.redComponent), 1.0, accuracy: 0.02)
    }

    func testLeadingIconProducesImage() {
        let instance = MenuBarInstance(
            top: MenuBarLine(elements: [MenuBarElement(content: .text("CPU"))]),
            leadingIcon: MenuBarIconSpec(source: .sfSymbol("cpu"))
        )
        let content = MenuBarAttributedTitleRenderer.render(input(instance), appearance: appearance)
        XCTAssertNotNil(content?.leadingImage)
    }

    func testAccessibilityLabelReadsValues() {
        let instance = MenuBarInstance(top: MenuBarLine(elements: [
            MenuBarElement(content: .text("CPU ")),
            MenuBarElement(content: .metric(.cpuUsage)),
        ]))
        let content = MenuBarAttributedTitleRenderer.render(input(instance, readings: [
            .cpuUsage: MenuBarMetricReading(text: "33%", value: 33, availability: .measured),
        ]), appearance: appearance)!
        XCTAssertTrue(content.accessibilityLabel.contains("33%"))
    }
}
