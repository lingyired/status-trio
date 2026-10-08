import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsRowHitAreaTests: XCTestCase {
    func testPopupSettingsButtonUsesFullRowHitArea() {
        let localization = makeLocalization()
        let settings = makeSettings()
        let store = SystemStatusStore(
            batteryMonitor: EmptyBatteryMonitor(),
            wifiMonitor: EmptyWiFiMonitor(),
            volumeMonitor: EmptyVolumeMonitor()
        )
        let panel = StatusPanelViewModel(
            store: store,
            settings: settings,
            localization: localization,
            actions: StatusPanelActions(store: store, settings: settings)
        )
        let view = StatusPopoverView(
            panel: panel,
            scrollTargets: PopoverScrollTargets(),
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

        let hitAreaWidths = interactiveSubViewWidths(
            for: view,
            size: NSSize(width: 300, height: 600)
        )

        XCTAssertTrue(
            hitAreaWidths.contains { abs($0 - 268) < 0.5 },
            "Expected the Settings row to react across the popup content width, got \(hitAreaWidths)"
        )
    }

    func testPreferenceCheckboxRowUsesFullRowHitArea() {
        let localization = makeLocalization()
        let view = PreferenceCheckboxRow(
            label: .settingsBatteryShowPercentage,
            isOn: .constant(false)
        )
        .environmentObject(localization)

        let hitAreaWidths = interactiveSubViewWidths(
            for: view,
            size: NSSize(width: 300, height: 40)
        )

        XCTAssertTrue(
            hitAreaWidths.contains { abs($0 - 300) < 0.5 },
            "Expected the checkbox row to react across its full width, got \(hitAreaWidths)"
        )
    }

    func testDisclosureRowUsesFullRowHitArea() {
        let localization = makeLocalization()
        let view = SettingsDisclosureRow(
            "cable.connector",
            tint: .teal,
            title: localization.string(.settingsNetworkConnectionIcons),
            subtitle: localization.string(.settingsNetworkConnectionIconsDescription),
            isExpanded: .constant(false)
        )
        .environmentObject(localization)
        .frame(width: 300)

        let hitAreaWidths = interactiveSubViewWidths(
            for: view,
            size: NSSize(width: 300, height: 80)
        )

        XCTAssertTrue(
            hitAreaWidths.contains { abs($0 - 300) < 0.5 },
            "Expected the disclosure row to react across its full width, got \(hitAreaWidths)"
        )
    }

    func testWiFiDetailsToggleUsesFullRowHitArea() {
        let localization = makeLocalization()
        let view = WiFiDetailsToggleRow(isExpanded: .constant(false))
            .environmentObject(localization)
            .frame(width: 260)

        let hitAreaWidths = interactiveSubViewWidths(
            for: view,
            size: NSSize(width: 260, height: 40)
        )

        XCTAssertTrue(
            hitAreaWidths.contains { abs($0 - 260) < 0.5 },
            "Expected the details row to react across the whole list width, got \(hitAreaWidths)"
        )
    }

    func testNavigationBackRowUsesFullHeaderHitArea() {
        let view = NavigationBackRow(
            accessibilityLabel: "Back",
            title: "Wi-Fi",
            action: {}
        )
        .frame(width: 300)

        let hitAreas = interactiveSubViewSizes(
            for: view,
            size: NSSize(width: 300, height: 60)
        )

        XCTAssertTrue(
            hitAreas.contains { $0.width >= 250 && $0.height >= 32 },
            "Expected the back row to react across the header width, got \(hitAreas)"
        )
    }

    private func interactiveSubViewWidths<V: View>(
        for view: V,
        size: NSSize
    ) -> [CGFloat] {
        interactiveSubViewSizes(for: view, size: size).map(\.width)
    }

    private func interactiveSubViewSizes<V: View>(
        for view: V,
        size: NSSize
    ) -> [NSSize] {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)

        // A hit area only exists once the row is in a window. A detached hosting
        // view is left partially laid out, and the interactive subtree it
        // realizes depends on the SDK: the macOS 26 SDK draws a `.checkbox`
        // toggle as an AppKit checkbox plus a SwiftUI label, so the row's
        // full-width target is only materialized inside a window.
        //
        // Nothing here may touch the process-wide activation policy: other tests
        // read it to decide whether the Dock is visible.
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        // Ordering the window front is what materializes the row's full-width
        // key-view proxy on the macOS 26 SDK; a window that is merely created is
        // not enough.
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        // Poll for the full-width target with a bounded timeout rather than
        // sleeping a fixed amount: this suite runs beside the Swift Testing
        // tests, and two CI incidents in this repository were caused by fixed
        // sleeps that lost exactly this kind of layout race.
        let deadline = Date().addingTimeInterval(2)
        var sizes = qualifyingSubViewSizes(of: hostingView)
        while !sizes.contains(where: { abs($0.width - size.width) < 0.5 }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            hostingView.layoutSubtreeIfNeeded()
            sizes = qualifyingSubViewSizes(of: hostingView)
        }

        return sizes
    }

    private func qualifyingSubViewSizes(of hostingView: NSView) -> [NSSize] {
        hostingView.subviews
            .filter { !$0.isHidden && $0.frame.height > 0 }
            .map(\.frame.size)
    }

    private func makeLocalization() -> Localization {
        let suiteName = "StatusTrioCoreTests.SettingsHitArea.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removeTestSuite(named: suiteName)
        addTeardownBlock { TestUserDefaults.removeSuite(named: suiteName) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.simplifiedChinese))
        return localization
    }

    private func makeSettings() -> SettingsStore {
        let suiteName = "StatusTrioCoreTests.SettingsHitAreaStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removeTestSuite(named: suiteName)
        addTeardownBlock { TestUserDefaults.removeSuite(named: suiteName) }
        return SettingsStore(defaults: defaults)
    }
}

@MainActor
private final class EmptyBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { continuation in
        continuation.finish()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class EmptyWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { continuation in
        continuation.finish()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class EmptyVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { continuation in
        continuation.finish()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
