import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// Offscreen captures of the shipping views with synthetic, injected data.
/// Hidden backing windows supply Retina scale, but no window is ordered,
/// no real controller is installed, and no input is sent.
@MainActor
final class PanelSliderScreenshotsTests: XCTestCase {
    private var hiddenWindows: [NSWindow] = []

    func testAudioPanelFixturesKeepBothNativeSlidersAndAvailableDeviceLists() throws {
        defer { closeHiddenWindows() }
        let localization = try makeLocalization()
        for dark in [false, true] {
            for mode in AudioMode.allCases {
                let output = outputState(mode, localization: localization)
                let input = inputState(mode, localization: localization)
                XCTAssertEqual(output.rows.count, 3)
                XCTAssertEqual(input.rows.count, 3)
                XCTAssertEqual(output.rows.filter(\.selected).count, 1)
                XCTAssertEqual(input.rows.filter(\.selected).count, 1)
                XCTAssertEqual(output.canAdjust, mode != .unavailable)
                XCTAssertEqual(input.canAdjust, mode != .unavailable)
                let host = makeHost(audioPanel(output: output, input: input), dark: dark,
                                    localization: localization)
                let sliders = nativeSliders(in: host)
                XCTAssertEqual(sliders.count, 2)
                XCTAssertEqual(host.bounds.width, 330, accuracy: 0.1)
                XCTAssertGreaterThan(host.bounds.height, 280)
                XCTAssertLessThan(host.bounds.height, 450)
                for slider in sliders {
                    XCTAssertEqual(slider.isEnabled, mode != .unavailable)
                    XCTAssertGreaterThan(slider.bounds.width, 100)
                }
                if mode != .unavailable {
                    XCTAssertEqual(sliders[0].doubleValue, 0.52, accuracy: 0.001)
                    XCTAssertEqual(sliders[1].doubleValue, 0.65, accuracy: 0.001)
                }
                try capture(host, name: "audio-\(mode.rawValue)-\(dark ? "dark" : "light")")
            }
        }
    }

    func testDetailChildFixturesUseShippingBatteryAndInputSourceViews() throws {
        defer { closeHiddenWindows() }
        let localization = try makeLocalization()
        let detail = PanelDetailState(title: "Battery", rows: [
            detailRow("charge", "Charge", "72%"),
            detailRow("condition", "Condition", "Normal"),
            detailRow("capacity", "Maximum capacity", "94%"),
            detailRow("cycles", "Cycle count", "128"),
            detailRow("power", "Power source", "Battery")
        ], isLoading: false, errorText: nil, explanation: nil)
        let sources = InputSourcePanelState(
            title: "Input Source", currentName: "ABC", rows: [
                .init(id: "fixture.abc", name: "ABC", iconURL: nil, marker: "A", isCurrent: true),
                .init(id: "fixture.pinyin", name: "Pinyin - Simplified", iconURL: nil, marker: "简", isCurrent: false),
                .init(id: "fixture.japanese", name: "Japanese - Romaji", iconURL: nil, marker: "あ", isCurrent: false)
            ], emptyMessage: nil, failureText: nil, openSettingsLabel: "Keyboard Settings…"
        )
        for dark in [false, true] {
            let battery = makeHost(BatteryDetailsView(
                state: detail, onBack: {}, onOpenBatterySettings: {},
                onCopyValue: { _ in }, onAppear: {}
            ).environment(\.isCascadingSubmenu, true)
                .environment(\.statusPanelManagesScrolling, true)
                .padding(14).frame(width: 330), dark: dark, localization: localization)
            let input = makeHost(InputSourceListView(
                state: sources, onBack: {}, onSelect: { _ in }, onOpenKeyboardSettings: {}
            ).environment(\.isCascadingSubmenu, true)
                .environment(\.statusPanelManagesScrolling, true)
                .padding(14).frame(width: 330), dark: dark, localization: localization)
            for (name, host) in [("battery-child", battery), ("input-source-child", input)] {
                XCTAssertEqual(host.bounds.width, 330, accuracy: 0.1)
                XCTAssertGreaterThan(host.bounds.height, 100)
                XCTAssertLessThan(host.bounds.height, 450)
                try capture(host, name: "\(name)-\(dark ? "dark" : "light")")
            }
        }
    }

    private enum AudioMode: String, CaseIterable {
        case available, muted, unavailable
    }

    private func audioPanel(output: VolumePanelState, input: AudioInputPanelState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sound output").font(.headline)
            VolumeControlsView(state: output, actions: StatusPanelActions(),
                               scrollTargets: PopoverScrollTargets(), onOpenSoundSettings: {})
            Divider()
            Text("Microphone input").font(.headline)
            AudioInputControlsView(state: input, actions: StatusPanelActions(),
                                   scrollTargets: PopoverScrollTargets(), onOpenSoundSettings: {})
        }
        .padding(14)
        .frame(width: 330)
    }

    private func outputState(_ mode: AudioMode, localization: Localization) -> VolumePanelState {
        let scalar: Double? = mode == .unavailable ? nil : 0.52
        let devices = [
            AudioOutputDevice(id: 101, name: "MacBook Pro Speakers", uid: "fixture.speakers",
                              isCurrent: true, volume: scalar, transport: .builtIn),
            AudioOutputDevice(id: 102, name: "Studio AirPods Pro", uid: "fixture.airpods",
                              isCurrent: false, transport: .bluetooth),
            AudioOutputDevice(id: 103, name: "Dell U2723QE", uid: "fixture.display",
                              isCurrent: false, transport: .hdmi)
        ]
        return AudioPanelMapper.volume(VolumeStatus(
            scalar: scalar, isMuted: mode == .muted, deviceName: devices[0].name,
            currentDevice: devices[0], outputDevices: devices,
            canSetVolume: mode != .unavailable, canMute: mode != .unavailable
        ), controllerAvailable: true, deviceList: .init(visibleLimit: nil), localization: localization)
    }

    private func inputState(_ mode: AudioMode, localization: Localization) -> AudioInputPanelState {
        AudioPanelMapper.input(AudioInputStatus(
            devices: [
                AudioInputDevice(id: 201, uid: "fixture.builtin-mic", name: "MacBook Pro Microphone"),
                AudioInputDevice(id: 202, uid: "fixture.usb-mic", name: "USB Studio Microphone"),
                AudioInputDevice(id: 203, uid: "fixture.airpods-mic", name: "Studio AirPods Pro")
            ], defaultDeviceID: 201, deviceName: "MacBook Pro Microphone",
            scalar: mode == .unavailable ? nil : 0.65, canSetVolume: mode != .unavailable,
            muteState: mode == .muted ? .muted : .unmuted, canSetMute: mode != .unavailable,
            isRefreshing: false, isBusy: false, error: nil
        ), localization: localization)
    }

    private func detailRow(_ id: String, _ label: String, _ value: String) -> PanelDetailRow {
        PanelDetailRow(id: id, label: label, value: value, accessibilityValue: value, tint: .primary)
    }

    private func makeLocalization() throws -> Localization {
        let suite = "PanelSliderScreenshotsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        return Localization(defaults: defaults, preferredLanguages: ["en"])
    }

    private func makeHost<V: View>(_ view: V, dark: Bool, localization: Localization) -> NSView {
        let host = NSHostingView(rootView: view
            .background(Color(nsColor: .windowBackgroundColor))
            .environmentObject(localization)
            .environment(\.colorScheme, dark ? .dark : .light)
            .transaction { $0.animation = nil; $0.disablesAnimations = true })
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = host.appearance
        window.contentView = host
        hiddenWindows = hiddenWindows + [window]
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func closeHiddenWindows() {
        for window in hiddenWindows {
            window.contentView = nil
            window.close()
        }
        hiddenWindows = []
    }

    private func nativeSliders(in root: NSView) -> [NSSlider] {
        (root as? NSSlider).map { [$0] } ?? root.subviews.flatMap { nativeSliders(in: $0) }
    }

    private func capture(_ view: NSView, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["STATUS_TRIO_PR_SCREENSHOTS_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
        let geometry = "points=\(NSStringFromRect(view.bounds)) pixels=\(bitmap.pixelsWide)x\(bitmap.pixelsHigh)\n"
        try geometry.write(to: directory.appendingPathComponent("\(name).geometry.txt"),
                           atomically: true, encoding: .utf8)
    }
}
