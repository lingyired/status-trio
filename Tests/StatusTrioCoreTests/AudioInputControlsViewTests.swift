import Foundation
import XCTest
@testable import StatusTrioCore

final class AudioInputControlsViewTests: XCTestCase {
    func testUnreadableGainKeepsDisabledSliderWithUnavailableVisualAndAccessibilityState() throws {
        let sourceURL = packageRoot
            .appendingPathComponent("Sources/StatusTrioCore/UI/AudioInputControlsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let controlsStart = try XCTUnwrap(source.range(of: "private var controls: some View {"))
        let controlsEnd = try XCTUnwrap(source.range(of: "    @ViewBuilder\n    private var muteIcon"))
        let controls = String(source[controlsStart.lowerBound..<controlsEnd.lowerBound])

        XCTAssertTrue(
            controls.contains("PanelLevelSlider("),
            "volume control layout must use the shared panel slider"
        )
        XCTAssertTrue(controls.contains("isEnabled: state.canAdjust"))
        XCTAssertTrue(controls.contains("if state.scalar == nil"))
        XCTAssertTrue(controls.contains("Text(\"—\")"))
        XCTAssertTrue(controls.contains("accessibilityValue: sliderAccessibilityValue"))
        XCTAssertTrue(controls.contains(".audioInputVolumeUnavailable"))
    }

    func testNoDeviceStateReplacesSliderWithEmptyHintAndDropsSquareBackground() throws {
        let sourceURL = packageRoot
            .appendingPathComponent("Sources/StatusTrioCore/UI/AudioInputControlsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let controlsStart = try XCTUnwrap(source.range(of: "private var controls: some View {"))
        let controlsEnd = try XCTUnwrap(source.range(of: "    @ViewBuilder\n    private var muteIcon"))
        let controls = String(source[controlsStart.lowerBound..<controlsEnd.lowerBound])

        XCTAssertTrue(
            controls.contains("PanelAudioEmptyDevicesHint("),
            "no input device must replace the slider with the shared empty hint"
        )
        XCTAssertTrue(controls.contains(".audioInputNoDevices"))
        XCTAssertFalse(
            controls.contains(".background(.background)"),
            "the rectangular \"—\" background is the square artifact from #378"
        )
        XCTAssertTrue(controls.contains(".background(.background, in: Capsule())"))
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

    /// A live input keeps the slider available while the device list has not
    /// loaded; only an absent input may replace it with the empty hint.
    @MainActor
    func testUnloadedInputListKeepsTheLiveSlider() throws {
        let suite = "StatusTrioCoreTests.AudioInput.Unloaded.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])

        func state(scalar: Double?) -> AudioInputPanelState {
            AudioPanelMapper.input(
                AudioInputStatus(
                    devices: [],
                    defaultDeviceID: nil,
                    deviceName: nil,
                    scalar: scalar,
                    canSetVolume: true,
                    muteState: .unmuted,
                    canSetMute: true,
                    isRefreshing: false,
                    isBusy: false,
                    error: nil,
                    isDefaultInputInUse: false
                ),
                localization: localization
            )
        }

        let liveButUnloaded = state(scalar: 0.31)
        let absent = state(scalar: nil)
        XCTAssertTrue(liveButUnloaded.rows.isEmpty)
        XCTAssertTrue(liveButUnloaded.hasUsableInput)
        XCTAssertFalse(absent.hasUsableInput)
    }

    func testEmptyInputStateRequiresAnAbsentUsableInput() throws {
        let sourceURL = packageRoot
            .appendingPathComponent("Sources/StatusTrioCore/UI/AudioInputControlsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private var hasNoInputDevices: Bool {"))
        let end = try XCTUnwrap(source.range(of: "private var settingsButton", range: start.upperBound..<source.endIndex))
        let predicate = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(predicate.contains("!state.hasUsableInput"))
        XCTAssertTrue(predicate.contains("state.rows.isEmpty"))
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
