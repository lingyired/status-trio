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
            )
            .environmentObject(localization)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 330, height: 480)
        window.contentView?.addSubview(hostingView)
        hostingView.layoutSubtreeIfNeeded()

        let marker = try XCTUnwrap(
            scrollTargetViews(in: hostingView).first { candidate in
                let center = candidate.convert(
                    NSPoint(x: candidate.bounds.midX, y: candidate.bounds.midY),
                    to: nil
                )
                return targets.target(at: center, in: window) == .volume
            }
        )
        let center = marker.convert(
            NSPoint(x: marker.bounds.midX, y: marker.bounds.midY),
            to: nil
        )
        XCTAssertGreaterThan(marker.bounds.height, 0)
        XCTAssertEqual(targets.target(at: center, in: window), .volume)
        XCTAssertNil(
            targets.target(
                at: NSPoint(x: center.x, y: center.y + 200),
                in: window
            )
        )
    }

    func testRegisteredVolumeControlMatchesPointsInsideItsFrame() {
        let window = makeWindow()
        let targets = PopoverScrollTargets()
        let control = makeControlView(in: window)
        targets.register(control, as: .volume)

        XCTAssertEqual(
            targets.target(at: NSPoint(x: 100, y: 70), in: window),
            .volume
        )
        XCTAssertNil(targets.target(at: NSPoint(x: 100, y: 20), in: window))
        XCTAssertNil(targets.target(at: NSPoint(x: 10, y: 70), in: window))
    }

    func testRegionIsEmptyBeforeRegistrationAndAfterRemoval() {
        let window = makeWindow()
        let targets = PopoverScrollTargets()
        let control = makeControlView(in: window)
        let point = NSPoint(x: 100, y: 70)

        XCTAssertNil(targets.target(at: point, in: window))

        targets.register(control, as: .volume)
        XCTAssertEqual(targets.target(at: point, in: window), .volume)

        targets.unregister(control)
        XCTAssertNil(targets.target(at: point, in: window))
    }

    func testStaleRemovalKeepsTheCurrentVolumeControl() {
        let window = makeWindow()
        let targets = PopoverScrollTargets()
        let control = makeControlView(in: window)
        let stale = NSView(frame: control.frame)
        targets.register(control, as: .volume)

        targets.unregister(stale)

        XCTAssertEqual(
            targets.target(at: NSPoint(x: 100, y: 70), in: window),
            .volume
        )
    }

    func testControlInAnotherWindowNeverMatches() {
        let window = makeWindow()
        let otherWindow = makeWindow()
        let targets = PopoverScrollTargets()
        targets.register(makeControlView(in: window), as: .volume)

        XCTAssertNil(targets.target(at: NSPoint(x: 100, y: 70), in: otherWindow))
        XCTAssertNil(targets.target(at: NSPoint(x: 100, y: 70), in: nil))
    }

    // MARK: #256 multi-slider registry

    func testBrightnessAndAudioInputSlidersCarryTheirOwnTargets() {
        let window = makeWindow()
        let targets = PopoverScrollTargets()
        let volume = makeControlView(in: window, frame: NSRect(x: 40, y: 60, width: 200, height: 30))
        let brightness = makeControlView(in: window, frame: NSRect(x: 40, y: 100, width: 200, height: 30))
        let input = makeControlView(in: window, frame: NSRect(x: 40, y: 140, width: 200, height: 30))
        targets.register(volume, as: .volume)
        targets.register(brightness, as: .brightness(displayID: "display-1"))
        targets.register(input, as: .audioInput)

        XCTAssertEqual(targets.target(at: NSPoint(x: 100, y: 70), in: window), .volume)
        XCTAssertEqual(
            targets.target(at: NSPoint(x: 100, y: 110), in: window),
            .brightness(displayID: "display-1")
        )
        XCTAssertEqual(targets.target(at: NSPoint(x: 100, y: 150), in: window), .audioInput)
        XCTAssertNil(targets.target(at: NSPoint(x: 100, y: 200), in: window))
    }

    func testOverlappingSlidersResolveToTheMostRecentlyRegistered() {
        let window = makeWindow()
        let targets = PopoverScrollTargets()
        let lower = makeControlView(in: window, frame: NSRect(x: 40, y: 60, width: 200, height: 30))
        let upper = makeControlView(in: window, frame: NSRect(x: 40, y: 60, width: 200, height: 30))
        targets.register(lower, as: .volume)
        targets.register(upper, as: .audioInput)

        XCTAssertEqual(
            targets.target(at: NSPoint(x: 100, y: 70), in: window),
            .audioInput
        )
    }

    func testReRegisteringMovesTheSliderToTheTop() {
        let window = makeWindow()
        let targets = PopoverScrollTargets()
        let first = makeControlView(in: window, frame: NSRect(x: 40, y: 60, width: 200, height: 30))
        let second = makeControlView(in: window, frame: NSRect(x: 40, y: 60, width: 200, height: 30))
        targets.register(first, as: .volume)
        targets.register(second, as: .audioInput)
        targets.register(first, as: .volume)

        XCTAssertEqual(
            targets.target(at: NSPoint(x: 100, y: 70), in: window),
            .volume
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

    private func makeControlView(
        in window: NSWindow,
        frame: NSRect = NSRect(x: 40, y: 60, width: 200, height: 30)
    ) -> NSView {
        let control = NSView(frame: frame)
        window.contentView?.addSubview(control)
        return control
    }

    private func scrollTargetViews(in view: NSView) -> [ScrollTargetView] {
        var result: [ScrollTargetView] = []
        if let marker = view as? ScrollTargetView {
            result.append(marker)
        }
        for subview in view.subviews {
            result.append(contentsOf: scrollTargetViews(in: subview))
        }
        return result
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
