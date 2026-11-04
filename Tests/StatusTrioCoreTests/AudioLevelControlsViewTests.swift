import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class AudioLevelControlsViewTests: XCTestCase {
    func testOutputAndInputUseThinNativeSlidersAtZeroHalfAndFullVolume() throws {
        for value in [0.0, 0.5, 1.0] {
            let localization = try localization()
            let output = try host(VolumeControlsView(
                state: outputState(value, localization: localization),
                actions: StatusPanelActions(), scrollTargets: PopoverScrollTargets(),
                onOpenSoundSettings: {}
            ), localization: localization)
            let input = try host(AudioInputControlsView(
                state: inputState(value, localization: localization),
                actions: StatusPanelActions(), scrollTargets: PopoverScrollTargets(),
                onOpenSoundSettings: {}
            ), localization: localization)
            for root in [output, input] {
                let slider = try XCTUnwrap(sliders(in: root).first)
                XCTAssertFalse(slider is PanelLevelSliderView, "audio must share the thin native brightness slider")
                XCTAssertEqual(slider.doubleValue, value, accuracy: 0.01)
                XCTAssertEqual(slider.bounds.height, 30, accuracy: 1)
                XCTAssertGreaterThanOrEqual(slider.bounds.width, 100)
                XCTAssertTrue(slider.isEnabled)
            }
        }
    }

    func testUnreadableInputKeepsUnavailableHelpOnDisabledNativeSlider() throws {
        let localization = try localization()
        let root = try host(AudioInputControlsView(
            state: inputState(nil, localization: localization),
            actions: StatusPanelActions(), scrollTargets: PopoverScrollTargets(),
            onOpenSoundSettings: {}
        ), localization: localization)
        let slider = try XCTUnwrap(sliders(in: root).first)
        XCTAssertFalse(slider is PanelLevelSliderView)
        XCTAssertFalse(slider.isEnabled)
        XCTAssertEqual(slider.accessibilityValue() as? String, "—")
        XCTAssertEqual(slider.accessibilityHelp(), localization.string(.audioInputVolumeUnavailable))
    }

    func testNativeOutputActionWritesAndFinishesThroughExistingInteraction() throws {
        let localization = try localization()
        var writes: [Double] = []
        var finishes = 0
        let root = try host(VolumeControlsView(
            state: outputState(0.5, localization: localization),
            actions: StatusPanelActions(
                setVolume: { writes = writes + [$0] },
                finishVolumeAdjustment: { finishes += 1 }
            ), scrollTargets: PopoverScrollTargets(), onOpenSoundSettings: {}
        ), localization: localization)
        let slider = try XCTUnwrap(sliders(in: root).first)
        try submit(0.75, through: slider)
        XCTAssertEqual(writes, [0.75])
        XCTAssertEqual(finishes, 1)
    }

    func testNativeInputActionPreservesRequestIdentity() throws {
        let localization = try localization()
        var writes: [Double] = []
        var requests: [UUID] = []
        let root = try host(AudioInputControlsView(
            state: inputState(0.5, localization: localization),
            actions: StatusPanelActions(setInputScalar: { value, requestID in
                writes = writes + [value]
                requests = requests + [requestID]
            }), scrollTargets: PopoverScrollTargets(), onOpenSoundSettings: {}
        ), localization: localization)
        let slider = try XCTUnwrap(sliders(in: root).first)
        try submit(0.75, through: slider)
        XCTAssertEqual(writes, [0.75])
        XCTAssertEqual(requests.count, 1)
    }

    private func submit(_ value: Double, through slider: NSSlider) throws {
        // Exercise the installed native action and caller's edit transaction,
        // without changing system audio or sending global input.
        let native = try XCTUnwrap(slider as? NativePanelLevelSliderControl)
        native.onEditingChanged?(true)
        slider.doubleValue = value
        slider.sendAction(slider.action, to: slider.target)
        native.onEditingChanged?(false)
    }

    private func localization() throws -> Localization {
        let suite = "AudioLevelControlsViewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        return Localization(defaults: defaults, preferredLanguages: ["en"])
    }

    private func outputState(_ value: Double?, localization: Localization) -> VolumePanelState {
        AudioPanelMapper.volume(VolumeStatus(
            scalar: value, isMuted: false, deviceName: "MacBook Pro Speakers",
            outputDevices: [AudioOutputDevice(id: 1, name: "MacBook Pro Speakers", isCurrent: true)]
        ), controllerAvailable: true, deviceList: .init(visibleLimit: nil), localization: localization)
    }

    private func inputState(_ value: Double?, localization: Localization) -> AudioInputPanelState {
        AudioPanelMapper.input(AudioInputStatus(
            devices: [AudioInputDevice(id: 2, uid: "test-mic", name: "MacBook Pro Microphone")],
            defaultDeviceID: 2, deviceName: "MacBook Pro Microphone",
            scalar: value, canSetVolume: true, muteState: .unmuted, canSetMute: true,
            isRefreshing: false, isBusy: false, error: nil
        ), localization: localization)
    }

    private func host<V: View>(_ view: V, localization: Localization) throws -> NSView {
        let host = NSHostingView(rootView: view.frame(width: 302).environmentObject(localization))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func sliders(in root: NSView) -> [NSSlider] {
        (root as? NSSlider).map { [$0] } ?? root.subviews.flatMap { sliders(in: $0) }
    }
}
