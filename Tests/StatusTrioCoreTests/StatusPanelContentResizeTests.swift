import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// Regression coverage for the detail-page resize jump: the panel grows and
/// shrinks with its content, but the edge attached to the menu bar must stay
/// put. On macOS 26+ the Liquid Glass background used to take the SwiftUI
/// hosting view's intrinsic size as its own and resize/reposition the window,
/// which pushed the panel off the top of the screen when a detail page made it
/// taller.
@MainActor
final class StatusPanelContentResizeTests: VisibleUITestCase {
    func testOpeningAndLeavingADetailPageKeepsTheMenuBarAnchoredEdgeFixed() throws {
        let suiteName = "StatusTrioCoreTests.StatusPanelContentResize.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removeTestSuite(named: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let store = SystemStatusStore(
            batteryMonitor: ResizeProbeBatteryMonitor(),
            wifiMonitor: ResizeProbeWiFiMonitor(),
            volumeMonitor: ResizeProbeVolumeMonitor(),
            initialSnapshot: StatusSnapshot(
                battery: BatteryStatus(
                    rawPercentage: 70,
                    isPresent: true,
                    isCharging: false,
                    isLowPowerMode: false,
                    isConnectedToPower: true
                ),
                wifi: .placeholder,
                volume: .placeholder
            )
        )
        let panelModel = StatusPanelViewModel(
            store: store,
            settings: settings,
            localization: localization,
            actions: StatusPanelActions(store: store, settings: settings)
        )
        let host = StatusPanelHostingController(
            rootView: StatusPopoverView(
                panel: panelModel,
                scrollTargets: PopoverScrollTargets(),
                layoutMetrics: StatusPanelLayoutMetrics(),
                requestWiFiNameAccess: {},
                requestBluetoothAuthorization: {},
                openBatterySettings: {},
                openAppBatterySettings: {},
                openWiFiSettings: {},
                openNetworkSettings: {},
                openSharingSettings: {},
                openLocationSettings: {},
                openBluetoothSettings: {},
                openBluetoothPermissionSettings: {},
                openSettings: {},
                openSoundSettings: {},
                openSoundInputSettings: {},
                openKeyboardSettings: {},
                quit: {}
            ).environmentObject(localization)
        )
        let panel = AnchoredStatusPanel()
        panel.installContent(host, backgroundStyle: .solid)

        let screenFrame = NSScreen.main?.frame
            ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let anchorWindow = NSWindow(
            contentRect: NSRect(
                x: screenFrame.midX,
                y: screenFrame.maxY - 60,
                width: 24,
                height: 30
            ),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let anchorView = NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 30))
        anchorWindow.contentView?.addSubview(anchorView)
        anchorWindow.orderFront(nil)
        defer {
            panel.performClose(nil)
            anchorWindow.orderOut(nil)
        }

        panel.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        settle(host)
        let summary = panel.frame
        XCTAssertGreaterThan(summary.height, 0)

        panelModel.showWiFiPage(showsDetailsInitially: false)
        settle(host)
        let detail = panel.frame
        XCTAssertEqual(
            detail.maxY,
            summary.maxY,
            accuracy: 0.5,
            "opening a detail page must keep the menu-bar edge fixed"
        )
        XCTAssertEqual(
            detail.minX,
            summary.minX,
            accuracy: 0.5,
            "opening a detail page must not move the panel sideways"
        )

        panelModel.showSummaryPage()
        settle(host)
        let returnedFromWiFi = panel.frame
        XCTAssertEqual(
            returnedFromWiFi.maxY,
            summary.maxY,
            accuracy: 0.5,
            "leaving a detail page must keep the menu-bar edge fixed"
        )
        XCTAssertEqual(
            returnedFromWiFi.minX,
            summary.minX,
            accuracy: 0.5,
            "leaving a detail page must not move the panel sideways"
        )
        XCTAssertEqual(
            returnedFromWiFi.height,
            summary.height,
            accuracy: 1.5,
            "the summary page must return to its original height"
        )

        panelModel.showBatteryPage()
        settle(host)
        let battery = panel.frame
        XCTAssertEqual(
            battery.maxY,
            summary.maxY,
            accuracy: 0.5,
            "opening the battery detail page must keep the menu-bar edge fixed"
        )

        panelModel.showSummaryPage()
        settle(host)
        let returnedFromBattery = panel.frame
        XCTAssertEqual(
            returnedFromBattery.maxY,
            summary.maxY,
            accuracy: 0.5,
            "leaving the battery detail page must keep the menu-bar edge fixed"
        )
        XCTAssertEqual(
            returnedFromBattery.height,
            summary.height,
            accuracy: 1.5,
            "the summary page must return to its original height after the battery page"
        )
    }

    private func settle<Content: View>(_ host: StatusPanelHostingController<Content>) {
        for _ in 0..<12 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            // Let AppKit and SwiftUI deliver their normal layout callbacks.
            // Calling viewDidLayout manually here hid production regressions.
        }
    }
}

@MainActor
private final class ResizeProbeBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class ResizeProbeWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class ResizeProbeVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    let betterDisplayCatalogUpdates: AsyncStream<BetterDisplayCatalogUpdate>
    init() {
        (updates, _) = AsyncStream.makeStream()
        (betterDisplayCatalogUpdates, _) = AsyncStream.makeStream()
    }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
