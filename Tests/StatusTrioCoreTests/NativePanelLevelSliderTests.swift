import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class NativePanelLevelSliderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }
    func testContinuousGestureCoalescesBindingWritesAndFlushesNewestBeforeFinish() {
        let slider = NativePanelLevelSliderControl()
        var values: [Double] = []
        var finishedValues: [Double] = []
        slider.onValueChanged = { values.append($0) }
        slider.onEditingChanged = { editing in
            if editing {
                // Send one synchronous native action burst during the actual
                // key transaction; no window or global input is involved.
                for value in [0.2, 0.4, 0.6] {
                    slider.doubleValue = value
                    slider.sendAction(slider.action, to: slider.target)
                }
                XCTAssertEqual(values, [0.2], "native drawing must not write every pointer tick into SwiftUI")
            } else {
                finishedValues = values
            }
        }
        // Closing the real key transaction must flush the newest native value
        // before the backend's editing-finished callback.
        slider.keyDown(with: adjustmentEvent(keyCode: 119))
        XCTAssertEqual(values, [0.2, 0.6])
        XCTAssertEqual(finishedValues, [0.2, 0.6])
        XCTAssertFalse(slider.isEditing)
    }

    func testSeparateGestureAlwaysReportsItsFirstActionImmediately() {
        let slider = NativePanelLevelSliderControl()
        var values: [Double] = []
        slider.onValueChanged = { values.append($0) }
        for value in [0.7, 0.3] {
            slider.onEditingChanged = { editing in
                guard editing else { return }
                slider.doubleValue = value
                slider.sendAction(slider.action, to: slider.target)
                XCTAssertEqual(values.last, value, "a new edit cannot inherit the previous gesture's throttle")
            }
            slider.keyDown(with: adjustmentEvent(keyCode: 119))
        }
        XCTAssertEqual(values, [0.7, 0.3])
    }

    func testAccessibilityActionOutsideGestureStillReportsImmediately() {
        let slider = NativePanelLevelSliderControl()
        var values: [Double] = []
        slider.onValueChanged = { values.append($0) }
        for value in [0.2, 0.6, 0.9] {
            slider.doubleValue = value
            slider.sendAction(slider.action, to: slider.target)
        }
        XCTAssertEqual(values, [0.2, 0.6, 0.9])
    }

    private func adjustmentEvent(keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: keyCode == 119 ? "\u{f72b}" : "\u{f729}",
            charactersIgnoringModifiers: keyCode == 119 ? "\u{f72b}" : "\u{f729}",
            isARepeat: false, keyCode: keyCode
        )!
    }
}
