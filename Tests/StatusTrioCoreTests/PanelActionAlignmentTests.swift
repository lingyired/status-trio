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
        let actions = probe.trailingGlyphRects(count: 2, minimumX: 200)
        XCTAssertEqual(actions.count, 2, "volume mute and Settings glyphs must render")
        guard actions.count == 2 else { return }

        let rowCenter = try XCTUnwrap(
            probe.subviewCenterY(where: { $0 is NSSlider }),
            "the volume row must render an AppKit slider to align its glyphs against"
        )
        for (name, rect) in zip(["mute", "settings"], actions) {
            let center = try XCTUnwrap(probe.glyphCenterY(in: rect))
            XCTAssertEqual(
                center,
                rowCenter,
                accuracy: 1,
                "\(name) center must match the volume slider's rendered center"
            )
        }
    }

    func testBrightnessRowCentersPercentageAndGearWithTheSlider() throws {
        let state = BrightnessPanelState(rows: [
            BrightnessRowState(
                id: "display",
                name: "Studio Display",
                isBuiltin: false,
                scalar: 0.5,
                canAdjust: true,
                backend: .directDDC,
                source: .directDDC,
                percentageText: "50%",
                accessibilityLabel: "Studio Display brightness",
                unavailableText: nil
            )
        ])
        let probe = try render(
            BrightnessControlsView(
                state: state,
                actions: StatusPanelActions(),
                scrollTargets: PopoverScrollTargets(),
                onOpenDisplaySettings: {}
            )
        )
        let actions = probe.trailingGlyphRects(count: 2, minimumX: 200)
        XCTAssertEqual(actions.count, 2, "brightness row must render its percentage and gear")
        guard actions.count == 2 else { return }

        let rowCenter = probe.controlRowCenterY(excluding: actions)
        for (name, rect) in zip(["percentage", "gear"], actions) {
            let center = try XCTUnwrap(probe.glyphCenterY(in: rect))
            XCTAssertEqual(
                center,
                try XCTUnwrap(rowCenter),
                accuracy: 1,
                "\(name) center must match the brightness row's rendered center"
            )
        }
    }

    func testAudioInputControlsCenterMuteAndSettingsWithTheSliderRow() throws {
        let state = try makeAudioInputState(showsDeviceList: false)
        let probe = try render(
            AudioInputControlsView(
                state: state,
                actions: StatusPanelActions(),
                scrollTargets: PopoverScrollTargets(),
                onOpenSoundSettings: {}
            )
        )
        let actions = probe.trailingGlyphRects(count: 2, minimumX: 200, maxX: 340)
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

    func testVolumeMicBrightnessSlidersShareTheSameLeadingSlotX() throws {
        let volumeProbe = try render(
            VolumeControlsView(
                state: try makeVolumeState(),
                actions: StatusPanelActions(),
                scrollTargets: PopoverScrollTargets(),
                onOpenSoundSettings: {}
            )
        )
        let micProbe = try render(
            AudioInputControlsView(
                state: try makeAudioInputState(showsDeviceList: false),
                actions: StatusPanelActions(),
                scrollTargets: PopoverScrollTargets(),
                onOpenSoundSettings: {}
            )
        )
        let brightnessProbe = try render(
            BrightnessControlsView(
                state: BrightnessPanelState(rows: [
                    BrightnessRowState(
                        id: "display",
                        name: "Studio Display",
                        isBuiltin: false,
                        scalar: 0.5,
                        canAdjust: true,
                        backend: .directDDC,
                        source: .directDDC,
                        percentageText: "50%",
                        accessibilityLabel: "Studio Display brightness",
                        unavailableText: nil
                    )
                ]),
                actions: StatusPanelActions(),
                scrollTargets: PopoverScrollTargets(),
                onOpenDisplaySettings: {}
            )
        )

        let xSources: [(String, CGFloat?)] = [
            ("volume", volumeProbe.subviewFrame(where: { $0 is NSSlider })?.minX),
            ("mic", micProbe.subviewFrame(where: { $0 is NSSlider })?.minX),
            ("brightness", brightnessProbe.subviewFrame(where: { $0 is NSSlider })?.minX)
        ]
        let sliders = xSources.compactMap { $0.1 }
        XCTAssertEqual(sliders.count, 3, "all three rows must render an NSSlider")
        guard sliders.count == 3 else { return }
        let reference = try XCTUnwrap(sliders.first)
        for (name, x) in xSources {
            XCTAssertNotNil(x, "\(name) slider must have a measurable leading x")
            if let x {
                XCTAssertEqual(
                    x,
                    reference,
                    accuracy: 0.5,
                    "\(name) slider must start on the same x as the volume slider"
                )
            }
        }
    }

    /// Issue #314: the trailing action cluster has to stay on shared columns
    /// even when one row shows the optional power button and another does not.
    /// Rows are right-anchored, so the gear and the chevron must keep the same
    /// horizontal centre whether or not the power button is present.
    func testWiFiTrailingColumnsStayAlignedWhenPowerButtonIsOptional() throws {
        let withPower = try render(makeNetworkRow(showsPower: true))
        let withoutPower = try render(makeNetworkRow(showsPower: false))

        let powered = withPower.trailingGlyphRects(count: 3, minimumX: 150)
        let unpowered = withoutPower.trailingGlyphRects(count: 2, minimumX: 150)
        XCTAssertEqual(powered.count, 3, "Wi-Fi row with power must draw power, chevron and Settings")
        XCTAssertEqual(unpowered.count, 2, "the row without power must draw chevron and Settings")
        guard powered.count == 3, unpowered.count == 2 else { return }

        // Right to left the two rows share the gear and chevron columns.
        XCTAssertEqual(
            powered[2].midX, unpowered[1].midX, accuracy: 0.5,
            "the gear must stay in the same column when the power button is removed"
        )
        XCTAssertEqual(
            powered[1].midX, unpowered[0].midX, accuracy: 0.5,
            "the chevron must stay in the same column when the power button is removed"
        )
    }

    private func makeNetworkRow(showsPower: Bool) -> NetworkStatusView {
        NetworkStatusView(
            showsWiFiPowerControl: showsPower,
            wifiPowerIsOn: true,
            wifiPowerCanSet: true,
            wifiPowerRequiresConfirmation: false,
            wifiPowerFailed: false,
            state: PanelSummaryState(
                title: "Example Network",
                subtitle: "192.168.1.20 · 5 GHz",
                measurements: nil,
                symbol: .symbol(name: "wifi", variableValue: nil, fallback: nil),
                tint: .secondary,
                accessibilityLabel: "Network",
                accessibilityValue: "Connected",
                showsSettings: true,
                intent: .wifiDetails
            ),
            onOpenWiFiDetails: { _ in },
            onOpenWiredDetails: {},
            onRequestNameAccess: {},
            onOpenWiFiSettings: {},
            onOpenNetworkSettings: {},
            onOpenLocationSettings: {}
        )
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
        )
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        return try XCTUnwrap(SummaryActionAlignmentProbe(hosting))
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
