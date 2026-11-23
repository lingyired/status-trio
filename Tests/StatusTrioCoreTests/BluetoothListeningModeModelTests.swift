import CoreAudio
import XCTest

@testable import StatusTrioCore

/// The model layer's rules — support-mask parsing, the selectable filter, the
/// display order, and the presentation's state transitions — held without any
/// CoreAudio or SwiftUI. The controller and the view both read from these, so
/// pinning them here is what keeps the two from each growing their own copy.
final class BluetoothListeningModeModelTests: XCTestCase {
    func testAvailableModesFollowDisplayOrderNotBitOrder() {
        // A mask that names all three should still order them NC, Transparency,
        // Adaptive rather than in bit significance.
        XCTAssertEqual(
            BluetoothListeningModeSupport.availableModes(from: 0b111),
            [.noiseCancellation, .transparency, .adaptive]
        )
    }

    func testOffHasNoSupportBitAndNeverAppearsInAvailableModes() {
        XCTAssertNil(BluetoothListeningMode.off.supportBit)
        // Even a mask with every bit set yields no `.off` — it is observation-only.
        XCTAssertFalse(BluetoothListeningModeSupport.availableModes(from: 0xFFFF).contains(.off))
    }

    func testUnknownBitsAreNotPromotedToModes() {
        let mask: UInt32 = 0b1_0000_0011 // known NC+Transparency plus future bits
        XCTAssertEqual(
            BluetoothListeningModeSupport.availableModes(from: mask),
            [.noiseCancellation, .transparency]
        )
        XCTAssertTrue(BluetoothListeningModeSupport.hasUnknownBits(mask))
        XCTAssertFalse(BluetoothListeningModeSupport.hasUnknownBits(0b111))
    }

    func testRawValueParsingFailsClosed() {
        XCTAssertEqual(BluetoothListeningModeRawValue.mode(from: 1), .off)
        XCTAssertEqual(BluetoothListeningModeRawValue.mode(from: 4), .adaptive)
        XCTAssertNil(BluetoothListeningModeRawValue.mode(from: 0)) // unresolved
        XCTAssertNil(BluetoothListeningModeRawValue.mode(from: 5)) // out of range
    }

    private func capability(
        modes: [BluetoothListeningMode],
        current: BluetoothListeningMode?,
        canSet: Bool = true
    ) -> BluetoothListeningModeCapability {
        BluetoothListeningModeCapability(
            audioDeviceID: 1,
            availableModes: modes,
            currentMode: current,
            canSet: canSet
        )
    }

    func testControlHiddenBelowTwoModes() {
        XCTAssertFalse(capability(modes: [.noiseCancellation], current: .noiseCancellation).isControllable)
        XCTAssertTrue(
            capability(modes: [.noiseCancellation, .transparency], current: .noiseCancellation).isControllable
        )
    }

    func testNonSettableDeviceIsNotControllable() {
        XCTAssertFalse(
            capability(
                modes: [.noiseCancellation, .transparency],
                current: .noiseCancellation,
                canSet: false
            ).isControllable
        )
    }

    // MARK: - Presentation (§18.3)

    func testOffCurrentShowsNoSelection() {
        let presentation = BluetoothListeningModePresentation(
            capability: capability(
                modes: [.noiseCancellation, .transparency, .adaptive],
                current: .off
            )
        )
        XCTAssertEqual(presentation.availableModes, [.noiseCancellation, .transparency, .adaptive])
        XCTAssertNil(presentation.selectedMode, "three buttons, none highlighted when the device is off")
    }

    func testUnknownCurrentShowsNoSelection() {
        let presentation = BluetoothListeningModePresentation(
            capability: capability(modes: [.noiseCancellation, .transparency], current: nil)
        )
        XCTAssertNil(presentation.selectedMode)
    }

    func testKnownCurrentHighlightsItsButton() {
        let presentation = BluetoothListeningModePresentation(
            capability: capability(modes: [.noiseCancellation, .transparency], current: .transparency)
        )
        XCTAssertEqual(presentation.selectedMode, .transparency)
    }

    func testChangingKeepsLastSelectionAndNamesTarget() {
        let idle = BluetoothListeningModePresentation(
            availableModes: [.noiseCancellation, .transparency, .adaptive],
            selectedMode: .noiseCancellation
        )
        let changing = idle.changing(to: .adaptive)
        XCTAssertEqual(changing.actionState, .changing(to: .adaptive))
        // The highlight stays on the last confirmed mode while the target spins.
        XCTAssertEqual(changing.selectedMode, .noiseCancellation)
    }

    func testSettledMovesSelectionAndClearsBusy() {
        let changing = BluetoothListeningModePresentation(
            availableModes: [.noiseCancellation, .transparency],
            selectedMode: .noiseCancellation
        ).changing(to: .transparency)
        let settled = changing.settled(on: .transparency)
        XCTAssertEqual(settled.selectedMode, .transparency)
        XCTAssertEqual(settled.actionState, .idle)
    }

    func testSettlingOnOffClearsSelection() {
        let base = BluetoothListeningModePresentation(
            availableModes: [.noiseCancellation, .transparency],
            selectedMode: .noiseCancellation
        )
        let settled = base.settled(on: .off)
        XCTAssertNil(settled.selectedMode, "a device that ends on Off highlights nothing")
    }

    func testSettledIgnoresModeNotInTheButtonSet() {
        // A write confirmed to a mode the device no longer offers cannot highlight
        // a button that is not there — the presentation drops the selection.
        let base = BluetoothListeningModePresentation(
            availableModes: [.noiseCancellation, .transparency],
            selectedMode: .noiseCancellation
        )
        let settled = base.settled(on: .adaptive)
        XCTAssertNil(settled.selectedMode)
    }

    // MARK: - Re-tap resolves to Off

    func testTapOnSelectedModeRequestsOff() {
        let presentation = BluetoothListeningModePresentation(
            availableModes: [.noiseCancellation, .transparency, .adaptive],
            selectedMode: .noiseCancellation
        )
        XCTAssertEqual(
            presentation.requestedMode(forTapped: .noiseCancellation),
            .off,
            "re-tapping the highlighted mode turns the device off"
        )
    }

    func testTapOnAnotherModeRequestsThatMode() {
        let presentation = BluetoothListeningModePresentation(
            availableModes: [.noiseCancellation, .transparency, .adaptive],
            selectedMode: .noiseCancellation
        )
        XCTAssertEqual(presentation.requestedMode(forTapped: .transparency), .transparency)
    }

    func testTapWithNoSelectionRequestsTheTappedMode() {
        let presentation = BluetoothListeningModePresentation(
            availableModes: [.noiseCancellation, .transparency],
            selectedMode: nil
        )
        XCTAssertEqual(presentation.requestedMode(forTapped: .transparency), .transparency)
    }
}
