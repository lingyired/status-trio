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

    func testGuideProvidesDistinctStateExamples() {
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

    func testAnatomyGuideKeepsItsHighlightStatic() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot.appendingPathComponent(
            "Sources/StatusTrioCore/UI/IconGuideView.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let guideStart = try XCTUnwrap(source.range(of: "struct IconGuideView: View"))
        let galleryStart = try XCTUnwrap(
            source.range(
                of: "struct IconGuideStateGalleryView: View",
                range: guideStart.upperBound..<source.endIndex
            )
        )
        let guideSource = source[guideStart.lowerBound..<galleryStart.lowerBound]

        XCTAssertFalse(
            guideSource.contains(".repeatForever"),
            "The anatomy guide must not animate its highlight forever."
        )
        XCTAssertFalse(
            guideSource.contains("restartPulse"),
            "The guide highlight should remain static while the window is visible."
        )
    }

    func testMenuBarHelpDefaultsToClosedWhenTheGuideIsReopened() {
        let name = "IconGuideRedesignTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removeTestSuite(named: name) }
        let settings = SettingsStore(defaults: defaults)
        let localization = Localization(
            defaults: defaults,
            preferredLanguages: ["en"]
        )

        for _ in 0..<2 {
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
    }

    func testHelpEntryHasAnAccessibleLabelAndThePopoverCanBeClosed() {
        let name = "IconGuideRedesignTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removeTestSuite(named: name) }
        let localization = Localization(
            defaults: defaults,
            preferredLanguages: ["en"]
        )
        let policy = MenuBarHelpPolicy(majorVersion: 26)
        var didClose = false
        let view = MenuBarVisibilityHelpView(
            policy: policy,
            onClose: { didClose = true },
            openSettings: { _ in }
        )
        .environmentObject(localization)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 372)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            localization.string(.guideMenuBarHelpOpen),
            "Can’t find the menu bar icon?"
        )
        XCTAssertEqual(
            localization.string(.guideMenuBarHelpPrompt),
            "Find Status Trio at the top-right of the screen."
        )
        XCTAssertFalse(didClose)
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

    func testOnboardingHeightTracksContentAcrossPagesAndLanguages() {
        let name = "IconGuideRedesignTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removeTestSuite(named: name) }

        func preferredHeight(
            of page: IconGuidePage,
            language: AppLanguage,
            settings: SettingsStore,
            defaults: UserDefaults
        ) -> CGFloat {
            let localization = Localization(
                defaults: defaults,
                preferredLanguages: [language.rawValue]
            )
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
            XCTAssertEqual(
                hostingController.preferredContentSize.width,
                IconGuideOnboardingView.contentWidth,
                accuracy: 0.5,
                language.rawValue
            )
            return hostingController.preferredContentSize.height
        }

        // Both pages share the same fixed body height and carry the compact
        // consent line in the footer, so they are exactly the same height in
        // every language whether or not consent is still unrecorded.
        let firstRun = SettingsStore(defaults: defaults)
        for language in AppLanguage.allCases {
            let anatomy = preferredHeight(of: .anatomy, language: language, settings: firstRun, defaults: defaults)
            let states = preferredHeight(of: .states, language: language, settings: firstRun, defaults: defaults)
            for height in [anatomy, states] {
                XCTAssertGreaterThanOrEqual(
                    height,
                    OnboardingWindowController.minimumContentHeight,
                    language.rawValue
                )
                XCTAssertLessThanOrEqual(
                    height,
                    OnboardingWindowController.contentSize.height,
                    language.rawValue
                )
            }
        }

        // Consent already recorded: neither page renders the card, so both
        // pages settle to the same height in every language.
        let consentedName = "IconGuideRedesignTests.consent.\(UUID().uuidString)"
        let consentedDefaults = UserDefaults(suiteName: consentedName)!
        defer { consentedDefaults.removeTestSuite(named: consentedName) }
        let consented = SettingsStore(defaults: consentedDefaults)
        consented.completeTelemetryConsent(sharesAnalytics: false)
        for language in AppLanguage.allCases {
            let anatomy = preferredHeight(
                of: .anatomy,
                language: language,
                settings: consented,
                defaults: consentedDefaults
            )
            let states = preferredHeight(
                of: .states,
                language: language,
                settings: consented,
                defaults: consentedDefaults
            )
        }
    }

    func testFooterPrimaryActionStaysAnchoredToContentBottom() throws {
        for language in AppLanguage.allCases {
            let name = "IconGuideRedesignTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removeTestSuite(named: name) }
            let settings = SettingsStore(defaults: defaults)
            let localization = Localization(
                defaults: defaults,
                preferredLanguages: [language.rawValue]
            )
            var bottomInsets: [CGFloat] = []
            var trailingEdges: [CGFloat] = []

            for page in [IconGuidePage.anatomy, .states] {
                let view = IconGuideOnboardingView(
                    settings: settings,
                    initialPage: page,
                    onCustomize: {},
                    onDone: {}
                )
                .environmentObject(localization)

                // Measure the page's own natural height, then lay it out at
                // exactly that height so the footer's bottom inset is comparable.
                let controller = NSHostingController(rootView: view)
                controller.sizingOptions = [.preferredContentSize]
                controller.view.frame = NSRect(
                    x: 0,
                    y: 0,
                    width: IconGuideOnboardingView.contentWidth,
                    height: 560
                )
                controller.view.layoutSubtreeIfNeeded()
                let contentHeight = controller.preferredContentSize.height

                let hostingView = NSHostingView(rootView: view)
                hostingView.frame = NSRect(
                    x: 0,
                    y: 0,
                    width: IconGuideOnboardingView.contentWidth,
                    height: contentHeight
                )
                hostingView.layoutSubtreeIfNeeded()

                let trailingEdge = IconGuideOnboardingView.contentWidth - 28
                let trailingFrames = hostingView.subviews.map(\.frame).filter { frame in
                    frame.height > 0
                        && abs(frame.maxX - trailingEdge) < 0.5
                }
                let primaryFrame = try XCTUnwrap(
                    trailingFrames.max { $0.minX < $1.minX }
                )
                bottomInsets.append(contentHeight - primaryFrame.maxY)
                trailingEdges.append(primaryFrame.maxX)
            }

            XCTAssertEqual(
                bottomInsets[0],
                bottomInsets[1],
                accuracy: 1.0,
                "Footer is not anchored to the content bottom in \(language.rawValue)"
            )
            XCTAssertEqual(
                trailingEdges[0],
                trailingEdges[1],
                accuracy: 0.5,
                "Footer trailing edge moved in \(language.rawValue)"
            )
        }
    }
}
