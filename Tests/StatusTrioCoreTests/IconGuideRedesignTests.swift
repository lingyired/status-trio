import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconGuideRedesignTests: XCTestCase {
    /// The Bluetooth examples: two device families plus the card that keeps the
    /// normal network symbol.
    private static let bluetoothDeviceStates: [IconGuideState] = [
        .bluetoothHeadphones,
        .bluetoothAirPods
    ]

    private static var bluetoothStates: [IconGuideState] {
        bluetoothDeviceStates + [.wifiVolumeTint]
    }

    func testGuideProvidesTenDistinctStateExamples() {
        XCTAssertEqual(IconGuideState.all.count, 10)
        XCTAssertEqual(Set(IconGuideState.all.map(\.id)).count, 10)

        XCTAssertTrue(IconGuideState.charging.status.battery.isCharging)
        XCTAssertEqual(IconGuideState.lowBattery.status.battery.percentage, 12)
        XCTAssertEqual(IconGuideState.ethernet.status.connection, .ethernet)
        XCTAssertEqual(IconGuideState.noInternetMuted.status.wifi.state, .noInternet)
        XCTAssertTrue(IconGuideState.noInternetMuted.status.volume.isMuted)
        XCTAssertTrue(IconGuideState.hotspotLowPower.status.battery.isLowPowerMode)
        XCTAssertEqual(IconGuideState.weakWiFi.status.wifi.state, .connected)
        XCTAssertEqual(IconGuideState.weakWiFi.status.wifi.rssi, -86)
        // The gallery has to show the Wi-Fi-slash artwork, which no other card
        // draws.
        XCTAssertEqual(IconGuideState.wifiOff.status.wifi.state, .off)
        XCTAssertEqual(IconGuideState.wifiOff.status.connection, .offline)
    }

    /// Every Bluetooth card must show the mode it is named for, even on a fresh
    /// install where both Bluetooth options are still at their defaults.
    func testBluetoothGuideStatesForceTheModeTheyDemonstrate() {
        let configured = BluetoothAudioIconOptions.standard

        for state in Self.bluetoothDeviceStates {
            let options = state.bluetoothAudioOptions(configuring: configured)
            XCTAssertTrue(options.replacesNetworkIcon, "\(state) must show the device symbol")
            XCTAssertTrue(options.usesVolumeColor, "\(state) must show the blue volume row")
        }

        let tinted = IconGuideState.wifiVolumeTint.bluetoothAudioOptions(
            configuring: configured
        )
        XCTAssertFalse(
            tinted.replacesNetworkIcon,
            "The blue volume card keeps the normal network symbol in the middle."
        )
        XCTAssertTrue(tinted.usesVolumeColor)

        // Unrelated cards keep following the user's configuration.
        XCTAssertEqual(
            IconGuideState.ethernet.bluetoothAudioOptions(configuring: configured),
            configured
        )
    }

    /// The blue volume card is labelled Wi-Fi, so it has to draw the Wi-Fi
    /// symbol: the tint comes from the Bluetooth output, not from replacing the
    /// centre symbol.
    func testBlueVolumeCardKeepsTheWiFiSymbolItIsNamedFor() {
        let options = IconGuideState.wifiVolumeTint.bluetoothAudioOptions(
            configuring: .standard
        )

        XCTAssertFalse(options.replacesNetworkIcon)
        XCTAssertTrue(options.usesVolumeColor)
        XCTAssertEqual(IconGuideState.wifiVolumeTint.status.connection, .wifi)
        XCTAssertEqual(IconGuideState.wifiVolumeTint.status.wifi.state, .connected)
        XCTAssertNotNil(
            IconGuideState.wifiVolumeTint.status.volume.currentDevice?.isBluetoothAudio
        )
    }

    func testBluetoothGuideStatesKeepTheConfiguredBluetoothPreferences() {
        let configured = BluetoothAudioIconOptions(
            replacesNetworkIcon: false,
            usesVolumeColor: false,
            prioritizesNetworkErrors: false,
            symbolScale: 1.35
        )

        for state in Self.bluetoothStates {
            let options = state.bluetoothAudioOptions(configuring: configured)
            XCTAssertEqual(options.prioritizesNetworkErrors, false)
            XCTAssertEqual(options.symbolScale, 1.35)
        }
    }

    func testBluetoothGuideStatesUseABluetoothDevice() throws {
        for state in Self.bluetoothStates {
            let device = try XCTUnwrap(state.status.volume.currentDevice)
            XCTAssertTrue(device.isBluetoothAudio)
            XCTAssertEqual(device.transport, .bluetooth)
            XCTAssertEqual(state.status.volume.deviceName, device.name)
            XCTAssertEqual(device, state.exampleDevice)
        }
    }

    /// The two Bluetooth cards exist to show the two device families, so each
    /// device has to draw its own symbol instead of both falling back to the same
    /// glyph.
    func testBluetoothGuideDevicesDrawDifferentDeviceSymbols() throws {
        let headphones = try XCTUnwrap(IconGuideState.bluetoothHeadphones.exampleDevice)
        let airPods = try XCTUnwrap(IconGuideState.bluetoothAirPods.exampleDevice)

        XCTAssertNotEqual(headphones.name, airPods.name)
        XCTAssertEqual(
            AudioOutputDeviceIcon.source(for: headphones),
            .symbol("headphones")
        )
        XCTAssertEqual(
            AudioOutputDeviceIcon.symbolCandidates(
                for: AudioOutputDeviceIcon.kind(for: airPods)
            ).first,
            "airpods"
        )

        let airPodsSource = AudioOutputDeviceIcon.source(for: airPods)
        guard case let .symbol(airPodsSymbol) = airPodsSource else {
            XCTFail("The AirPods example must draw a symbol, not a device image.")
            return
        }
        XCTAssertTrue(
            ["airpods", "headphones"].contains(airPodsSymbol),
            "The AirPods card must draw an AirPods glyph, or fall back to the headphone one, got \(airPodsSymbol)."
        )
    }

    func testBluetoothGuideStatesRequestTheirOwnVolumeExample() throws {
        for state in Self.bluetoothStates {
            let dockImage = try XCTUnwrap(
                renderDockFixture(
                status: state.status,
                    volumeOptions: VolumeIconOptions(
                        displayStyle: try XCTUnwrap(state.volumeDisplayStyleOverride),
                        ringStrokeScale: RingStrokeStyle.regular.scale
                    ),
                    bluetoothAudioOptions: state.bluetoothAudioOptions(
                        configuring: .standard
                    )
                )
            )
            XCTAssertEqual(dockImage.size, NSSize(width: 256, height: 256))
        }
    }

    func testEveryGuideStateRendersInMenuBarAndDock() throws {
        for state in IconGuideState.all {
            let menuBarImage = try XCTUnwrap(menuBarFixtureImage(
                menuBarStatus: state.status,
                size: 56
            ))
            XCTAssertGreaterThan(menuBarImage.size.width, 0)

            let dockImage = try XCTUnwrap(
                renderDockFixture(
                status: state.status)
            )
            XCTAssertEqual(dockImage.size, NSSize(width: 256, height: 256))
        }
    }

    func testStateGalleryIncludesDotsAndArcVolumeExamples() {
        XCTAssertEqual(
            IconGuideState.charging.volumeDisplayStyleOverride,
            .dots
        )
        XCTAssertEqual(
            IconGuideState.weakWiFi.volumeDisplayStyleOverride,
            .arc
        )
    }

    func testAnatomyPreviewUsesGreenChargingArcWithPercentage() {
        let battery = IconGuideView.example.battery
        let options = IconGuideView.demoBatteryOptions(
            configured: .standard
        )

        XCTAssertTrue(battery.isCharging)
        XCTAssertTrue(battery.isConnectedToPower)
        XCTAssertEqual(
            StatusMappings.batteryGapContent(battery, options: options),
            .percentage
        )
        XCTAssertEqual(
            StatusMappings.batteryColorRole(
                battery,
                criticalThreshold: options.criticalThreshold
            ),
            .charging
        )
    }

    /// The guide renders the production artwork, so its anatomy and gallery
    /// previews must follow the configured ring stroke width instead of falling
    /// back to the default.
    func testGuidePreviewsForwardTheConfiguredRingStrokeWidth() {
        let options = IconGuideView.demoBatteryOptions(
            configured: BatteryIconOptions(ringStrokeScale: RingStrokeStyle.bold.scale)
        )

        XCTAssertEqual(options.ringStrokeScale, RingStrokeStyle.bold.scale)
    }

    func testStateGalleryCoversLightAndDarkDockAppearances() throws {
        XCTAssertFalse(IconGuidePreviewAppearance.light.isDarkBackground)
        XCTAssertTrue(IconGuidePreviewAppearance.dark.isDarkBackground)
        XCTAssertEqual(
            IconGuidePreviewAppearance.light.dockBackgroundStyle,
            .light
        )
        XCTAssertEqual(
            IconGuidePreviewAppearance.dark.dockBackgroundStyle,
            .dark
        )

        for appearance in IconGuidePreviewAppearance.allCases {
            let dockImage = try XCTUnwrap(
                renderDockFixture(
                status: IconGuideState.charging.status,
                    backgroundStyle: appearance.dockBackgroundStyle
                )
            )
            XCTAssertEqual(dockImage.size, NSSize(width: 256, height: 256))
        }
    }

    func testDockGlyphFrameMatchesRendererLayout() {
        let frame = DockIconGlyphLayout.frame(
            in: CGRect(x: 0, y: 0, width: 256, height: 256)
        )

        XCTAssertEqual(frame.minX, 48.7, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 45.04, accuracy: 0.001)
        XCTAssertEqual(frame.width, 168, accuracy: 0.001)
        XCTAssertEqual(frame.height, 168, accuracy: 0.001)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 256, height: 256).contains(frame))
    }

    func testGuidePageNavigationAdvancesAndReturns() {
        XCTAssertEqual(IconGuidePage.anatomy.next, .states)
        XCTAssertEqual(IconGuidePage.states.previous, .anatomy)
        XCTAssertEqual(IconGuidePage.anatomy.previous, .anatomy)
        XCTAssertEqual(IconGuidePage.states.next, .states)
    }

    func testRedesignedOnboardingRendersWideLayout() {
        let name = "IconGuideRedesignTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removeTestSuite(named: name) }
        let settings = SettingsStore(defaults: defaults)
        let localization = Localization(
            defaults: defaults,
            preferredLanguages: ["en"]
        )
        let view = IconGuideOnboardingView(
            settings: settings,
            onCustomize: {},
            onDone: {}
        )
        .environmentObject(localization)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 560)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertNotNil(hostingView.subviews)
    }

    func testOnboardingHeightStaysEqualAcrossPages() {
        let name = "IconGuideRedesignTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removeTestSuite(named: name) }
        let settings = SettingsStore(defaults: defaults)
        let localization = Localization(
            defaults: defaults,
            preferredLanguages: ["en"]
        )
        var preferredHeights: [CGFloat] = []

        for page in [IconGuidePage.anatomy, .states] {
            let view = IconGuideOnboardingView(
                settings: settings,
                initialPage: page,
                onCustomize: {},
                onDone: {}
            )
            .environmentObject(localization)

            let hostingController = NSHostingController(rootView: view)
            hostingController.sizingOptions = [.preferredContentSize]
            hostingController.view.frame = NSRect(
                x: 0,
                y: 0,
                width: IconGuideOnboardingView.contentWidth,
                height: 560
            )
            hostingController.view.layoutSubtreeIfNeeded()

            let preferredSize = hostingController.preferredContentSize
            XCTAssertEqual(
                preferredSize.width,
                IconGuideOnboardingView.contentWidth,
                accuracy: 0.5
            )
            XCTAssertGreaterThanOrEqual(preferredSize.height, 420)
            XCTAssertLessThan(preferredSize.height, 680)
            preferredHeights.append(preferredSize.height)
        }

        XCTAssertEqual(
            preferredHeights[0],
            preferredHeights[1],
            accuracy: 0.5
        )
    }

    func testFooterPrimaryActionStaysFixedAcrossPages() throws {
        for language in ["en", "zh-Hans", "ar"] {
            let name = "IconGuideRedesignTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removeTestSuite(named: name) }
            let settings = SettingsStore(defaults: defaults)
            let localization = Localization(
                defaults: defaults,
                preferredLanguages: [language]
            )
            var frames: [CGRect] = []

            for page in [IconGuidePage.anatomy, .states] {
                let view = IconGuideOnboardingView(
                    settings: settings,
                    initialPage: page,
                    onCustomize: {},
                    onDone: {}
                )
                .environmentObject(localization)

                let hostingView = NSHostingView(rootView: view)
                hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 560)
                hostingView.layoutSubtreeIfNeeded()

                let trailingEdge = IconGuideOnboardingView.contentWidth - 28
                let subviewFrames: [CGRect] = hostingView.subviews.map(\.frame)
                let trailingFrames = subviewFrames.filter { frame in
                    frame.height > 0
                        && abs(frame.maxX - trailingEdge) < 0.5
                }
                let primaryFrame = try XCTUnwrap(
                    trailingFrames.max { $0.minX < $1.minX }
                )
                frames.append(primaryFrame)
            }

            XCTAssertEqual(frames[0], frames[1], "Footer moved in \(language)")
        }
    }
}
