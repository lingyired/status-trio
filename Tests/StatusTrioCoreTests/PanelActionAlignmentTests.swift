import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class PanelActionAlignmentTests: XCTestCase {
    func testVolumeControlsCenterMuteAndSettingsWithTheSliderRow() throws {
        let state = try makeVolumeState()
        let probe = try render(
            VolumeControlsView(
                state: state,
                actions: StatusPanelActions(),
                scrollTargets: PopoverScrollTargets(),
                onOpenSoundSettings: {}
            )
        )
        let actions = probe.leadingAndTrailingGlyphRects(maximumWidth: 24)
        XCTAssertEqual(actions.count, 2, "volume mute and Settings glyphs must render")
        guard actions.count == 2 else { return }

        let rowCenter = try XCTUnwrap(probe.sliderControlCenterY)
        for (name, rect) in zip(["mute", "settings"], actions) {
            let center = try XCTUnwrap(probe.glyphCenterY(in: rect))
            XCTAssertEqual(
                center,
                rowCenter,
                accuracy: 1,
                "\(name) center must match the volume row's rendered center"
            )
        }
    }

    func testAudioInputControlsCenterMuteAndSettingsWithTheSliderRow() throws {
        let state = try makeAudioInputState(showsDeviceList: false)
        let probe = try render(
            AudioInputControlsView(
                state: state,
                actions: StatusPanelActions(),
                onOpenSoundSettings: {}
            )
        )
        // The no-device row below the controls starts inside this x-range. Keep
        // only the narrow action glyphs so the row cannot shadow Mute/Settings.
        let actions = probe.trailingGlyphRects(
            count: 2,
            minimumX: 200,
            maxX: 340,
            maximumWidth: 28
        )
        XCTAssertEqual(actions.count, 2, "input mute and Settings glyphs must render")
        guard actions.count == 2 else { return }

        let rowCenter = probe.controlRowCenterY(excluding: actions)
        for (name, rect) in zip(["mute", "settings"], actions) {
            let center = try XCTUnwrap(probe.glyphCenterY(in: rect))
            XCTAssertEqual(
                center,
                try XCTUnwrap(rowCenter),
                accuracy: 0.5,
                "\(name) center must match the input slider row's rendered center"
            )
        }
    }

    func testNetworkRowsCenterChevronAndSettingsWithTheSummaryContent() throws {
        for intent in [PanelSummaryIntent.wifiDetails, .wiredDetails] {
            let state = PanelSummaryState(
                title: intent == .wiredDetails ? "USB Ethernet" : "Example Network",
                subtitle: "192.168.1.20 · 5 GHz",
                measurements: nil,
                symbol: .symbol(
                    name: intent == .wiredDetails ? "cable.connector" : "wifi",
                    variableValue: nil,
                    fallback: nil
                ),
                tint: .secondary,
                accessibilityLabel: "Network",
                accessibilityValue: "Connected",
                showsSettings: true,
                intent: intent
            )
            let probe = try render(
                NetworkStatusView(
                    state: state,
                    onOpenWiFiDetails: { _ in },
                    onOpenWiredDetails: {},
                    onRequestNameAccess: {},
                    onOpenWiFiSettings: {},
                    onOpenNetworkSettings: {},
                    onOpenLocationSettings: {}
                )
            )
            let actions = probe.trailingGlyphRects(count: 2, minimumX: 200)
            XCTAssertEqual(actions.count, 2, "\(intent) must render chevron and Settings")
            guard actions.count == 2 else { continue }

            let contentCenter = try XCTUnwrap(
                probe.glyphCenterY(
                    from: 14 + PanelSummaryActionMetrics.hitTarget + 10,
                    to: actions[0].minX - 10
                )
            )
            for (name, rect) in zip(["chevron", "settings"], actions) {
                let center = try XCTUnwrap(probe.glyphCenterY(in: rect))
                XCTAssertEqual(
                    center,
                    contentCenter,
                    accuracy: 0.5,
                    "\(intent) \(name) center \(center) must match \(contentCenter)"
                )
            }
        }
    }

    func testInputSourceRowCentersChevronAndSettingsWithTheSummaryContent() throws {
        let state = InputSourcePanelState(
            title: "输入法",
            currentName: "微信输入法",
            rows: [],
            emptyMessage: nil,
            failureText: nil,
            openSettingsLabel: "打开键盘设置"
        )
        let probe = try render(
            InputSourceStatusView(
                state: state,
                onOpen: {},
                onOpenKeyboardSettings: {}
            )
        )
        let actions = probe.trailingGlyphRects(count: 2, minimumX: 200)
        XCTAssertEqual(actions.count, 2, "input source must render chevron and Settings")
        guard actions.count == 2 else { return }

        let contentCenter = try XCTUnwrap(
            probe.glyphCenterY(
                from: 14 + PanelSummaryActionMetrics.hitTarget + 10,
                to: actions[0].minX - 10
            )
        )
        for (name, rect) in zip(["chevron", "settings"], actions) {
            let center = try XCTUnwrap(probe.glyphCenterY(in: rect))
            XCTAssertEqual(
                center,
                contentCenter,
                accuracy: 0.5,
                "\(name) center \(center) must match the two-line content center \(contentCenter)"
            )
        }
    }

    private func render<V: View>(_ view: V) throws -> SummaryActionAlignmentProbe {
        let suite = "StatusTrioCoreTests.PanelActionAlignment.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])

        let hosting = NSHostingView(
            rootView: view
                .padding(14)
                .frame(width: 330)
                .background(Color(white: 0.96))
                .environmentObject(localization)
                .environment(\.colorScheme, .light)
                .environment(\.displayScale, 2)
        )
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        return try XCTUnwrap(SummaryActionAlignmentProbe(hosting, pixelScale: 2))
    }

    private func makeVolumeState() throws -> VolumePanelState {
        let suite = "StatusTrioCoreTests.VolumeActionAlignment.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        return AudioPanelMapper.volume(
            VolumeStatus(
                scalar: 0.4,
                isMuted: false,
                deviceName: "MacBook Pro Speakers",
                outputDevices: [
                    AudioOutputDevice(
                        id: 1,
                        name: "MacBook Pro Speakers",
                        isCurrent: true
                    )
                ]
            ),
            controllerAvailable: true,
            deviceList: AudioOutputListPreferences(visibleLimit: nil),
            localization: localization
        )
    }

    private func makeAudioInputState(showsDeviceList: Bool) throws -> AudioInputPanelState {
        let suite = "StatusTrioCoreTests.AudioInputActionAlignment.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let device = AudioInputDevice(id: 11, uid: "layout-mic", name: "Studio Mic")
        return AudioPanelMapper.input(
            AudioInputStatus(
                devices: showsDeviceList ? [device] : [],
                defaultDeviceID: showsDeviceList ? device.id : nil,
                deviceName: device.name,
                scalar: 0.5,
                canSetVolume: true,
                muteState: .unmuted,
                canSetMute: true,
                isRefreshing: false,
                isBusy: false,
                error: nil
            ),
            localization: localization
        )
    }
}
