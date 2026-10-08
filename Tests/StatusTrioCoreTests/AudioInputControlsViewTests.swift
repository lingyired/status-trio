import Foundation
import XCTest

final class AudioInputControlsViewTests: XCTestCase {
    func testUnreadableGainKeepsDisabledSliderWithUnavailableVisualAndAccessibilityState() throws {
        let sourceURL = packageRoot
            .appendingPathComponent("Sources/StatusTrioCore/UI/AudioInputControlsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let controlsStart = try XCTUnwrap(source.range(of: "private var controls: some View {"))
        let controlsEnd = try XCTUnwrap(source.range(of: "    @ViewBuilder\n    private var muteIcon"))
        let controls = String(source[controlsStart.lowerBound..<controlsEnd.lowerBound])

        XCTAssertTrue(controls.contains("Slider("), "volume control layout must contain the slider")
        XCTAssertTrue(controls.contains(".disabled(!state.canAdjust)"))
        XCTAssertTrue(controls.contains("if state.scalar == nil"))
        XCTAssertTrue(controls.contains("Text(\"—\")"))
        XCTAssertTrue(controls.contains(".accessibilityValue(sliderAccessibilityValue)"))
        XCTAssertTrue(controls.contains(".audioInputVolumeUnavailable"))
    }

    func testSliderAccessibilityValueUsesReadbackAwareDraftPresentation() throws {
        let sourceURL = packageRoot
            .appendingPathComponent("Sources/StatusTrioCore/UI/AudioInputControlsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let valueStart = try XCTUnwrap(source.range(of: "private var sliderAccessibilityValue: String {"))
        let valueEnd = try XCTUnwrap(source.range(of: "    var body: some View {", range: valueStart.upperBound..<source.endIndex))
        let accessibilityValue = String(source[valueStart.lowerBound..<valueEnd.lowerBound])

        XCTAssertTrue(accessibilityValue.contains("volumeDraft.accessibilityValue("))
        XCTAssertTrue(
            accessibilityValue.contains("systemScalar: state.scalar"),
            "the drag draft must not bypass current system readback availability"
        )
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
