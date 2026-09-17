import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconGuideRedesignTests: XCTestCase {
    func testGuideProvidesSixDistinctStateExamples() {
        XCTAssertEqual(IconGuideState.all.count, 6)
        XCTAssertEqual(Set(IconGuideState.all.map(\.id)).count, 6)

        XCTAssertTrue(IconGuideState.charging.status.battery.isCharging)
        XCTAssertEqual(IconGuideState.lowBattery.status.battery.percentage, 12)
        XCTAssertEqual(IconGuideState.ethernet.status.connection, .ethernet)
        XCTAssertEqual(IconGuideState.noInternetMuted.status.wifi.state, .noInternet)
        XCTAssertTrue(IconGuideState.noInternetMuted.status.volume.isMuted)
        XCTAssertTrue(IconGuideState.hotspotLowPower.status.battery.isLowPowerMode)
        XCTAssertEqual(IconGuideState.weakWiFi.status.wifi.state, .connected)
        XCTAssertEqual(IconGuideState.weakWiFi.status.wifi.rssi, -86)
    }

    func testEveryGuideStateRendersInMenuBarAndDock() throws {
        for state in IconGuideState.all {
            let menuBarImage = StatusIconRenderer.image(
                menuBarStatus: state.status,
                size: 56
            )
            XCTAssertGreaterThan(menuBarImage.size.width, 0)

            let dockImage = try XCTUnwrap(
                DockIconRenderer.image(status: state.status)
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

    func testStateGalleryCoversLightAndDarkMenuBarAndDockAppearances() throws {
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
            let menuBarImage = StatusIconRenderer.image(
                menuBarStatus: IconGuideState.charging.status,
                size: 40,
                appearance: NSAppearance(
                    named: appearance.isDarkBackground ? .darkAqua : .aqua
                )
            )
            XCTAssertGreaterThan(menuBarImage.size.width, 0)

            let dockImage = try XCTUnwrap(
                DockIconRenderer.image(
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
        defer { defaults.removePersistentDomain(forName: name) }
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
}
