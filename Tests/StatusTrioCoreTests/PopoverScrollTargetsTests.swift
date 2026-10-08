import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class PopoverScrollTargetsTests: XCTestCase {
    func testStatusPanelRegistersItsVolumeControlRegion() throws {
        let name = "StatusTrioCoreTests.PopoverScrollTargets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defer { defaults.removeTestSuite(named: name) }

        let window = makeWindow()
        let targets = PopoverScrollTargets()
        let settings = SettingsStore(defaults: defaults)
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let store = SystemStatusStore(
            batteryMonitor: MarkerBatteryMonitor(),
            wifiMonitor: MarkerWiFiMonitor(),
            volumeMonitor: MarkerVolumeMonitor()
        )
        let panel = StatusPanelViewModel(
            store: store,
            settings: settings,
            localization: localization,
            actions: StatusPanelActions(store: store, settings: settings)
        )
        let hostingView = NSHostingView(
            rootView: StatusPopoverView(
                panel: panel,
                scrollTargets: targets,
                requestWiFiNameAccess: {},
                requestBluetoothAuthorization: {},
                openBatterySettings: {},
                openWiFiSettings: {},
                openNetworkSettings: {},
                openLocationSettings: {},
                openBluetoothSettings: {},
                openBluetoothPermissionSettings: {},
                openSettings: {},
                openSoundSettings: {},
                quit: {}
            )
            .environmentObject(localization)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 330, height: 480)
        window.contentView?.addSubview(hostingView)
        hostingView.layoutSubtreeIfNeeded()

        let marker = try XCTUnwrap(scrollTargetView(in: hostingView))
        let center = marker.convert(
            NSPoint(x: marker.bounds.midX, y: marker.bounds.midY),
            to: nil
        )
        XCTAssertGreaterThan(marker.bounds.height, 0)
        XCTAssertTrue(targets.containsVolumeControl(at: center, in: window))
        XCTAssertFalse(
            targets.containsVolumeControl(
                at: NSPoint(x: center.x, y: center.y + 200),
                in: window
            )
        )
    }

    func testRegisteredVolumeControlMatchesPointsInsideItsFrame() {
        let window = makeWindow()
        let targets = PopoverScrollTargets()
        let control = makeControlView(in: window)
        targets.registerVolumeControl(control)

        XCTAssertTrue(
            targets.containsVolumeControl(at: NSPoint(x: 100, y: 70), in: window)
        )
        XCTAssertFalse(
            targets.containsVolumeControl(at: NSPoint(x: 100, y: 20), in: window)
        )
        XCTAssertFalse(
            targets.containsVolumeControl(at: NSPoint(x: 10, y: 70), in: window)
        )
    }

    func testRegionIsEmptyBeforeRegistrationAndAfterRemoval() {
        let window = makeWindow()
        let targets = PopoverScrollTargets()
        let control = makeControlView(in: window)
        let point = NSPoint(x: 100, y: 70)

        XCTAssertFalse(targets.containsVolumeControl(at: point, in: window))

        targets.registerVolumeControl(control)
        XCTAssertTrue(targets.containsVolumeControl(at: point, in: window))

        targets.unregisterVolumeControl(control)
        XCTAssertFalse(targets.containsVolumeControl(at: point, in: window))
    }

    func testStaleRemovalKeepsTheCurrentVolumeControl() {
        let window = makeWindow()
        let targets = PopoverScrollTargets()
        let control = makeControlView(in: window)
        let stale = NSView(frame: control.frame)
        targets.registerVolumeControl(control)

        targets.unregisterVolumeControl(stale)

        XCTAssertTrue(
            targets.containsVolumeControl(at: NSPoint(x: 100, y: 70), in: window)
        )
    }

    func testControlInAnotherWindowNeverMatches() {
        let window = makeWindow()
        let otherWindow = makeWindow()
        let targets = PopoverScrollTargets()
        targets.registerVolumeControl(makeControlView(in: window))

        XCTAssertFalse(
            targets.containsVolumeControl(at: NSPoint(x: 100, y: 70), in: otherWindow)
        )
        XCTAssertFalse(
            targets.containsVolumeControl(at: NSPoint(x: 100, y: 70), in: nil)
        )
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
    }

    private func makeControlView(in window: NSWindow) -> NSView {
        let control = NSView(frame: NSRect(x: 40, y: 60, width: 200, height: 30))
        window.contentView?.addSubview(control)
        return control
    }

    private func scrollTargetView(in view: NSView) -> ScrollTargetView? {
        if let marker = view as? ScrollTargetView {
            return marker
        }
        for subview in view.subviews {
            if let marker = scrollTargetView(in: subview) {
                return marker
            }
        }
        return nil
    }
}

@MainActor
private final class MarkerBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class MarkerWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class MarkerVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
