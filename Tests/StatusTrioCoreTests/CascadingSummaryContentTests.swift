import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class CascadingSummaryContentTests: XCTestCase {
    func testOpeningEachDetailKeepsMainVolumeControlInPlace() throws {
        let fixture = PanelStoreFixture()
        for section in PopupSection.allCases {
            fixture.settings.setPopupSection(section, enabled: [.battery, .network, .volume, .inputSource].contains(section))
        }
        let panel = fixture.makePanel()
        panel.start()
        defer { panel.showSummaryPage(); panel.stop() }
        let host = NSHostingView(rootView: makeView(panel: panel).environmentObject(fixture.localization))
        host.frame = NSRect(x: 0, y: 0, width: 330, height: 600)
        host.layoutSubtreeIfNeeded()
        let originalCount = nativeSliders(in: host).count
        XCTAssertEqual(originalCount, 1)

        for open in [
            { panel.showBatteryPage() },
            { panel.showWiFiPage(showsDetailsInitially: false) },
            { panel.showWiredPage() },
            { panel.showInputSourcePage() }
        ] {
            open()
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(nativeSliders(in: host).count, originalCount,
                           "a detail child must not replace the main controls")
            panel.showSummaryPage()
            host.layoutSubtreeIfNeeded()
        }
    }

    private func makeView(panel: StatusPanelViewModel) -> StatusPopoverView {
        StatusPopoverView(
            panel: panel, scrollTargets: PopoverScrollTargets(), layoutMetrics: StatusPanelLayoutMetrics(),
            requestWiFiNameAccess: {}, requestBluetoothAuthorization: {},
            openBatterySettings: {}, openAppBatterySettings: {}, openWiFiSettings: {},
            openNetworkSettings: {}, openSharingSettings: {}, openLocationSettings: {},
            openBluetoothSettings: {}, openBluetoothPermissionSettings: {}, openSettings: {},
            openSoundSettings: {}, openSoundInputSettings: {}, openKeyboardSettings: {}, quit: {}
        )
    }

    private func nativeSliders(in root: NSView) -> [NativePanelLevelSliderControl] {
        (root as? NativePanelLevelSliderControl).map { [$0] }
            ?? root.subviews.flatMap { nativeSliders(in: $0) }
    }
}
